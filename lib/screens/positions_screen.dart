import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/position_model.dart';
import '../services/demo_trading_engine.dart';
import '../services/mexc_api_service.dart';
import '../main.dart';

class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> with SingleTickerProviderStateMixin {
  final _api = MexcApiService();
  final Map<String, double> _livePrices = {};
  Timer? _refreshTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshPrices();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPrices());
  }

  Future<void> _refreshPrices() async {
    final engine = context.read<DemoTradingEngine>();
    final symbols = engine.openPositions.map((p) => p.symbol).toSet();
    if (symbols.isEmpty) return;

    for (final symbol in symbols) {
      try {
        final price = await _api.fetchPrice(symbol);
        if (mounted) {
          setState(() => _livePrices[symbol] = price);
        }
        engine.checkPositionTriggers(symbol, price);
      } catch (_) {
        // Игнорируем единичные сбои сети — попробуем на следующем тике
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<DemoTradingEngine>();

    return Column(
      children: [
        AppBar(
          title: const Text('Позиции'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Открытые'),
              Tab(text: 'История'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOpenList(engine),
              _buildHistoryList(engine),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOpenList(DemoTradingEngine engine) {
    final positions = engine.openPositions;
    if (positions.isEmpty) {
      return const Center(
        child: Text('Нет открытых позиций', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: positions.length,
      itemBuilder: (context, index) {
        final p = positions[index];
        final currentPrice = _livePrices[p.symbol] ?? p.entryPrice;
        final pnl = p.unrealizedPnl(currentPrice);
        final pnlPercent = p.unrealizedPnlPercent(currentPrice);
        final isProfit = pnl >= 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (p.side == PositionSide.long ? AppColors.up : AppColors.down)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.type == PositionType.spot
                              ? 'СПОТ'
                              : '${p.side == PositionSide.long ? "LONG" : "SHORT"} ${p.leverage}x',
                          style: TextStyle(
                            color: p.side == PositionSide.long ? AppColors.up : AppColors.down,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(p.symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  TextButton(
                    onPressed: () => engine.closePosition(p.id, currentPrice),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: const Text('Закрыть', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoColumn(label: 'Вход', value: p.entryPrice.toStringAsFixed(2)),
                  _InfoColumn(label: 'Текущая', value: currentPrice.toStringAsFixed(2)),
                  _InfoColumn(label: 'Маржа', value: '\$${p.marginUsdt.toStringAsFixed(2)}'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('PnL', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text(
                        '${isProfit ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isProfit ? AppColors.up : AppColors.down,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${isProfit ? '+' : ''}${pnlPercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: isProfit ? AppColors.up : AppColors.down,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (p.liquidationPrice != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Ликвидация при: \$${p.liquidationPrice!.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryList(DemoTradingEngine engine) {
    final positions = engine.closedPositions;
    if (positions.isEmpty) {
      return const Center(
        child: Text('История пуста', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: positions.length,
      itemBuilder: (context, index) {
        final p = positions[index];
        final pnl = p.closePrice != null ? p.unrealizedPnl(p.closePrice!) : 0.0;
        final isProfit = pnl >= 0;

        return ListTile(
          tileColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          title: Row(
            children: [
              Text(p.symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (p.status == PositionStatus.liquidated)
                const Text('ЛИКВИДАЦИЯ', style: TextStyle(color: Colors.orange, fontSize: 11)),
            ],
          ),
          subtitle: Text(
            '${p.type == PositionType.spot ? "Спот" : "Фьючерсы ${p.leverage}x"} • '
            '${p.closedAt != null ? "${p.closedAt!.day}.${p.closedAt!.month} ${p.closedAt!.hour}:${p.closedAt!.minute.toString().padLeft(2, '0')}" : ""}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            '${isProfit ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
            style: TextStyle(
              color: isProfit ? AppColors.up : AppColors.down,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  const _InfoColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
