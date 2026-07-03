import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../services/secure_storage_service.dart';

/// Исключение для ошибок реальной торговли — отдельный тип, чтобы UI
/// мог чётко отличить "ошибка биржи" от "ошибка сети/кода".
class MexcTradingException implements Exception {
  final String message;
  final int? code;
  MexcTradingException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Сервис реальной торговли на MEXC (спот + фьючерсы).
///
/// ВАЖНО: это работает с НАСТОЯЩИМИ деньгами пользователя. MEXC не
/// предоставляет тестовую/песочницу среду — каждый вызов этого сервиса
/// исполняется на реальном рынке. Все вызовы должны проходить через
/// проверки в TradingGuard (лимиты суммы, подтверждение) ДО обращения
/// сюда — этот сервис сам по себе не содержит защитных проверок.
class MexcRealTradingService {
  static const String _spotBase = 'https://api.mexc.com';
  static const String _futuresBase = 'https://contract.mexc.com';

  final SecureStorageService _secureStorage;
  MexcRealTradingService(this._secureStorage);

  Future<({String apiKey, String secretKey})> _getCredentials() async {
    final apiKey = await _secureStorage.getApiKey();
    final secretKey = await _secureStorage.getSecretKey();
    if (apiKey == null || secretKey == null || apiKey.isEmpty || secretKey.isEmpty) {
      throw MexcTradingException(
        'API-ключ не настроен. Добавьте его в Настройках перед реальной торговлей.',
      );
    }
    return (apiKey: apiKey, secretKey: secretKey);
  }

  /// HMAC SHA256 подпись для спот-эндпоинтов (Binance-совместимый формат)
  String _signSpot(String queryString, String secretKey) {
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(queryString);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  // ──────────────────────────── СПОТ ────────────────────────────

  /// Получить баланс спот-счёта
  Future<Map<String, double>> fetchSpotBalances() async {
    final creds = await _getCredentials();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final query = 'timestamp=$timestamp&recvWindow=5000';
    final signature = _signSpot(query, creds.secretKey);

    final uri = Uri.parse('$_spotBase/api/v3/account?$query&signature=$signature');
    final response = await http.get(uri, headers: {'X-MEXC-APIKEY': creds.apiKey});

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw MexcTradingException(
        data['msg']?.toString() ?? 'Ошибка получения баланса',
        code: data['code'],
      );
    }

    final balances = <String, double>{};
    for (final b in (data['balances'] as List<dynamic>)) {
      final free = double.tryParse(b['free'].toString()) ?? 0;
      if (free > 0) balances[b['asset']] = free;
    }
    return balances;
  }

  /// Разместить спот-ордер.
  /// type: 'MARKET' или 'LIMIT'. side: 'BUY' или 'SELL'.
  /// Для MARKET ордера price не передаётся.
  Future<Map<String, dynamic>> placeSpotOrder({
    required String symbol,
    required String side, // BUY | SELL
    required String type, // MARKET | LIMIT
    required double quantity,
    double? price,
  }) async {
    final creds = await _getCredentials();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final params = <String, String>{
      'symbol': symbol,
      'side': side,
      'type': type,
      'quantity': quantity.toString(),
      if (type == 'LIMIT' && price != null) 'price': price.toString(),
      if (type == 'LIMIT') 'timeInForce': 'GTC',
      'recvWindow': '5000',
      'timestamp': timestamp.toString(),
    };

    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final signature = _signSpot(query, creds.secretKey);

    final uri = Uri.parse('$_spotBase/api/v3/order');
    final response = await http.post(
      uri,
      headers: {
        'X-MEXC-APIKEY': creds.apiKey,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: '$query&signature=$signature',
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw MexcTradingException(
        data['msg']?.toString() ?? 'Ошибка размещения ордера',
        code: data['code'],
      );
    }
    return data as Map<String, dynamic>;
  }

  /// Поставить SL или TP как отдельный стоп-ордер (спот:
  /// STOP_LOSS_LIMIT / TAKE_PROFIT_LIMIT)
  Future<Map<String, dynamic>> placeSpotStopOrder({
    required String symbol,
    required String side,
    required double quantity,
    required double stopPrice,
    required double limitPrice,
    required bool isStopLoss,
  }) async {
    final creds = await _getCredentials();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final params = <String, String>{
      'symbol': symbol,
      'side': side,
      'type': isStopLoss ? 'STOP_LOSS_LIMIT' : 'TAKE_PROFIT_LIMIT',
      'quantity': quantity.toString(),
      'price': limitPrice.toString(),
      'stopPrice': stopPrice.toString(),
      'timeInForce': 'GTC',
      'recvWindow': '5000',
      'timestamp': timestamp.toString(),
    };

    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final signature = _signSpot(query, creds.secretKey);

    final uri = Uri.parse('$_spotBase/api/v3/order');
    final response = await http.post(
      uri,
      headers: {
        'X-MEXC-APIKEY': creds.apiKey,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: '$query&signature=$signature',
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw MexcTradingException(
        data['msg']?.toString() ?? 'Ошибка размещения стоп-ордера',
        code: data['code'],
      );
    }
    return data as Map<String, dynamic>;
  }

  /// Получить список открытых ордеров
  Future<List<dynamic>> fetchOpenOrders(String symbol) async {
    final creds = await _getCredentials();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final query = 'symbol=$symbol&timestamp=$timestamp&recvWindow=5000';
    final signature = _signSpot(query, creds.secretKey);

    final uri = Uri.parse('$_spotBase/api/v3/openOrders?$query&signature=$signature');
    final response = await http.get(uri, headers: {'X-MEXC-APIKEY': creds.apiKey});

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw MexcTradingException(data['msg']?.toString() ?? 'Ошибка получения ордеров');
    }
    return data as List<dynamic>;
  }

  /// Отменить ордер
  Future<void> cancelOrder({required String symbol, required String orderId}) async {
    final creds = await _getCredentials();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final query = 'symbol=$symbol&orderId=$orderId&timestamp=$timestamp&recvWindow=5000';
    final signature = _signSpot(query, creds.secretKey);

    final uri = Uri.parse('$_spotBase/api/v3/order?$query&signature=$signature');
    final response = await http.delete(uri, headers: {'X-MEXC-APIKEY': creds.apiKey});

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw MexcTradingException(data['msg']?.toString() ?? 'Ошибка отмены ордера');
    }
  }

