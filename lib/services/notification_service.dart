import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

enum AlertType { priceAbove, priceBelow }

class PriceAlert {
  final String id;
  final String symbol;
  final AlertType type;
  final double targetValue;
  bool triggered;
  bool active;
  final DateTime createdAt;

  PriceAlert({
    required this.id,
    required this.symbol,
    required this.type,
    required this.targetValue,
    this.triggered = false,
    this.active = true,
    required this.createdAt,
  });

  String get description {
    switch (type) {
      case AlertType.priceAbove:
        return '$symbol поднялся выше \$${targetValue.toStringAsFixed(2)}';
      case AlertType.priceBelow:
        return '$symbol упал ниже \$${targetValue.toStringAsFixed(2)}';
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'symbol': symbol,
        'type': type.name,
        'targetValue': targetValue,
        'triggered': triggered,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PriceAlert.fromMap(Map<dynamic, dynamic> map) => PriceAlert(
        id: map['id'],
        symbol: map['symbol'],
        type: AlertType.values.byName(map['type']),
        targetValue: (map['targetValue'] as num).toDouble(),
        triggered: map['triggered'] ?? false,
        active: map['active'] ?? true,
        createdAt: DateTime.parse(map['createdAt']),
      );
}

const _channelId = 'mexc_alerts';
const _alertsBoxName = 'price_alerts_box';
const _bgTaskName = 'mexcPriceCheck';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static late Box _box;

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      'MEXC Алерты',
      description: 'Уведомления о ценах на криптовалюту',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _box = await Hive.openBox(_alertsBoxName);

    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'MEXC Алерты',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  static List<PriceAlert> getAll() => _box.values
      .map((e) => PriceAlert.fromMap(Map<dynamic, dynamic>.from(e)))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static List<PriceAlert> getActive() =>
      getAll().where((a) => a.active && !a.triggered).toList();

  static Future<void> add(PriceAlert alert) async {
    await _box.put(alert.id, alert.toMap());
    _scheduleBackground();
  }

  static Future<void> delete(String id) => _box.delete(id);

  static Future<void> toggle(String id, bool active) async {
    final raw = _box.get(id);
    if (raw == null) return;
    final alert = PriceAlert.fromMap(Map<dynamic, dynamic>.from(raw));
    alert.active = active;
    await _box.put(id, alert.toMap());
  }

  /// Вызывается из UI при каждом обновлении цены — мгновенная проверка
  static Future<void> checkForSymbol(String symbol, double price) async {
    final alerts = getActive().where((a) => a.symbol == symbol).toList();
    for (final alert in alerts) {
      final hit = alert.type == AlertType.priceAbove
          ? price >= alert.targetValue
          : price <= alert.targetValue;
      if (!hit) continue;

      alert.triggered = true;
      alert.active = false;
      await _box.put(alert.id, alert.toMap());
      await show(title: '🔔 Алерт: $symbol', body: alert.description, id: alert.id.hashCode);
    }
  }

  static void _scheduleBackground() {
    Workmanager().registerPeriodicTask(
      _bgTaskName,
      _bgTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  static void cancelBackground() => Workmanager().cancelByUniqueName(_bgTaskName);
}

/// Top-level callback для WorkManager — обязательно вне класса
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _bgTaskName) return true;
    try {
      await Hive.initFlutter();
      final box = await Hive.openBox(_alertsBoxName);

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final alerts = box.values
          .map((e) => PriceAlert.fromMap(Map<dynamic, dynamic>.from(e)))
          .where((a) => a.active && !a.triggered)
          .toList();

      final symbols = alerts.map((a) => a.symbol).toSet();

      for (final symbol in symbols) {
        final price = await _fetchPriceDartIo(symbol);
        if (price == null) continue;

        for (final alert in alerts.where((a) => a.symbol == symbol)) {
          final hit = alert.type == AlertType.priceAbove
              ? price >= alert.targetValue
              : price <= alert.targetValue;
          if (!hit) continue;

          alert.triggered = true;
          alert.active = false;
          await box.put(alert.id, alert.toMap());

          await plugin.show(
            alert.id.hashCode,
            '🔔 Алерт: $symbol',
            alert.description,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                'MEXC Алерты',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      }
    } catch (_) {
      // Фоновая задача не должна крашить воркер
    }
    return true;
  });
}

/// Прямой HTTP GET через dart:io (без http-пакета) — надёжнее в изоляте
Future<double?> _fetchPriceDartIo(String symbol) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(
      Uri.parse('https://api.mexc.com/api/v3/ticker/price?symbol=$symbol'),
    );
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return double.tryParse(data['price'].toString());
  } catch (_) {
    return null;
  }
}
