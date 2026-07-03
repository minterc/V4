import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../models/position_model.dart';

/// Движок демо-трейдинга. Все деньги виртуальные, хранятся локально
/// в Hive. Биржа НЕ используется для исполнения ордеров — только
/// для получения цены (через MexcApiService отдельно).
class DemoTradingEngine extends ChangeNotifier {
  static const String _balanceBox = 'demo_balance_box';
  static const String _positionsBox = 'demo_positions_box';
  static const double startingBalance = 10000.0; // стартовый виртуальный USDT

  late Box _balance;
  late Box _positions;
  final _uuid = const Uuid();

  double get balanceUsdt =>
      (_balance.get('usdt', defaultValue: startingBalance) as num).toDouble();

  List<DemoPosition> get openPositions => _positions.values
      .map((e) => DemoPosition.fromMap(Map<String, dynamic>.from(e)))
      .where((p) => p.status == PositionStatus.open)
      .toList();

  List<DemoPosition> get closedPositions => _positions.values
      .map((e) => DemoPosition.fromMap(Map<String, dynamic>.from(e)))
      .where((p) => p.status != PositionStatus.open)
      .toList()
        ..sort((a, b) => (b.closedAt ?? DateTime.now())
            .compareTo(a.closedAt ?? DateTime.now()));

  /// Маржа, заблокированная в открытых позициях
  double get usedMargin =>
      openPositions.fold(0.0, (sum, p) => sum + p.marginUsdt);

  /// Свободный баланс, доступный для новых позиций
  double get freeBalance => balanceUsdt - usedMargin;

  Future<void> init() async {
    await Hive.initFlutter();
    _balance = await Hive.openBox(_balanceBox);
    _positions = await Hive.openBox(_positionsBox);

    if (!_balance.containsKey('usdt')) {
      _balance.put('usdt', startingBalance);
    }
  }

  /// Сбросить демо-счёт к начальному состоянию
  Future<void> resetAccount() async {
    await _positions.clear();
    await _balance.put('usdt', startingBalance);
    notifyListeners();
  }

  /// Установить произвольную сумму демо-баланса (без сброса позиций)
  Future<void> setBalance(double amount) async {
    if (amount < 0) return;
    await _balance.put('usdt', amount);
    notifyListeners();
  }

  /// Открыть позицию.
  /// usdtAmount — сколько виртуальных USDT вложить (это и есть маржа
  /// для фьючерсов, либо полная сумма покупки для спота).
  /// leverage — для спота всегда 1.
  String openPosition({
    required String symbol,
    required PositionType type,
    required PositionSide side,
    required double currentPrice,
    required double usdtAmount,
    required int leverage,
    double? stopLossPrice,
    double? takeProfitPrice,
  }) {
    if (usdtAmount <= 0) {
      throw Exception('Сумма должна быть больше нуля');
    }
    if (usdtAmount > freeBalance) {
      throw Exception('Недостаточно свободного баланса');
    }
    if (type == PositionType.spot && side == PositionSide.short) {
      throw Exception('Шорт недоступен в спот-режиме');
    }

    final effectiveLeverage = type == PositionType.spot ? 1 : leverage;
    // Номинальный объём = маржа * плечо
    final notional = usdtAmount * effectiveLeverage;
    final quantity = notional / currentPrice;

    final position = DemoPosition(
      id: _uuid.v4(),
      symbol: symbol,
      type: type,
      side: side,
      entryPrice: currentPrice,
      quantity: quantity,
      marginUsdt: usdtAmount,
      leverage: effectiveLeverage,
      openedAt: DateTime.now(),
      stopLossPrice: stopLossPrice,
      takeProfitPrice: takeProfitPrice,
    );

    _positions.put(position.id, position.toMap());
    notifyListeners();
    return position.id;
  }

  /// Закрыть позицию по текущей цене (вручную пользователем)
  void closePosition(String positionId, double currentPrice) {
    final raw = _positions.get(positionId);
    if (raw == null) return;

    final position = DemoPosition.fromMap(Map<String, dynamic>.from(raw));
    if (position.status != PositionStatus.open) return;

    final pnl = position.unrealizedPnl(currentPrice);
    _settlePosition(position, currentPrice, pnl, PositionStatus.closed);
  }

  /// Проверка ликвидации/SL/TP — вызывается при каждом обновлении цены.
  /// Должна вызываться из экрана, который слушает поток цен.
  void checkPositionTriggers(String symbol, double currentPrice) {
    final positionsForSymbol =
        openPositions.where((p) => p.symbol == symbol).toList();

    for (final position in positionsForSymbol) {
      // Ликвидация (только фьючерсы)
      final liqPrice = position.liquidationPrice;
      if (liqPrice != null) {
        final liquidated = position.side == PositionSide.long
            ? currentPrice <= liqPrice
            : currentPrice >= liqPrice;
        if (liquidated) {
          _settlePosition(
            position,
            liqPrice,
            -position.marginUsdt, // вся маржа теряется при ликвидации
            PositionStatus.liquidated,
          );
          continue;
        }
      }

      // Stop-Loss
      if (position.stopLossPrice != null) {
        final hitSl = position.side == PositionSide.long
            ? currentPrice <= position.stopLossPrice!
            : currentPrice >= position.stopLossPrice!;
        if (hitSl) {
          final pnl = position.unrealizedPnl(position.stopLossPrice!);
          _settlePosition(
              position, position.stopLossPrice!, pnl, PositionStatus.closed);
          continue;
        }
      }

      // Take-Profit
      if (position.takeProfitPrice != null) {
        final hitTp = position.side == PositionSide.long
            ? currentPrice >= position.takeProfitPrice!
            : currentPrice <= position.takeProfitPrice!;
        if (hitTp) {
          final pnl = position.unrealizedPnl(position.takeProfitPrice!);
          _settlePosition(
              position, position.takeProfitPrice!, pnl, PositionStatus.closed);
        }
      }
    }
  }

  void _settlePosition(
    DemoPosition position,
    double closePrice,
    double pnl,
    PositionStatus finalStatus,
  ) {
    position.closePrice = closePrice;
    position.closedAt = DateTime.now();
    position.status = finalStatus;

    _positions.put(position.id, position.toMap());

    // Возвращаем маржу + PnL на баланс (при ликвидации PnL = -маржа,
    // то есть на баланс возвращается 0)
    final returnedAmount = position.marginUsdt + pnl;
    final newBalance = balanceUsdt + (returnedAmount > 0 ? returnedAmount : 0.0);
    _balance.put('usdt', newBalance);

    notifyListeners();
  }
}
