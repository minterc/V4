import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';
import '../models/chart_preset_model.dart';
import '../models/symbol_model.dart';

/// Экран TradingView-графика с поддержкой индикаторов, рисования линий
/// и сохранения пресетов.
class ChartScreen extends StatefulWidget {
  final Symbol symbol;
  const ChartScreen({super.key, required this.symbol});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late WebViewController _controller;
  late ChartPreset _preset;
  bool _loading = true;
  bool _presetsOpen = false;
  List<ChartPreset> _savedPresets = [];
  static const String _presetsBox = 'chart_presets_box';
  late Box _box;

  @override
  void initState() {
    super.initState();
    _preset = ChartPreset(
      id: 'current',
      name: 'Текущий',
      symbol: widget.symbol.symbol,
      savedAt: DateTime.now(),
      showVolume: true,
    );
    _initBox();
    _initWebView();
  }

  Future<void> _initBox() async {
    _box = await Hive.openBox(_presetsBox);
    _loadPresets();
  }

  void _loadPresets() {
    setState(() {
      _savedPresets = _box.values
          .map((e) => ChartPreset.fromMap(Map<dynamic, dynamic>.from(e)))
          .where((p) => p.symbol == widget.symbol.symbol)
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    });
  }

  /// Конвертируем таймфрейм в формат TradingView:
  /// 1m→1, 5m→5, 15m→15, 1h→60, 4h→240, 1d→D
  String _tvInterval(String interval) {
    const map = {
      '1m': '1', '5m': '5', '15m': '15', '30m': '30',
      '1h': '60', '4h': '240', '1d': 'D', '1w': 'W',
    };
    return map[interval] ?? '15';
  }

