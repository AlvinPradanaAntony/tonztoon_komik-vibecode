part of '../notifications_screen.dart';

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _selectedFilter = 'Semua';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsProvider);
    final notifications = notificationsAsync.asData?.value ?? const [];
    final visibleNotifications = _visibleNotifications(
      notifications,
      _selectedFilter,
    );
    final unreadCount = notifications.where((item) => item.unread).length;
    final isDark = theme.brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        extendBody: true,
        appBar: AppBar(
          title: Text('Notifikasi', style: theme.textTheme.titleLarge),
          centerTitle: false,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: 'Kembali',
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
              icon: const Icon(TonztoonIcons.arrowBack),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton(
                onPressed: unreadCount == 0 ? null : _markAllRead,
                child: const Text('Tandai dibaca'),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: notificationsAsync.when(
                data: (_) => RefreshIndicator(
                  onRefresh: _refreshNotifications,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
                    children: [
                      _NotificationSummary(unreadCount: unreadCount),
                      const SizedBox(height: 18),
                      _FilterStrip(
                        notifications: notifications,
                        selectedFilter: _selectedFilter,
                        onChanged: (value) =>
                            setState(() => _selectedFilter = value),
                      ),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        title: _selectedFilter == 'Semua'
                            ? 'Terbaru'
                            : 'Kategori $_selectedFilter',
                        count: visibleNotifications.length,
                      ),
                      const SizedBox(height: 10),
                      if (visibleNotifications.isEmpty)
                        _NotificationEmptyState(filter: _selectedFilter)
                      else
                        for (final item in visibleNotifications) ...[
                          _NotificationTile(
                            item: item,
                            onTap: () => _openNotification(item),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
                loading: () => const _NotificationsLoading(),
                error: (error, stackTrace) {
                  logAppError(
                    error,
                    stackTrace,
                    context: 'Notifications provider failed',
                  );
                  return _NotificationsError(
                    message: friendlyErrorMessage(
                      error,
                      fallbackMessage:
                          'Notifikasi belum dapat dimuat. Silakan coba lagi.',
                    ),
                    onRetry: () => ref.invalidate(notificationsProvider),
                  );
                },
              ),
            ),
            AppEdgeFade(background: theme.scaffoldBackgroundColor, height: 120),
          ],
        ),
        floatingActionButton: notifications.isEmpty
            ? null
            : FloatingActionButton(
                heroTag: 'notifications-clear',
                tooltip: 'Bersihkan notifikasi',
                onPressed: _clearNotifications,
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.surface,
                shape: const CircleBorder(),
                child: const Icon(TonztoonIcons.trash),
              ),
      ),
    );
  }

  Future<void> _refreshNotifications() {
    return ref.read(notificationsProvider.notifier).refresh();
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsProvider.notifier).markAllRead();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Semua notifikasi ditandai dibaca.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Mark all notifications read failed',
        fallbackMessage:
            'Gagal menandai semua notifikasi dibaca. Silakan coba lagi.',
      );
    }
  }

  Future<void> _clearNotifications() async {
    final confirmed = await showTonztoonConfirmDialog(
      context,
      title: 'Bersihkan notifikasi?',
      message:
          'Semua notifikasi akan dihapus dari perangkat ini dan tidak dapat dikembalikan.',
      eyebrow: 'BERSIHKAN NOTIFIKASI',
      confirmLabel: 'Bersihkan',
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.trash,
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(notificationsProvider.notifier).clear();
      if (!mounted) return;
      setState(() => _selectedFilter = 'Semua');
      showAppSnackBar(
        context,
        message: 'Semua notifikasi telah dibersihkan.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Clear notifications failed',
        fallbackMessage:
            'Notifikasi belum dapat dibersihkan. Silakan coba lagi.',
      );
    }
  }

  Future<void> _openNotification(AppNotification item) async {
    try {
      if (item.unread) {
        await ref.read(notificationsProvider.notifier).markRead(item.id);
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Open notification failed',
        fallbackMessage: 'Gagal membuka notifikasi. Silakan coba lagi.',
      );
      return;
    }

    if (!mounted) return;
    final route = item.actionRoute;
    if (route == null || route.isEmpty) return;
    final uri = Uri.tryParse(route);
    if (uri != null &&
        (uri.path == '/notifications' || uri.path == '/notifications/')) {
      return;
    }

    if (uri?.path == '/library') {
      context.go(route);
      return;
    }
    await context.push<void>(route);
  }
}
