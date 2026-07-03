import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';
import '../models/symbol_model.dart';
import '../models/position_model.dart';
import '../models/chart_preset_model.dart';
import '../services/mexc_api_service.dart';
import '../services/demo_trading_engine.dart';
import '../services/favorites_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Объединённый экран монеты: TradingView-график + торговля в одном месте.
/// Переключение через нижние вкладки прямо внутри экрана.
class CoinDetailScreen extends StatefulWidget {
  final Symbol symbol;
  const CoinDetailScreen({super.key, required this.symbol});

  @override
  State<CoinDetailScreen> createState() => _CoinDetailScreenState();
}

class _CoinDetailScreenState extends State<CoinDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = MexcApiService();

  // Цена
  double? _currentPrice;
  double? _priceChangePercent;
  StreamSubscription<double>? _priceSub;
  Timer? _restTimer;
  Timer? _triggerTimer;

  // График
  late WebViewController _webController;
  bool _chartLoading = true;
  late ChartPreset _preset;
  List<ChartPreset> _savedPresets = [];
  static const String _presetsBox = 'chart_presets_box';
  late Box _box;

  // Торговля
  PositionType _posType = PositionType.spot;
  PositionSide _posSide = PositionSide.long;
  int _leverage = 10;
  final _amountCtrl = TextEditingController(text: '100');
  bool _useSl = false;
  bool _useTp = false;
  final _slCtrl = TextEditingController();
  final _tpCtrl = TextEditingController();
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _preset = ChartPreset(
      id: 'current_${widget.symbol.symbol}',
      name: 'Текущий',
      symbol: widget.symbol.symbol,
      savedAt: DateTime.now(),
      showVolume: true,
    );
    _initStorage();
    _initWebView();
    _startPriceUpdates();
  }

  Future<void> _initStorage() async {
    _box = await Hive.openBox(_presetsBox);
    _loadPresets();

    // Восстановить последний пресет для этого символа если есть
    final lastKey = 'last_${widget.symbol.symbol}';
    final raw = _box.get(lastKey);
    if (raw != null) {
      final p = ChartPreset.fromMap(Map<dynamic, dynamic>.from(raw));
      setState(() {
        _preset.interval = p.interval;
        _preset.showMa20 = p.showMa20;
        _preset.showMa50 = p.showMa50;
        _preset.showMa200 = p.showMa200;
        _preset.showEma12 = p.showEma12;
        _preset.showEma26 = p.showEma26;
        _preset.showBollinger = p.showBollinger;
        _preset.showRsi = p.showRsi;
        _preset.showMacd = p.showMacd;
        _preset.showVolume = p.showVolume;
        _preset.showStochastic = p.showStochastic;
      });
      _reloadChart();
    }
  }

  void _loadPresets() {
    setState(() {
      _savedPresets = _box.values
          .where((e) {
            try {
              final p = ChartPreset.fromMap(Map<dynamic, dynamic>.from(e));
              return p.symbol == widget.symbol.symbol && !p.id.startsWith('last_') && !p.id.startsWith('current_');
            } catch (_) { return false; }
          })
          .map((e) => ChartPreset.fromMap(Map<dynamic, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    });
  }

  /// Сохраняем последние настройки индикаторов автоматически
  Future<void> _saveLastPreset() async {
    final lastKey = 'last_${widget.symbol.symbol}';
    await _box.put(lastKey, ChartPreset(
      id: lastKey,
      name: 'last',
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
      showStochastic: _preset.showStochastic,
      savedAt: DateTime.now(),
    ).toMap());
  }

  void _startPriceUpdates() {
    // WebSocket для живой цены
    _priceSub = _api.subscribeToPriceStream(widget.symbol.symbol).listen((p) {
      if (mounted) setState(() => _currentPrice = p);
    });

    // REST fallback каждые 4 сек
    _restTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final p = await _api.fetchPrice(widget.symbol.symbol);
        if (mounted) {
          final prev = _currentPrice;
          setState(() {
            _currentPrice = p;
            if (prev != null) _priceChangePercent = ((p - prev) / prev) * 100;
          });
        }
      } catch (_) {}
    });

    // Проверка SL/TP/ликвидации каждые 2 сек
    _triggerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_currentPrice != null && mounted) {
        context.read<DemoTradingEngine>().checkPositionTriggers(
          widget.symbol.symbol, _currentPrice!,
        );
        NotificationService.checkForSymbol(widget.symbol.symbol, _currentPrice!);
      }
    });

    // Первая загрузка цены
    _api.fetchPrice(widget.symbol.symbol).then((p) {
      if (mounted) setState(() => _currentPrice = p);
    }).catchError((_) {});
  }

  String _tvInterval(String interval) {
    const map = {'1m': '1', '5m': '5', '15m': '15', '30m': '30',
                  '1h': '60', '4h': '240', '1d': 'D', '1w': 'W'};
    return map[interval] ?? '15';
  }

  String _buildHtml() {
    final tvSymbol = 'MEXC:${widget.symbol.symbol}';
    final interval = _tvInterval(_preset.interval);
    final studies = <String>[];
    if (_preset.showMa20) studies.add('"MASimple@tv-basicstudies"');
    if (_preset.showMa50) studies.add('"MASimple@tv-basicstudies"');
    if (_preset.showEma12 || _preset.showEma26) studies.add('"MAExp@tv-basicstudies"');
    if (_preset.showBollinger) studies.add('"BB@tv-basicstudies"');
    if (_preset.showRsi) studies.add('"RSI@tv-basicstudies"');
    if (_preset.showMacd) studies.add('"MACD@tv-basicstudies"');
    if (_preset.showVolume) studies.add('"Volume@tv-basicstudies"');
    if (_preset.showStochastic) studies.add('"Stochastic@tv-basicstudies"');

    return '''<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0">
<style>*{margin:0;padding:0;box-sizing:border-box}html,body{width:100%;height:100%;background:#0B0E11;overflow:hidden}#c{width:100%;height:100%}</style>
</head><body><div id="c"></div>
<script src="https://s3.tradingview.com/tv.js"></script>
<script>
new TradingView.widget({
  "autosize":true,"symbol":"$tvSymbol","interval":"$interval",
  "timezone":"Etc/UTC","theme":"dark","style":"1","locale":"ru",
  "toolbar_bg":"#161A1E","enable_publishing":false,
  "allow_symbol_change":false,"container_id":"c",
  "save_image":true,
  "studies":[${studies.join(',')}],
  "overrides":{
    "mainSeriesProperties.candleStyle.upColor":"#0ECB81",
    "mainSeriesProperties.candleStyle.downColor":"#F6465D",
    "mainSeriesProperties.candleStyle.wickUpColor":"#0ECB81",
    "mainSeriesProperties.candleStyle.wickDownColor":"#F6465D"
  }
});
</script></body></html>''';
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _chartLoading = true),
        onPageFinished: (_) => setState(() => _chartLoading = false),
      ))
      ..loadHtmlString(_buildHtml(), baseUrl: 'https://s3.tradingview.com');
  }

  void _reloadChart() {
    setState(() => _chartLoading = true);
    _webController.loadHtmlString(_buildHtml(), baseUrl: 'https://s3.tradingview.com');
    _saveLastPreset();
  }

  void _toggleIndicator(String key) {
    setState(() {
      switch (key) {
        case 'ma20': _preset.showMa20 = !_preset.showMa20; break;
        case 'ma50': _preset.showMa50 = !_preset.showMa50; break;
        case 'ema': _preset.showEma12 = !_preset.showEma12; break;
        case 'bb': _preset.showBollinger = !_preset.showBollinger; break;
        case 'rsi': _preset.showRsi = !_preset.showRsi; break;
        case 'macd': _preset.showMacd = !_preset.showMacd; break;
        case 'vol': _preset.showVolume = !_preset.showVolume; break;
        case 'stoch': _preset.showStochastic = !_preset.showStochastic; break;
      }
    });
    _reloadChart();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _priceSub?.cancel();
    _restTimer?.cancel();
    _triggerTimer?.cancel();
    _amountCtrl.dispose();
    _slCtrl.dispose();
    _tpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fav = context.watch<FavoritesService>();
    final isFav = fav.isFavorite(widget.symbol.symbol);
    final isUp = (_priceChangePercent ?? 0) >= 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.symbol.displayName, style: const TextStyle(fontSize: 16)),
            if (_currentPrice != null)
              Text(
                '\$${_currentPrice!.toStringAsFixed(_currentPrice! < 1 ? 6 : 2)}'
                '${_priceChangePercent != null ? "  ${isUp ? "+" : ""}${_priceChangePercent!.toStringAsFixed(2)}%" : ""}',
                style: TextStyle(
                  fontSize: 13,
                  color: isUp ? AppColors.up : AppColors.down,
                ),
              ),
          ],
        ),
        actions: [
          // Алерт
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Добавить алерт',
            onPressed: () => _showAlertDialog(),
          ),
          // Избранное
          IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border,
                color: isFav ? AppColors.accent : null),
            onPressed: () => fav.toggle(widget.symbol.symbol),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'График'),
            Tab(text: 'Торговля'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChartTab(),
          _buildTradeTab(),
        ],
      ),
    );
  }

  // ── Вкладка График ──

  Widget _buildChartTab() {
    return Column(
      children: [
        _buildIntervalBar(),
        _buildIndicatorsBar(),
        _buildPresetsBar(),
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _webController),
              if (_chartLoading)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntervalBar() {
    const intervals = ['1m', '5m', '15m', '1h', '4h', '1d'];
    return Container(
      height: 38,
      color: AppColors.cardBg,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: intervals.map((tf) {
                final sel = tf == _preset.interval;
                return GestureDetector(
                  onTap: () { setState(() => _preset.interval = tf); _reloadChart(); },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.center,
                    child: Text(tf, style: TextStyle(
                      color: sel ? Colors.black : Colors.grey,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    )),
                  ),
                );
              }).toList(),
            ),
          ),
          // Кнопка сохранения пресета
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            tooltip: 'Сохранить пресет',
            onPressed: _savePreset,
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorsBar() {
    final inds = [
      ('MA20', 'ma20', _preset.showMa20),
      ('MA50', 'ma50', _preset.showMa50),
      ('EMA', 'ema', _preset.showEma12),
      ('BB', 'bb', _preset.showBollinger),
      ('RSI', 'rsi', _preset.showRsi),
      ('MACD', 'macd', _preset.showMacd),
      ('Vol', 'vol', _preset.showVolume),
      ('Stoch', 'stoch', _preset.showStochastic), // пункт 5
    ];
    return Container(
      height: 36,
      color: AppColors.background,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: inds.map((ind) {
          final (label, key, active) = ind;
          return GestureDetector(
            onTap: () => _toggleIndicator(key),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.accent.withOpacity(0.2) : AppColors.cardBg,
                border: Border.all(
                  color: active ? AppColors.accent : Colors.grey.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(label, style: TextStyle(
                color: active ? AppColors.accent : Colors.grey,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              )),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPresetsBar() {
    if (_savedPresets.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 36,
      color: AppColors.cardBg,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        itemCount: _savedPresets.length,
        itemBuilder: (ctx, i) {
          final p = _savedPresets[i];
          return GestureDetector(
            onTap: () {
              setState(() {
                _preset.interval = p.interval;
                _preset.showMa20 = p.showMa20;
                _preset.showMa50 = p.showMa50;
                _preset.showMa200 = p.showMa200;
                _preset.showEma12 = p.showEma12;
                _preset.showEma26 = p.showEma26;
                _preset.showBollinger = p.showBollinger;
                _preset.showRsi = p.showRsi;
                _preset.showMacd = p.showMacd;
                _preset.showVolume = p.showVolume;
                _preset.showStochastic = p.showStochastic;
              });
              _reloadChart();
            },
            onLongPress: () async {
              await _box.delete(p.id);
              _loadPresets();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(p.name, style: const TextStyle(fontSize: 11)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _savePreset() async {
    final ctrl = TextEditingController(
        text: '${widget.symbol.baseAsset} ${_preset.interval}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Сохранить пресет'),
        content: TextField(controller: ctrl,
            decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final saved = ChartPreset(
      id: const Uuid().v4(),
      name: ctrl.text.trim().isEmpty ? '${widget.symbol.baseAsset} ${_preset.interval}' : ctrl.text.trim(),
      symbol: widget.symbol.symbol,
      interval: _preset.interval,
      showMa20: _preset.showMa20, showMa50: _preset.showMa50,
      showMa200: _preset.showMa200, showEma12: _preset.showEma12,
      showEma26: _preset.showEma26, showBollinger: _preset.showBollinger,
      showRsi: _preset.showRsi, showMacd: _preset.showMacd,
      showVolume: _preset.showVolume, showStochastic: _preset.showStochastic,
      savedAt: DateTime.now(),
    );
    await _box.put(saved.id, saved.toMap());
    _loadPresets();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Пресет сохранён')));
  }

  // ── Вкладка Торговля ──

  Widget _buildTradeTab() {
    final engine = context.watch<DemoTradingEngine>();
    final settings = context.watch<SettingsService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Спот / Фьючерсы
            SegmentedButton<PositionType>(
              segments: const [
                ButtonSegment(value: PositionType.spot, label: Text('Спот')),
                ButtonSegment(value: PositionType.futures, label: Text('Фьючерсы')),
              ],
              selected: {_posType},
              onSelectionChanged: (s) => setState(() => _posType = s.first),
            ),
            const SizedBox(height: 12),

            // Long / Short (фьючерсы)
            if (_posType == PositionType.futures) ...[
              Row(children: [
                Expanded(child: _SideBtn(
                  label: 'Long ↑', color: AppColors.up,
                  selected: _posSide == PositionSide.long,
                  onTap: () => setState(() => _posSide = PositionSide.long),
                )),
                const SizedBox(width: 8),
                Expanded(child: _SideBtn(
                  label: 'Short ↓', color: AppColors.down,
                  selected: _posSide == PositionSide.short,
                  onTap: () => setState(() => _posSide = PositionSide.short),
                )),
              ]),
              const SizedBox(height: 12),
              Text('Плечо: ${_leverage}x',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: _leverage.toDouble().clamp(1, settings.settings.maxLeverage.toDouble()),
                min: 1, max: settings.settings.maxLeverage.toDouble(),
                divisions: settings.settings.maxLeverage - 1,
                activeColor: AppColors.accent,
                label: '${_leverage}x',
                onChanged: (v) => setState(() => _leverage = v.round()),
              ),
            ],

            // Сумма
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _posType == PositionType.spot ? 'Сумма (USDT)' : 'Маржа (USDT)',
                filled: true, fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                suffixText: 'USDT',
              ),
            ),
            const SizedBox(height: 4),
            Text('Свободно: \$${engine.freeBalance.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),

            // Быстрые кнопки % от баланса
            Row(children: [25, 50, 75, 100].map((pct) =>
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    side: BorderSide(color: Colors.grey.withOpacity(0.4)),
                  ),
                  onPressed: () {
                    final amount = engine.freeBalance * pct / 100;
                    _amountCtrl.text = amount.toStringAsFixed(2);
                  },
                  child: Text('$pct%', style: const TextStyle(fontSize: 12)),
                ),
              )),
            ).toList()),
            const SizedBox(height: 12),

            // SL
            SwitchListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              title: const Text('Stop-Loss'),
              value: _useSl,
              onChanged: (v) => setState(() => _useSl = v),
            ),
            if (_useSl) TextField(
              controller: _slCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Цена Stop-Loss',
                filled: true, fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),

            // TP
            SwitchListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              title: const Text('Take-Profit'),
              value: _useTp,
              onChanged: (v) => setState(() => _useTp = v),
            ),
            if (_useTp) TextField(
              controller: _tpCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Цена Take-Profit',
                filled: true, fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _posType == PositionType.futures && _posSide == PositionSide.short
                      ? AppColors.down : AppColors.up,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _placing || _currentPrice == null ? null : _openPosition,
                child: _placing
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _posType == PositionType.spot ? 'Купить'
                            : _posSide == PositionSide.long ? 'Открыть Long ↑' : 'Открыть Short ↓',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPosition() {
    final engine = context.read<DemoTradingEngine>();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) { _err('Введите корректную сумму'); return; }

    double? sl, tp;
    if (_useSl) { sl = double.tryParse(_slCtrl.text.replaceAll(',', '.')); if (sl == null) { _err('Неверная цена SL'); return; } }
    if (_useTp) { tp = double.tryParse(_tpCtrl.text.replaceAll(',', '.')); if (tp == null) { _err('Неверная цена TP'); return; } }

    try {
      engine.openPosition(
        symbol: widget.symbol.symbol,
        type: _posType,
        side: _posType == PositionType.spot ? PositionSide.long : _posSide,
        currentPrice: _currentPrice!,
        usdtAmount: amount,
        leverage: _leverage,
        stopLossPrice: sl,
        takeProfitPrice: tp,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Позиция открыта')));
      // Переключаемся на вкладку графика
      _tabController.animateTo(0);
    } catch (e) {
      _err(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.down));
  }

  void _showAlertDialog() {
    final priceCtrl = TextEditingController(
      text: _currentPrice?.toStringAsFixed(_currentPrice! < 1 ? 6 : 2) ?? '');
    AlertType type = AlertType.priceAbove;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: Text('Алерт: ${widget.symbol.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentPrice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Текущая: \$${_currentPrice!.toStringAsFixed(_currentPrice! < 1 ? 6 : 2)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Цена срабатывания'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AlertType>(
                segments: const [
                  ButtonSegment(value: AlertType.priceAbove, label: Text('Выше ↑')),
                  ButtonSegment(value: AlertType.priceBelow, label: Text('Ниже ↓')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDlg(() => type = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Отмена')),
            TextButton(
              onPressed: () async {
                final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
                if (price == null) return;
                await NotificationService.add(PriceAlert(
                  id: const Uuid().v4(),
                  symbol: widget.symbol.symbol,
                  type: type,
                  targetValue: price,
                  createdAt: DateTime.now(),
                ));
                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Алерт добавлен')));
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SideBtn({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : AppColors.background,
          border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? color : Colors.grey,
          fontWeight: FontWeight.w600,
        )),
      ),
    );
  }
}
