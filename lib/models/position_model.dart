enum PositionType { spot, futures }

enum PositionSide { long, short } // для спота всегда long

enum PositionStatus { open, closed, liquidated }

/// Демо-позиция (виртуальная, без реальных денег).
/// Хранится локально на устройстве — биржа используется только как
/// источник цены.
class DemoPosition {
  final String id;
  final String symbol; // BTCUSDT
  final PositionType type;
  final PositionSide side;
  final double entryPrice;
  final double quantity; // объём в базовом активе (например, BTC)
  final double marginUsdt; // сколько USDT заморожено как маржа
  final int leverage; // 1 для спота, 1-125 для фьючерсов
  final DateTime openedAt;

  double? closePrice;
  DateTime? closedAt;
  PositionStatus status;

  // Стоп-лосс / тейк-профит (опционально, в цене актива)
  double? stopLossPrice;
  double? takeProfitPrice;

  DemoPosition({
    required this.id,
    required this.symbol,
    required this.type,
    required this.side,
    required this.entryPrice,
    required this.quantity,
    required this.marginUsdt,
    required this.leverage,
    required this.openedAt,
    this.status = PositionStatus.open,
    this.stopLossPrice,
    this.takeProfitPrice,
    this.closePrice,
    this.closedAt,
  });

  /// Номинальный размер позиции в USDT (с учётом плеча)
  double get notionalUsdt => entryPrice * quantity;

  /// Нереализованный PnL в USDT при текущей цене
  double unrealizedPnl(double currentPrice) {
    final priceDiff = side == PositionSide.long
        ? (currentPrice - entryPrice)
        : (entryPrice - currentPrice);
    return priceDiff * quantity;
  }

  /// PnL в процентах от маржи (а не от цены!) — то, что видит юзер
  double unrealizedPnlPercent(double currentPrice) {
    if (marginUsdt == 0) return 0;
    return (unrealizedPnl(currentPrice) / marginUsdt) * 100;
  }

  /// Цена ликвидации (приблизительно, без учёта funding/fees) —
  /// только для фьючерсов с плечом.
  double? get liquidationPrice {
    if (type != PositionType.futures || leverage <= 1) return null;
    // Грубая модель: ликвидация при потере ~95% маржи
    final maintenanceRatio = 0.95;
    final liqDistance = entryPrice * (maintenanceRatio / leverage);
    return side == PositionSide.long
        ? entryPrice - liqDistance
        : entryPrice + liqDistance;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'symbol': symbol,
        'type': type.name,
        'side': side.name,
        'entryPrice': entryPrice,
        'quantity': quantity,
        'marginUsdt': marginUsdt,
        'leverage': leverage,
        'openedAt': openedAt.toIso8601String(),
        'status': status.name,
        'stopLossPrice': stopLossPrice,
        'takeProfitPrice': takeProfitPrice,
        'closePrice': closePrice,
        'closedAt': closedAt?.toIso8601String(),
      };

  /// Безопасное приведение num -> double (Hive/JSON может вернуть int,
  /// если значение было "целым", например 100 вместо 100.0)
  static double? _toDoubleOrNull(dynamic v) =>
      v == null ? null : (v as num).toDouble();

  static double _toDouble(dynamic v) => (v as num).toDouble();

  factory DemoPosition.fromMap(Map<String, dynamic> map) => DemoPosition(
        id: map['id'],
        symbol: map['symbol'],
        type: PositionType.values.byName(map['type']),
        side: PositionSide.values.byName(map['side']),
        entryPrice: _toDouble(map['entryPrice']),
        quantity: _toDouble(map['quantity']),
        marginUsdt: _toDouble(map['marginUsdt']),
        leverage: (map['leverage'] as num).toInt(),
        openedAt: DateTime.parse(map['openedAt']),
        status: PositionStatus.values.byName(map['status']),
        stopLossPrice: _toDoubleOrNull(map['stopLossPrice']),
        takeProfitPrice: _toDoubleOrNull(map['takeProfitPrice']),
        closePrice: _toDoubleOrNull(map['closePrice']),
        closedAt:
            map['closedAt'] != null ? DateTime.parse(map['closedAt']) : null,
      );
}
