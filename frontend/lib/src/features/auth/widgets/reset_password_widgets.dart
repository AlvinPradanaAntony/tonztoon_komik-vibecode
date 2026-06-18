part of '../auth_screen.dart';

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
