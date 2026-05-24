const Object _authUserUnset = Object();

class AuthUser {
  const AuthUser({
    required this.id,
    this.email,
    this.displayName,
    this.username,
    this.avatarUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final userMetadata = json['user_metadata'] as Map<String, dynamic>?;
    final rawClaims = json['raw_claims'] as Map<String, dynamic>?;
    final rawClaimsMetadata =
        rawClaims?['user_metadata'] as Map<String, dynamic>?;
    return AuthUser(
      id: json['id'] as String? ?? json['user_id'] as String? ?? '',
      email: json['email'] as String?,
      displayName:
          json['display_name'] as String? ??
          userMetadata?['display_name'] as String? ??
          rawClaimsMetadata?['display_name'] as String? ??
          json['name'] as String? ??
          userMetadata?['name'] as String? ??
          rawClaimsMetadata?['name'] as String? ??
          json['full_name'] as String?,
      username:
          json['username'] as String? ??
          userMetadata?['username'] as String? ??
          rawClaimsMetadata?['username'] as String?,
      avatarUrl:
          json['avatar_url'] as String? ??
          userMetadata?['avatar_url'] as String? ??
          rawClaimsMetadata?['avatar_url'] as String? ??
          json['picture'] as String? ??
          userMetadata?['picture'] as String? ??
          rawClaimsMetadata?['picture'] as String?,
    );
  }

  final String id;
  final String? email;
  final String? displayName;
  final String? username;
  final String? avatarUrl;

  AuthUser copyWith({
    String? id,
    Object? email = _authUserUnset,
    Object? displayName = _authUserUnset,
    Object? username = _authUserUnset,
    Object? avatarUrl = _authUserUnset,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email == _authUserUnset ? this.email : email as String?,
      displayName: displayName == _authUserUnset
          ? this.displayName
          : displayName as String?,
      username: username == _authUserUnset
          ? this.username
          : username as String?,
      avatarUrl: avatarUrl == _authUserUnset
          ? this.avatarUrl
          : avatarUrl as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'username': username,
      'avatar_url': avatarUrl,
    };
  }
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

class AuthSecurityOverview {
  const AuthSecurityOverview({
    required this.emailVerified,
    required this.hasPassword,
    required this.currentSession,
    this.email,
    this.provider,
  });

  factory AuthSecurityOverview.fromJson(Map<String, dynamic> json) {
    return AuthSecurityOverview(
      email: json['email'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      hasPassword: json['has_password'] as bool? ?? true,
      provider: json['provider'] as String?,
      currentSession: AuthSecuritySession.fromJson(
        Map<String, dynamic>.from(
          json['current_session'] as Map? ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  final String? email;
  final bool emailVerified;
  final bool hasPassword;
  final String? provider;
  final AuthSecuritySession currentSession;
}

class AuthSecuritySession {
  const AuthSecuritySession({this.sessionId, this.issuedAt, this.expiresAt});

  factory AuthSecuritySession.fromJson(Map<String, dynamic> json) {
    return AuthSecuritySession(
      sessionId: json['session_id'] as String?,
      issuedAt: json['issued_at'] as int?,
      expiresAt: json['expires_at'] as int?,
    );
  }

  final String? sessionId;
  final int? issuedAt;
  final int? expiresAt;

  DateTime? get issuedAtDate => _secondsToDate(issuedAt);
  DateTime? get expiresAtDate => _secondsToDate(expiresAt);

  static DateTime? _secondsToDate(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}
