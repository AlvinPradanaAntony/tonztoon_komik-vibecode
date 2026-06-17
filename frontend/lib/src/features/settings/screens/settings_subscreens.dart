part of '../settings_screen.dart';

class _PrivacySecurityScreen extends ConsumerWidget {
  const _PrivacySecurityScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(authSecurityOverviewProvider);

    return _AccountFlowScaffold(
      title: 'Privacy & Security',
      children: [
        security.when(
          loading: () => const _PrivacySecurityLoading(),
          error: (error, stackTrace) => _PrivacySecurityError(
            message: '$error',
            onRetry: () => ref.invalidate(authSecurityOverviewProvider),
          ),
          data: (overview) => _PrivacySecurityContent(overview: overview),
        ),
      ],
    );
  }
}

class _PrivacySecurityContent extends ConsumerWidget {
  const _PrivacySecurityContent({required this.overview});

  final AuthSecurityOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = overview.email?.trim();
    final emailSubtitle = email == null || email.isEmpty
        ? 'Email tidak tersedia'
        : email;
    final provider = overview.provider?.trim();
    final session = overview.currentSession;
    final auth = ref.watch(authControllerProvider);
    final username = auth.user?.username?.trim();
    final hasUsername = username != null && username.isNotEmpty;
    final usernameSubtitle = hasUsername
        ? '@$username - tidak dapat diubah'
        : 'Belum dibuat';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecurityScoreCard(overview: overview),
        const SizedBox(height: 18),
        const _SectionLabel(text: 'Account Protection'),
        const SizedBox(height: 8),
        _SettingsSection(
          children: [
            _SettingsRow(
              icon: TonztoonIcons.mail,
              title: 'Email Verification',
              subtitle: emailSubtitle,
              trailing: _StatusBadge(
                label: overview.emailVerified ? 'Verified' : 'Unverified',
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.user,
              title: 'Username',
              subtitle: usernameSubtitle,
              trailing: hasUsername
                  ? Icon(
                      TonztoonIcons.lock,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : null,
              onTap: hasUsername
                  ? null
                  : () => _showCreateUsernameDialog(context, ref),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.keyRound,
              title: overview.hasPassword ? 'Password login' : 'Buat password',
              subtitle: overview.hasPassword
                  ? 'Ubah password untuk login dengan email'
                  : provider == 'google'
                  ? 'Aktifkan login email untuk akun Google ini'
                  : 'Tambahkan password untuk login email',
              onTap: () => _showChangePasswordDialog(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionLabel(text: 'Active Session'),
        const SizedBox(height: 8),
        _SettingsSection(
          children: [
            _DeviceRow(
              title: 'Current session',
              subtitle: _sessionSubtitle(session),
              icon: Icons.phone_android_rounded,
              active: true,
            ),
            const _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.logout,
              title: 'Logout Current Session',
              subtitle: 'Revoke this device session now',
              onTap: () => _logoutCurrentSession(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showCreateUsernameDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final saved = await _showProfileTextDialog(
      context,
      title: 'Buat username',
      label: 'Username',
      initialValue: '',
      helperText:
          'Username tampil di profil sebagai @username dan tidak dapat diubah setelah dibuat. Gunakan huruf, angka, titik, strip, atau underscore.',
      maxLength: 50,
      emptyError: 'Username wajib diisi.',
      submitLabel: 'Buat username',
      validator: _validateUsernameValue,
      onSubmit: (value) => ref
          .read(authControllerProvider.notifier)
          .updateProfile(username: value),
    );
    if (!context.mounted || saved == null) return;
    showAppSnackBar(
      context,
      message: 'Username berhasil dibuat.',
      type: AppSnackBarType.success,
    );
  }

  static String _sessionSubtitle(AuthSecuritySession session) {
    final expires = session.expiresAtDate;
    if (expires == null) return 'Sesi aktif saat ini';
    return 'Aktif sampai ${DateFormat('dd MMM yyyy, HH:mm').format(expires)}';
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final changed = await showTonztoonModal<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ChangePasswordDialog(
        title: overview.hasPassword ? 'Ubah password login' : 'Buat password',
        description: overview.hasPassword
            ? null
            : 'Tambahkan password agar akun ini bisa dipakai login dengan email.',
        submitLabel: overview.hasPassword ? 'Simpan' : 'Buat password',
        savingLabel: overview.hasPassword ? 'Simpan' : 'Menyimpan...',
        onSubmit: (password) =>
            ref.read(authControllerProvider.notifier).updatePassword(password),
      ),
    );
    if (!context.mounted || changed != true) return;
    ref.invalidate(authSecurityOverviewProvider);
    showAppSnackBar(
      context,
      message: 'Password berhasil diperbarui.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _logoutCurrentSession(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showTonztoonConfirmDialog(
      context,
      eyebrow: 'Sesi Akun',
      title: 'Logout sesi ini?',
      message:
          'Kamu perlu login lagi untuk memakai akun ini di perangkat sekarang.',
      helperText:
          'Data akun tetap aman. Riwayat, koleksi, dan progress tersimpan selama sudah tersinkron.',
      cancelLabel: 'Batal',
      confirmLabel: 'Logout',
      helperIcon: TonztoonIcons.shieldCheck,
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.logoutDeviceSession,
    );
    if (!context.mounted || confirmed != true) return;

    await ref.read(authControllerProvider.notifier).logout();
    ref.invalidate(homeDataProvider);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showAppSnackBar(
      context,
      message: 'Logout berhasil.',
      type: AppSnackBarType.success,
    );
  }
}

class _SecurityScoreCard extends StatelessWidget {
  const _SecurityScoreCard({required this.overview});

  final AuthSecurityOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = overview.provider?.trim().toLowerCase();
    final title = !overview.hasPassword && provider == 'google'
        ? 'Login email belum aktif'
        : overview.emailVerified
        ? 'Security looks good'
        : 'Email verification needed';
    final message = !overview.hasPassword && provider == 'google'
        ? 'Tambahkan password jika ingin masuk tanpa tombol Google.'
        : overview.emailVerified
        ? 'Email akun terverifikasi dan sesi aktif terlindungi.'
        : 'Verifikasi email Anda agar pemulihan akun lebih aman.';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                TonztoonIcons.shieldCheck,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySecurityLoading extends StatelessWidget {
  const _PrivacySecurityLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppShimmer(
          child: AppShimmerBlock(
            width: double.infinity,
            height: 90,
            borderRadius: 18,
          ),
        ),
        SizedBox(height: 18),
        _SectionLabel(text: 'Account Protection'),
        SizedBox(height: 8),
        _SettingsSectionSkeleton(rowCount: 2),
        SizedBox(height: 20),
        _SectionLabel(text: 'Active Session'),
        SizedBox(height: 8),
        _SettingsSectionSkeleton(rowCount: 2),
      ],
    );
  }
}

class _PrivacySecurityError extends StatelessWidget {
  const _PrivacySecurityError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _SettingsSection(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Icon(TonztoonIcons.warning, color: colorScheme.error),
            const SizedBox(height: 8),
            Text(
              'Gagal memuat pengaturan keamanan.',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _MyFavoritesScreen extends StatelessWidget {
  const _MyFavoritesScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Favorites'),
        actions: [
          IconButton(
            tooltip: 'Buka tab Scene di Pustaka',
            onPressed: () => context.go(libraryScenesLocation),
            icon: const Icon(TonztoonIcons.library),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const FavoriteScenesPane(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 28),
        allowDelete: false,
      ),
    );
  }
}

class _MyDownloadsScreen extends StatelessWidget {
  const _MyDownloadsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Downloads'),
        actions: [
          IconButton(
            tooltip: 'Buka tab Unduhan di Pustaka',
            onPressed: () => context.go(libraryDownloadsLocation),
            icon: const Icon(TonztoonIcons.library),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const OfflineDownloadsPane(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 28),
        readyOnly: true,
        allowDelete: false,
      ),
    );
  }
}