  // ──────────────────────────── ФЬЮЧЕРСЫ ────────────────────────────
  // Примечание: фьючерсный API MEXC использует другую схему подписи
  // (заголовки ApiKey / Request-Time / Signature вместо query-параметров).
  // Так как это финансово-критичный код, перед боевым использованием
  // ОБЯЗАТЕЛЬНО сверьте детали с актуальной документацией MEXC Futures —
  // схема могла измениться.

  String _signFutures(String accessKey, String requestTime, String paramsString, String secretKey) {
    // Согласно документации MEXC Futures: подписываемая строка =
    // accessKey + requestTime + paramsString
    final target = '$accessKey$requestTime$paramsString';
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(target);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  /// Разместить фьючерсный ордер с плечом.
  /// side: 1 = открыть лонг, 2 = закрыть шорт, 3 = открыть шорт, 4 = закрыть лонг
  Future<Map<String, dynamic>> placeFuturesOrder({
    required String symbol, // например BTC_USDT (с подчёркиванием для фьючерсов)
    required int side,
    required double vol, // объём в контрактах
    required int leverage,
    double? price, // null = рыночный ордер
    int openType = 1, // 1 = изолированная маржа, 2 = кросс-маржа
  }) async {
    final creds = await _getCredentials();
    final requestTime = DateTime.now().millisecondsSinceEpoch.toString();

    final bodyMap = {
      'symbol': symbol,
      'side': side,
      'openType': openType,
      'type': price == null ? 5 : 1, // 5 = market, 1 = limit
      'vol': vol,
      'leverage': leverage,
      if (price != null) 'price': price,
    };
    final bodyJson = jsonEncode(bodyMap);

    final signature = _signFutures(creds.apiKey, requestTime, bodyJson, creds.secretKey);

    final uri = Uri.parse('$_futuresBase/api/v1/private/order/submit');
    final response = await http.post(
      uri,
      headers: {
        'ApiKey': creds.apiKey,
        'Request-Time': requestTime,
        'Signature': signature,
        'Content-Type': 'application/json',
      },
      body: bodyJson,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw MexcTradingException(
        data['message']?.toString() ?? 'Ошибка размещения фьючерсного ордера',
        code: data['code'],
      );
    }
    return data as Map<String, dynamic>;
  }

  /// Получить баланс фьючерсного счёта
  Future<double> fetchFuturesBalance() async {
    final creds = await _getCredentials();
    final requestTime = DateTime.now().millisecondsSinceEpoch.toString();
    const paramsString = ''; // GET без тела — пустая строка параметров

    final signature = _signFutures(creds.apiKey, requestTime, paramsString, creds.secretKey);

    final uri = Uri.parse('$_futuresBase/api/v1/private/account/asset/USDT');
    final response = await http.get(
      uri,
      headers: {
        'ApiKey': creds.apiKey,
        'Request-Time': requestTime,
        'Signature': signature,
      },
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw MexcTradingException(data['message']?.toString() ?? 'Ошибка получения баланса фьючерсов');
    }
    return double.tryParse(data['data']?['availableBalance']?.toString() ?? '0') ?? 0;
  }
}
