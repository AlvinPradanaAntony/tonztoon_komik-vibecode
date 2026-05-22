import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../core/app_error.dart';
import '../../core/api_client.dart';
import '../../core/app_icons.dart';
import '../../repositories/providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

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
              : 'Login belum berhasil. Periksa email dan password lalu coba lagi.',
        ),
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

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrasi berhasil'),
        content: Text(_registerSuccessMessage(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ke halaman login'),
          ),
        ],
      ),
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
  }) {
    return _showAuthFailureDialog(context, title: title, message: message);
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

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.registerMode, required this.palette});

  final bool registerMode;
  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(AppAssets.logoAppLarge, height: 42, fit: BoxFit.contain),
        const SizedBox(height: 26),
        Text(
          registerMode ? 'Buat akun TonzToon' : 'Masuk ke akun kamu',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w900,
            height: 1.06,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          registerMode
              ? 'Sinkronkan pustaka, riwayat baca, dan preferensi antar perangkat.'
              : 'Lanjutkan membaca, kelola pustaka, dan simpan pengaturan favorit.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.muted,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

Future<void> _showAuthFailureDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String _authErrorMessage(
  Object error, {
  String fallbackMessage = 'Terjadi kesalahan. Silakan coba lagi.',
}) {
  return friendlyErrorMessage(error, fallbackMessage: fallbackMessage);
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.formKey,
    required this.palette,
    required this.registerMode,
    required this.submitting,
    required this.displayNameController,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
    required this.onToggleMode,
    required this.onForgotPassword,
    required this.onGoogle,
    required this.onGuest,
  });

  final GlobalKey<FormState> formKey;
  final _AuthPalette palette;
  final bool registerMode;
  final bool submitting;
  final TextEditingController displayNameController;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;
  final VoidCallback onForgotPassword;
  final VoidCallback onGoogle;
  final VoidCallback onGuest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.shadowAlpha),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: registerMode
                    ? Column(
                        children: [
                          _AuthField(
                            label: 'Nama akun',
                            controller: displayNameController,
                            palette: palette,
                            prefixIcon: TonztoonIcons.user,
                            enabled: !submitting,
                            validator: _validateDisplayName,
                          ),
                          const SizedBox(height: 16),
                          _AuthField(
                            label: 'Username',
                            controller: usernameController,
                            palette: palette,
                            prefixIcon: TonztoonIcons.badge,
                            enabled: !submitting,
                            validator: _validateUsername,
                          ),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              _AuthField(
                label: 'Email',
                controller: emailController,
                palette: palette,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: TonztoonIcons.mail,
                enabled: !submitting,
                validator: _validateEmail,
              ),
              const SizedBox(height: 16),
              _AuthField(
                label: 'Password',
                controller: passwordController,
                palette: palette,
                prefixIcon: TonztoonIcons.lock,
                obscureText: obscurePassword,
                enabled: !submitting,
                validator: _validatePassword,
                suffixIcon: IconButton(
                  tooltip: obscurePassword
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  onPressed: submitting ? null : onTogglePassword,
                  icon: Icon(
                    obscurePassword ? TonztoonIcons.eyeOff : TonztoonIcons.eye,
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: registerMode
                    ? Column(
                        children: [
                          const SizedBox(height: 16),
                          _AuthField(
                            label: 'Konfirmasi password',
                            controller: confirmPasswordController,
                            palette: palette,
                            prefixIcon: TonztoonIcons.keyRound,
                            obscureText: obscureConfirmPassword,
                            enabled: !submitting,
                            validator: (value) => _validateConfirmPassword(
                              value,
                              passwordController.text,
                            ),
                            suffixIcon: IconButton(
                              tooltip: obscureConfirmPassword
                                  ? 'Tampilkan password'
                                  : 'Sembunyikan password',
                              onPressed: submitting
                                  ? null
                                  : onToggleConfirmPassword,
                              icon: Icon(
                                obscureConfirmPassword
                                    ? TonztoonIcons.eyeOff
                                    : TonztoonIcons.eye,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              if (!registerMode) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: submitting ? null : onForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Lupa password?'),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: _AuthSubmitButton(
                  registerMode: registerMode,
                  submitting: submitting,
                  onPressed: submitting ? null : onSubmit,
                ),
              ),
              const SizedBox(height: 18),
              _OrDivider(color: palette.border, textColor: palette.muted),
              const SizedBox(height: 18),
              _SocialButton(
                label: 'Continue with Google',
                onPressed: submitting ? null : onGoogle,
                leading: const _GoogleGlyph(),
              ),
              const SizedBox(height: 10),
              _SocialButton(
                label: 'Continue as Guest',
                onPressed: submitting ? null : onGuest,
                leading: const Icon(TonztoonIcons.chevronRight),
              ),
              const SizedBox(height: 16),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      registerMode ? 'Sudah punya akun?' : 'Belum punya akun?',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: submitting ? null : onToggleMode,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        registerMode ? 'Login' : 'Register',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: submitting ? palette.muted : palette.accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email wajib diisi.';
    final valid = RegExp(
      r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
      caseSensitive: false,
    ).hasMatch(email);
    if (!valid) return 'Format email tidak valid.';
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Password wajib diisi.';
    return null;
  }

  String? _validateDisplayName(String? value) {
    final displayName = value?.trim() ?? '';
    if (displayName.isEmpty) return 'Nama akun wajib diisi.';
    if (displayName.length > 120) return 'Nama akun maksimal 120 karakter.';
    return null;
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Username wajib diisi.';
    if (username.length > 50) return 'Username maksimal 50 karakter.';
    final valid = RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username);
    if (!valid) {
      return 'Username hanya boleh berisi huruf, angka, titik, dash, atau underscore.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Konfirmasi password wajib diisi.';
    if (value != password) return 'Konfirmasi password tidak sama.';
    return null;
  }
}

class _AuthSubmitButton extends StatelessWidget {
  const _AuthSubmitButton({
    required this.registerMode,
    required this.submitting,
    required this.onPressed,
  });

  final bool registerMode;
  final bool submitting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: submitting
            ? SizedBox.square(
                key: const ValueKey('auth-submit-loading'),
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.onPrimary,
                ),
              )
            : Row(
                key: const ValueKey('auth-submit-label'),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    registerMode ? TonztoonIcons.userPlus : TonztoonIcons.login,
                  ),
                  const SizedBox(width: 8),
                  Text(registerMode ? 'Register dengan Email' : 'Login'),
                ],
              ),
      ),
    );
  }
}

