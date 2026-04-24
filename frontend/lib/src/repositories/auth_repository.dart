import '../core/api_client.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/auth.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokenStore, this._store);

  final TonztoonApi _api;
  final TokenStore _tokenStore;
  final LocalStore _store;

  Future<AuthState> restore() async {
    final token = await _tokenStore.readAccessToken();
    if (token == null || token.isEmpty) {
      return const AuthState.guest();
    }

    try {
      final response = await _api.get<Map<String, dynamic>>('/auth/me');
      final user = AuthUser.fromJson(response.data ?? const {});
      await _store.auth.put('user', {'id': user.id, 'email': user.email});
      return AuthState.authenticated(user);
    } catch (_) {
      await _tokenStore.clear();
      return const AuthState.guest(message: 'Session expired.');
    }
  }

  Future<AuthState> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final session = AuthSession.fromJson(response.data ?? const {});
    return _persistSession(session);
  }

  Future<AuthState> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
    final session = AuthSession.fromJson(response.data ?? const {});
    if (session.accessToken.isEmpty) {
      return AuthState.guest(
        message: session.message ?? 'Please confirm your email before login.',
      );
    }
    return _persistSession(session);
  }

  Future<void> logout() async {
    try {
      await _api.post<Map<String, dynamic>>('/auth/logout');
    } catch (_) {
      // Local logout should still succeed if the server cannot be reached.
    }
    await _tokenStore.clear();
    await _store.auth.clear();
  }

  Future<AuthState> _persistSession(AuthSession session) async {
    if (session.accessToken.isEmpty || session.user == null) {
      return AuthState.guest(
        message: session.message ?? 'Authentication failed.',
      );
    }
    await _tokenStore.save(
      TokenPair(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
      ),
    );
    await _store.auth.put('user', {
      'id': session.user!.id,
      'email': session.user!.email,
    });
    return AuthState.authenticated(session.user!);
  }
}
