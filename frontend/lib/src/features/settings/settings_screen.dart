import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_error.dart';
import '../../core/app_snackbar.dart';
import '../../core/avatar_image.dart';
import '../../core/app_navigation.dart';
import '../../core/app_icons.dart';
import '../../models/auth.dart';
import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/guest_migration_dialog.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import '../library/library_shared_panes.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    required this.isSignedIn,
    required this.onOpenAuth,
    required this.onLogout,
  });

  final bool isSignedIn;
  final VoidCallback onOpenAuth;
  final Future<void> Function() onLogout;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final Future<PackageInfo> _packageInfoFuture;
  bool _loggingOut = false;
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
                onMarkReadChanged: (value) =>
                    _savePrefs(readerPrefs.copyWith(markReadOnComplete: value)),
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
              _AppVersionSection(packageInfoFuture: _packageInfoFuture),
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

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };
}

String _readerModeLabel(String mode) {
  return mode == 'paged' ? 'Paged' : 'Vertical';
}

String _directionLabel(String direction) {
  return direction == 'rtl' ? 'RTL' : 'LTR';
}

String? _validateUsernameValue(String? value) {
  final username = value?.trim() ?? '';
  if (username.isEmpty) return 'Username wajib diisi.';
  if (username.length < 3) return 'Username minimal 3 karakter.';
  if (username.length > 50) return 'Username maksimal 50 karakter.';
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username)) {
    return 'Gunakan huruf, angka, titik, strip, atau underscore.';
  }
  return null;
}

void _openAccountFlow(BuildContext context, Widget page) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (context) => page));
}

Future<String?> _showProfileTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String initialValue,
  required Future<void> Function(String value) onSubmit,
  String? helperText,
  TextInputType? keyboardType,
  int? maxLength,
  bool allowEmpty = false,
  String emptyError = 'Field ini wajib diisi.',
  String cancelLabel = 'Batal',
  String submitLabel = 'Simpan',
  String? Function(String? value)? validator,
}) {
  return showTonztoonModal<String>(
    context: context,
    builder: (context) => _ProfileTextDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      onSubmit: onSubmit,
      helperText: helperText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      allowEmpty: allowEmpty,
      emptyError: emptyError,
      cancelLabel: cancelLabel,
      submitLabel: submitLabel,
      validator: validator,
    ),
  );
}

class _ProfileTextDialog extends StatefulWidget {
  const _ProfileTextDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.onSubmit,
    required this.allowEmpty,
    required this.emptyError,
    required this.cancelLabel,
    required this.submitLabel,
    this.helperText,
    this.keyboardType,
    this.maxLength,
    this.validator,
  });

  final String title;
  final String label;
  final String initialValue;
  final Future<void> Function(String value) onSubmit;
  final String? helperText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool allowEmpty;
  final String emptyError;
  final String cancelLabel;
  final String submitLabel;
  final String? Function(String? value)? validator;

  @override
  State<_ProfileTextDialog> createState() => _ProfileTextDialogState();
}

