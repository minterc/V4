import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/demo_trading_engine.dart';
import '../services/settings_service.dart';
import '../models/settings_model.dart';
import '../main.dart';
import 'coin_search_screen.dart';
import 'positions_screen.dart';
import 'settings_screen.dart';
import 'bot_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _DashboardTab(),
      const PositionsScreen(),
      const BotScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tabIndex]),
      floatingActionButton: _tabIndex == 0 || _tabIndex == 1
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Новая сделка'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CoinSearchScreen()),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: AppColors.cardBg,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Обзор'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Позиции'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Бот'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<DemoTradingEngine>();
    final settings = context.watch<SettingsService>();
    final isReal = settings.settings.mode == AppMode.real;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Row(
            children: [
              const Text('MEXC Trader'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isReal ? AppColors.down : AppColors.up).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isReal ? AppColors.down : AppColors.up,
                    width: 1,
                  ),
                ),
                child: Text(
                  isReal ? 'REAL' : 'DEMO',
                  style: TextStyle(
                    color: isReal ? AppColors.down : AppColors.up,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          floating: true,
          backgroundColor: AppColors.background,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Баннер предупреждения для реального режима
                if (isReal) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.down.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.down.withOpacity(0.5)),
                    ),
                    child: const Text(
                      '⚠️ Реальный режим активен. Все сделки исполняются на бирже с настоящими деньгами.',
                      style: TextStyle(color: AppColors.down, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Карточка баланса (демо)
                if (!isReal) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Демо-баланс', style: TextStyle(color: Colors.grey, fontSize: 14)),
                        const SizedBox(height: 8),
                        Text(
                          '\$${engine.balanceUsdt.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _StatChip(label: 'Свободно', value: '\$${engine.freeBalance.toStringAsFixed(2)}'),
                            const SizedBox(width: 8),
                            _StatChip(label: 'В позициях', value: '\$${engine.usedMargin.toStringAsFixed(2)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Row(
                  children: [
                    Text(
                      isReal ? 'Открытые ордера' : 'Открытых позиций: ${engine.openPositions.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (!isReal)
                  const Text(
                    'Демо-режим. Реальные деньги не используются — только настоящие котировки с MEXC.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
