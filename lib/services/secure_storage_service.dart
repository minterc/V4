import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Безопасное хранение API-ключей MEXC.
/// На Android использует Keystore-backed шифрование, на iOS — Keychain.
/// Ключи НИКОГДА не должны попадать в обычное Hive-хранилище, логи,
/// или передаваться куда-либо, кроме самих запросов к api.mexc.com.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyApiKey = 'mexc_api_key';
  static const _keySecretKey = 'mexc_secret_key';

  Future<void> saveCredentials({
    required String apiKey,
    required String secretKey,
  }) async {
    await _storage.write(key: _keyApiKey, value: apiKey);
    await _storage.write(key: _keySecretKey, value: secretKey);
  }

  Future<String?> getApiKey() => _storage.read(key: _keyApiKey);
  Future<String?> getSecretKey() => _storage.read(key: _keySecretKey);

  Future<bool> hasCredentials() async {
    final key = await getApiKey();
    final secret = await getSecretKey();
    return key != null && key.isNotEmpty && secret != null && secret.isNotEmpty;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keySecretKey);
  }
}
