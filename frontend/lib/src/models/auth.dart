class AuthUser {
  const AuthUser({required this.id, this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? json['user_id'] as String? ?? '',
      email: json['email'] as String?,
    );
  }

  final String id;
  final String? email;
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.message,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final session = json['session'] as Map<String, dynamic>?;
    final userJson = json['user'] as Map<String, dynamic>?;
    return AuthSession(
      user: userJson == null ? null : AuthUser.fromJson(userJson),
      accessToken: session?['access_token'] as String? ?? '',
      refreshToken: session?['refresh_token'] as String?,
      expiresAt: session?['expires_at'] as int?,
      message: json['message'] as String?,
    );
  }

  final AuthUser? user;
  final String accessToken;
  final String? refreshToken;
  final int? expiresAt;
  final String? message;
}

class AuthState {
  const AuthState({required this.status, this.user, this.message});

  const AuthState.booting() : this(status: AuthStatus.booting);
  const AuthState.guest({String? message})
    : this(status: AuthStatus.guest, message: message);
  const AuthState.authenticated(AuthUser user)
    : this(status: AuthStatus.authenticated, user: user);

  final AuthStatus status;
  final AuthUser? user;
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

enum AuthStatus { booting, guest, authenticated }
