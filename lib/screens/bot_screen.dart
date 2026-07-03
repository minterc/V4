import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../bot/bot_engine.dart';
import '../bot/pine_script_interpreter.dart';

class BotScreen extends StatelessWidget {
  const BotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bot = context.watch<BotEngine>();
    final strategies = bot.getStrategies();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Бот'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (bot.status == BotStatus.running ? AppColors.up : Colors.grey).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: bot.status == BotStatus.running ? AppColors.up : Colors.grey),
            ),
            child: Text(
              bot.status == BotStatus.running ? '● РАБОТАЕТ' : '○ ОСТАНОВЛЕН',
              style: TextStyle(
                fontSize: 11,
                color: bot.status == BotStatus.running ? AppColors.up : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'Логи бота',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BotLogsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Новая стратегия'),
        onPressed: () => _showAddStrategy(context, bot),
      ),
      body: strategies.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Нет стратегий', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text(
                    'Создайте стратегию на Pine Script-подобном языке.\nБот будет торговать автоматически.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: strategies.length,
              itemBuilder: (ctx, i) => _StrategyCard(
                strategy: strategies[i],
                bot: bot,
              ),
            ),
    );
  }

  void _showAddStrategy(BuildContext context, BotEngine bot) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StrategyEditorScreen()),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  final BotStrategy strategy;
  final BotEngine bot;

  const _StrategyCard({required this.strategy, required this.bot});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: strategy.enabled
            ? Border.all(color: AppColors.up.withOpacity(0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strategy.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      '${strategy.symbol} • ${strategy.interval} • ${strategy.isDemoMode ? "Demo" : "Real"}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Включить/выключить
              Switch(
                value: strategy.enabled,
                activeColor: AppColors.up,
                onChanged: (v) => bot.toggleStrategy(strategy.id, v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Редактировать
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Скрипт'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  side: BorderSide(color: Colors.grey.withOpacity(0.4)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrategyEditorScreen(existing: strategy),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Запустить один раз (тест)
              OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow_outlined, size: 16),
                label: const Text('Тест'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  side: BorderSide(color: AppColors.accent.withOpacity(0.6)),
                  foregroundColor: AppColors.accent,
                ),
                onPressed: () async {
                  final result = await bot.runOnce(strategy);
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: AppColors.cardBg,
                        title: const Text('Результат теста'),
                        content: SingleChildScrollView(
                          child: Text(
                            result.logs.isEmpty
                                ? 'Сигнал: ${result.signal.name}\nLogs: пусто'
                                : result.logs.join('\n'),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
              const Spacer(),
              // Удалить
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: AppColors.cardBg,
                      title: const Text('Удалить стратегию?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                            child: const Text('Удалить', style: TextStyle(color: AppColors.down))),
                      ],
                    ),
                  );
                  if (ok == true) await bot.deleteStrategy(strategy.id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Экран редактора скриптов
class StrategyEditorScreen extends StatefulWidget {
  final BotStrategy? existing;
  const StrategyEditorScreen({super.key, this.existing});

  @override
  State<StrategyEditorScreen> createState() => _StrategyEditorScreenState();
}

class _StrategyEditorScreenState extends State<StrategyEditorScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _symbolCtrl;
  late TextEditingController _scriptCtrl;
  String _interval = '15m';
  bool _isDemoMode = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? 'Моя стратегия');
    _symbolCtrl = TextEditingController(text: widget.existing?.symbol ?? 'BTCUSDT');
    _scriptCtrl = TextEditingController(text: widget.existing?.script ?? _defaultScript);
    _interval = widget.existing?.interval ?? '15m';
    _isDemoMode = widget.existing?.isDemoMode ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _scriptCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bot = context.read<BotEngine>();
    if (widget.existing != null) {
      widget.existing!.name = _nameCtrl.text.trim();
      widget.existing!.symbol = _symbolCtrl.text.trim().toUpperCase();
      widget.existing!.interval = _interval;
      widget.existing!.script = _scriptCtrl.text;
      widget.existing!.isDemoMode = _isDemoMode;
      await bot.updateStrategy(widget.existing!);
    } else {
      await bot.addStrategy(
        name: _nameCtrl.text.trim(),
        symbol: _symbolCtrl.text.trim().toUpperCase(),
        interval: _interval,
        script: _scriptCtrl.text,
        isDemoMode: _isDemoMode,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'Редактор стратегии' : 'Новая стратегия'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Настройки стратегии
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.cardBg,
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _symbolCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Символ',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  )),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  // Таймфрейм
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _interval,
                    decoration: const InputDecoration(
                      labelText: 'Таймфрейм',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: ['1m', '5m', '15m', '1h', '4h', '1d']
                        .map((tf) => DropdownMenuItem(value: tf, child: Text(tf)))
                        .toList(),
                    onChanged: (v) => setState(() => _interval = v!),
                  )),
                  const SizedBox(width: 8),
                  // Режим
                  Expanded(child: DropdownButtonFormField<bool>(
                    value: _isDemoMode,
                    decoration: const InputDecoration(
                      labelText: 'Режим',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Demo')),
                      DropdownMenuItem(value: false, child: Text('Real ⚠️')),
                    ],
                    onChanged: (v) => setState(() => _isDemoMode = v!),
                  )),
                ]),
              ],
            ),
          ),

          // Панель инструментов редактора
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              const Text('Pine Script', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.quiz_outlined, size: 16),
                label: const Text('Справка'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                onPressed: () => _showHelp(context),
              ),
              TextButton.icon(
                icon: _testing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 16, color: AppColors.accent),
                label: const Text('Тест'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                onPressed: _testing ? null : () => _runTest(context),
              ),
            ]),
          ),

          // Результат теста
          if (_testResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: AppColors.cardBg,
              child: Text(
                _testResult!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.up),
              ),
            ),

          // Редактор скрипта
          Expanded(
            child: TextField(
              controller: _scriptCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(12),
                border: InputBorder.none,
                fillColor: Color(0xFF0D1117),
                filled: true,
              ),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runTest(BuildContext context) async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final bot = context.read<BotEngine>();
      final tempStrategy = BotStrategy(
        id: 'test',
        name: 'test',
        symbol: _symbolCtrl.text.trim().toUpperCase(),
        interval: _interval,
        script: _scriptCtrl.text,
        isDemoMode: true,
        createdAt: DateTime.now(),
      );
      final result = await bot.runOnce(tempStrategy);
      setState(() {
        _testResult = [
          '▶ Тест на ${_symbolCtrl.text.toUpperCase()} ${_interval}',
          '◆ Сигнал: ${result.signal.name}',
          if (result.qty != null) '◆ Объём: \$${result.qty!.toStringAsFixed(2)}',
          if (result.stopLoss != null) '◆ SL: ${result.stopLoss}${result.stopLossIsPercent ? "%" : ""}',
          if (result.takeProfit != null) '◆ TP: ${result.takeProfit}${result.takeProfitIsPercent ? "%" : ""}',
          '─────────',
          ...result.logs,
        ].join('\n');
      });
    } catch (e) {
      setState(() => _testResult = '❌ Ошибка: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Справка по скрипту'),
        content: SingleChildScrollView(
          child: Text(_helpText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

/// Экран логов бота
class BotLogsScreen extends StatelessWidget {
  const BotLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bot = context.watch<BotEngine>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи бота'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => bot.clearLogs(),
          ),
        ],
      ),
      body: bot.logs.isEmpty
          ? const Center(child: Text('Логов пока нет', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: bot.logs.length,
              itemBuilder: (ctx, i) {
                final log = bot.logs[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${log.time.hour.toString().padLeft(2,'0')}:${log.time.minute.toString().padLeft(2,'0')}',
                        style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 8),
                      Text('[${log.symbol}]',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          )),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.message,
                          style: TextStyle(
                            color: log.isError ? AppColors.down : Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

const _defaultScript = '''
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

// Сигналы входа и выхода
buy = rsi < rsiOversold and close > ma20
sell = rsi > rsiOverbought

// Торговля
if buy
    strategy.entry("Long", strategy.long, qty=orderSize)
    strategy.exit("Exit", "Long", profit=5, loss=2)

if sell
    strategy.close("Long")
''';

const _helpText = '''
ПОДДЕРЖИВАЕМЫЕ ФУНКЦИИ:

Индикаторы:
  ta.rsi(src, period)
  ta.sma(src, period)
  ta.ema(src, period)
  ta.stoch(k, smooth, d)
  [upper, mid, lower] = ta.bb(src, period, mult)
  [macd, signal, hist] = ta.macd(src, fast, slow, signal)
  ta.crossover(series1, series2)
  ta.crossunder(series1, series2)
  ta.highest(src, period)
  ta.lowest(src, period)

Переменные цены:
  close, open, high, low, volume

Торговля:
  strategy.entry("id", strategy.long, qty=100)
  strategy.entry("id", strategy.short, qty=100)
  strategy.close("id")
  strategy.exit("id", "from", profit=5, loss=2)
    (profit/loss в % от позиции)

Логика:
  if условие
      действие
  
  and, or, not
  >, <, >=, <=, ==, !=

Пример (RSI + SMA):
  rsi = ta.rsi(close, 14)
  ma = ta.sma(close, 20)
  if rsi < 30 and close > ma
      strategy.entry("L", strategy.long, qty=100)
  if rsi > 70
      strategy.close("L")
''';
