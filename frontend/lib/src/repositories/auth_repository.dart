import 'dart:typed_data';

import 'package:dio/dio.dart';

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
      final profileUser = await _profileUser(user);
      await _store.auth.put('user', profileUser.toJson());
      return AuthState.authenticated(profileUser);
    } on ApiException catch (error) {
      final cached = _cachedUserState();
      if (error.statusCode == 401) {
        final refreshToken = await _tokenStore.readRefreshToken();
        if (refreshToken != null && refreshToken.isNotEmpty && cached != null) {
          return cached;
        }
        await _tokenStore.clear();
        await _store.auth.clear();
        return const AuthState.guest(message: 'Session expired.');
      }
      if (cached != null) return cached;
      return AuthState.guest(message: error.message);
    } catch (_) {
      return _cachedUserState() ??
          const AuthState.guest(message: 'Unable to restore session.');
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
    String? username,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
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

  Future<void> requestPasswordReset({required String email}) async {
    await _api.post<Map<String, dynamic>>(
      '/auth/password/forgot',
      data: {'email': email.trim()},
    );
  }

  Future<AuthState> verifyPasswordRecovery({
    required String email,
    required String tokenHash,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/password/recovery/verify',
      data: {'email': email.trim(), 'token_hash': tokenHash},
    );
    final session = AuthSession.fromJson(response.data ?? const {});
    return _persistSession(session);
  }

  Future<AuthState> verifyEmailSignup({
    required String email,
    required String tokenHash,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/email/verify',
      data: {'email': email.trim(), 'token_hash': tokenHash},
    );
    final session = AuthSession.fromJson(response.data ?? const {});
    return _persistSession(session);
  }

  Future<AuthState> useAuthSession({
    required String accessToken,
    String? refreshToken,
    int? expiresAt,
  }) async {
    await _tokenStore.save(
      TokenPair(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
      ),
    );
    return restore();
  }

  Future<void> updatePassword({required String password}) async {
    await _api.post<Map<String, dynamic>>(
      '/auth/password/update',
      data: {'password': password},
    );
  }

  Future<AuthSecurityOverview> getSecurityOverview() async {
    final response = await _api.get<Map<String, dynamic>>('/auth/security');
    return AuthSecurityOverview.fromJson(response.data ?? const {});
  }

  Future<AuthState> updateProfile({
    required AuthUser currentUser,
    String? displayName,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;

    final response = await _api.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: data,
    );
    final profile = AuthUser.fromJson(response.data ?? const {});
    final updated = currentUser.copyWith(
      displayName: profile.displayName,
      username: profile.username,
      avatarUrl: profile.avatarUrl,
    );
    await _store.auth.put('user', updated.toJson());
    return AuthState.authenticated(updated);
  }

  Future<AuthState> uploadAvatar({
    required AuthUser currentUser,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/auth/profile/avatar',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      }),
    );
    final profile = AuthUser.fromJson(response.data ?? const {});
    final updated = currentUser.copyWith(
      displayName: profile.displayName,
      username: profile.username,
      avatarUrl: profile.avatarUrl,
    );
    await _store.auth.put('user', updated.toJson());
    return AuthState.authenticated(updated);
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
    final user = await _profileUser(session.user!);
    await _store.auth.put('user', user.toJson());
    return AuthState.authenticated(user);
  }

  Future<AuthUser> _profileUser(AuthUser user) async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/auth/profile');
      final profile = AuthUser.fromJson(response.data ?? const {});
      return user.copyWith(
        displayName: profile.displayName,
        username: profile.username,
        avatarUrl: profile.avatarUrl,
      );
    } catch (_) {
      return user;
    }
  }

  AuthState? _cachedUserState() {
    final raw = _store.auth.get('user');
    if (raw is! Map) return null;

    final user = AuthUser.fromJson(Map<String, dynamic>.from(raw));
    if (user.id.isEmpty) return null;
    return AuthState.authenticated(user);
  }
}
