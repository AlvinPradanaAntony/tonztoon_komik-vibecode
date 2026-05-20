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
    void Function()? onContinueReadingChanged,
  }) : _notificationRepository = notificationRepository,
       _onNotificationsChanged = onNotificationsChanged,
       _onContinueReadingChanged = onContinueReadingChanged;

  final TonztoonApi _api;
  final TokenStore _tokenStore;
  final LocalStore _store;
  final NotificationRepository? _notificationRepository;
  final void Function()? _onNotificationsChanged;
  final void Function()? _onContinueReadingChanged;
  final Queue<ReadingProgress> _progressSyncQueue = Queue<ReadingProgress>();
  final Set<String> _progressRefreshKeys = <String>{};
  bool _syncingProgress = false;
  bool _refreshingContinueReading = false;
  DateTime? _lastContinueReadingRefreshAt;
  static const _continueReadingRefreshCooldown = Duration(seconds: 10);

  Future<List<ReadingProgress>> getContinueReading() async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      _refreshContinueReadingInBackground();
      return _authenticatedLocalContinueReading()
        ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    }
    return _localContinueReading();
  }

  Future<ReadingProgress?> getProgress(String sourceName, String slug) async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      final local = _authenticatedLocalProgress(sourceName, slug);
      if (local != null) {
        _refreshProgressInBackground(sourceName, slug);
        return local;
      }

      try {
        final remote = await _remoteProgress(sourceName, slug);
        if (remote != null) {
          await _cacheRemoteProgress(remote);
        }
        return remote;
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

  Future<List<ReadingProgress>> _remoteContinueReading() async {
    final response = await _api.get<List<dynamic>>(
      '/library/progress/continue-reading',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ReadingProgress.fromLibraryJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<ReadingProgress?> _remoteProgress(
    String sourceName,
    String slug,
  ) async {
    final response = await _api.get<Map<String, dynamic>?>(
      '/library/progress/$sourceName/comics/$slug',
    );
    final data = response.data;
    return data == null ? null : ReadingProgress.fromLibraryJson(data);
  }

  void _refreshProgressInBackground(String sourceName, String slug) {
    final key = ReadingProgress.key(sourceName, slug);
    if (!_progressRefreshKeys.add(key)) return;
    unawaited(
      _refreshProgressFromCloud(sourceName, slug).whenComplete(() {
        _progressRefreshKeys.remove(key);
      }),
    );
  }

  Future<void> _refreshProgressFromCloud(String sourceName, String slug) async {
    final token = await _tokenStore.readAccessToken();
    if (token == null || token.isEmpty) return;

    try {
      final remote = await _remoteProgress(sourceName, slug);
      if (remote == null) return;
      final changed = await _cacheRemoteProgress(remote);
      if (changed) {
        _onContinueReadingChanged?.call();
      }
    } catch (_) {
      // The reader should keep using the local account cache when cloud refresh
      // is unavailable; sync failures are surfaced from PUT progress instead.
    }
  }

  void _refreshContinueReadingInBackground() {
    if (_refreshingContinueReading) return;
    final lastRefresh = _lastContinueReadingRefreshAt;
    final now = DateTime.now();
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _continueReadingRefreshCooldown) {
      return;
    }

    _refreshingContinueReading = true;
    _lastContinueReadingRefreshAt = now;
    unawaited(
      _refreshContinueReadingFromCloud().whenComplete(() {
        _refreshingContinueReading = false;
      }),
    );
  }

  Future<void> _refreshContinueReadingFromCloud() async {
    final token = await _tokenStore.readAccessToken();
    if (token == null || token.isEmpty) return;

    try {
      final remote = await _remoteContinueReading();
      final changed = await _cacheRemoteContinueReading(remote);
      if (changed) {
        _onContinueReadingChanged?.call();
      }
    } catch (_) {
      // Keep the local-first UI path quiet; PUT sync failures already create
      // user-visible notifications when progress cannot be uploaded.
    }
  }

  Future<bool> _cacheRemoteContinueReading(List<ReadingProgress> remote) async {
    var changed = false;

    for (final remoteProgress in remote) {
      if (await _cacheRemoteProgress(remoteProgress)) {
        changed = true;
      }
    }

    return changed;
  }

  Future<bool> _cacheRemoteProgress(ReadingProgress remoteProgress) async {
    final key = remoteProgress.storageKey;
    final raw = _store.progress.get(key);
    final isAuthenticatedCache =
        LocalStateMetadata.isAuthenticatedProgressCache(_store, key);

    if (raw is Map<dynamic, dynamic> && !isAuthenticatedCache) {
      // A guest progress entry with the same key may still be waiting for
      // migration. Do not overwrite or re-label it as account cache here.
      return false;
    }

    final local = raw is Map<dynamic, dynamic>
        ? ReadingProgress.fromLocalJson(raw)
        : null;
    final newest = _newestProgress(remoteProgress, local);
    if (newest != remoteProgress) {
      return false;
    }

    await LocalStateMetadata.markAuthenticatedProgressCache(
      _store,
      remoteProgress,
    );
    if (remoteProgress.isCompleted) {
      await _saveLocalCompletedChapter(remoteProgress);
    }
    if (local != null && _progressEquals(local, remoteProgress)) {
      return false;
    }
    await _store.progress.put(key, remoteProgress.toLocalJson());
    return true;
  }

  ReadingProgress? _newestProgress(
    ReadingProgress? remote,
    ReadingProgress? local,
  ) {
    if (remote == null) return local;
    if (local == null) return remote;
    return local.lastReadAt.isAfter(remote.lastReadAt) ? local : remote;
  }

  bool _progressEquals(ReadingProgress a, ReadingProgress b) {
    return a.sourceName == b.sourceName &&
        a.comicSlug == b.comicSlug &&
        a.comicTitle == b.comicTitle &&
        a.coverImageUrl == b.coverImageUrl &&
        a.chapterNumber == b.chapterNumber &&
        a.readingMode == b.readingMode &&
        a.scrollOffset == b.scrollOffset &&
        a.pageIndex == b.pageIndex &&
        a.lastReadPageItemIndex == b.lastReadPageItemIndex &&
        a.totalPageItems == b.totalPageItems &&
        a.isCompleted == b.isCompleted &&
        a.lastReadAt.isAtSameMomentAs(b.lastReadAt);
  }

  ReadingProgress? _authenticatedLocalProgress(String sourceName, String slug) {
    final key = ReadingProgress.key(sourceName, slug);
    if (!LocalStateMetadata.isAuthenticatedProgressCache(_store, key)) {
      return null;
    }
    return _localProgress(sourceName, slug);
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

  List<ReadingProgress> _authenticatedLocalContinueReading() {
    return _store.progress
        .toMap()
        .entries
        .where((entry) {
          return entry.value is Map<dynamic, dynamic> &&
              LocalStateMetadata.isAuthenticatedProgressCache(
                _store,
                entry.key.toString(),
              );
        })
        .map((entry) {
          return ReadingProgress.fromLocalJson(
            entry.value as Map<dynamic, dynamic>,
          );
        })
        .toList();
  }
}