class _ProfileTextDialogState extends State<_ProfileTextDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: TonztoonModalDialog(
        title: widget.title,
        message:
            widget.helperText ?? 'Perbarui data profil akun TonzToon kamu.',
        art: TonztoonModalArt.editHeaderProfile,
        showCloseButton: !_saving,
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            keyboardType: widget.keyboardType,
            maxLength: widget.maxLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _errorText,
            ),
            validator: (value) {
              final customError = widget.validator?.call(value);
              if (customError != null) return customError;
              final text = value?.trim() ?? '';
              if (!widget.allowEmpty && text.isEmpty) return widget.emptyError;
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        secondaryLabel: widget.cancelLabel,
        onSecondaryPressed: _saving ? null : () => Navigator.of(context).pop(),
        primaryLabel: _saving ? 'Menyimpan...' : widget.submitLabel,
        primaryLoading: _saving,
        onPrimaryPressed: _saving ? null : _submit,
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final value = _controller.text.trim();
    try {
      await widget.onSubmit(value);
      if (!mounted) return;
      Navigator.of(context).pop(value);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        fallbackMessage: 'Perubahan profil belum dapat disimpan.',
      );
      logAppError(error, stackTrace, context: 'Save profile field failed');
      setState(() {
        _saving = false;
        _errorText = message;
      });
      showAppSnackBar(context, message: message, type: AppSnackBarType.failure);
    }
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({required this.auth});

  final AuthState auth;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  static const double _profileInlineEditButtonBalancedWidth = 28;

  bool _saving = false;
  final AvatarImagePicker _avatarPicker = AvatarImagePicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = _displayName(widget.auth);
    final username = widget.auth.user?.username?.trim();
    final initials = _initials(name);
    final avatarUrl = widget.auth.user?.avatarUrl?.trim();

    return Column(
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipOval(
                          child: ColoredBox(
                            color: colorScheme.surface,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? Center(
                                    child: Text(
                                      initials,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  )
                                : Image.network(
                                    avatarUrl,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                    errorBuilder:
                                        (context, error, stackTrace) => Center(
                                          child: Text(
                                            initials,
                                            style: theme.textTheme.headlineSmall
                                                ?.copyWith(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                        ),
                                  ),
                          ),
                        ),
                      ),
                      if (avatarUrl == null || avatarUrl.isEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.tertiary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _ProfileEditButton(
                  tooltip: 'Ubah foto profil',
                  busy: _saving,
                  onPressed: _editAvatar,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: _profileInlineEditButtonBalancedWidth),
            Flexible(
              child: Text(
                name,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _ProfileEditButton(
              tooltip: 'Ubah display name',
              variant: _ProfileEditButtonVariant.inline,
              busy: _saving,
              onPressed: _editDisplayName,
            ),
          ],
        ),
        if (username != null && username.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '@$username',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
        ] else
          const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              'READER',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editDisplayName() async {
    final current = widget.auth.user?.displayName?.trim();
    final name = await _showProfileTextDialog(
      context,
      title: 'Edit display name',
      label: 'Display name',
      initialValue: current?.isNotEmpty == true
          ? current!
          : _displayName(widget.auth),
      maxLength: 120,
      emptyError: 'Display name wajib diisi.',
      onSubmit: (value) => ref
          .read(authControllerProvider.notifier)
          .updateProfile(displayName: value),
    );
    if (!mounted || name == null) return;
    showAppSnackBar(
      context,
      message: 'Profil berhasil diperbarui.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _editAvatar() async {
    final source = await _showAvatarSourceSheet(context);
    if (!mounted || source == null) return;

    setState(() => _saving = true);
    var uploadDialogShown = false;
    try {
      final avatar = await _avatarPicker.pick(
        context,
        source,
        onSelected: () {
          if (!mounted) return;
          _showAvatarUploadDialog(context);
          uploadDialogShown = true;
        },
      );
      if (!mounted || avatar == null) return;
      await ref.read(authControllerProvider.notifier).uploadAvatar(avatar);
      if (!mounted) return;
      if (uploadDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        uploadDialogShown = false;
      }
      showAppSnackBar(
        context,
        message: 'Foto profil berhasil diperbarui.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (uploadDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        uploadDialogShown = false;
      }
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Upload profile avatar failed',
        fallbackMessage: 'Gagal unggah Foto profil. Silakan coba lagi.',
      );
    } finally {
      if (mounted && uploadDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAvatarUploadDialog(BuildContext context) {
    unawaited(
      showTonztoonModal<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const PopScope(canPop: false, child: _AvatarUploadDialog()),
      ),
    );
  }

  Future<ImageSource?> _showAvatarSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(TonztoonIcons.image),
                title: const Text('Pilih dari galeri'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(TonztoonIcons.camera),
                title: const Text('Ambil foto'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayName(AuthState auth) {
    final displayName = auth.user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final email = auth.user?.email;
    if (email == null || email.trim().isEmpty) return 'TonzToon Reader';
    final handle = email.split('@').first;
    final words = handle
        .split(RegExp(r'[._-]+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return handle;
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  String _initials(String name) {
    final words = name.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return 'TT';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class _ProfileEditButton extends StatelessWidget {
  const _ProfileEditButton({
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.variant = _ProfileEditButtonVariant.avatar,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;
  final _ProfileEditButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isInline = variant == _ProfileEditButtonVariant.inline;
    final size = isInline ? 24.0 : 30.0;
    final iconSize = isInline ? 12.0 : 14.0;

    return Material(
      color: isInline
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primary,
      shape: const CircleBorder(),
      elevation: isInline ? 0 : 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              TonztoonIcons.pencil,
              size: iconSize,
              color: isInline
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

enum _ProfileEditButtonVariant { avatar, inline }

class _AvatarUploadDialog extends StatelessWidget {
  const _AvatarUploadDialog();

  @override
  Widget build(BuildContext context) {
    return const TonztoonModalDialog(
      title: 'Mengunggah foto',
      message:
          'Foto profil sedang diproses dan disimpan. Tunggu sebentar sampai unggahan selesai.',
      art: TonztoonModalArt.editHeaderProfile,
      showActions: false,
      showCloseButton: false,
      content: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 2.8),
      ),
    );
  }
}

class _ProfileStats extends ConsumerWidget {
  const _ProfileStats({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingTime = ref.watch(readingTimeProvider);
    final bookmarkCount = _bookmarkCountLabel(summary);
    final activeTime = _readingTimeLabel(readingTime);

    return _SettingsSection(
      child: Row(
        children: [
          Expanded(
            child: _StatBlock(
              value: bookmarkCount,
              label: 'Bookmark',
              onTap: () => context.go(libraryBookmarksLocation),
            ),
          ),
          const SizedBox(height: 42, child: VerticalDivider(width: 1)),
          Expanded(
            child: _StatBlock(value: activeTime, label: 'Aktif'),
          ),
        ],
      ),
    );
  }

  String _bookmarkCountLabel(AsyncValue<LibrarySummary> summary) {
    final bookmarkCount = summary.asData?.value.counts.bookmarks;
    if (bookmarkCount == null) return '...';
    if (bookmarkCount > 999) return '999+';
    return '$bookmarkCount';
  }
}

class _GuestReadingTimeCard extends ConsumerWidget {
  const _GuestReadingTimeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readingTime = ref.watch(readingTimeProvider);

    return _SettingsSection(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            const _IconBubble(icon: TonztoonIcons.bookOpen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Waktu Baca Guest',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tersimpan lokal dan bisa dimigrasi saat login',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _readingTimeLabel(readingTime),
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _readingTimeLabel(Duration duration) {
  if (duration.inSeconds <= 0) return '0m';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}j ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) return '${minutes}m';
  return '${duration.inSeconds}s';
}

class _FavoriteScenesSettingsRow extends ConsumerWidget {
  const _FavoriteScenesSettingsRow({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = summary.asData?.value.counts.favoriteScenes;

    return _SettingsRow(
      icon: TonztoonIcons.heart,
      title: 'My Favorites',
      subtitle: count == null
          ? 'Favorite comic scenes only'
          : '$count scene komik favorit',
      onTap: () => _openAccountFlow(context, const _MyFavoritesScreen()),
    );
  }
}

class _SavedCollectionsSettingsRow extends ConsumerWidget {
  const _SavedCollectionsSettingsRow({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = summary.asData?.value.counts.collections;

    return _SettingsRow(
      icon: TonztoonIcons.bookmark,
      title: 'Saved Collections',
      subtitle: count == null
          ? 'Synced reading shelves'
          : '$count koleksi tersinkron',
      onTap: () => context.go(libraryCollectionsLocation),
    );
  }
}

class _MyDownloadsSettingsRow extends ConsumerWidget {
  const _MyDownloadsSettingsRow({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = summary.asData?.value.counts.downloads;

    return _SettingsRow(
      icon: TonztoonIcons.download,
      title: 'My Downloads',
      subtitle: count == null
          ? 'Synced download wishlist'
          : '$count chapter tersimpan di wishlist download',
      onTap: () => _openAccountFlow(context, const _MyDownloadsScreen()),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.tertiary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: content,
        ),
      ),
    );
  }
}

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

class _ProfileSetupDialog extends StatefulWidget {
  const _ProfileSetupDialog({
    required this.requireUsername,
    required this.requirePassword,
    required this.title,
    required this.description,
    required this.cancelLabel,
    required this.submitLabel,
    required this.savingLabel,
    required this.onSubmit,
  });

  final bool requireUsername;
  final bool requirePassword;
  final String title;
  final String description;
  final String cancelLabel;
  final String submitLabel;
  final String savingLabel;
  final Future<void> Function({String? username, String? password}) onSubmit;

  @override
  State<_ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<_ProfileSetupDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_saving,
      child: TonztoonModalDialog(
        title: widget.title,
        message: widget.description,
        art: widget.requireUsername && widget.requirePassword
            ? TonztoonModalArt.accountSetup
            : widget.requirePassword
            ? TonztoonModalArt.passwordSetup
            : TonztoonModalArt.accountSetup,
        showCloseButton: !_saving,
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorText != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorText!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.requireUsername) ...[
                  TextFormField(
                    controller: _usernameController,
                    enabled: !_saving,
                    autofocus: true,
                    maxLength: 50,
                    textInputAction: widget.requirePassword
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      helperText:
                          'Tampil sebagai @username dan tidak dapat diubah setelah dibuat. Huruf, angka, titik, strip, atau underscore.',
                    ),
                    validator: _validateUsernameValue,
                    onFieldSubmitted: (_) {
                      if (!widget.requirePassword) _submit();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.requirePassword) ...[
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_saving,
                    autofocus: !widget.requireUsername,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password baru',
                      helperText: 'Minimal 8 karakter.',
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Tampilkan password'
                            : 'Sembunyikan password',
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        icon: Icon(
                          _obscurePassword
                              ? TonztoonIcons.eye
                              : TonztoonIcons.eyeOff,
                        ),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmController,
                    enabled: !_saving,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Konfirmasi password',
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirm
                            ? 'Tampilkan password'
                            : 'Sembunyikan password',
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                        icon: Icon(
                          _obscureConfirm
                              ? TonztoonIcons.eye
                              : TonztoonIcons.eyeOff,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Konfirmasi password tidak sama.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
              ],
            ),
          ),
        ),
        secondaryLabel: widget.cancelLabel,
        onSecondaryPressed: _saving
            ? null
            : () => Navigator.of(context).pop(false),
        primaryLabel: _saving ? widget.savingLabel : widget.submitLabel,
        primaryLoading: _saving,
        onPrimaryPressed: _saving ? null : _submit,
      ),
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Password minimal 8 karakter.';
    if (password.length > 128) return 'Password maksimal 128 karakter.';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(
        username: widget.requireUsername
            ? _usernameController.text.trim()
            : null,
        password: widget.requirePassword ? _passwordController.text : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        fallbackMessage: 'Data akun belum dapat disimpan. Silakan coba lagi.',
      );
      logAppError(error, stackTrace, context: 'Save profile setup failed');
      setState(() {
        _saving = false;
        _errorText = message;
      });
      showAppSnackBar(context, message: message, type: AppSnackBarType.failure);
    }
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
    required this.onSubmit,
    this.title = 'Change Password',
    this.description,
    this.submitLabel = 'Simpan',
    this.savingLabel = 'Simpan',
  });

  final Future<void> Function(String password) onSubmit;
  final String title;
  final String? description;
  final String submitLabel;
  final String savingLabel;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: TonztoonModalDialog(
        title: widget.title,
        message:
            widget.description ??
            'Gunakan password baru yang kuat dan mudah kamu ingat.',
        helperText: 'Password minimal 8 karakter dan maksimal 128 karakter.',
        helperIcon: TonztoonIcons.keyRound,
        art: TonztoonModalArt.passwordSetup,
        showCloseButton: !_saving,
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _passwordController,
                enabled: !_saving,
                autofocus: true,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Password baru',
                  errorText: _errorText,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Tampilkan password'
                        : 'Sembunyikan password',
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    icon: Icon(
                      _obscurePassword
                          ? TonztoonIcons.eye
                          : TonztoonIcons.eyeOff,
                    ),
                  ),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (password.length < 8) {
                    return 'Password minimal 8 karakter.';
                  }
                  if (password.length > 128) {
                    return 'Password maksimal 128 karakter.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                enabled: !_saving,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Konfirmasi password',
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm
                        ? 'Tampilkan password'
                        : 'Sembunyikan password',
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                    icon: Icon(
                      _obscureConfirm
                          ? TonztoonIcons.eye
                          : TonztoonIcons.eyeOff,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Konfirmasi password tidak sama.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        secondaryLabel: 'Batal',
        onSecondaryPressed: _saving
            ? null
            : () => Navigator.of(context).pop(false),
        primaryLabel: _saving ? widget.savingLabel : widget.submitLabel,
        primaryLoading: _saving,
        onPrimaryPressed: _saving ? null : _submit,
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(_passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        fallbackMessage: 'Password gagal disimpan. Silakan coba lagi.',
      );
      logAppError(error, stackTrace, context: 'Save password failed');
      setState(() {
        _saving = false;
        _errorText = message;
      });
      showAppSnackBar(context, message: message, type: AppSnackBarType.failure);
    }
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

class _PushNotificationsSettingsRow extends ConsumerStatefulWidget {
  const _PushNotificationsSettingsRow();

  @override
  ConsumerState<_PushNotificationsSettingsRow> createState() =>
      _PushNotificationsSettingsRowState();
}

class _PushNotificationsSettingsRowState
    extends ConsumerState<_PushNotificationsSettingsRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(pushNotificationPreferencesProvider);

    return _SettingsRow(
      icon: TonztoonIcons.bell,
      title: 'Push Notifications',
      subtitle: preferences.enabled
          ? 'Update chapter dan status download aktif'
          : 'Aktifkan alert untuk perangkat ini',
      onTap: _saving ? null : () => _setEnabled(!preferences.enabled),
      trailing: Switch.adaptive(
        value: preferences.enabled,
        onChanged: _saving ? null : _setEnabled,
      ),
    );
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      if (value) {
        final granted = await ref
            .read(pushNotificationServiceProvider)
            .requestPermissions();
        if (!granted) {
          if (!mounted) return;
          showAppSnackBar(
            context,
            message:
                'Izin notifikasi belum diberikan. Aktifkan izin TonzToon dari pengaturan perangkat.',
            type: AppSnackBarType.warning,
          );
          return;
        }
      }

      await ref
          .read(pushNotificationPreferencesProvider.notifier)
          .setEnabled(value);
      if (!value) {
        await ref.read(pushNotificationServiceProvider).dismissAll();
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Update push notification preference failed',
        fallbackMessage: 'Pengaturan notifikasi belum dapat disimpan.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.active,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: active ? const _StatusBadge(label: 'Now') : null,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AccountFlowScaffold extends StatelessWidget {
  const _AccountFlowScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: children,
      ),
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.prefs,
    required this.themeMode,
    required this.isSignedIn,
    required this.onThemeChanged,
    required this.onReaderModeChanged,
    required this.onDirectionChanged,
    required this.onBingeModeChanged,
    required this.onMarkReadChanged,
    required this.onClearCache,
    required this.onOpenAuth,
  });

  final ReaderPreferences prefs;
  final ThemeMode themeMode;
  final bool isSignedIn;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String> onReaderModeChanged;
  final ValueChanged<String> onDirectionChanged;
  final ValueChanged<bool> onBingeModeChanged;
  final ValueChanged<bool> onMarkReadChanged;
  final VoidCallback onClearCache;
  final VoidCallback onOpenAuth;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      children: [
        _SegmentedSetting(
          icon: TonztoonIcons.lightMode,
          title: 'Theme',
          options: const {
            'System': Icons.brightness_auto_rounded,
            'Light': Icons.light_mode_rounded,
            'Dark': Icons.dark_mode_rounded,
          },
          selected: _themeModeLabel(themeMode),
          onChanged: onThemeChanged,
        ),
        const _SettingsDivider(),
        _SegmentedSetting(
          icon: TonztoonIcons.bookOpen,
          title: 'Reader Mode',
          options: const {
            'Vertical': Icons.view_day_rounded,
            'Paged': Icons.view_carousel_rounded,
          },
          selected: _readerModeLabel(prefs.defaultReadingMode),
          onChanged: onReaderModeChanged,
        ),
        const _SettingsDivider(),
        _SegmentedSetting(
          icon: TonztoonIcons.rows,
          title: 'Direction',
          options: const {
            'LTR': Icons.format_textdirection_l_to_r_rounded,
            'RTL': Icons.format_textdirection_r_to_l_rounded,
          },
          selected: _directionLabel(prefs.readingDirection),
          onChanged: onDirectionChanged,
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.skipForward,
          title: 'Binge Mode',
          subtitle: 'Auto-next chapter dan continuous reading',
          trailing: Switch.adaptive(
            value: prefs.defaultBingeMode,
            onChanged: onBingeModeChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.check,
          title: 'Mark Read on Complete',
          subtitle: 'Save completed chapters visually',
          trailing: Switch.adaptive(
            value: prefs.markReadOnComplete,
            onChanged: onMarkReadChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.paintbrush,
          title: 'Clear Catalog Cache',
          subtitle: 'Refresh source, catalog, comic, and chapter data',
          onTap: onClearCache,
        ),
        if (!isSignedIn) ...[
          const _SettingsDivider(),
          _SettingsRow(
            icon: TonztoonIcons.login,
            title: 'Login / Register',
            subtitle: 'Email, Google, atau lanjut sebagai guest',
            onTap: onOpenAuth,
          ),
        ],
      ],
    );
  }
}

class _SegmentedSetting extends StatelessWidget {
  const _SegmentedSetting({
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final Map<String, IconData> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      child: Row(
        children: [
          _IconBubble(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in options.entries)
                  GestureDetector(
                    onTap: () => onChanged(entry.key),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected == entry.key
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        entry.value,
                        size: 18,
                        color: selected == entry.key
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AppVersionSection extends StatelessWidget {
  const _AppVersionSection({required this.packageInfoFuture});

  final Future<PackageInfo> packageInfoFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: packageInfoFuture,
      builder: (context, snapshot) {
        final versionLabel = switch (snapshot) {
          AsyncSnapshot<PackageInfo>(hasData: true, data: final info?) =>
            _formatVersion(info),
          AsyncSnapshot<PackageInfo>(hasError: true) => 'Tidak tersedia',
          _ => 'Memuat...',
        };

        return _SettingsSection(
          children: [
            _SettingsRow(
              icon: TonztoonIcons.badge,
              title: 'App Version',
              subtitle: 'Mengikuti metadata build terbaru',
              trailing: Text(
                versionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatVersion(PackageInfo info) {
    final version = info.version.trim();
    final buildNumber = info.buildNumber.trim();
    if (version.isEmpty && buildNumber.isEmpty) return 'Tidak tersedia';
    if (buildNumber.isEmpty) return 'v$version';
    if (version.isEmpty) return 'Build $buildNumber';
    return 'v$version ($buildNumber)';
  }
}

class _SettingsLoadingPlaceholder extends StatelessWidget {
  const _SettingsLoadingPlaceholder({required this.isSignedIn});

  final bool isSignedIn;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
      children: [
        if (isSignedIn) ...[
          const _ProfileHeaderSkeleton(),
          const SizedBox(height: 18),
          const _ProfileStatsSkeleton(),
          const SizedBox(height: 24),
          const _SectionLabelSkeleton(width: 74),
          const SizedBox(height: 8),
          const _SettingsSectionSkeleton(rowCount: 6, includeSwitch: true),
          const SizedBox(height: 24),
        ] else ...[
          const _SettingsSectionSkeleton(rowCount: 1, compact: true),
          const SizedBox(height: 24),
        ],
        const _SectionLabelSkeleton(width: 96),
        const SizedBox(height: 8),
        _SettingsSectionSkeleton(rowCount: isSignedIn ? 8 : 9),
        if (isSignedIn) ...[
          const SizedBox(height: 24),
          const _SettingsButtonSkeleton(),
        ],
        const SizedBox(height: 24),
        const _SectionLabelSkeleton(width: 54),
        const SizedBox(height: 8),
        const _SettingsSectionSkeleton(rowCount: 1, compact: true),
      ],
    );
  }
}

class _ProfileHeaderSkeleton extends StatelessWidget {
  const _ProfileHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Column(
        children: [
          AppShimmerBlock(width: 88, height: 88, borderRadius: 44),
          SizedBox(height: 12),
          AppShimmerBlock(width: 170, height: 24),
          SizedBox(height: 8),
          AppShimmerBlock(width: 70, height: 24, borderRadius: 18),
        ],
      ),
    );
  }
}

class _ProfileStatsSkeleton extends StatelessWidget {
  const _ProfileStatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: AppShimmer(
        child: Row(
          children: [
            Expanded(child: _StatBlockSkeleton()),
            SizedBox(width: 28),
            Expanded(child: _StatBlockSkeleton()),
          ],
        ),
      ),
    );
  }
}

class _StatBlockSkeleton extends StatelessWidget {
  const _StatBlockSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppShimmerBlock(width: 44, height: 26),
        SizedBox(height: 4),
        AppShimmerBlock(width: 68, height: 13),
      ],
    );
  }
}

class _SectionLabelSkeleton extends StatelessWidget {
  const _SectionLabelSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(child: AppShimmerBlock(width: width, height: 16));
  }
}

class _SettingsSectionSkeleton extends StatelessWidget {
  const _SettingsSectionSkeleton({
    required this.rowCount,
    this.compact = false,
    this.includeSwitch = false,
  });

  final int rowCount;
  final bool compact;
  final bool includeSwitch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < rowCount; index++) ...[
          _SettingsRowSkeleton(
            compact: compact,
            trailingWide: includeSwitch && index == rowCount - 1,
          ),
          if (index != rowCount - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SettingsRowSkeleton extends StatelessWidget {
  const _SettingsRowSkeleton({this.compact = false, this.trailingWide = false});

  final bool compact;
  final bool trailingWide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: AppShimmer(
        child: Row(
          children: [
            const AppShimmerBlock(width: 35, height: 35, borderRadius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppShimmerBlock(
                    width: compact ? 132 : double.infinity,
                    height: 16,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    const AppShimmerBlock(width: 210, height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppShimmerBlock(
              width: trailingWide ? 52 : 18,
              height: trailingWide ? 28 : 18,
              borderRadius: trailingWide ? 14 : 9,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsButtonSkeleton extends StatelessWidget {
  const _SettingsButtonSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: AppShimmerBlock(
        width: double.infinity,
        height: 50,
        borderRadius: 18,
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({this.child, this.children});

  final Widget? child;
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.24
                  : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child ?? Column(children: children ?? const []),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: colorScheme.primary.withValues(alpha: 0.12),
        highlightColor: colorScheme.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          child: Row(
            children: [
              _IconBubble(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    TonztoonIcons.chevronRight,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 50,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
