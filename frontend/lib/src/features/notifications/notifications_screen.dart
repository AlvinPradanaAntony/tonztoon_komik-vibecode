import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_error.dart';
import '../../core/app_icons.dart';
import '../../core/app_snackbar.dart';
import '../../models/app_notification.dart';
import '../../repositories/providers.dart';
import '../../widgets/tonztoon_modal_dialog.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

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
            _NotificationsBottomFade(background: theme.scaffoldBackgroundColor),
          ],
        ),
        floatingActionButton: notifications.isEmpty
            ? null
            : FloatingActionButton(
                tooltip: 'Bersihkan notifikasi',
                onPressed: _clearNotifications,
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: Colors.white,
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
    context.go(route);
  }
}

class _NotificationsBottomFade extends StatelessWidget {
  const _NotificationsBottomFade({required this.background});

  final Color background;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 120,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.6, 1.0],
              colors: [
                background.withValues(alpha: 0.0),
                background.withValues(alpha: 0.9),
                background,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      key: const ValueKey('notification-summary'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF143248), Color(0xFF402515)]
              : const [Color(0xFFFFF2DD), Color(0xFFE8F6FF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.74),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(TonztoonIcons.bell, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unreadCount == 0
                        ? 'Tidak ada notifikasi baru'
                        : '$unreadCount notifikasi baru',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Update chapter, aktivitas pustaka, dan rekomendasi bacaan.',
                    style: theme.textTheme.bodySmall,
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

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.selectedFilter, required this.onChanged});

  final String selectedFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in const [
            'Semua',
            'Update',
            'Pustaka',
            'Sistem',
          ]) ...[
            ChoiceChip(
              key: ValueKey('notification-filter-$filter'),
              label: Text(filter),
              selected: selectedFilter == filter,
              onSelected: (_) => onChanged(filter),
              showCheckmark: false,
              backgroundColor: isDark
                  ? colorScheme.surfaceContainer
                  : colorScheme.surface,
              selectedColor: colorScheme.primary,
              disabledColor: colorScheme.surfaceContainerLow,
              surfaceTintColor: Colors.transparent,
              labelStyle: TextStyle(
                color: selectedFilter == filter
                    ? colorScheme.onPrimary
                    : isDark
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: selectedFilter == filter
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(
                          alpha: isDark ? 0.8 : 1,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(TonztoonIcons.autoAwesome, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          '$count item',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = _notificationStyle(item);

    // Background color: Blend with primary if unread for a soft modern tint
    final cardColor = item.unread
        ? Color.lerp(colorScheme.surface, colorScheme.primary, 0.07)!
        : colorScheme.surface;

    // Subtle colored shadow for unread, flat shadow for read
    final shadowColor = item.unread
        ? colorScheme.primary.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.04);

    final elevation = item.unread ? 2.5 : 0.8;

    return Material(
      color: cardColor,
      elevation: elevation,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: item.unread
            ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.16), width: 1)
            : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Visual Accent Indicator on the left edge
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 4.5,
                decoration: BoxDecoration(
                  color: item.unread ? colorScheme.primary : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NotificationIcon(
                        icon: style.icon,
                        accent: style.accent,
                        isUnread: item.unread,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: item.unread ? FontWeight.w800 : FontWeight.w600,
                                      color: item.unread
                                          ? null
                                          : (theme.textTheme.titleMedium?.color ?? colorScheme.onSurface).withValues(alpha: 0.72),
                                    ),
                                  ),
                                ),
                                if (item.unread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.primary.withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          spreadRadius: 1.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  _relativeTime(item.createdAt),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: item.unread
                                        ? colorScheme.secondary
                                        : colorScheme.secondary.withValues(alpha: 0.6),
                                    fontWeight: item.unread ? FontWeight.w900 : FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.35,
                                color: item.unread
                                    ? null
                                    : (theme.textTheme.bodySmall?.color ?? colorScheme.onSurfaceVariant).withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 9),
                            _CategoryPill(
                              label: item.category,
                              isUnread: item.unread,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({
    required this.icon,
    required this.accent,
    required this.isUnread,
  });

  final IconData icon;
  final Color accent;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isUnread
            ? accent.withValues(alpha: 0.20)
            : accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isUnread
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          size: 20,
          color: isUnread ? accent : accent.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.isUnread});

  final String label;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUnread
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: isUnread
                    ? null
                    : (Theme.of(context).textTheme.labelSmall?.color ?? colorScheme.onSurface).withValues(alpha: 0.6),
              ),
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 2.6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          children: [
            Icon(TonztoonIcons.bell, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              filter == 'Semua'
                  ? 'Belum ada notifikasi'
                  : 'Belum ada notifikasi $filter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Aktivitas nyata seperti status download akan muncul di sini.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsLoading extends StatelessWidget {
  const _NotificationsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
      children: const [
        _LoadingCard(height: 96),
        SizedBox(height: 18),
        Row(
          children: [
            _LoadingCard(width: 78, height: 34),
            SizedBox(width: 8),
            _LoadingCard(width: 78, height: 34),
            SizedBox(width: 8),
            _LoadingCard(width: 92, height: 34),
          ],
        ),
        SizedBox(height: 20),
        _LoadingCard(width: 170, height: 24),
        SizedBox(height: 10),
        _LoadingCard(height: 92),
        SizedBox(height: 12),
        _LoadingCard(height: 92),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({this.width = double.infinity, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class _NotificationsError extends StatelessWidget {
  const _NotificationsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.warning, size: 34),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

List<AppNotification> _visibleNotifications(
  List<AppNotification> notifications,
  String filter,
) {
  if (filter == 'Semua') return notifications;
  if (filter == 'Sistem') {
    return notifications
        .where(
          (item) => item.category != 'Update' && item.category != 'Pustaka',
        )
        .toList(growable: false);
  }
  return notifications
      .where((item) => item.category == filter)
      .toList(growable: false);
}

_NotificationStyle _notificationStyle(AppNotification item) {
  return switch (item.kind) {
    'download_completed' => const _NotificationStyle(
      icon: TonztoonIcons.download,
      accent: Color(0xFF3A86FF),
    ),
    'download_failed' => const _NotificationStyle(
      icon: TonztoonIcons.warning,
      accent: Color(0xFFEF4444),
    ),
    'download_cancelled' => const _NotificationStyle(
      icon: TonztoonIcons.close,
      accent: Color(0xFF64748B),
    ),
    'recommendation' => const _NotificationStyle(
      icon: TonztoonIcons.autoAwesome,
      accent: Color(0xFFFFD60A),
    ),
    'chapter_update' => const _NotificationStyle(
      icon: TonztoonIcons.bookOpen,
      accent: Color(0xFFFF9D00),
    ),
    'progress_sync_failed' => const _NotificationStyle(
      icon: TonztoonIcons.warning,
      accent: Color(0xFFEF4444),
    ),
    _ => const _NotificationStyle(
      icon: TonztoonIcons.bell,
      accent: Color(0xFF22C55E),
    ),
  };
}

String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays == 1) return 'Kemarin';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  return '${value.day}/${value.month}/${value.year}';
}

class _NotificationStyle {
  const _NotificationStyle({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;
}
