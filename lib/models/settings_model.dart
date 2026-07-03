/// Режим работы приложения. Demo — виртуальные деньги (по умолчанию,
/// безопасно). Real — настоящие сделки на бирже через API-ключ.
enum AppMode { demo, real }

/// Настройки приложения, хранятся в Hive (НЕ для секретных данных —
/// API-ключи хранятся отдельно через SecureStorageService).
class AppSettings {
  AppMode mode;

  // Защитные ограничения для реального режима
  bool confirmBeforeRealOrder;
  double maxOrderUsdt; // максимальная сумма одной сделки в реальном режиме
  int maxLeverage; // ограничение плеча сверху, даже если биржа разрешает больше

  // Поведение алертов
  bool alertsEnabled;
  bool alertSoundEnabled;

  // Отображение
  String preferredCurrency; // пока всегда USDT, задел на будущее
  String chartTheme; // 'dark' | 'light'

  AppSettings({
    this.mode = AppMode.demo,
    this.confirmBeforeRealOrder = true,
    this.maxOrderUsdt = 100.0,
    this.maxLeverage = 20,
    this.alertsEnabled = true,
    this.alertSoundEnabled = true,
    this.preferredCurrency = 'USDT',
    this.chartTheme = 'dark',
  });

  Map<String, dynamic> toMap() => {
        'mode': mode.name,
        'confirmBeforeRealOrder': confirmBeforeRealOrder,
        'maxOrderUsdt': maxOrderUsdt,
        'maxLeverage': maxLeverage,
        'alertsEnabled': alertsEnabled,
        'alertSoundEnabled': alertSoundEnabled,
        'preferredCurrency': preferredCurrency,
        'chartTheme': chartTheme,
      };

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) => AppSettings(
        mode: AppMode.values.byName(map['mode'] ?? 'demo'),
        confirmBeforeRealOrder: map['confirmBeforeRealOrder'] ?? true,
        maxOrderUsdt: (map['maxOrderUsdt'] as num?)?.toDouble() ?? 100.0,
        maxLeverage: (map['maxLeverage'] as num?)?.toInt() ?? 20,
        alertsEnabled: map['alertsEnabled'] ?? true,
        alertSoundEnabled: map['alertSoundEnabled'] ?? true,
        preferredCurrency: map['preferredCurrency'] ?? 'USDT',
        chartTheme: map['chartTheme'] ?? 'dark',
      );
}
