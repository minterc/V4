import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/symbol_model.dart';
import '../models/position_model.dart';
import '../services/mexc_api_service.dart';
import '../services/demo_trading_engine.dart';
import '../main.dart';

class TradeScreen extends StatefulWidget {
  final Symbol symbol;
  const TradeScreen({super.key, required this.symbol});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  final _api = MexcApiService();

  List<Candle> _candles = [];
  double? _currentPrice;
  double? _priceChangePercent;
  bool _loadingChart = true;
  String _interval = '15m';

  StreamSubscription<double>? _priceSub;
  Timer? _triggerCheckTimer;
  Timer? _restPriceFallbackTimer;

  // Форма открытия позиции
  PositionType _posType = PositionType.spot;
  PositionSide _posSide = PositionSide.long;
  int _leverage = 10;
  final _amountController = TextEditingController(text: '100');
  bool _useSl = false;
  bool _useTp = false;
  final _slController = TextEditingController();
  final _tpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadChart();
    _subscribeToPrice();

    // Периодическая проверка SL/TP/ликвидации (раз в 2 секунды)
    _triggerCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_currentPrice != null) {
        context
            .read<DemoTradingEngine>()
            .checkPositionTriggers(widget.symbol.symbol, _currentPrice!);
      }
    });

    // Резервное обновление цены через REST на случай проблем с WebSocket
    _restPriceFallbackTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final price = await _api.fetchPrice(widget.symbol.symbol);
        if (mounted) {
          setState(() => _currentPrice = price);
        }
      } catch (_) {
        // Сеть временно недоступна — просто пропускаем тик
      }
    });
  }

  Future<void> _loadChart() async {
    setState(() => _loadingChart = true);
    try {
      final candles =
          await _api.fetchKlines(widget.symbol.symbol, interval: _interval, limit: 100);
      final price = await _api.fetchPrice(widget.symbol.symbol);
      setState(() {
        _candles = candles;
        _currentPrice = price;
        if (candles.length > 1) {
          final first = candles.first.close;
          _priceChangePercent = ((price - first) / first) * 100;
        }
        _loadingChart = false;
      });
    } catch (e) {
      setState(() => _loadingChart = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить график')),
        );
      }
    }
  }

  void _subscribeToPrice() {
    _priceSub = _api.subscribeToPriceStream(widget.symbol.symbol).listen((price) {
      if (mounted) {
        setState(() => _currentPrice = price);
      }
    });
  }

  @override
  void dispose() {
    _priceSub?.cancel();
    _triggerCheckTimer?.cancel();
    _restPriceFallbackTimer?.cancel();
    _amountController.dispose();
    _slController.dispose();
    _tpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<DemoTradingEngine>();
    final isUp = (_priceChangePercent ?? 0) >= 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol.displayName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Текущая цена
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _currentPrice != null
                      ? '\$${_currentPrice!.toStringAsFixed(_currentPrice! < 1 ? 6 : 2)}'
                      : '...',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                if (_priceChangePercent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${isUp ? '+' : ''}${_priceChangePercent!.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: isUp ? AppColors.up : AppColors.down,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Выбор таймфрейма
            Wrap(
              spacing: 8,
              children: ['1m', '5m', '15m', '1h', '4h', '1d'].map((tf) {
                final selected = tf == _interval;
                return ChoiceChip(
                  label: Text(tf),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _interval = tf);
                    _loadChart();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // График
            SizedBox(
              height: 250,
              child: _loadingChart
                  ? const Center(child: CircularProgressIndicator())
                  : _buildChart(),
            ),
            const SizedBox(height: 24),

            // Форма открытия позиции
            _buildOrderForm(engine),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_candles.isEmpty) {
      return const Center(child: Text('Нет данных графика'));
    }

    final spots = _candles
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.close))
        .toList();

    final minY = _candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final maxY = _candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: minY * 0.999,
        maxY: maxY * 1.001,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                '\$${s.y.toStringAsFixed(2)}',
                const TextStyle(color: Colors.white),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderForm(DemoTradingEngine engine) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
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

          // Long / Short (только для фьючерсов)
          if (_posType == PositionType.futures)
            Row(
              children: [
                Expanded(
                  child: _SideButton(
                    label: 'Long (вверх)',
                    color: AppColors.up,
                    selected: _posSide == PositionSide.long,
                    onTap: () => setState(() => _posSide = PositionSide.long),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SideButton(
                    label: 'Short (вниз)',
                    color: AppColors.down,
                    selected: _posSide == PositionSide.short,
                    onTap: () => setState(() => _posSide = PositionSide.short),
                  ),
                ),
              ],
            ),
          if (_posType == PositionType.futures) const SizedBox(height: 16),

          // Плечо
          if (_posType == PositionType.futures) ...[
            Text('Плечо: ${_leverage}x', style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: _leverage.toDouble(),
              min: 1,
              max: 125,
              divisions: 124,
              activeColor: AppColors.accent,
              label: '${_leverage}x',
              onChanged: (v) => setState(() => _leverage = v.round()),
            ),
            const SizedBox(height: 8),
          ],

          // Сумма (маржа)
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _posType == PositionType.spot ? 'Сумма (USDT)' : 'Маржа (USDT)',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixText: 'USDT',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Свободно: \$${engine.freeBalance.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // Stop-Loss
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop-Loss'),
            value: _useSl,
            onChanged: (v) => setState(() => _useSl = v),
          ),
          if (_useSl)
            TextField(
              controller: _slController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Цена Stop-Loss',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          const SizedBox(height: 8),

          // Take-Profit
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Take-Profit'),
            value: _useTp,
            onChanged: (v) => setState(() => _useTp = v),
          ),
          if (_useTp)
            TextField(
              controller: _tpController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Цена Take-Profit',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _posType == PositionType.futures && _posSide == PositionSide.short
                    ? AppColors.down
                    : AppColors.up,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _currentPrice == null ? null : _openPosition,
              child: Text(
                _posType == PositionType.spot
                    ? 'Купить'
                    : (_posSide == PositionSide.long ? 'Открыть Long' : 'Открыть Short'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPosition() {
    final engine = context.read<DemoTradingEngine>();
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));

    if (amount == null || amount <= 0) {
      _showError('Введите корректную сумму');
      return;
    }

    double? sl;
    double? tp;
    if (_useSl) {
      sl = double.tryParse(_slController.text.replaceAll(',', '.'));
      if (sl == null) {
        _showError('Введите корректную цену Stop-Loss');
        return;
      }
    }
    if (_useTp) {
      tp = double.tryParse(_tpController.text.replaceAll(',', '.'));
      if (tp == null) {
        _showError('Введите корректную цену Take-Profit');
        return;
      }
    }

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
        const SnackBar(content: Text('Позиция открыта')),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.down),
    );
  }
}

class _SideButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SideButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : AppColors.background,
          border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
