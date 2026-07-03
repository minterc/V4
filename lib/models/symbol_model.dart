/// Модель торговой пары (монеты), доступной на MEXC
class Symbol {
  final String symbol; // например BTCUSDT
  final String baseAsset; // BTC
  final String quoteAsset; // USDT
  final bool futuresAvailable;

  Symbol({
    required this.symbol,
    required this.baseAsset,
    required this.quoteAsset,
    this.futuresAvailable = false,
  });

  /// Красивое отображение типа "BTC/USDT"
  String get displayName => '$baseAsset/$quoteAsset';

  factory Symbol.fromSpotJson(Map<String, dynamic> json) {
    return Symbol(
      symbol: json['symbol'] as String,
      baseAsset: json['baseAsset'] as String,
      quoteAsset: json['quoteAsset'] as String,
    );
  }

  @override
  bool operator ==(Object other) => other is Symbol && other.symbol == symbol;

  @override
  int get hashCode => symbol.hashCode;
}

/// Одна свеча (OHLCV)
class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  /// MEXC возвращает массив:
  /// [openTime, open, high, low, close, volume, closeTime, ...]
  factory Candle.fromMexcArray(List<dynamic> raw) {
    return Candle(
      time: DateTime.fromMillisecondsSinceEpoch(raw[0] as int),
      open: double.parse(raw[1].toString()),
      high: double.parse(raw[2].toString()),
      low: double.parse(raw[3].toString()),
      close: double.parse(raw[4].toString()),
      volume: double.parse(raw[5].toString()),
    );
  }
}
