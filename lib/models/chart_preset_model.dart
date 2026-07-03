/// Пресет настроек графика — сохраняется пользователем и может
/// быть применён к любому символу.
class ChartPreset {
  final String id;
  String name; // пользовательское название пресета
  final String symbol; // символ, для которого создан пресет
  String interval; // таймфрейм: 1m, 5m, 15m, 1h, 4h, 1d

  // Включённые индикаторы
  bool showMa20;
  bool showMa50;
  bool showMa200;
  bool showEma12;
  bool showEma26;
  bool showBollinger;
  bool showRsi;
  bool showMacd;
  bool showVolume;
  bool showStochastic;

  // Параметры индикаторов
  int rsiPeriod;
  int bollPeriod;
  double bollStdDev;

  final DateTime savedAt;

  ChartPreset({
    required this.id,
    required this.name,
    required this.symbol,
    this.interval = '15m',
    this.showMa20 = false,
    this.showMa50 = false,
    this.showMa200 = false,
    this.showEma12 = false,
    this.showEma26 = false,
    this.showBollinger = false,
    this.showRsi = false,
    this.showMacd = false,
    this.showVolume = true,
    this.showStochastic = false,
    this.rsiPeriod = 14,
    this.bollPeriod = 20,
    this.bollStdDev = 2.0,
    required this.savedAt,
  });

  /// Список активных индикаторов как строки — передаётся в TradingView URL
  List<String> get activeStudies {
    final studies = <String>[];
    if (showMa20) studies.add('MASimple@tv-basicstudies');
    if (showEma12 || showEma26) studies.add('MAExp@tv-basicstudies');
    if (showBollinger) studies.add('BB@tv-basicstudies');
    if (showRsi) studies.add('RSI@tv-basicstudies');
    if (showMacd) studies.add('MACD@tv-basicstudies');
    if (showVolume) studies.add('Volume@tv-basicstudies');
    return studies;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'interval': interval,
        'showMa20': showMa20,
        'showMa50': showMa50,
        'showMa200': showMa200,
        'showEma12': showEma12,
        'showEma26': showEma26,
        'showBollinger': showBollinger,
        'showRsi': showRsi,
        'showMacd': showMacd,
        'showVolume': showVolume,
        'showStochastic': showStochastic,
        'rsiPeriod': rsiPeriod,
        'bollPeriod': bollPeriod,
        'bollStdDev': bollStdDev,
        'savedAt': savedAt.toIso8601String(),
      };

  factory ChartPreset.fromMap(Map<dynamic, dynamic> m) => ChartPreset(
        id: m['id'],
        name: m['name'],
        symbol: m['symbol'],
        interval: m['interval'] ?? '15m',
        showMa20: m['showMa20'] ?? false,
        showMa50: m['showMa50'] ?? false,
        showMa200: m['showMa200'] ?? false,
        showEma12: m['showEma12'] ?? false,
        showEma26: m['showEma26'] ?? false,
        showBollinger: m['showBollinger'] ?? false,
        showRsi: m['showRsi'] ?? false,
        showMacd: m['showMacd'] ?? false,
        showVolume: m['showVolume'] ?? true,
        showStochastic: m['showStochastic'] ?? false,
        rsiPeriod: (m['rsiPeriod'] as num?)?.toInt() ?? 14,
        bollPeriod: (m['bollPeriod'] as num?)?.toInt() ?? 20,
        bollStdDev: (m['bollStdDev'] as num?)?.toDouble() ?? 2.0,
        savedAt: DateTime.parse(m['savedAt']),
      );

  ChartPreset copyWith({String? name, String? interval}) => ChartPreset(
        id: id,
        name: name ?? this.name,
        symbol: symbol,
        interval: interval ?? this.interval,
        showMa20: showMa20,
        showMa50: showMa50,
        showMa200: showMa200,
        showEma12: showEma12,
        showEma26: showEma26,
        showBollinger: showBollinger,
        showRsi: showRsi,
        showMacd: showMacd,
        showVolume: showVolume,
        rsiPeriod: rsiPeriod,
        bollPeriod: bollPeriod,
        bollStdDev: bollStdDev,
        savedAt: savedAt,
      );
}