String? _validateRecoveryEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Email wajib diisi.';
  final valid = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  ).hasMatch(email);
  if (!valid) return 'Format email tidak valid.';
  return null;
}

String? _validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Password baru wajib diisi.';
  if (password.length < 8) return 'Password minimal 8 karakter.';
  return null;
}

String? _validateConfirmNewPassword(String? value, String password) {
  if ((value ?? '').isEmpty) return 'Konfirmasi password wajib diisi.';
  if (value != password) return 'Konfirmasi password tidak sama.';
  return null;
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _instructionSent = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
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
                  _ForgotPasswordHeader(
                    palette: palette,
                    instructionSent: _instructionSent,
                  ),
                  const SizedBox(height: 26),
                  _ForgotPasswordCard(
                    formKey: _formKey,
                    palette: palette,
                    emailController: _emailController,
                    instructionSent: _instructionSent,
                    submitting: _submitting,
                    errorMessage: _errorMessage,
                    onSubmit: _submit,
                    onEditEmail: () => setState(() {
                      _instructionSent = false;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(TonztoonIcons.chevronLeft, size: 18),
                    label: const Text('Kembali ke login'),
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
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(email: _emailController.text);
      if (!mounted) return;
      setState(() => _instructionSent = true);
    } catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Password reset request failed');
      if (!mounted) return;
      final message = _authErrorMessage(
        error,
        fallbackMessage:
            'Permintaan reset password belum berhasil. Coba beberapa saat lagi.',
      );
      setState(() => _errorMessage = message);
      await _showAuthFailureDialog(
        context,
        title: 'Reset password gagal',
        message: message,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

}

class _ForgotPasswordHeader extends StatelessWidget {
  const _ForgotPasswordHeader({
    required this.palette,
    required this.instructionSent,
  });

  final _AuthPalette palette;
  final bool instructionSent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(AppAssets.logoAppLarge, height: 42, fit: BoxFit.contain),
        const SizedBox(height: 26),
        Text(
          instructionSent ? 'Cek email kamu' : 'Lupa password?',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w900,
            height: 1.06,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          instructionSent
              ? 'Jika email terdaftar, link reset password sudah dikirim lewat Supabase Auth.'
              : 'Masukkan email akun TonzToon. Kami akan mengirim link resmi untuk membuat password baru.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.muted,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ForgotPasswordCard extends StatelessWidget {
  const _ForgotPasswordCard({
    required this.formKey,
    required this.palette,
    required this.emailController,
    required this.instructionSent,
    required this.submitting,
    required this.errorMessage,
    required this.onSubmit,
    required this.onEditEmail,
  });

  final GlobalKey<FormState> formKey;
  final _AuthPalette palette;
  final TextEditingController emailController;
  final bool instructionSent;
  final bool submitting;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onEditEmail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.shadowAlpha),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: instructionSent
              ? _ForgotPasswordSuccess(
                  key: const ValueKey('reset-success'),
                  palette: palette,
                  email: emailController.text,
                  onEditEmail: onEditEmail,
                )
              : _ForgotPasswordForm(
                  key: const ValueKey('reset-form'),
                  formKey: formKey,
                  palette: palette,
                  emailController: emailController,
                  submitting: submitting,
                  errorMessage: errorMessage,
                  onSubmit: onSubmit,
                ),
        ),
      ),
    );
  }
}

