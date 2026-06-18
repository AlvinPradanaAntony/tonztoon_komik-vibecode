part of '../auth_screen.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({
    super.key,
    this.initialEmail = '',
    this.tokenHash,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String initialEmail;
  final String? tokenHash;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresAt;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _submitting = false;
  bool _completed = false;
  bool _sessionReady = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  bool get _hasAccessToken => (widget.accessToken ?? '').trim().isNotEmpty;
  bool get _hasTokenHash => (widget.tokenHash ?? '').trim().isNotEmpty;
  bool get _needsEmailForTokenHash => _hasTokenHash && !_hasAccessToken;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _AuthPalette.fromTheme(theme);
    final overlayStyle = _authSystemOverlayStyle(theme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _leaveRecovery();
        },
        child: Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            systemOverlayStyle: overlayStyle,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                tooltip: 'Kembali',
                onPressed: _leaveRecovery,
                icon: const Icon(TonztoonIcons.arrowBack),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                  children: [
                    Image.asset(AppAssets.logoAppLarge, height: 42),
                    const SizedBox(height: 26),
                    Text(
                      _completed ? 'Password diperbarui' : 'Buat password baru',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w900,
                        height: 1.06,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _completed
                          ? 'Kamu bisa lanjut memakai akun TonzToon dengan password baru.'
                          : 'Gunakan password baru untuk menyelesaikan proses pemulihan akun.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.muted,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 26),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: palette.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: palette.shadowAlpha,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                        child: _completed
                            ? _ResetPasswordSuccess(palette: palette)
                            : _ResetPasswordForm(
                                formKey: _formKey,
                                palette: palette,
                                emailController: _emailController,
                                passwordController: _passwordController,
                                confirmPasswordController:
                                    _confirmPasswordController,
                                needsEmail: _needsEmailForTokenHash,
                                submitting: _submitting,
                                errorMessage: _errorMessage,
                                obscurePassword: _obscurePassword,
                                obscureConfirmPassword: _obscureConfirmPassword,
                                onTogglePassword: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                onToggleConfirmPassword: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                                onSubmit: _submit,
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: _goToAuthFallback,
                      icon: const Icon(TonztoonIcons.login, size: 18),
                      label: Text(_completed ? 'Lanjut ke akun' : 'Kembali'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.accent,
                        textStyle: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _leaveRecovery() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    _goToAuthFallback();
  }

  void _goToAuthFallback() {
    context.go(
      ref.read(authControllerProvider).isAuthenticated ? '/settings' : '/auth',
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await _prepareRecoverySession();
      await ref
          .read(authControllerProvider.notifier)
          .updatePassword(_passwordController.text);
      if (!mounted) return;
      setState(() => _completed = true);
    } catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Password update failed');
      if (!mounted) return;
      final message = _authErrorMessage(
        error,
        fallbackMessage:
            'Password belum dapat diperbarui. Periksa link reset lalu coba lagi.',
      );
      setState(() => _errorMessage = message);
      await _showAuthFailureDialog(
        context,
        title: 'Password gagal diperbarui',
        message: message,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _prepareRecoverySession() async {
    if (_sessionReady || ref.read(authControllerProvider).isAuthenticated) {
      _sessionReady = true;
      return;
    }

    final controller = ref.read(authControllerProvider.notifier);
    if (_hasAccessToken) {
      await controller.useAuthSession(
        accessToken: widget.accessToken!.trim(),
        refreshToken: widget.refreshToken?.trim(),
        expiresAt: widget.expiresAt,
      );
    } else if (_hasTokenHash) {
      await controller.verifyPasswordRecovery(
        _emailController.text.trim(),
        widget.tokenHash!.trim(),
      );
    } else {
      throw ApiException(
        'Link reset tidak lengkap. Minta link baru dari halaman lupa password.',
      );
    }

    if (!ref.read(authControllerProvider).isAuthenticated) {
      throw ApiException('Sesi reset password tidak valid. Minta link baru.');
    }
    _sessionReady = true;
  }
}
