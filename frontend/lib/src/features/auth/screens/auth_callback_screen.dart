part of '../auth_screen.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({
    super.key,
    this.callbackType,
    this.email,
    this.callbackError,
    this.tokenHash,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String? callbackType;
  final String? email;
  final String? callbackError;
  final String? tokenHash;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresAt;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _errorMessage;

  bool get _isEmailVerification => widget.callbackType == 'signup';

  String get _loadingTitle =>
      _isEmailVerification ? 'Memverifikasi email' : 'Menyelesaikan login';

  String get _loadingMessage => _isEmailVerification
      ? 'Sebentar, kami sedang mengaktifkan akun kamu.'
      : 'Sebentar, kami sedang memulihkan sesi akun kamu.';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_completeAuthCallback);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _AuthPalette.fromTheme(theme);
    final overlayStyle = _authSystemOverlayStyle(theme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: palette.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ResetIconBadge(
                          icon: _errorMessage == null
                              ? TonztoonIcons.shieldCheck
                              : TonztoonIcons.warning,
                          palette: palette,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage == null
                              ? _loadingTitle
                              : 'Callback auth gagal',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ?? _loadingMessage,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.muted,
                            height: 1.4,
                          ),
                        ),
                        if (_errorMessage == null) ...[
                          const SizedBox(height: 18),
                          const LinearProgressIndicator(),
                        ] else ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => context.go('/auth'),
                              icon: const Icon(TonztoonIcons.login),
                              label: const Text('Kembali ke login'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeAuthCallback() async {
    final callbackError = widget.callbackError?.trim();
    if (callbackError != null && callbackError.isNotEmpty) {
      setState(() {
        _errorMessage = _isEmailVerification
            ? 'Verifikasi email gagal: $callbackError'
            : 'Callback auth gagal: $callbackError';
      });
      return;
    }

    final accessToken = widget.accessToken?.trim();
    final tokenHash = widget.tokenHash?.trim();
    final email = widget.email?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      if (_isEmailVerification &&
          tokenHash != null &&
          tokenHash.isNotEmpty &&
          email != null &&
          email.isNotEmpty) {
        await _verifySignupToken(email: email, tokenHash: tokenHash);
        return;
      }

      setState(() {
        _errorMessage = _isEmailVerification
            ? 'Link verifikasi email tidak lengkap. Minta link baru dari halaman register.'
            : 'Link auth tidak membawa sesi yang valid. Silakan login ulang.';
      });
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .useAuthSession(
            accessToken: accessToken,
            refreshToken: widget.refreshToken?.trim(),
            expiresAt: widget.expiresAt,
          );
      if (!mounted) return;
      context.go('/settings');
    } catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Auth callback session failed');
      if (!mounted) return;
      setState(() {
        _errorMessage = _authErrorMessage(
          error,
          fallbackMessage: 'Tidak dapat memulihkan sesi. Silakan login ulang.',
        );
      });
    }
  }

  Future<void> _verifySignupToken({
    required String email,
    required String tokenHash,
  }) async {
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyEmailSignup(email, tokenHash);
      if (!mounted) return;
      context.go('/settings');
    } catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Email verification failed');
      if (!mounted) return;
      setState(() {
        _errorMessage = _authErrorMessage(
          error,
          fallbackMessage:
              'Tidak dapat memverifikasi email. Silakan minta link baru.',
        );
      });
    }
  }
}
