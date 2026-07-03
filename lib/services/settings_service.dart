import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/settings_model.dart';

/// Хранилище и провайдер настроек приложения (не секретных).
class SettingsService extends ChangeNotifier {
  static const String _boxName = 'app_settings_box';
  late Box _box;

  AppSettings _settings = AppSettings();
  AppSettings get settings => _settings;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    final raw = _box.get('settings');
    if (raw != null) {
      _settings = AppSettings.fromMap(Map<dynamic, dynamic>.from(raw));
    } else {
      await _persist();
    }
  }

  Future<void> _persist() async {
    await _box.put('settings', _settings.toMap());
    notifyListeners();
  }

  Future<void> setMode(AppMode mode) async {
    _settings.mode = mode;
    await _persist();
  }

  Future<void> setConfirmBeforeRealOrder(bool value) async {
    _settings.confirmBeforeRealOrder = value;
    await _persist();
  }

  Future<void> setMaxOrderUsdt(double value) async {
    _settings.maxOrderUsdt = value;
    await _persist();
  }

  Future<void> setMaxLeverage(int value) async {
    _settings.maxLeverage = value;
    await _persist();
  }

  Future<void> setAlertsEnabled(bool value) async {
    _settings.alertsEnabled = value;
    await _persist();
  }

  Future<void> setAlertSoundEnabled(bool value) async {
    _settings.alertSoundEnabled = value;
    await _persist();
  }

  Future<void> setChartTheme(String value) async {
    _settings.chartTheme = value;
    await _persist();
  }
}
