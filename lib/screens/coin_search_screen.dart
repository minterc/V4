import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/symbol_model.dart';
import '../services/mexc_api_service.dart';
import '../services/favorites_service.dart';
import '../services/notification_service.dart';
import '../main.dart';
import 'coin_detail_screen.dart';

class CoinSearchScreen extends StatefulWidget {
  const CoinSearchScreen({super.key});

  @override
  State<CoinSearchScreen> createState() => _CoinSearchScreenState();
}

class _CoinSearchScreenState extends State<CoinSearchScreen>
    with SingleTickerProviderStateMixin {
  final _api = MexcApiService();
  final _searchController = TextEditingController();
  late TabController _tabController;

  List<Symbol> _allSymbols = [];
  Map<String, double> _prices = {};
  Map<String, double> _prevPrices = {};
  List<Symbol> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadData();
    _searchController.addListener(_onSearch);
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final symbols = await _api.fetchAllSymbols();
      final prices = await _api.fetchAllPrices();
      final sorted = [...symbols]..sort((a, b) {
          final aHas = prices.containsKey(a.symbol);
          final bHas = prices.containsKey(b.symbol);
          if (aHas == bHas) return 0;
          return aHas ? -1 : 1;
        });
      setState(() {
        _allSymbols = sorted;
        _prices = prices;
        _filtered = sorted.take(50).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Ошибка загрузки. Проверьте интернет.'; _loading = false; });
    }
  }

  void _onSearch() {
    final q = _searchController.text.trim().toUpperCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _allSymbols.take(50).toList();
      } else {
        var res = _allSymbols
            .where((s) => s.baseAsset.toUpperCase().contains(q) || s.symbol.contains(q))
            .toList();
        res.sort((a, b) {
          final aExact = a.baseAsset.toUpperCase() == q ? 0 : 1;
          final bExact = b.baseAsset.toUpperCase() == q ? 0 : 1;
          return aExact.compareTo(bExact);
        });
        _filtered = res.take(50).toList();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesService>();
    final favSymbols = _allSymbols.where((s) => favorites.isFavorite(s.symbol)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Рынок'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Все монеты'),
            Tab(icon: Icon(Icons.star, size: 18), text: 'Избранное'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка Все монеты
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск: BTC, ETH, SOL...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.cardBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
              if (_error != null)
                Expanded(child: Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _loadData, child: const Text('Повторить')),
                  ],
                ))),
              if (!_loading && _error == null)
                Expanded(child: _buildList(_filtered, favorites)),
            ],
          ),
          // Вкладка Избранное
          favSymbols.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Нет избранных монет', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text('Нажмите ⭐ рядом с монетой чтобы добавить',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : _buildList(favSymbols, favorites),
        ],
      ),
    );
  }

  Widget _buildList(List<Symbol> symbols, FavoritesService favorites) {
    return ListView.builder(
      itemCount: symbols.length,
      itemBuilder: (ctx, i) {
        final s = symbols[i];
        final price = _prices[s.symbol];
        final isFav = favorites.isFavorite(s.symbol);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.cardBg,
            child: Text(
              s.baseAsset.isNotEmpty ? s.baseAsset[0] : '?',
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: price != null
              ? Text('\$${price.toStringAsFixed(price < 1 ? 6 : 2)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Кнопка алерта прямо из списка
              IconButton(
                icon: const Icon(Icons.notifications_none, size: 20, color: Colors.grey),
                tooltip: 'Добавить алерт',
                onPressed: () => _showAlertDialog(ctx, s, price),
              ),
              // Избранное
              IconButton(
                icon: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: isFav ? AppColors.accent : Colors.grey,
                  size: 20,
                ),
                onPressed: () => favorites.toggle(s.symbol),
              ),
            ],
          ),
          onTap: () => Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => CoinDetailScreen(symbol: s)),
          ),
        );
      },
    );
  }

  /// Диалог добавления алерта прямо со страницы монеты — не нужно вводить символ вручную
  void _showAlertDialog(BuildContext ctx, Symbol symbol, double? currentPrice) {
    final priceCtrl = TextEditingController(
      text: currentPrice?.toStringAsFixed(currentPrice < 1 ? 6 : 2) ?? '',
    );
    AlertType type = AlertType.priceAbove;

    showDialog(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: Text('Алерт: ${symbol.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentPrice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Текущая цена: \$${currentPrice.toStringAsFixed(currentPrice < 1 ? 6 : 2)}',
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
                  symbol: symbol.symbol,
                  type: type,
                  targetValue: price,
                  createdAt: DateTime.now(),
                ));
                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Алерт добавлен для ${symbol.displayName}')),
                  );
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}
