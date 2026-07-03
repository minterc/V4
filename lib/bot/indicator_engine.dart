import '../models/symbol_model.dart';

/// Вычисляет технические индикаторы по массиву свечей.
/// Все функции работают аналогично ta.* в Pine Script.
class IndicatorEngine {
  final List<Candle> candles;

  IndicatorEngine(this.candles);

  List<double> get closes => candles.map((c) => c.close).toList();
  List<double> get highs => candles.map((c) => c.high).toList();
  List<double> get lows => candles.map((c) => c.low).toList();
  List<double> get volumes => candles.map((c) => c.volume).toList();

  /// Последнее значение (текущая свеча)
  double get close => closes.last;
  double get open => candles.last.open;
  double get high => highs.last;
  double get low => lows.last;
  double get volume => volumes.last;

  // ── SMA ──
  double sma(List<double> src, int period) {
    if (src.length < period) return double.nan;
    final slice = src.sublist(src.length - period);
    return slice.reduce((a, b) => a + b) / period;
  }

  List<double> smaList(List<double> src, int period) {
    final result = <double>[];
    for (int i = 0; i < src.length; i++) {
      if (i < period - 1) {
        result.add(double.nan);
      } else {
        final slice = src.sublist(i - period + 1, i + 1);
        result.add(slice.reduce((a, b) => a + b) / period);
      }
    }
    return result;
  }

  // ── EMA ──
  List<double> emaList(List<double> src, int period) {
    final result = <double>[];
    final k = 2.0 / (period + 1);
    for (int i = 0; i < src.length; i++) {
      if (i == 0) {
        result.add(src[0]);
      } else {
        result.add(src[i] * k + result[i - 1] * (1 - k));
      }
    }
    return result;
  }

  double ema(List<double> src, int period) => emaList(src, period).last;

  // ── RSI ──
  List<double> rsiList(List<double> src, int period) {
    final result = List<double>.filled(src.length, double.nan);
    if (src.length < period + 1) return result;

    double avgGain = 0, avgLoss = 0;
    for (int i = 1; i <= period; i++) {
      final diff = src[i] - src[i - 1];
      if (diff > 0) avgGain += diff;
      else avgLoss += (-diff);
    }
    avgGain /= period;
    avgLoss /= period;

    if (avgLoss == 0) {
      result[period] = 100;
    } else {
      result[period] = 100 - (100 / (1 + avgGain / avgLoss));
    }

    for (int i = period + 1; i < src.length; i++) {
      final diff = src[i] - src[i - 1];
      final gain = diff > 0 ? diff : 0.0;
      final loss = diff < 0 ? -diff : 0.0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;
      result[i] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss));
    }
    return result;
  }

  double rsi(List<double> src, int period) {
    final list = rsiList(src, period);
    return list.lastWhere((v) => !v.isNaN, orElse: () => double.nan);
  }

  // ── MACD ──
  /// Возвращает [macdLine, signalLine, histogram]
  ({double macd, double signal, double hist}) macd(
      List<double> src, int fast, int slow, int signal) {
    final fastEma = emaList(src, fast);
    final slowEma = emaList(src, slow);
    final macdLine = List.generate(src.length, (i) => fastEma[i] - slowEma[i]);
    final signalLine = emaList(macdLine, signal);
    final hist = List.generate(src.length, (i) => macdLine[i] - signalLine[i]);
    return (
      macd: macdLine.last,
      signal: signalLine.last,
      hist: hist.last,
    );
  }

  // ── Bollinger Bands ──
  ({double upper, double middle, double lower}) bollingerBands(
      List<double> src, int period, double stdDevMult) {
    final middle = sma(src, period);
    final slice = src.sublist(src.length - period);
    final variance = slice.map((v) => (v - middle) * (v - middle)).reduce((a, b) => a + b) / period;
    final stdDev = variance <= 0 ? 0.0 : variance == 0 ? 0.0 : _sqrt(variance);
    return (
      upper: middle + stdDevMult * stdDev,
      middle: middle,
      lower: middle - stdDevMult * stdDev,
    );
  }

  double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v;
    double last = 0;
    while ((x - last).abs() > 0.0001) {
      last = x;
      x = (x + v / x) / 2;
    }
    return x;
  }

  // ── Stochastic ──
  ({double k, double d}) stochastic(int kPeriod, int dPeriod, int smooth) {
    if (candles.length < kPeriod) return (k: double.nan, d: double.nan);

    final rawK = <double>[];
    for (int i = kPeriod - 1; i < candles.length; i++) {
      final slice = candles.sublist(i - kPeriod + 1, i + 1);
      final highestHigh = slice.map((c) => c.high).reduce((a, b) => a > b ? a : b);
      final lowestLow = slice.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      final range = highestHigh - lowestLow;
      rawK.add(range == 0 ? 50 : (slice.last.close - lowestLow) / range * 100);
    }

    final smoothK = smaList(rawK, smooth);
    final dLine = smaList(smoothK.where((v) => !v.isNaN).toList(), dPeriod);

    return (
      k: smoothK.lastWhere((v) => !v.isNaN, orElse: () => double.nan),
      d: dLine.lastWhere((v) => !v.isNaN, orElse: () => double.nan),
    );
  }

  // ── Crossover / Crossunder (как ta.crossover в Pine Script) ──
  /// Возвращает true если series1 пересекла series2 снизу вверх
  bool crossover(double current1, double current2, double prev1, double prev2) {
    return prev1 <= prev2 && current1 > current2;
  }

  bool crossunder(double current1, double current2, double prev1, double prev2) {
    return prev1 >= prev2 && current1 < current2;
  }

  // ── Вспомогательные ──
  double highest(List<double> src, int period) {
    if (src.length < period) return src.reduce((a, b) => a > b ? a : b);
    return src.sublist(src.length - period).reduce((a, b) => a > b ? a : b);
  }

  double lowest(List<double> src, int period) {
    if (src.length < period) return src.reduce((a, b) => a < b ? a : b);
    return src.sublist(src.length - period).reduce((a, b) => a < b ? a : b);
  }
}