  /// Генерируем HTML со встроенным TradingView Advanced Chart Widget.
  /// Виджет официально бесплатный для личного использования.
  String _buildHtml() {
    // MEXC-формат для TradingView: "MEXC:BTCUSDT"
    final tvSymbol = 'MEXC:${widget.symbol.symbol}';
    final interval = _tvInterval(_preset.interval);
    final theme = 'dark';

    // Список исследований (индикаторов)
    final studies = <String>[];
    if (_preset.showMa20) studies.add('"MASimple@tv-basicstudies"');
    if (_preset.showMa50) studies.add('"MASimple@tv-basicstudies"');
    if (_preset.showEma12 || _preset.showEma26) studies.add('"MAExp@tv-basicstudies"');
    if (_preset.showBollinger) studies.add('"BB@tv-basicstudies"');
    if (_preset.showRsi) studies.add('"RSI@tv-basicstudies"');
    if (_preset.showMacd) studies.add('"MACD@tv-basicstudies"');
    if (_preset.showVolume) studies.add('"Volume@tv-basicstudies"');

    final studiesJson = '[${studies.join(',')}]';

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; background: #0B0E11; overflow: hidden; }
  #tv_chart { width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="tv_chart"></div>
<script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
<script type="text/javascript">
new TradingView.widget({
  "autosize": true,
  "symbol": "$tvSymbol",
  "interval": "$interval",
  "timezone": "Etc/UTC",
  "theme": "$theme",
  "style": "1",
  "locale": "ru",
  "toolbar_bg": "#161A1E",
  "enable_publishing": false,
  "allow_symbol_change": false,
  "container_id": "tv_chart",
  "hide_top_toolbar": false,
  "hide_legend": false,
  "save_image": true,
  "studies": $studiesJson,
  "drawings_access": {
    "type": "all",
    "tools": [{ "name": "Regression Trend" }]
  },
  "overrides": {
    "mainSeriesProperties.candleStyle.upColor": "#0ECB81",
    "mainSeriesProperties.candleStyle.downColor": "#F6465D",
    "mainSeriesProperties.candleStyle.wickUpColor": "#0ECB81",
    "mainSeriesProperties.candleStyle.wickDownColor": "#F6465D"
  }
});
</script>
</body>
</html>
''';
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (e) {
          setState(() => _loading = false);
        },
      ))
      ..loadHtmlString(_buildHtml(), baseUrl: 'https://s3.tradingview.com');
  }

  void _reloadChart() {
    setState(() => _loading = true);
    _controller.loadHtmlString(_buildHtml(), baseUrl: 'https://s3.tradingview.com');
  }

  Future<void> _savePreset() async {
    final nameController = TextEditingController(
      text: '${widget.symbol.baseAsset} ${_preset.interval}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Сохранить пресет'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Название пресета'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final saved = ChartPreset(
      id: const Uuid().v4(),
      name: nameController.text.trim().isEmpty
          ? '${widget.symbol.baseAsset} ${_preset.interval}'
          : nameController.text.trim(),
      symbol: widget.symbol.symbol,
      interval: _preset.interval,
      showMa20: _preset.showMa20,
      showMa50: _preset.showMa50,
      showMa200: _preset.showMa200,
      showEma12: _preset.showEma12,
      showEma26: _preset.showEma26,
      showBollinger: _preset.showBollinger,
      showRsi: _preset.showRsi,
      showMacd: _preset.showMacd,
      showVolume: _preset.showVolume,
      rsiPeriod: _preset.rsiPeriod,
      bollPeriod: _preset.bollPeriod,
      bollStdDev: _preset.bollStdDev,
      savedAt: DateTime.now(),
    );

    await _box.put(saved.id, saved.toMap());
    _loadPresets();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пресет сохранён')),
      );
    }
  }

  void _applyPreset(ChartPreset preset) {
    setState(() {
      _preset.interval = preset.interval;
      _preset.showMa20 = preset.showMa20;
      _preset.showMa50 = preset.showMa50;
      _preset.showMa200 = preset.showMa200;
      _preset.showEma12 = preset.showEma12;
      _preset.showEma26 = preset.showEma26;
      _preset.showBollinger = preset.showBollinger;
      _preset.showRsi = preset.showRsi;
      _preset.showMacd = preset.showMacd;
      _preset.showVolume = preset.showVolume;
      _presetsOpen = false;
    });
    _reloadChart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.symbol.displayName),
        actions: [
          // Кнопка сохранения пресета
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Сохранить пресет',
            onPressed: _savePreset,
          ),
          // Кнопка загрузки пресета
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Мои пресеты',
            onPressed: () => setState(() => _presetsOpen = !_presetsOpen),
          ),
        ],
      ),
      body: Column(
        children: [
          // Панель таймфреймов
          _buildIntervalBar(),
          // Панель индикаторов
          _buildIndicatorsBar(),
          // Список пресетов (сворачиваемый)
          if (_presetsOpen) _buildPresetsList(),
          // TradingView WebView
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalBar() {
    const intervals = ['1m', '5m', '15m', '1h', '4h', '1d'];
    return Container(
      height: 40,
      color: AppColors.cardBg,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: intervals.map((tf) {
          final selected = tf == _preset.interval;
          return GestureDetector(
            onTap: () {
              setState(() => _preset.interval = tf);
              _reloadChart();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                tf,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.grey,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIndicatorsBar() {
    return Container(
      height: 40,
      color: AppColors.background,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _IndChip(label: 'MA20', active: _preset.showMa20, onTap: () {
            setState(() => _preset.showMa20 = !_preset.showMa20);
            _reloadChart();
          }),
          _IndChip(label: 'MA50', active: _preset.showMa50, onTap: () {
            setState(() => _preset.showMa50 = !_preset.showMa50);
            _reloadChart();
          }),
          _IndChip(label: 'EMA', active: _preset.showEma12, onTap: () {
            setState(() => _preset.showEma12 = !_preset.showEma12);
            _reloadChart();
          }),
          _IndChip(label: 'BB', active: _preset.showBollinger, onTap: () {
            setState(() => _preset.showBollinger = !_preset.showBollinger);
            _reloadChart();
          }),
          _IndChip(label: 'RSI', active: _preset.showRsi, onTap: () {
            setState(() => _preset.showRsi = !_preset.showRsi);
            _reloadChart();
          }),
          _IndChip(label: 'MACD', active: _preset.showMacd, onTap: () {
            setState(() => _preset.showMacd = !_preset.showMacd);
            _reloadChart();
          }),
          _IndChip(label: 'Vol', active: _preset.showVolume, onTap: () {
            setState(() => _preset.showVolume = !_preset.showVolume);
            _reloadChart();
          }),
        ],
      ),
    );
  }

  Widget _buildPresetsList() {
    if (_savedPresets.isEmpty) {
      return Container(
        color: AppColors.cardBg,
        padding: const EdgeInsets.all(12),
        child: const Text('Нет сохранённых пресетов', style: TextStyle(color: Colors.grey)),
      );
    }
    return Container(
      color: AppColors.cardBg,
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _savedPresets.length,
        itemBuilder: (ctx, i) {
          final p = _savedPresets[i];
          return GestureDetector(
            onTap: () => _applyPreset(p),
            onLongPress: () async {
              await _box.delete(p.id);
              _loadPresets();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(p.name, style: const TextStyle(fontSize: 13)),
            ),
          );
        },
      ),
    );
  }
}

class _IndChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _IndChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.2) : AppColors.cardBg,
          border: Border.all(
            color: active ? AppColors.accent : Colors.grey.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.accent : Colors.grey,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
