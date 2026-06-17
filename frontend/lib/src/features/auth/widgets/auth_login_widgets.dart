part of '../auth_screen.dart';

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.24 : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                label: registerMode ? 'Email' : 'Email atau username',
                controller: emailController,
                palette: palette,
                keyboardType: registerMode
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                prefixIcon: TonztoonIcons.mail,
                enabled: !submitting,
                validator: registerMode
                    ? _validateEmail
                    : _validateLoginIdentifier,
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
              if (!registerMode) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: submitting ? null : onForgotPassword,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Lupa password?'),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                const SizedBox(height: 16),
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
    final valid = _isValidEmail(email);
    if (!valid) return 'Format email tidak valid.';
    return null;
  }

  String? _validateLoginIdentifier(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.isEmpty) return 'Email atau username wajib diisi.';
    if (identifier.contains('@')) {
      return _isValidEmail(identifier) ? null : 'Format email tidak valid.';
    }
    if (identifier.length > 50) return 'Username maksimal 50 karakter.';
    final valid = RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(identifier);
    if (!valid) {
      return 'Username hanya boleh berisi huruf, angka, titik, dash, atau underscore.';
    }
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