class _ForgotPasswordForm extends StatelessWidget {
  const _ForgotPasswordForm({
    super.key,
    required this.formKey,
    required this.palette,
    required this.emailController,
    required this.submitting,
    required this.errorMessage,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final _AuthPalette palette;
  final TextEditingController emailController;
  final bool submitting;
  final String? errorMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResetIconBadge(icon: TonztoonIcons.keyRound, palette: palette),
          const SizedBox(height: 16),
          Text(
            'Reset via email',
            style: theme.textTheme.titleLarge?.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pastikan email masih aktif supaya link reset mudah ditemukan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _AuthField(
            label: 'Email',
            controller: emailController,
            palette: palette,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: TonztoonIcons.mail,
            enabled: !submitting,
            validator: _validateRecoveryEmail,
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            _InlineAuthMessage(message: errorMessage!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(TonztoonIcons.mail),
              label: Text(
                submitting ? 'Mengirim instruksi...' : 'Kirim instruksi reset',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForgotPasswordSuccess extends StatelessWidget {
  const _ForgotPasswordSuccess({
    super.key,
    required this.palette,
    required this.email,
    required this.onEditEmail,
  });

  final _AuthPalette palette;
  final String email;
  final VoidCallback onEditEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetEmail = email.trim().isEmpty ? 'email akun kamu' : email.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResetIconBadge(icon: TonztoonIcons.badgeCheck, palette: palette),
        const SizedBox(height: 16),
        Text(
          'Instruksi reset sudah dikirim',
          style: theme.textTheme.titleLarge?.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Jika akun $targetEmail terdaftar, link pemulihan sudah masuk ke inbox.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        _ResetStep(
          icon: TonztoonIcons.mail,
          title: 'Buka inbox',
          subtitle: 'Cari email dari TonzToon dan buka link reset.',
          palette: palette,
        ),
        const SizedBox(height: 10),
        _ResetStep(
          icon: TonztoonIcons.lock,
          title: 'Buat password baru',
          subtitle: 'Gunakan kombinasi yang mudah kamu ingat dan aman.',
          palette: palette,
        ),
        const SizedBox(height: 10),
        _ResetStep(
          icon: TonztoonIcons.login,
          title: 'Login kembali',
          subtitle: 'Masuk lagi untuk melanjutkan pustaka dan riwayat baca.',
          palette: palette,
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onEditEmail,
            icon: const Icon(TonztoonIcons.pencil),
            label: const Text('Ubah email'),
          ),
        ),
      ],
    );
  }
}

class _ResetIconBadge extends StatelessWidget {
  const _ResetIconBadge({required this.icon, required this.palette});

  final IconData icon;
  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.13),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 54,
        child: Icon(icon, color: palette.accent, size: 26),
      ),
    );
  }
}

