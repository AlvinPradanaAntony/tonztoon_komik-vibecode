part of '../notifications_screen.dart';

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
