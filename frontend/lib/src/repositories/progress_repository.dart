import 'dart:async';
import 'dart:collection';

import '../core/api_client.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/progress.dart';
import 'local_state_metadata.dart';
import 'notification_repository.dart';

class ProgressRepository {
  ProgressRepository(
    this._api,
    this._tokenStore,
    this._store, {
    NotificationRepository? notificationRepository,
    void Function()? onNotificationsChanged,
  }) : _notificationRepository = notificationRepository,
       _onNotificationsChanged = onNotificationsChanged;

  final TonztoonApi _api;
  final TokenStore _tokenStore;
  final LocalStore _store;
  final NotificationRepository? _notificationRepository;
  final void Function()? _onNotificationsChanged;
  final Queue<ReadingProgress> _progressSyncQueue = Queue<ReadingProgress>();
  bool _syncingProgress = false;

  Future<List<ReadingProgress>> getContinueReading() async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _api.get<List<dynamic>>(
          '/library/progress/continue-reading',
        );
        return (response.data ?? const [])
            .whereType<Map>()
            .map(
              (item) => ReadingProgress.fromLibraryJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList();
      } catch (_) {
        return _localContinueReading();
      }
    }
    return _localContinueReading();
  }

  Future<ReadingProgress?> getProgress(String sourceName, String slug) async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _api.get<Map<String, dynamic>?>(
          '/library/progress/$sourceName/comics/$slug',
        );
        final data = response.data;
        return data == null ? null : ReadingProgress.fromLibraryJson(data);
      } catch (_) {
        return _localProgress(sourceName, slug);
      }
    }
    return _localProgress(sourceName, slug);
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    await _store.progress.put(progress.storageKey, progress.toLocalJson());
    if (progress.isCompleted) {
      await _saveLocalCompletedChapter(progress);
    }

    final token = await _tokenStore.readAccessToken();
    if (token == null || token.isEmpty) {
      await LocalStateMetadata.clearAuthenticatedProgressCache(
        _store,
        progress,
      );
      return;
    }

    await LocalStateMetadata.markAuthenticatedProgressCache(_store, progress);
    _enqueueProgressSync(progress);
  }

  void _enqueueProgressSync(ReadingProgress progress) {
    _progressSyncQueue.add(progress);
    if (_syncingProgress) return;
    unawaited(_drainProgressSyncQueue());
  }

  Future<void> _drainProgressSyncQueue() async {
    if (_syncingProgress) return;
    _syncingProgress = true;
    try {
      while (_progressSyncQueue.isNotEmpty) {
        await _syncProgressToCloud(_progressSyncQueue.removeFirst());
      }
    } finally {
      _syncingProgress = false;
    }
  }

  Future<void> _syncProgressToCloud(ReadingProgress progress) async {
    try {
      await _api.put<Map<String, dynamic>>(
        '/library/progress/${progress.sourceName}/comics/${progress.comicSlug}/chapters/${progress.chapterNumber}',
        data: progress.toProgressPayload(),
      );
      final notifications = _notificationRepository;
      if (notifications != null) {
        await notifications.remove(NotificationRepository.progressSyncFailedId);
        _onNotificationsChanged?.call();
      }
    } catch (_) {
      final notifications = _notificationRepository;
      if (notifications != null) {
        await notifications.add(notifications.progressSyncFailed());
        _onNotificationsChanged?.call();
      }
    }
  }

  ReadingProgress? _localProgress(String sourceName, String slug) {
    final raw = _store.progress.get(ReadingProgress.key(sourceName, slug));
    if (raw is Map) {
      return ReadingProgress.fromLocalJson(raw);
    }
    return null;
  }

  Future<void> _saveLocalCompletedChapter(ReadingProgress progress) async {
    final key = ReadingProgress.completedChaptersKey(
      progress.sourceName,
      progress.comicSlug,
    );
    final raw = _store.progress.get(key);
    final numbers = <double>{};
    if (raw is List) {
      numbers.addAll(raw.whereType<num>().map((value) => value.toDouble()));
    }
    numbers.add(progress.chapterNumber);
    final sorted = numbers.toList()..sort();
    await _store.progress.put(key, sorted);
  }

  List<ReadingProgress> _localContinueReading() {
    return _store.progress.values
        .whereType<Map<dynamic, dynamic>>()
        .map(ReadingProgress.fromLocalJson)
        .toList()
      ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
  }
}
