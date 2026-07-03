import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/symbol_model.dart';

/// Сервис работы с публичным (не требующим ключей) API MEXC.
/// Используется только для получения реальных котировок —
/// никакие реальные сделки через него не выполняются.
class MexcApiService {
  static const String _restBase = 'https://api.mexc.com';
  static const String _wsBase = 'wss://wbs-api.mexc.com/ws';

  /// Получить список всех доступных спот-пар (для поиска монет)
  Future<List<Symbol>> fetchAllSymbols() async {
    final uri = Uri.parse('$_restBase/api/v3/exchangeInfo');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить список монет: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final symbolsJson = data['symbols'] as List<dynamic>;

    // Примечание: поле isSpotTradingAllowed у MEXC ненадёжно (известный баг —
    // может быть false даже для активно торгуемых пар вроде BTCUSDT).
    // Поэтому фильтруем только по валюте котировки (USDT) и наличию статуса,
    // отличного от явно отключённого/делистнутого.
    return symbolsJson
        .where((s) {
          final quote = s['quoteAsset'] == 'USDT';
          final status = s['status']?.toString().toUpperCase() ?? '';
          final notDisabled = status != 'OFFLINE' && status != 'DELISTED' && status != '0';
          return quote && notDisabled;
        })
        .map((s) => Symbol.fromSpotJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Текущая цена одной пары
  Future<double> fetchPrice(String symbol) async {
    final uri = Uri.parse('$_restBase/api/v3/ticker/price?symbol=$symbol');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить цену для $symbol');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return double.parse(data['price'].toString());
  }

  /// Цены сразу всех пар (используется на экране поиска/списка монет)
  Future<Map<String, double>> fetchAllPrices() async {
    final uri = Uri.parse('$_restBase/api/v3/ticker/price');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить цены');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final Map<String, double> prices = {};
    for (final item in data) {
      prices[item['symbol']] = double.parse(item['price'].toString());
    }
    return prices;
  }

  /// Получить свечи (для графика). interval: 1m, 5m, 15m, 1h, 4h, 1d
  Future<List<Candle>> fetchKlines(
    String symbol, {
    String interval = '15m',
    int limit = 200,
  }) async {
    final uri = Uri.parse(
      '$_restBase/api/v3/klines?symbol=$symbol&interval=$interval&limit=$limit',
    );
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить свечи для $symbol');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((raw) => Candle.fromMexcArray(raw as List<dynamic>)).toList();
  }

  /// Живой поток цены через WebSocket (для обновления в реальном времени).
  /// Возвращает Stream<double> с ценой последней сделки.
  Stream<double> subscribeToPriceStream(String symbol) {
    final channel = WebSocketChannel.connect(Uri.parse(_wsBase));
    final lowerSymbol = symbol.toUpperCase();

    final subscribeMsg = jsonEncode({
      "method": "SUBSCRIPTION",
      "params": ["spot@public.deals.v3.api@$lowerSymbol"],
    });
    channel.sink.add(subscribeMsg);

    final controller = StreamController<double>();

    channel.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message as String);
          // Структура ответа deals: {"d":{"deals":[{"p":"...","v":"..."}]},...}
          final deals = decoded['d']?['deals'] as List<dynamic>?;
          if (deals != null && deals.isNotEmpty) {
            final price = double.parse(deals.last['p'].toString());
            controller.add(price);
          }
        } catch (_) {
          // Игнорируем служебные сообщения (ping/pong, подтверждения подписки)
        }
      },
      onError: (e) => controller.addError(e),
      onDone: () => controller.close(),
    );

    controller.onCancel = () {
      channel.sink.close();
    };

    return controller.stream;
  }
}
