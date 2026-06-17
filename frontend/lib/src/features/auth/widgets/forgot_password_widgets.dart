part of '../auth_screen.dart';

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
