import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_icons.dart';
import '../../models/auth.dart';
import '../../repositories/providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final palette = _AuthPalette.fromBrightness(Theme.of(context).brightness);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: auth.isAuthenticated
                ? _SignedInView(
                    palette: palette,
                    busy: _busy,
                    email: auth.user?.email ?? auth.user?.id ?? 'Signed in',
                    onLogout: _logout,
                  )
                : _AuthFormView(
                    palette: palette,
                    formKey: _formKey,
                    email: _email,
                    password: _password,
                    confirmPassword: _confirmPassword,
                    registerMode: _registerMode,
                    busy: _busy,
                    rememberMe: _rememberMe,
                    obscurePassword: _obscurePassword,
                    obscureConfirmPassword: _obscureConfirmPassword,
                    message: auth.message,
                    onRememberChanged: (value) {
                      setState(() => _rememberMe = value ?? false);
                    },
                    onTogglePassword: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    onToggleConfirmPassword: () {
                      setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                    onSubmit: _submit,
                    onToggleMode: () {
                      _formKey.currentState?.reset();
                      _confirmPassword.clear();
                      setState(() => _registerMode = !_registerMode);
                    },
                    onGuest: () => context.go('/'),
                    onSocial: _showComingSoon,
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (_registerMode) {
        await controller.register(_email.text.trim(), _password.text, null);
      } else {
        await controller.login(_email.text.trim(), _password.text);
      }
      if (!mounted) return;
      if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
        ref.invalidate(homeDataProvider);
        context.go('/');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).logout();
    ref.invalidate(homeDataProvider);
    if (mounted) {
      setState(() => _busy = false);
      context.go('/');
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Social login coming soon.')));
  }
}

class _AuthFormView extends StatelessWidget {
  const _AuthFormView({
    required this.palette,
    required this.formKey,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.registerMode,
    required this.busy,
    required this.rememberMe,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
    required this.onToggleMode,
    required this.onGuest,
    required this.onSocial,
    this.message,
  });

  final _AuthPalette palette;
  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final bool registerMode;
  final bool busy;
  final bool rememberMe;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final String? message;
  final ValueChanged<bool?> onRememberChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;
  final VoidCallback onGuest;
  final VoidCallback onSocial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      children: [
        Text(
          registerMode
              ? 'Sign Up To Your Account.'
              : 'Login Now To Your Account.',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        if (!registerMode) ...[
          const SizedBox(height: 8),
          Text(
            message ?? 'Access your account to manage settings, sync progress.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.muted,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 28),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AuthField(
                label: 'Email',
                controller: email,
                palette: palette,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || !value.contains('@')) {
                    return 'Enter a valid email.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              _AuthField(
                label: 'Password',
                controller: password,
                palette: palette,
                obscureText: obscurePassword,
                suffixIcon: IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscurePassword ? TonztoonIcons.eyeOff : TonztoonIcons.eye,
                    size: 18,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
              ),
              if (registerMode) ...[
                const SizedBox(height: 18),
                _AuthField(
                  label: 'Confirm Password',
                  controller: confirmPassword,
                  palette: palette,
                  obscureText: obscureConfirmPassword,
                  suffixIcon: IconButton(
                    onPressed: onToggleConfirmPassword,
                    icon: Icon(
                      obscureConfirmPassword
                          ? TonztoonIcons.eyeOff
                          : TonztoonIcons.eye,
                      size: 18,
                    ),
                  ),
                  validator: (value) {
                    if (value != password.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: busy ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: palette.accent.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(registerMode ? 'Sign UP' : 'Login'),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Checkbox(
              value: rememberMe,
              onChanged: onRememberChanged,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: palette.muted),
              shape: const CircleBorder(),
            ),
            Text(
              'Remember me',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (!registerMode)
              TextButton(
                onPressed: null,
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _OrDivider(palette: palette),
        const SizedBox(height: 22),
        _SocialButton(
          palette: palette,
          label: 'Sign in with Google',
          icon: 'G',
          onPressed: onSocial,
        ),
        const SizedBox(height: 12),
        _SocialButton(
          palette: palette,
          label: 'Continue with Apple',
          iconData: TonztoonIcons.apple,
          onPressed: onSocial,
        ),
        const SizedBox(height: 14),
        _SocialButton(
          palette: palette,
          label: 'Continue as Guest',
          iconData: TonztoonIcons.chevronRight,
          onPressed: onGuest,
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            Text(
              registerMode
                  ? 'Already have an account?'
                  : 'Don’t have an account?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              onTap: busy ? null : onToggleMode,
              child: Text(
                registerMode ? 'Login' : 'Sign Up',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    required this.palette,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final _AuthPalette palette;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
          cursorColor: palette.accent,
          decoration: InputDecoration(
            filled: true,
            fillColor: palette.input,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 17,
            ),
            suffixIcon: suffixIcon,
            suffixIconColor: palette.text,
            border: _fieldBorder(Colors.transparent),
            enabledBorder: _fieldBorder(Colors.transparent),
            focusedBorder: _fieldBorder(palette.accent),
            errorBorder: _fieldBorder(palette.error),
            focusedErrorBorder: _fieldBorder(palette.error),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _fieldBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: BorderSide(color: color, width: 1.4),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.palette});

  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: palette.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'OR',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(child: Divider(color: palette.border)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.palette,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconData,
  });

  final _AuthPalette palette;
  final String label;
  final VoidCallback onPressed;
  final String? icon;
  final IconData? iconData;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.text,
          backgroundColor: palette.input,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (iconData != null)
              Icon(iconData, size: 18, color: palette.text)
            else
              Text(
                icon!,
                style: const TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _SignedInView extends StatelessWidget {
  const _SignedInView({
    required this.palette,
    required this.busy,
    required this.email,
    required this.onLogout,
  });

  final _AuthPalette palette;
  final bool busy;
  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: palette.input,
              shape: BoxShape.circle,
            ),
            child: Icon(
              TonztoonIcons.accountCircle,
              color: palette.accent,
              size: 44,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            email,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: busy ? null : onLogout,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              icon: const Icon(TonztoonIcons.logout),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthPalette {
  const _AuthPalette({
    required this.background,
    required this.input,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
    required this.error,
  });

  final Color background;
  final Color input;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;
  final Color error;

  factory _AuthPalette.fromBrightness(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const _AuthPalette(
        background: Color(0xFF080808),
        input: Color(0xFF151515),
        text: Color(0xFFF4F4F4),
        muted: Color(0xFFB8B8B8),
        border: Color(0xFF202020),
        accent: Color(0xFFFF3B86),
        error: Color(0xFFFF5A6D),
      );
    }
    return const _AuthPalette(
      background: Color(0xFFF7F8FA),
      input: Color(0xFFFFFFFF),
      text: Color(0xFF141414),
      muted: Color(0xFF667075),
      border: Color(0xFFE2E6EA),
      accent: Color(0xFFFF3B86),
      error: Color(0xFFCC244F),
    );
  }
}