class _ResetStep extends StatelessWidget {
  const _ResetStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 38,
                child: Icon(icon, size: 18, color: palette.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineAuthMessage extends StatelessWidget {
  const _InlineAuthMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              TonztoonIcons.warning,
              color: colorScheme.onErrorContainer,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _ResetPasswordForm extends StatelessWidget {
  const _ResetPasswordForm({
    required this.formKey,
    required this.palette,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.needsEmail,
    required this.submitting,
    required this.errorMessage,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final _AuthPalette palette;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool needsEmail;
  final bool submitting;
  final String? errorMessage;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResetIconBadge(icon: TonztoonIcons.shieldCheck, palette: palette),
          if (needsEmail) ...[
            const SizedBox(height: 18),
            _AuthField(
              label: 'Email',
              controller: emailController,
              palette: palette,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: TonztoonIcons.mail,
              enabled: !submitting,
              validator: _validateRecoveryEmail,
            ),
          ],
          const SizedBox(height: 18),
          _AuthField(
            label: 'Password baru',
            controller: passwordController,
            palette: palette,
            prefixIcon: TonztoonIcons.lock,
            obscureText: obscurePassword,
            enabled: !submitting,
            validator: _validateNewPassword,
            suffixIcon: IconButton(
              tooltip: obscurePassword
                  ? 'Tampilkan password'
                  : 'Sembunyikan password',
              onPressed: submitting ? null : onTogglePassword,
              icon: Icon(
                obscurePassword ? TonztoonIcons.eyeOff : TonztoonIcons.eye,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AuthField(
            label: 'Konfirmasi password baru',
            controller: confirmPasswordController,
            palette: palette,
            prefixIcon: TonztoonIcons.keyRound,
            obscureText: obscureConfirmPassword,
            enabled: !submitting,
            validator: (value) =>
                _validateConfirmNewPassword(value, passwordController.text),
            suffixIcon: IconButton(
              tooltip: obscureConfirmPassword
                  ? 'Tampilkan password'
                  : 'Sembunyikan password',
              onPressed: submitting ? null : onToggleConfirmPassword,
              icon: Icon(
                obscureConfirmPassword
                    ? TonztoonIcons.eyeOff
                    : TonztoonIcons.eye,
              ),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            _InlineAuthMessage(message: errorMessage!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(TonztoonIcons.check),
              label: Text(
                submitting ? 'Memperbarui password...' : 'Simpan password baru',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetPasswordSuccess extends StatelessWidget {
  const _ResetPasswordSuccess({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResetIconBadge(icon: TonztoonIcons.badgeCheck, palette: palette),
        const SizedBox(height: 16),
        Text(
          'Password baru tersimpan',
          style: theme.textTheme.titleLarge?.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sesi akun sudah aktif. Kamu dapat melanjutkan membaca atau membuka pengaturan akun.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

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

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    required this.palette,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.enabled = true,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final _AuthPalette palette;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool enabled;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: TextInputAction.next,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(prefixIcon),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: palette.input,
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(palette.accent),
      ),
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: color, width: 1.4),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.color, required this.textColor});

  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.leading,
    required this.onPressed,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(dimension: 20, child: Center(child: leading)),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'lib/src/assets/google_logo.svg',
      width: 18,
      height: 18,
    );
  }
}

class _AuthPalette {
  const _AuthPalette({
    required this.background,
    required this.surface,
    required this.input,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
    required this.shadowAlpha,
  });

  final Color background;
  final Color surface;
  final Color input;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;
  final double shadowAlpha;

  factory _AuthPalette.fromTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return _AuthPalette(
      background: theme.scaffoldBackgroundColor,
      surface: colorScheme.surface,
      input: colorScheme.surfaceContainerHighest,
      text: colorScheme.onSurface,
      muted: colorScheme.onSurfaceVariant,
      border: colorScheme.outlineVariant,
      accent: colorScheme.primary,
      shadowAlpha: isDark ? 0.30 : 0.08,
    );
  }
}

SystemUiOverlayStyle _authSystemOverlayStyle(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: theme.scaffoldBackgroundColor,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  );
}
