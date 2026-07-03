import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/demo_trading_engine.dart';
import 'services/settings_service.dart';
import 'services/notification_service.dart';
import 'services/favorites_service.dart';
import 'services/mexc_api_service.dart';
import 'bot/bot_engine.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = DemoTradingEngine();
  await engine.init();

  final settingsService = SettingsService();
  await settingsService.init();

  final favoritesService = FavoritesService();
  await favoritesService.init();

  await NotificationService.init();
  await NotificationService.requestPermission();

  final botEngine = BotEngine(MexcApiService(), engine);
  await botEngine.init();

  runApp(MyApp(
    engine: engine,
    settings: settingsService,
    favorites: favoritesService,
    bot: botEngine,
  ));
}

class MyApp extends StatelessWidget {
  final DemoTradingEngine engine;
  final SettingsService settings;
  final FavoritesService favorites;
  final BotEngine bot;

  const MyApp({
    super.key,
    required this.engine,
    required this.settings,
    required this.favorites,
    required this.bot,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: engine),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: favorites),
        ChangeNotifierProvider.value(value: bot),
      ],
      child: MaterialApp(
        title: 'MEXC Trader',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0E11),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFF0B90B),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0B0E11),
            elevation: 0,
          ),
          cardColor: const Color(0xFF161A1E),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class AppColors {
  static const Color up = Color(0xFF0ECB81);
  static const Color down = Color(0xFFF6465D);
  static const Color accent = Color(0xFFF0B90B);
  static const Color cardBg = Color(0xFF161A1E);
  static const Color background = Color(0xFF0B0E11);
}
