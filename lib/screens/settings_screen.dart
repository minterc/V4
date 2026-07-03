import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../models/settings_model.dart';
import '../services/settings_service.dart';
import '../services/secure_storage_service.dart';
import '../services/notification_service.dart';
import '../services/demo_trading_engine.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _secureStorage = SecureStorageService();
  final _apiKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();
  bool _keysLoaded = false;
  bool _hasKeys = false;
  bool _showKeys = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final hasKeys = await _secureStorage.hasCredentials();
    if (hasKeys) {
      final apiKey = await _secureStorage.getApiKey();
      final secret = await _secureStorage.getSecretKey();
      _apiKeyCtrl.text = apiKey ?? '';
      _secretKeyCtrl.text = secret ?? '';
    }
    setState(() {
      _hasKeys = hasKeys;
      _keysLoaded = true;
    });
  }

  Future<void> _saveKeys() async {
    final api = _apiKeyCtrl.text.trim();
    final secret = _secretKeyCtrl.text.trim();
    if (api.isEmpty || secret.isEmpty) {
      _snack('Заполните оба поля');
      return;
    }
    await _secureStorage.saveCredentials(apiKey: api, secretKey: secret);
    setState(() => _hasKeys = true);
    _snack('API-ключи сохранены');
  }

  Future<void> _clearKeys() async {
    final confirm = await _confirm(
      'Удалить API-ключи?',
      'Реальный режим станет недоступен до повторного ввода ключей.',
    );
    if (!confirm) return;
    await _secureStorage.clearCredentials();
    _apiKeyCtrl.clear();
    _secretKeyCtrl.clear();
    setState(() => _hasKeys = false);

    final settings = context.read<SettingsService>();
    if (settings.settings.mode == AppMode.real) {
      await settings.setMode(AppMode.demo);
    }
    _snack('API-ключи удалены, режим переключён на Demo');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBg,
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Подтвердить', style: TextStyle(color: AppColors.down)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final s = settings.settings;
    final engine = context.watch<DemoTradingEngine>();
    final isReal = s.mode == AppMode.real;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Режим торговли ──
          _Section(
            title: 'Режим торговли',
            child: Column(
              children: [
                _WarningBanner(
                  message: isReal
                      ? '⚠️ РЕАЛЬНЫЙ РЕЖИМ АКТИВЕН — сделки исполняются на бирже с настоящими деньгами'
                      : '✅ Демо-режим — все сделки виртуальные, деньги не тратятся',
                  color: isReal ? AppColors.down : AppColors.up,
                ),
                const SizedBox(height: 12),
                SegmentedButton<AppMode>(
                  segments: const [
                    ButtonSegment(value: AppMode.demo, label: Text('Demo'), icon: Icon(Icons.science_outlined)),
                    ButtonSegment(value: AppMode.real, label: Text('Real'), icon: Icon(Icons.currency_bitcoin)),
                  ],
                  selected: {s.mode},
                  onSelectionChanged: (sel) async {
                    if (sel.first == AppMode.real) {
                      if (!_hasKeys) {
                        _snack('Сначала введите API-ключи ниже');
                        return;
                      }
                      final ok = await _confirm(
                        'Переключиться в реальный режим?',
                        'Все ордера будут исполняться на бирже MEXC с настоящими деньгами. '
                        'Убедитесь, что ваш API-ключ создан БЕЗ права вывода средств.',
                      );
                      if (!ok) return;
                    }
                    await settings.setMode(sel.first);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── API-ключи ──
          _Section(
            title: 'API-ключи MEXC',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Создайте ключ на MEXC: Аккаунт → API-управление.\n'
                  '⚠️ Обязательно снимите галочку «Вывод средств» — '
                  'разрешите только «Торговля».',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (!_keysLoaded)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: !_showKeys,
                    decoration: _inputDecoration('API Key'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _secretKeyCtrl,
                    obscureText: !_showKeys,
                    decoration: _inputDecoration('Secret Key'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: Icon(_showKeys ? Icons.visibility_off : Icons.visibility),
                        label: Text(_showKeys ? 'Скрыть' : 'Показать'),
                        onPressed: () => setState(() => _showKeys = !_showKeys),
                      ),
                      const Spacer(),
                      if (_hasKeys)
                        TextButton(
                          onPressed: _clearKeys,
                          child: const Text('Удалить', style: TextStyle(color: AppColors.down)),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                        onPressed: _saveKeys,
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                  if (_hasKeys)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('✅ Ключи сохранены (зашифрованы на устройстве)',
                          style: TextStyle(color: AppColors.up, fontSize: 12)),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Защита в реальном режиме ──
          _Section(
            title: 'Защита (реальный режим)',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Подтверждение перед каждым ордером'),
                  subtitle: const Text('Диалог «Вы уверены?» перед исполнением', style: TextStyle(fontSize: 12)),
                  value: s.confirmBeforeRealOrder,
                  onChanged: (v) => settings.setConfirmBeforeRealOrder(v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Макс. сумма одной сделки'),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        controller: TextEditingController(text: s.maxOrderUsdt.toStringAsFixed(0)),
                        decoration: _inputDecoration('USDT'),
                        onSubmitted: (v) {
                          final val = double.tryParse(v);
                          if (val != null && val > 0) settings.setMaxOrderUsdt(val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('Макс. плечо')),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        controller: TextEditingController(text: s.maxLeverage.toString()),
                        decoration: _inputDecoration('x'),
                        onSubmitted: (v) {
                          final val = int.tryParse(v);
                          if (val != null && val >= 1 && val <= 125) settings.setMaxLeverage(val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Алерты ──
          _Section(
            title: 'Уведомления',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ценовые алерты'),
                  value: s.alertsEnabled,
                  onChanged: (v) => settings.setAlertsEnabled(v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Звук уведомлений'),
                  value: s.alertSoundEnabled,
                  onChanged: (v) => settings.setAlertSoundEnabled(v),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Управление алертами'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AlertsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Демо-счёт ──
          _Section(
            title: 'Демо-счёт',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Баланс: \$${engine.balanceUsdt.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                // Редактирование суммы демо-баланса
                Row(
                  children: [
                    const Expanded(child: Text('Установить баланс')),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: _inputDecoration('USDT'),
                        onSubmitted: (v) async {
                          final val = double.tryParse(v.replaceAll(',', '.'));
                          if (val == null || val < 0) {
                            _snack('Введите корректную сумму');
                            return;
                          }
                          final ok = await _confirm(
                            'Изменить демо-баланс?',
                            'Баланс будет установлен в \$${val.toStringAsFixed(2)}. Открытые позиции останутся.',
                          );
                          if (ok) {
                            engine.setBalance(val);
                            _snack('Баланс обновлён');
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Сбросить к \$10,000'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.down),
                  onPressed: () async {
                    final ok = await _confirm('Сбросить демо-счёт?',
                        'Баланс вернётся к \$10,000, все позиции и история будут удалены.');
                    if (ok) engine.resetAccount();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}

// ── Экран управления алертами ──

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<PriceAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _alerts = NotificationService.getAll());

  Future<void> _addAlert() async {
    final symbolCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    AlertType type = AlertType.priceAbove;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('Новый алерт'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: symbolCtrl,
                decoration: const InputDecoration(labelText: 'Символ (например BTCUSDT)'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Цена срабатывания'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<AlertType>(
                segments: const [
                  ButtonSegment(value: AlertType.priceAbove, label: Text('Выше')),
                  ButtonSegment(value: AlertType.priceBelow, label: Text('Ниже')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDlg(() => type = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            TextButton(
              onPressed: () async {
                final symbol = symbolCtrl.text.trim().toUpperCase();
                final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
                if (symbol.isEmpty || price == null) return;

                await NotificationService.add(PriceAlert(
                  id: const Uuid().v4(),
                  symbol: symbol,
                  type: type,
                  targetValue: price,
                  createdAt: DateTime.now(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
                _reload();
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Алерты')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: _addAlert,
        child: const Icon(Icons.add),
      ),
      body: _alerts.isEmpty
          ? const Center(child: Text('Нет алертов', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _alerts.length,
              itemBuilder: (ctx, i) {
                final a = _alerts[i];
                return ListTile(
                  tileColor: AppColors.cardBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: Text(a.description),
                  subtitle: Text(
                    a.triggered ? 'Сработал' : (a.active ? 'Активен' : 'Отключён'),
                    style: TextStyle(
                      color: a.triggered
                          ? AppColors.up
                          : (a.active ? Colors.grey : Colors.grey.withOpacity(0.5)),
                      fontSize: 12,
                    ),
                  ),
                  leading: Icon(
                    a.type == AlertType.priceAbove ? Icons.arrow_upward : Icons.arrow_downward,
                    color: a.type == AlertType.priceAbove ? AppColors.up : AppColors.down,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!a.triggered)
                        Switch(
                          value: a.active,
                          onChanged: (v) async {
                            await NotificationService.toggle(a.id, v);
                            _reload();
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        onPressed: () async {
                          await NotificationService.delete(a.id);
                          _reload();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ── Вспомогательные виджеты ──

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  final Color color;
  const _WarningBanner({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
