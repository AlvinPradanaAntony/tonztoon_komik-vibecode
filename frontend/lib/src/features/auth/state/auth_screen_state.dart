part of '../auth_screen.dart';

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _registerMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitting = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
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
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          systemOverlayStyle: overlayStyle,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: 'Kembali',
              onPressed: () => Navigator.of(context).pop(),
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
                  _AuthHeader(registerMode: _registerMode, palette: palette),
                  const SizedBox(height: 26),
                  _AuthCard(
                    formKey: _formKey,
                    palette: palette,
                    registerMode: _registerMode,
                    submitting: _submitting,
                    displayNameController: _displayNameController,
                    usernameController: _usernameController,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    confirmPasswordController: _confirmPasswordController,
                    obscurePassword: _obscurePassword,
                    obscureConfirmPassword: _obscureConfirmPassword,
                    onTogglePassword: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    onToggleConfirmPassword: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                    onSubmit: _submitEmail,
                    onToggleMode: () {
                      _formKey.currentState?.reset();
                      setState(() {
                        _registerMode = !_registerMode;
                        _displayNameController.clear();
                        _usernameController.clear();
                        _confirmPasswordController.clear();
                      });
                    },
                    onForgotPassword: () => _openForgotPassword(context),
                    onGoogle: _continueGoogle,
                    onGuest: () => context.go('/'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openForgotPassword(BuildContext context) {
    context.push(
      '/auth/forgot-password?email=${Uri.encodeQueryComponent(_emailController.text)}',
    );
  }

  Future<void> _submitEmail() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _submitting = true);
    final mode = _registerMode;
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (mode) {
        await controller.register(
          _emailController.text.trim(),
          _passwordController.text,
          _displayNameController.text.trim(),
          _usernameController.text.trim(),
        );
      } else {
        await controller.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }
      final auth = ref.read(authControllerProvider);
      if (!auth.isAuthenticated) {
        if (mode) {
          await _handleRegisterPendingConfirmation(auth.message);
          return;
        }
        throw ApiException(
          auth.message ?? 'Login belum berhasil. Silakan coba lagi.',
        );
      }
      ref.invalidate(homeDataProvider);
      if (!mounted) return;
      context.go('/');
    } catch (error, stackTrace) {
      logAppError(
        error,
        stackTrace,
        context: mode ? 'Register email failed' : 'Login email failed',
      );
      if (!mounted) return;
      await _showAuthErrorDialog(
        title: mode ? 'Register gagal' : 'Login gagal',
        message: _authErrorMessage(
          error,
          fallbackMessage: mode
              ? 'Registrasi belum berhasil. Periksa data akun lalu coba lagi.'
              : 'Login belum berhasil. Periksa email/username dan password lalu coba lagi.',
        ),
        showResetPassword: !mode,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _handleRegisterPendingConfirmation(String? message) async {
    if (!mounted) return;
    _formKey.currentState?.reset();
    setState(() {
      _registerMode = false;
      _displayNameController.clear();
      _usernameController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _obscurePassword = true;
      _obscureConfirmPassword = true;
    });

    await showTonztoonNoticeDialog(
      context,
      title: 'Registrasi berhasil',
      message: _registerSuccessMessage(message),
      helperText:
          'Buka email yang kamu daftarkan, lalu klik link konfirmasi sebelum login.',
      helperIcon: TonztoonIcons.mail,
      primaryLabel: 'Ke halaman login',
      variant: TonztoonModalVariant.success,
      art: TonztoonModalArt.sendToEmail,
    );
  }

  String _registerSuccessMessage(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.contains('email confirmation') ||
        normalized.contains('confirm your email')) {
      return 'Akun berhasil dibuat. Silakan cek email untuk konfirmasi, lalu login dengan akun tersebut.';
    }
    return message!.trim();
  }

  Future<void> _showAuthErrorDialog({
    required String title,
    required String message,
    bool showResetPassword = false,
  }) {
    return _showAuthFailureDialog(
      context,
      title: title,
      message: message,
      onForgotPassword: showResetPassword
          ? () => _openForgotPassword(context)
          : null,
    );
  }

  Future<void> _continueGoogle() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).loginWithGoogle();
      final auth = ref.read(authControllerProvider);
      if (!auth.isAuthenticated) {
        throw ApiException(
          auth.message ?? 'Login Google belum berhasil. Silakan coba lagi.',
        );
      }
      ref.invalidate(homeDataProvider);
      if (!mounted) return;
      context.go('/');
    } catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Login Google failed');
      if (!mounted) return;
      await _showAuthErrorDialog(
        title: 'Login Google gagal',
        message: _authErrorMessage(
          error,
          fallbackMessage:
              'Login Google belum berhasil. Periksa akun Google lalu coba lagi.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
