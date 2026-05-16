import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../models/app_notification.dart';
import '../../repositories/providers.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifikasi', style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
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
              data: (_) => ListView(
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
              loading: () => const _NotificationsLoading(),
              error: (error, stackTrace) => _NotificationsError(
                message: error.toString(),
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
            ),
          ),
          _NotificationsBottomFade(background: theme.scaffoldBackgroundColor),
        ],
      ),
    );
  }

  Future<void> _markAllRead() {
    return ref.read(notificationsProvider.notifier).markAllRead();
  }

  Future<void> _openNotification(AppNotification item) async {
    if (item.unread) {
      await ref.read(notificationsProvider.notifier).markRead(item.id);
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF17232E), Color(0xFF261A16)]
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
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in const [
            'Semua',
            'Update',
            'Pustaka',
            'Rekomendasi',
          ]) ...[
            ChoiceChip(
              label: Text(filter),
              selected: selectedFilter == filter,
              onSelected: (_) => onChanged(filter),
              selectedColor: colorScheme.primary.withValues(alpha: 0.18),
              labelStyle: TextStyle(
                color: selectedFilter == filter
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: colorScheme.outlineVariant),
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

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: item.unread
                  ? colorScheme.primary.withValues(alpha: 0.38)
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NotificationIcon(icon: style.icon, accent: style.accent),
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
                              style: theme.textTheme.titleMedium,
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
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Text(
                            _relativeTime(item.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CategoryPill(label: item.category),
                        ],
                      ),
                    ],
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

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 20, color: accent),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
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
