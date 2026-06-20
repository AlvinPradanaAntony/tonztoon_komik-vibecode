part of '../settings_screen.dart';

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final Future<PackageInfo> _packageInfoFuture;
  bool _loggingOut = false;
  bool _checkingForUpdate = false;
  bool _profileSetupPromptInFlight = false;
  String? _passwordSetupCheckedUserId;
  String? _usernameSetupCheckedUserId;
  String? _profileAvatarUrl;
  bool _profileAvatarReady = true;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = ref.watch(readerPreferencesProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final showHomeHelpdeskButton = ref.watch(homeHelpdeskButtonVisibleProvider);
    final auth = ref.watch(authControllerProvider);
    final librarySummary = widget.isSignedIn
        ? ref.watch(librarySummaryProvider)
        : const AsyncData<LibrarySummary>(
            LibrarySummary(
              counts: LibrarySummaryCounts(
                bookmarks: 0,
                collections: 0,
                favoriteScenes: 0,
                history: 0,
                downloads: 0,
                continueReading: 0,
              ),
              readingTimeSeconds: 0,
            ),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSignedIn ? 'My Profile' : 'Settings',
          style: theme.textTheme.titleLarge,
        ),
        centerTitle: false,
      ),
      body: AppAsyncView<ReaderPreferences>(
        value: prefs,
        onRetry: () => ref.invalidate(readerPreferencesProvider),
        loadingBuilder: (context) =>
            _SettingsLoadingPlaceholder(isSignedIn: widget.isSignedIn),
        builder: (readerPrefs) {
          final migrationSummary = widget.isSignedIn
              ? ref.read(libraryRepositoryProvider).getGuestMigrationSummary()
              : null;
          final showMigrationRow =
              migrationSummary != null && !migrationSummary.isEmpty;
          final profileReady =
              !widget.isSignedIn || _ensureProfileAvatarReady(auth);
          final profileStatsReady =
              !widget.isSignedIn || _hasInitialValue(librarySummary);

          if (!profileReady || !profileStatsReady) {
            return _SettingsLoadingPlaceholder(isSignedIn: widget.isSignedIn);
          }

          _maybePromptProfileSetup(auth);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
            children: [
              if (widget.isSignedIn) ...[
                _ProfileHeader(auth: auth),
                const SizedBox(height: 18),
                _ProfileStats(summary: librarySummary),
                const SizedBox(height: 24),
                const _SectionLabel(text: 'Account'),
                const SizedBox(height: 8),
                _SettingsSection(
                  children: [
                    _SettingsRow(
                      icon: TonztoonIcons.settings2,
                      title: 'Privacy & Security',
                      subtitle: 'Password, devices, and account access',
                      onTap: () => _openAccountFlow(
                        context,
                        const _PrivacySecurityScreen(),
                      ),
                    ),
                    if (showMigrationRow) ...[
                      const _SettingsDivider(),
                      _SettingsRow(
                        icon: TonztoonIcons.cloudUpload,
                        title: 'Sync Migration Data',
                        subtitle: _migrationRowSubtitle(migrationSummary),
                        onTap: _syncMigrationData,
                      ),
                    ],
                    const _SettingsDivider(),
                    _SavedCollectionsSettingsRow(summary: librarySummary),
                    const _SettingsDivider(),
                    _FavoriteScenesSettingsRow(summary: librarySummary),
                    const _SettingsDivider(),
                    _MyDownloadsSettingsRow(summary: librarySummary),
                    const _SettingsDivider(),
                    const _PushNotificationsSettingsRow(),
                  ],
                ),
                const SizedBox(height: 24),
              ] else ...[
                const _GuestReadingTimeCard(),
                const SizedBox(height: 24),
              ],
              const _SectionLabel(text: 'Preferences'),
              const SizedBox(height: 8),
              _PreferencesSection(
                prefs: readerPrefs,
                themeMode: themeMode,
                showHomeHelpdeskButton: showHomeHelpdeskButton,
                isSignedIn: widget.isSignedIn,
                onThemeChanged: (value) =>
                    _setThemeMode(_themeModeFromLabel(value)),
                onReaderModeChanged: (value) => _savePrefs(
                  readerPrefs.copyWith(
                    defaultReadingMode: value == 'Paged' ? 'paged' : 'vertical',
                  ),
                ),
                onDirectionChanged: (value) => _savePrefs(
                  readerPrefs.copyWith(readingDirection: value.toLowerCase()),
                ),
                onBingeModeChanged: (value) =>
                    _savePrefs(readerPrefs.copyWith(defaultBingeMode: value)),
                onAutoScrollChanged: (value) =>
                    _savePrefs(readerPrefs.copyWith(autoScrollEnabled: value)),
                onMarkReadChanged: (value) =>
                    _savePrefs(readerPrefs.copyWith(markReadOnComplete: value)),
                onHomeHelpdeskButtonChanged: _setHomeHelpdeskButtonVisible,
                onClearCache: _clearCache,
                onOpenAuth: widget.onOpenAuth,
              ),
              if (widget.isSignedIn) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loggingOut ? null : _logout,
                  icon: _loggingOut
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(TonztoonIcons.logout, size: 18),
                  label: const Text('Logout'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const _SectionLabel(text: 'About'),
              const SizedBox(height: 8),
              _SettingsSection(
                children: [
                  _SettingsRow(
                    icon: TonztoonIcons.lifeBuoy,
                    title: 'Helpdesk',
                    subtitle: 'Kirim review atau laporkan masalah aplikasi',
                    onTap: _openHelpdesk,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AppVersionSection(
                packageInfoFuture: _packageInfoFuture,
                checkingForUpdate: _checkingForUpdate,
                onCheckForUpdate: _checkForUpdates,
                onShowAppInfo: _showAppInfo,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    try {
      await ref.read(appThemeModeProvider.notifier).setMode(mode);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Set theme mode failed',
        fallbackMessage: 'Tema belum dapat diubah. Silakan coba lagi.',
      );
    }
  }

  Future<void> _setHomeHelpdeskButtonVisible(bool value) async {
    try {
      await ref
          .read(homeHelpdeskButtonVisibleProvider.notifier)
          .setVisible(value);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Save home helpdesk button preference failed',
        fallbackMessage: 'Pengaturan tombol helpdesk belum dapat disimpan.',
      );
    }
  }

  Future<void> _openHelpdesk() async {
    final repository = ref.read(helpdeskRepositoryProvider);
    final receipt = await showHelpdeskDialog(
      context,
      onSubmit: (draft) =>
          repository.submit(draft, clientSource: 'settings_helpdesk'),
    );
    if (!mounted || receipt == null) return;
    showAppSnackBar(
      context,
      title: 'Terkirim',
      message: 'Terima kasih. Kode laporan kamu: ${receipt.referenceCode}.',
      type: AppSnackBarType.success,
    );
  }

  bool _ensureProfileAvatarReady(AuthState auth) {
    final avatarUrl = auth.user?.avatarUrl?.trim();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      _profileAvatarUrl = null;
      _profileAvatarReady = true;
      return true;
    }

    if (_profileAvatarUrl == avatarUrl) return _profileAvatarReady;

    _profileAvatarUrl = avatarUrl;
    _profileAvatarReady = false;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await precacheImage(NetworkImage(avatarUrl), context);
      } catch (_) {
        // Let the avatar widget fall back to initials through its errorBuilder.
      }
      if (!mounted || _profileAvatarUrl != avatarUrl) return;
      setState(() {
        _profileAvatarReady = true;
      });
    });

    return false;
  }

  bool _hasInitialValue<T>(AsyncValue<T> value) {
    return value.hasValue || !value.isLoading;
  }

  Future<void> _savePrefs(ReaderPreferences prefs) async {
    try {
      await ref.read(readerPreferencesProvider.notifier).save(prefs);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Save reader preferences failed',
        fallbackMessage: 'Preferensi belum dapat disimpan. Silakan coba lagi.',
      );
    }
  }

  Future<void> _clearCache() async {
    try {
      await ref.read(localStoreProvider).cache.clear();
      ref.invalidate(sourcesProvider);
      ref.invalidate(homeDataProvider);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Cache katalog dibersihkan.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Clear catalog cache failed',
        fallbackMessage: 'Cache belum dapat dibersihkan. Silakan coba lagi.',
      );
    }
  }

  Future<void> _showAppInfo() async {
    final service = ref.read(appUpdateServiceProvider);
    await showAppInfoDialog(context, service: service);
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    try {
      final service = ref.read(appUpdateServiceProvider);
      final release = await service.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        await showTonztoonNoticeDialog(
          context,
          eyebrow: 'Pembaruan Aplikasi',
          title: 'TonzToon sudah terbaru',
          message: 'Tidak ada versi baru yang perlu dipasang saat ini.',
          helperText: 'Kamu sudah memakai rilis TonzToon paling baru.',
          helperIcon: TonztoonIcons.badgeCheck,
          primaryLabel: 'OK',
          variant: TonztoonModalVariant.success,
          art: TonztoonModalArt.cloudSync,
        );
        return;
      }
      await showAppUpdateDialog(context, release: release, service: service);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Manual app update check failed',
        fallbackMessage:
            'Pembaruan belum dapat diperiksa. Pastikan koneksi internet aktif.',
      );
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    final confirmed = await showTonztoonConfirmDialog(
      context,
      eyebrow: 'Sesi Akun',
      title: 'Keluar dari akun?',
      message:
          'Kamu akan keluar dari akun ini dan perlu login kembali untuk menyinkronkan pustaka.',
      helperText:
          'Data pustaka yang sudah tersimpan di akun tetap aman dan bisa dipulihkan setelah login.',
      cancelLabel: 'Batal',
      confirmLabel: 'Ya, Keluar',
      helperIcon: TonztoonIcons.shieldCheck,
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.logoutAccount,
    );
    if (!mounted || confirmed != true) return;

    setState(() => _loggingOut = true);
    try {
      await widget.onLogout();
      ref.invalidate(homeDataProvider);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Logout berhasil.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Logout failed',
        fallbackMessage: 'Logout belum berhasil. Silakan coba lagi.',
      );
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  void _maybePromptProfileSetup(AuthState auth) {
    final userId = auth.user?.id.trim();
    if (!widget.isSignedIn ||
        !auth.isAuthenticated ||
        userId == null ||
        userId.isEmpty ||
        _profileSetupPromptInFlight) {
      return;
    }

    final shouldCheckPassword = _passwordSetupCheckedUserId != userId;
    final shouldCheckUsername =
        _usernameSetupCheckedUserId != userId && _needsUsername(auth);
    if (!shouldCheckPassword && !shouldCheckUsername) return;

    _profileSetupPromptInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var needsPassword = false;
      var needsUsername = false;
      try {
        if (shouldCheckPassword) {
          _passwordSetupCheckedUserId = userId;
          final overview = await ref
              .read(authRepositoryProvider)
              .getSecurityOverview();
          if (!mounted) return;

          final currentAuth = ref.read(authControllerProvider);
          final provider = overview.provider?.trim().toLowerCase();
          needsPassword =
              _isCurrentUser(currentAuth, userId) &&
              provider == 'google' &&
              !overview.hasPassword;
        }

        if (!mounted) return;
        final currentAuth = ref.read(authControllerProvider);
        if (_usernameSetupCheckedUserId != userId &&
            _isCurrentUser(currentAuth, userId) &&
            _needsUsername(currentAuth)) {
          _usernameSetupCheckedUserId = userId;
          needsUsername = true;
        }

        if (!needsPassword && !needsUsername) return;

        final completed = await _showProfileSetupDialog(
          requireUsername: needsUsername,
          requirePassword: needsPassword,
        );
        if (!mounted || completed != true) return;

        if (needsPassword) ref.invalidate(authSecurityOverviewProvider);
        showAppSnackBar(
          context,
          message: needsPassword && needsUsername
              ? 'Username dan password berhasil disimpan.'
              : needsPassword
              ? 'Password berhasil dibuat.'
              : 'Username berhasil dibuat.',
          type: AppSnackBarType.success,
        );
      } catch (error, stackTrace) {
        logAppError(error, stackTrace, context: 'Check profile setup failed');
      } finally {
        _profileSetupPromptInFlight = false;
      }
    });
  }

  bool _isCurrentUser(AuthState auth, String userId) {
    return widget.isSignedIn &&
        auth.isAuthenticated &&
        auth.user?.id.trim() == userId;
  }

  bool _needsUsername(AuthState auth) {
    final username = auth.user?.username?.trim();
    return username == null || username.isEmpty;
  }

  Future<bool?> _showProfileSetupDialog({
    required bool requireUsername,
    required bool requirePassword,
  }) {
    return showTonztoonModal<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProfileSetupDialog(
        requireUsername: requireUsername,
        requirePassword: requirePassword,
        title: requireUsername && requirePassword
            ? 'Lengkapi akun kamu'
            : requirePassword
            ? 'Buat password login'
            : 'Buat username',
        description: requireUsername && requirePassword
            ? 'Tambahkan username dan password agar akun TonzToon kamu siap dipakai dengan Google maupun email.'
            : requirePassword
            ? 'Tambahkan password agar akun Google kamu juga bisa dipakai login dengan email.'
            : 'Tambahkan username agar profil kamu mudah dikenali.',
        cancelLabel: 'Nanti saja',
        submitLabel: requireUsername && requirePassword
            ? 'Simpan akun'
            : requirePassword
            ? 'Buat password'
            : 'Buat username',
        savingLabel: 'Menyimpan...',
        onSubmit: ({String? username, String? password}) async {
          final controller = ref.read(authControllerProvider.notifier);
          if (username != null) {
            await controller.updateProfile(username: username);
          }
          if (password != null) {
            await controller.updatePassword(password);
          }
        },
      ),
    );
  }

  String _migrationRowSubtitle(GuestMigrationSummary summary) {
    final itemCount = guestMigrationItemCount(summary);
    return '$itemCount item guest siap disinkronkan';
  }

  Future<void> _syncMigrationData() async {
    final repo = ref.read(libraryRepositoryProvider);
    final summary = repo.getGuestMigrationSummary();
    if (summary.isEmpty) {
      showAppSnackBar(
        context,
        message: 'Tidak ada data guest untuk migrasi.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final action = await showGuestMigrationDialog(
      context,
      summary: summary,
      title: 'Sync Migration Data',
      message:
          'Data guest lokal berikut akan dipindahkan ke akun cloud Anda. Data lokal akan dibersihkan setelah sinkron berhasil.',
    );
    if (!mounted || action != GuestMigrationDialogAction.migrate) return;

    var loadingShown = false;
    try {
      _showMigrationLoadingDialog();
      loadingShown = true;
      await repo.importLocalSnapshotToCloud();
      _refreshMigratedData();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingShown = false;
      showAppSnackBar(
        context,
        message: 'Data guest berhasil disinkronkan.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Guest data migration failed',
        fallbackMessage:
            'Migrasi data guest belum berhasil. Silakan coba lagi.',
      );
    }
  }

  void _refreshMigratedData() {
    ref.invalidate(homeDataProvider);
    ref.invalidate(librarySummaryProvider);
    ref.invalidate(bookmarksProvider);
    ref.invalidate(collectionsProvider);
    ref.invalidate(favoriteScenesProvider);
    ref.invalidate(downloadsProvider);
    ref.invalidate(historyProvider);
    ref.invalidate(paginatedHistoryProvider);
    ref.invalidate(readingTimeProvider);
    unawaited(ref.read(readingTimeProvider.notifier).refreshFromCloud());
    setState(() {});
  }

  void _showMigrationLoadingDialog() {
    unawaited(
      showTonztoonModal<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const PopScope(canPop: false, child: GuestMigrationLoadingDialog()),
      ),
    );
  }

  ThemeMode _themeModeFromLabel(String label) {
    return switch (label) {
      'Light' => ThemeMode.light,
      'Dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
