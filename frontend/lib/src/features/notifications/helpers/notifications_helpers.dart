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
  // 1. Check for specific action-based kinds first
  switch (item.kind) {
    case 'download_completed':
      return const _NotificationStyle(
        icon: TonztoonIcons.download,
        accent: Color(0xFF3A86FF),
      );
    case 'download_failed':
      return const _NotificationStyle(
        icon: TonztoonIcons.warning,
        accent: Color(0xFFEF4444),
      );
    case 'download_cancelled':
      return const _NotificationStyle(
        icon: TonztoonIcons.close,
        accent: Color(0xFF64748B),
      );
    case 'progress_sync_failed':
      return const _NotificationStyle(
        icon: TonztoonIcons.warning,
        accent: Color(0xFFEF4444),
      );
    case 'recommendation':
      return const _NotificationStyle(
        icon: TonztoonIcons.autoAwesome,
        accent: Color(0xFFFFD60A),
      );
    case 'chapter_update':
      return const _NotificationStyle(
        icon: TonztoonIcons.bookOpen,
        accent: Color(0xFFFF9D00),
      );
  }

  // 2. Fallback to category-based styling for consistent visual identity
  switch (item.category) {
    case 'Update':
      return const _NotificationStyle(
        icon: TonztoonIcons.bookOpen,
        accent: Color(0xFFFF9D00),
      );
    case 'Pustaka':
      return const _NotificationStyle(
        icon: TonztoonIcons.library,
        accent: Color(0xFF7F00FF),
      );
    case 'Pengumuman':
      return const _NotificationStyle(
        icon: TonztoonIcons.autoAwesome,
        accent: Color(0xFFF59E0B),
      );
    case 'Testing':
      return const _NotificationStyle(
        icon: TonztoonIcons.bug,
        accent: Color(0xFF00B4DB),
      );
    case 'Maintenance':
      return const _NotificationStyle(
        icon: TonztoonIcons.settings,
        accent: Color(0xFFED213A),
      );
    default:
      return const _NotificationStyle(
        icon: TonztoonIcons.bell,
        accent: Color(0xFF22C55E),
      );
  }
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
