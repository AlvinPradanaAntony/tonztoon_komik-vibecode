import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenPair {
  const TokenPair({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresAt;
}

abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<int?> readExpiresAt();
  Future<void> save(TokenPair pair);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _expiresAt = 'expires_at';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessToken);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshToken);

  @override
  Future<int?> readExpiresAt() async {
    final value = await _storage.read(key: _expiresAt);
    return value == null ? null : int.tryParse(value);
  }

  @override
  Future<void> save(TokenPair pair) async {
    await _storage.write(key: _accessToken, value: pair.accessToken);
    if (pair.refreshToken != null) {
      await _storage.write(key: _refreshToken, value: pair.refreshToken);
    }
    if (pair.expiresAt != null) {
      await _storage.write(key: _expiresAt, value: '${pair.expiresAt}');
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessToken);
    await _storage.delete(key: _refreshToken);
    await _storage.delete(key: _expiresAt);
  }
}

class MemoryTokenStore implements TokenStore {
  String? accessToken;
  String? refreshToken;
  int? expiresAt;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<int?> readExpiresAt() async => expiresAt;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> save(TokenPair pair) async {
    accessToken = pair.accessToken;
    refreshToken = pair.refreshToken ?? refreshToken;
    expiresAt = pair.expiresAt;
  }
}
