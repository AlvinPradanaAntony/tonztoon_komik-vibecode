import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../core/app_icons.dart';
import '../../repositories/providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final TextEditingController _emailController = TextEditingController(
    text: 'reader@tonztoon.app',
  );
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _registerMode = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _AuthPalette.fromTheme(Theme.of(context));

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
                  palette: palette,
                  registerMode: _registerMode,
                  emailController: _emailController,
                  passwordController: _passwordController,
                  confirmPasswordController: _confirmPasswordController,
                  rememberMe: _rememberMe,
                  obscurePassword: _obscurePassword,
                  obscureConfirmPassword: _obscureConfirmPassword,
                  onRememberChanged: (value) =>
                      setState(() => _rememberMe = value ?? false),
                  onTogglePassword: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  onToggleConfirmPassword: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                  onSubmit: _submitEmail,
                  onToggleMode: () {
                    setState(() {
                      _registerMode = !_registerMode;
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
    );
  }

  void _openForgotPassword(BuildContext context) {
    context.push(
      '/auth/forgot-password?email=${Uri.encodeQueryComponent(_emailController.text)}',
    );
  }

  Future<void> _submitEmail() async {
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (_registerMode) {
        await controller.register(
          _emailController.text.trim(),
          _passwordController.text,
          null,
        );
      } else {
        await controller.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }
      ref.invalidate(homeDataProvider);
      if (!mounted) return;
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _continueGoogle() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Google sign-in belum tersambung ke backend.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.palette,
    required this.registerMode,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.rememberMe,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
    required this.onToggleMode,
    required this.onForgotPassword,
    required this.onGoogle,
    required this.onGuest,
  });

  final _AuthPalette palette;
  final bool registerMode;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool rememberMe;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final ValueChanged<bool?> onRememberChanged;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthField(
              label: 'Email',
              controller: emailController,
              palette: palette,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: TonztoonIcons.mail,
            ),
            const SizedBox(height: 16),
            _AuthField(
              label: 'Password',
              controller: passwordController,
              palette: palette,
              prefixIcon: TonztoonIcons.lock,
              obscureText: obscurePassword,
              suffixIcon: IconButton(
                tooltip: obscurePassword
                    ? 'Tampilkan password'
                    : 'Sembunyikan password',
                onPressed: onTogglePassword,
                icon: Icon(
                  obscurePassword ? TonztoonIcons.eyeOff : TonztoonIcons.eye,
                ),
              ),
            ),
            if (registerMode) ...[
              const SizedBox(height: 16),
              _AuthField(
                label: 'Konfirmasi password',
                controller: confirmPasswordController,
                palette: palette,
                prefixIcon: TonztoonIcons.keyRound,
                obscureText: obscureConfirmPassword,
                suffixIcon: IconButton(
                  tooltip: obscureConfirmPassword
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  onPressed: onToggleConfirmPassword,
                  icon: Icon(
                    obscureConfirmPassword
                        ? TonztoonIcons.eyeOff
                        : TonztoonIcons.eye,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: rememberMe,
                  onChanged: onRememberChanged,
                  visualDensity: VisualDensity.compact,
                  shape: const CircleBorder(),
                ),
                Text(
                  'Remember me',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (!registerMode)
                  TextButton(
                    onPressed: onForgotPassword,
                    child: const Text('Lupa password?'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSubmit,
                icon: Icon(
                  registerMode ? TonztoonIcons.userPlus : TonztoonIcons.login,
                ),
                label: Text(registerMode ? 'Register dengan Email' : 'Login'),
              ),
            ),
            const SizedBox(height: 18),
            _OrDivider(color: palette.border, textColor: palette.muted),
            const SizedBox(height: 18),
            _SocialButton(
              label: 'Continue with Google',
              onPressed: onGoogle,
              leading: const _GoogleGlyph(),
            ),
            const SizedBox(height: 10),
            _SocialButton(
              label: 'Continue as Guest',
              onPressed: onGuest,
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
                  GestureDetector(
                    onTap: onToggleMode,
                    child: Text(
                      registerMode ? 'Login' : 'Register',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.accent,
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
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _instructionSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _AuthPalette.fromTheme(Theme.of(context));
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
                  palette: palette,
                  emailController: _emailController,
                  instructionSent: _instructionSent,
                  onSubmit: () => setState(() => _instructionSent = true),
                  onEditEmail: () => setState(() => _instructionSent = false),
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
    );
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
              ? 'Kami menyiapkan instruksi pemulihan agar kamu bisa kembali membaca dengan akun yang sama.'
              : 'Masukkan email akun TonzToon. Kami akan menampilkan alur pengiriman instruksi reset password.',
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
    required this.palette,
    required this.emailController,
    required this.instructionSent,
    required this.onSubmit,
    required this.onEditEmail,
  });

  final _AuthPalette palette;
  final TextEditingController emailController;
  final bool instructionSent;
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
                  palette: palette,
                  emailController: emailController,
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
    required this.palette,
    required this.emailController,
    required this.onSubmit,
  });

  final _AuthPalette palette;
  final TextEditingController emailController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
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
          'Pastikan email masih aktif supaya instruksi reset mudah ditemukan.',
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
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(TonztoonIcons.mail),
            label: const Text('Kirim instruksi reset'),
          ),
        ),
      ],
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
          'Instruksi reset siap dikirim',
          style: theme.textTheme.titleLarge?.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Kami akan mengirim link pemulihan ke $targetEmail.',
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

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    required this.palette,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final _AuthPalette palette;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: TextInputAction.next,
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
  final VoidCallback onPressed;

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
