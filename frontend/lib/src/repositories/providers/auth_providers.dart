part of '../providers.dart';

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final authSecurityOverviewProvider = FutureProvider<AuthSecurityOverview>((
  ref,
) {
  ref.watch(authControllerProvider);
  return ref.watch(authRepositoryProvider).getSecurityOverview();
});

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.booting();

  Future<void> restore() async {
    state = const AuthState.booting();
    state = await ref.read(authRepositoryProvider).restore();
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> login(String identifier, String password) async {
    state = await ref
        .read(authRepositoryProvider)
        .login(identifier: identifier, password: password);
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> loginWithGoogle() async {
    state = await ref.read(authRepositoryProvider).loginWithGoogle();
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> register(
    String email,
    String password,
    String? displayName,
    String? username,
  ) async {
    state = await ref
        .read(authRepositoryProvider)
        .register(
          email: email,
          password: password,
          displayName: displayName,
          username: username,
        );
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> verifyPasswordRecovery(String email, String tokenHash) async {
    state = await ref
        .read(authRepositoryProvider)
        .verifyPasswordRecovery(email: email, tokenHash: tokenHash);
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> verifyEmailSignup(String email, String tokenHash) async {
    state = await ref
        .read(authRepositoryProvider)
        .verifyEmailSignup(email: email, tokenHash: tokenHash);
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> useAuthSession({
    required String accessToken,
    String? refreshToken,
    int? expiresAt,
  }) async {
    state = await ref
        .read(authRepositoryProvider)
        .useAuthSession(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: expiresAt,
        );
    unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
  }

  Future<void> updatePassword(String password) {
    return ref.read(authRepositoryProvider).updatePassword(password: password);
  }

  Future<void> updatePushNotificationsEnabled(bool enabled) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .updatePushNotificationsEnabled(
          currentUser: currentUser,
          enabled: enabled,
        );
  }

  Future<void> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
  }) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .updateProfile(
          currentUser: currentUser,
          username: username,
          displayName: displayName,
          avatarUrl: avatarUrl,
        );
  }

  Future<void> uploadAvatar(OptimizedAvatar avatar) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .uploadAvatar(
          currentUser: currentUser,
          bytes: avatar.bytes,
          fileName: avatar.fileName,
          contentType: avatar.contentType,
        );
  }

  Future<void> logout() async {
    await ref.read(pushRegistrationServiceProvider).unregisterDevice();
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState.guest();
  }
}
