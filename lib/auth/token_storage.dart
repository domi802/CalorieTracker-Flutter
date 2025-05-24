import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _accessKey  = 'accessToken';
  static const _refreshKey = 'refreshToken';

  final _storage = const FlutterSecureStorage();

  Future<void> save(String access, String refresh) async {
    await _storage
      ..write(key: _accessKey,  value: access)
      ..write(key: _refreshKey, value: refresh);
  }

  Future<String?> get access async  => _storage.read(key: _accessKey);
  Future<String?> get refresh async => _storage.read(key: _refreshKey);

  Future<void> clear() => _storage.deleteAll();
}
