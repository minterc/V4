import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/symbol_model.dart';
import '../models/position_model.dart';
import '../services/mexc_api_service.dart';
import '../services/demo_trading_engine.dart';
import '../services/notification_service.dart';
import 'pine_script_interpreter.dart';

enum BotStatus { stopped, running, error }

/// Одна запись в логе бота
class BotLogEntry {
  final DateTime time;
  final String symbol;
  final String message;
  final bool isError;

  BotLogEntry({
    required this.time,
    required this.symbol,
    required this.message,
    this.isError = false,
  });
}

/// Активная стратегия пользователя
class BotStrategy {
  final String id;
  String name;
  String symbol;
  String interval; // таймфрейм свечей
  String script; // Pine Script-подобный скрипт
  bool enabled;
  bool isDemoMode; // true = демо, false = реальный режим
  final DateTime createdAt;

  BotStrategy({
    required this.id,
    required this.name,
    required this.symbol,
    required this.interval,
    required this.script,
    this.enabled = false,
    this.isDemoMode = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'interval': interval,
        'script': script,
        'enabled': enabled,
        'isDemoMode': isDemoMode,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BotStrategy.fromMap(Map<dynamic, dynamic> m) => BotStrategy(
        id: m['id'],
        name: m['name'],
        symbol: m['symbol'],
        interval: m['interval'] ?? '15m',
        script: m['script'],
        enabled: m['enabled'] ?? false,
        isDemoMode: m['isDemoMode'] ?? true,
        createdAt: DateTime.parse(m['createdAt']),
      );
}

/// Движок бота — управляет стратегиями, запускает интерпретатор,
/// исполняет сигналы через демо-движок или реальный API.
class BotEngine extends ChangeNotifier {
  static const String _strategiesBox = 'bot_strategies_box';
  static const String _logsBox = 'bot_logs_box';

  final MexcApiService _api;
  final DemoTradingEngine _demo;

  late Box _stratBox;
  late Box _logBox;

  final Map<String, Timer> _timers = {}; // symbol+interval -> Timer
  final List<BotLogEntry> _logs = [];
  BotStatus _status = BotStatus.stopped;

  BotStatus get status => _status;
  List<BotLogEntry> get logs => List.unmodifiable(_logs);

  BotEngine(this._api, this._demo);

  Future<void> init() async {
    _stratBox = await Hive.openBox(_strategiesBox);
    _logBox = await Hive.openBox(_logsBox);

    // Восстанавливаем логи из Hive (последние 200)
    final savedLogs = _logBox.values.toList();
    for (final raw in savedLogs.take(200)) {
      try {
        final m = Map<dynamic, dynamic>.from(raw);
        _logs.add(BotLogEntry(
          time: DateTime.parse(m['time']),
          symbol: m['symbol'],
          message: m['message'],
          isError: m['isError'] ?? false,
        ));
      } catch (_) {}
    }

    // Автозапуск включённых стратегий
    for (final s in getStrategies().where((s) => s.enabled)) {
      _scheduleStrategy(s);
    }
    if (_timers.isNotEmpty) _status = BotStatus.running;
    notifyListeners();
  }

  // ── Управление стратегиями ──

  List<BotStrategy> getStrategies() => _stratBox.values
      .map((e) => BotStrategy.fromMap(Map<dynamic, dynamic>.from(e)))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<BotStrategy> addStrategy({
    required String name,
    required String symbol,
    String interval = '15m',
    String script = _defaultScript,
    bool isDemoMode = true,
  }) async {
    final s = BotStrategy(
      id: const Uuid().v4(),
      name: name,
      symbol: symbol.toUpperCase(),
      interval: interval,
      script: script,
      isDemoMode: isDemoMode,
      createdAt: DateTime.now(),
    );
    await _stratBox.put(s.id, s.toMap());
    notifyListeners();
    return s;
  }

  Future<void> updateStrategy(BotStrategy s) async {
    await _stratBox.put(s.id, s.toMap());
    notifyListeners();
  }

  Future<void> deleteStrategy(String id) async {
    _stopStrategy(id);
    await _stratBox.delete(id);
    notifyListeners();
  }

  /// Включить/выключить стратегию
  Future<void> toggleStrategy(String id, bool enabled) async {
    final raw = _stratBox.get(id);
    if (raw == null) return;
    final s = BotStrategy.fromMap(Map<dynamic, dynamic>.from(raw));
    s.enabled = enabled;
    await _stratBox.put(id, s.toMap());

    if (enabled) {
      _scheduleStrategy(s);
      _log(s.symbol, '▶️ Стратегия "${s.name}" запущена');
    } else {
      _stopStrategy(id);
      _log(s.symbol, '⏹️ Стратегия "${s.name}" остановлена');
    }

    _status = _timers.isNotEmpty ? BotStatus.running : BotStatus.stopped;
    notifyListeners();
  }

  /// Запустить стратегию немедленно (для тестирования)
  Future<ScriptResult> runOnce(BotStrategy s) async {
    return await _executeStrategy(s);
  }

  // ── Внутренняя логика ──

  void _scheduleStrategy(BotStrategy s) {
    _stopStrategy(s.id);
    final duration = _intervalToDuration(s.interval);
    _timers[s.id] = Timer.periodic(duration, (_) async {
      await _executeStrategy(s);
    });
  }

  void _stopStrategy(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
  }

  Duration _intervalToDuration(String interval) {
    switch (interval) {
      case '1m': return const Duration(minutes: 1);
      case '5m': return const Duration(minutes: 5);
      case '15m': return const Duration(minutes: 15);
      case '1h': return const Duration(hours: 1);
      case '4h': return const Duration(hours: 4);
      case '1d': return const Duration(hours: 24);
      default: return const Duration(minutes: 15);
    }
  }

  Future<ScriptResult> _executeStrategy(BotStrategy s) async {
    try {
      // Получаем реальные свечи для расчёта индикаторов
      final candles = await _api.fetchKlines(s.symbol, interval: s.interval, limit: 200);
      final currentPrice = await _api.fetchPrice(s.symbol);

      // Проверяем есть ли открытая позиция по этому символу
      final hasPos = _demo.openPositions.any((p) => p.symbol == s.symbol);

      // Запускаем интерпретатор
      final interpreter = PineScriptInterpreter(
        candles: candles,
        currentPrice: currentPrice,
        hasOpenPosition: hasPos,
      );
      final result = interpreter.execute(s.script);

      // Логируем результат интерпретатора
      for (final log in result.logs) {
        _log(s.symbol, log);
      }

      // Исполняем сигнал
      if (result.signal != BotSignal.none) {
        await _executeSignal(s, result, currentPrice);
      }

      return result;
    } catch (e) {
      _log(s.symbol, '❌ Ошибка выполнения стратегии "${s.name}": $e', isError: true);
      return ScriptResult(logs: ['❌ $e']);
    }
  }

  Future<void> _executeSignal(
    BotStrategy s,
    ScriptResult result,
    double currentPrice,
  ) async {
    final qty = result.qty ?? 100.0;

    if (result.signal == BotSignal.openLong || result.signal == BotSignal.buy) {
      if (s.isDemoMode) {
        // Вычисляем SL/TP цены
        double? slPrice;
        double? tpPrice;
        if (result.stopLoss != null) {
          slPrice = result.stopLossIsPercent
              ? currentPrice * (1 - result.stopLoss! / 100)
              : result.stopLoss;
        }
        if (result.takeProfit != null) {
          tpPrice = result.takeProfitIsPercent
              ? currentPrice * (1 + result.takeProfit! / 100)
              : result.takeProfit;
        }

        _demo.openPosition(
          symbol: s.symbol,
          type: PositionType.spot,
          side: PositionSide.long,
          currentPrice: currentPrice,
          usdtAmount: qty,
          leverage: result.leverage,
          stopLossPrice: slPrice,
          takeProfitPrice: tpPrice,
        );
        _log(s.symbol, '🟢 [DEMO] Куплено ${s.symbol} на \$$qty по \$$currentPrice');
        await NotificationService.show(
          title: '🤖 Бот: ${s.symbol}',
          body: 'Открыт Long по \$${currentPrice.toStringAsFixed(2)}',
        );
      } else {
        _log(s.symbol, '⚠️ Реальный режим бота в разработке', isError: false);
      }
    } else if (result.signal == BotSignal.sell ||
        result.signal == BotSignal.closeLong ||
        result.signal == BotSignal.closeShort) {
      if (s.isDemoMode) {
        final positions = _demo.openPositions.where((p) => p.symbol == s.symbol).toList();
        for (final pos in positions) {
          _demo.closePosition(pos.id, currentPrice);
        }
        if (positions.isNotEmpty) {
          _log(s.symbol, '🔴 [DEMO] Закрыты позиции ${s.symbol} по \$$currentPrice');
          await NotificationService.show(
            title: '🤖 Бот: ${s.symbol}',
            body: 'Закрыта позиция по \$${currentPrice.toStringAsFixed(2)}',
          );
        }
      }
    } else if (result.signal == BotSignal.openShort) {
      if (s.isDemoMode) {
        _demo.openPosition(
          symbol: s.symbol,
          type: PositionType.futures,
          side: PositionSide.short,
          currentPrice: currentPrice,
          usdtAmount: qty,
          leverage: result.leverage,
        );
        _log(s.symbol, '🔴 [DEMO] Short ${s.symbol} на \$$qty по \$$currentPrice');
      }
    }
  }

  void _log(String symbol, String message, {bool isError = false}) {
    final entry = BotLogEntry(
      time: DateTime.now(),
      symbol: symbol,
      message: message,
      isError: isError,
    );
    _logs.insert(0, entry);
    if (_logs.length > 500) _logs.removeLast();

    // Сохраняем в Hive (последние 200)
    _logBox.put(DateTime.now().millisecondsSinceEpoch.toString(), {
      'time': entry.time.toIso8601String(),
      'symbol': entry.symbol,
      'message': entry.message,
      'isError': entry.isError,
    });

    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    _logBox.clear();
    notifyListeners();
  }
}

const String _defaultScript = '''
//@version=5
strategy("Моя стратегия RSI", overlay=true)

// Параметры
rsiPeriod = 14
rsiOversold = 30
rsiOverbought = 70
orderSize = 100

// Индикаторы
rsi = ta.rsi(close, rsiPeriod)
ma20 = ta.sma(close, 20)

// Сигналы
buy = rsi < rsiOversold and close > ma20
sell = rsi > rsiOverbought

// Торговля
if buy
    strategy.entry("Long", strategy.long, qty=orderSize)
    strategy.exit("Exit", "Long", profit=5, loss=2)

if sell
    strategy.close("Long")
''';
