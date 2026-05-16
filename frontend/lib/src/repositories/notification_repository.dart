import '../core/storage.dart';
import '../models/app_notification.dart';
import '../models/comic.dart';
import '../models/library.dart';

class NotificationRepository {
  NotificationRepository(this._store);

  static const _storageKey = 'app_notifications';
  static const _latestChapterSeenKey = 'notification_latest_chapters_seen';
  static const progressSyncFailedId = 'sync:progress:failed';
  static const _maxNotifications = 120;

  final LocalStore _store;

  Future<List<AppNotification>> getNotifications() async {
    final notifications = _readNotifications()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notifications;
  }

  Future<List<AppNotification>> add(AppNotification notification) async {
    final notifications = _readNotifications();
    final index = notifications.indexWhere(
      (item) => item.id == notification.id,
    );
    if (index >= 0) {
      notifications[index] = notification;
    } else {
      notifications.insert(0, notification);
    }
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = notifications.take(_maxNotifications).toList();
    await _writeNotifications(trimmed);
    return trimmed;
  }

  Future<List<AppNotification>> markRead(String id) async {
    final notifications =
        _readNotifications()
            .map((item) => item.id == id ? item.copyWith(unread: false) : item)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeNotifications(notifications);
    return notifications;
  }

  Future<List<AppNotification>> markAllRead() async {
    final notifications =
        _readNotifications()
            .map((item) => item.copyWith(unread: false))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeNotifications(notifications);
    return notifications;
  }

  Future<List<AppNotification>> remove(String id) async {
    final notifications =
        _readNotifications().where((item) => item.id != id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _writeNotifications(notifications);
    return notifications;
  }

  Future<List<AppNotification>> recordLatestChapterUpdates(
    List<ComicSummary> comics,
  ) async {
    final seen = _readSeenLatestChapters();
    final notifications = _readNotifications();
    var changed = false;

    for (final comic in comics) {
      final latest = comic.latestChapterNumber;
      if (latest == null || latest <= 0 || comic.slug.isEmpty) continue;

      final key = '${comic.sourceName}|${comic.slug}';
      final previous = seen[key];
      if (previous != null && latest > previous) {
        notifications.insert(
          0,
          AppNotification(
            id: 'chapter:${comic.sourceName}:${comic.slug}:$latest',
            title: 'Chapter baru tersedia',
            message:
                '${comic.title} Chapter ${_formatChapterNumber(latest)} baru saja rilis.',
            category: 'Update',
            kind: 'chapter_update',
            createdAt: DateTime.now(),
            actionRoute:
                '/comic/${Uri.encodeComponent(comic.sourceName)}/${Uri.encodeComponent(comic.slug)}',
          ),
        );
        changed = true;
      }
      if (previous == null || latest > previous) {
        seen[key] = latest;
      }
    }

    await _store.library.put(_latestChapterSeenKey, seen);
    if (!changed) return getNotifications();

    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = notifications.take(_maxNotifications).toList();
    await _writeNotifications(trimmed);
    return trimmed;
  }

  AppNotification downloadCompleted(OfflineDownloadBatch batch) {
    return _downloadNotification(
      batch,
      idSuffix: 'completed',
      title: 'Download selesai',
      message: '${batch.comic.title} siap dibaca offline.',
      kind: 'download_completed',
    );
  }

  AppNotification downloadFailed(OfflineDownloadBatch batch) {
    return _downloadNotification(
      batch,
      idSuffix: 'failed',
      title: 'Download gagal',
      message: batch.lastError?.isNotEmpty == true
          ? batch.lastError!
          : '${batch.comic.title} gagal diunduh.',
      kind: 'download_failed',
    );
  }

  AppNotification downloadCancelled(OfflineDownloadBatch batch) {
    return _downloadNotification(
      batch,
      idSuffix: 'cancelled',
      title: 'Download dibatalkan',
      message: '${batch.comic.title} tidak jadi diunduh.',
      kind: 'download_cancelled',
    );
  }

  AppNotification progressSyncFailed() {
    return AppNotification(
      id: progressSyncFailedId,
      title: 'Progress belum tersinkron',
      message:
          'Progress tersimpan di perangkat ini dan akan dicoba lagi saat kamu lanjut membaca.',
      category: 'Pustaka',
      kind: 'progress_sync_failed',
      createdAt: DateTime.now(),
    );
  }

  AppNotification _downloadNotification(
    OfflineDownloadBatch batch, {
    required String idSuffix,
    required String title,
    required String message,
    required String kind,
  }) {
    return AppNotification(
      id: 'download:${batch.id}:$idSuffix',
      title: title,
      message: message,
      category: 'Pustaka',
      kind: kind,
      createdAt: DateTime.now(),
      actionRoute: '/library?tab=downloads',
    );
  }

  List<AppNotification> _readNotifications() {
    final raw = _store.library.get(_storageKey);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map(AppNotification.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Map<String, double> _readSeenLatestChapters() {
    final raw = _store.library.get(_latestChapterSeenKey);
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0,
      ),
    );
  }

  Future<void> _writeNotifications(List<AppNotification> notifications) {
    return _store.library.put(
      _storageKey,
      notifications.map((item) => item.toJson()).toList(),
    );
  }

  String _formatChapterNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
