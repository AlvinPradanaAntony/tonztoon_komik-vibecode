import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/app_navigation.dart';
import '../core/avatar_image.dart';
import '../core/config.dart';
import '../core/download_notification_service.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/auth.dart';
import '../models/app_notification.dart';
import '../models/comic.dart';
import '../models/library.dart';
import '../models/progress.dart';
import '../models/source_info.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';
import 'library_repository.dart';
import 'notification_repository.dart';
import 'offline_repository.dart';
import 'progress_repository.dart';

final configProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());

final downloadNotificationServiceProvider =
    Provider<DownloadNotificationService>(
      (ref) => DownloadNotificationService(
        onOpenDownloads: openDownloadsFromNotification,
      ),
    );

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
      AppThemeModeController.new,
    );

final readingTimeProvider = NotifierProvider<ReadingTimeController, Duration>(
  ReadingTimeController.new,
);

class ReadingTimeController extends Notifier<Duration> {
  static const _storageKeyPrefix = 'reading_time_total_seconds';
  late String _storageKey;
  late String _pendingDeltaKey;
  bool _syncing = false;

  @override
  Duration build() {
    final auth = ref.watch(authControllerProvider);
    _storageKey = _storageKeyForAuth(auth);
    _pendingDeltaKey = '${_storageKey}_pending_delta';
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    final seconds = switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    if (auth.isAuthenticated) {
      unawaited(_syncCloudReadingTime());
    }
    return Duration(seconds: seconds);
  }

  Future<void> add(Duration duration) async {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return;

    final next = state + Duration(seconds: seconds);
    await _setLocalSeconds(next.inSeconds);

    if (ref.read(authControllerProvider).isAuthenticated) {
      await _addPendingDelta(seconds);
      unawaited(_syncCloudReadingTime());
    }
  }

  Future<void> refreshFromCloud() {
    return _syncCloudReadingTime();
  }

  Future<void> _syncCloudReadingTime() async {
    if (_syncing || !ref.read(authControllerProvider).isAuthenticated) return;
    _syncing = true;
    var shouldSyncAgain = false;
    final storageKey = _storageKey;
    final pendingDeltaKey = _pendingDeltaKey;
    try {
      final pending = _readSeconds(
        ref.read(localStoreProvider).settings.get(pendingDeltaKey),
      );
      final repository = ref.read(libraryRepositoryProvider);
      final remoteSeconds = pending > 0
          ? await repository.addReadingTimeDeltaSeconds(pending)
          : await repository.getReadingTimeSeconds();
      if (remoteSeconds == null) return;
      if (pending > 0) {
        final latestPending = _readSeconds(
          ref.read(localStoreProvider).settings.get(pendingDeltaKey),
        );
        final unsent = latestPending > pending ? latestPending - pending : 0;
        if (unsent > 0) {
          await ref
              .read(localStoreProvider)
              .settings
              .put(pendingDeltaKey, unsent);
          shouldSyncAgain = true;
        } else {
          await ref.read(localStoreProvider).settings.delete(pendingDeltaKey);
        }
        await _setLocalSeconds(remoteSeconds + unsent, storageKey: storageKey);
      } else {
        await _setLocalSeconds(remoteSeconds, storageKey: storageKey);
      }
    } finally {
      _syncing = false;
    }
    if (shouldSyncAgain && storageKey == _storageKey) {
      unawaited(_syncCloudReadingTime());
    }
  }

  Future<void> _setLocalSeconds(int seconds, {String? storageKey}) async {
    final key = storageKey ?? _storageKey;
    if (key == _storageKey) {
      state = Duration(seconds: seconds);
    }
    await ref.read(localStoreProvider).settings.put(key, seconds);
  }

  Future<void> _addPendingDelta(int seconds) async {
    final current = _readSeconds(
      ref.read(localStoreProvider).settings.get(_pendingDeltaKey),
    );
    await ref
        .read(localStoreProvider)
        .settings
        .put(_pendingDeltaKey, current + seconds);
  }

  int _readSeconds(Object? value) {
    return switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
  }

  String _storageKeyForAuth(AuthState auth) {
    final user = auth.user;
    if (!auth.isAuthenticated || user == null) {
      return '${_storageKeyPrefix}_guest';
    }

    final id = user.id.trim();
    if (id.isNotEmpty) return '${_storageKeyPrefix}_user_$id';

    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      return '${_storageKeyPrefix}_user_$email';
    }

    return '${_storageKeyPrefix}_guest';
  }
}

class AppThemeModeController extends Notifier<ThemeMode> {
  static const _storageKey = 'theme_mode';

  @override
  ThemeMode build() {
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    return _themeModeFromName(value is String ? value : null);
  }

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(localStoreProvider).settings.put(_storageKey, mode.name);
    state = mode;
  }

  static ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiProvider = Provider<TonztoonApi>((ref) {
  return TonztoonApi(
    config: ref.watch(configProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(
    ref.watch(apiProvider),
    ref.watch(localStoreProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
  );
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
  );
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
  );
});

final offlineRepositoryProvider = Provider<OfflineRepository>((ref) {
  return OfflineRepository(
    ref.watch(apiProvider),
    ref.watch(localStoreProvider),
  );
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(localStoreProvider));
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final authSecurityOverviewProvider = FutureProvider<AuthSecurityOverview>((
  ref,
) {
  ref.watch(authControllerProvider);
  return ref.watch(authRepositoryProvider).getSecurityOverview();
});

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.booting();

  Future<void> restore() async {
    state = const AuthState.booting();
    state = await ref.read(authRepositoryProvider).restore();
  }

  Future<void> login(String email, String password) async {
    state = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
  }

  Future<void> register(
    String email,
    String password,
    String? displayName,
    String? username,
  ) async {
    state = await ref
        .read(authRepositoryProvider)
        .register(
          email: email,
          password: password,
          displayName: displayName,
          username: username,
        );
  }

  Future<void> verifyPasswordRecovery(String email, String tokenHash) async {
    state = await ref
        .read(authRepositoryProvider)
        .verifyPasswordRecovery(email: email, tokenHash: tokenHash);
  }

  Future<void> verifyEmailSignup(String email, String tokenHash) async {
    state = await ref
        .read(authRepositoryProvider)
        .verifyEmailSignup(email: email, tokenHash: tokenHash);
  }

  Future<void> useAuthSession({
    required String accessToken,
    String? refreshToken,
    int? expiresAt,
  }) async {
    state = await ref
        .read(authRepositoryProvider)
        .useAuthSession(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: expiresAt,
        );
  }

  Future<void> updatePassword(String password) {
    return ref.read(authRepositoryProvider).updatePassword(password: password);
  }

  Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .updateProfile(
          currentUser: currentUser,
          displayName: displayName,
          avatarUrl: avatarUrl,
        );
  }

  Future<void> uploadAvatar(OptimizedAvatar avatar) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .uploadAvatar(
          currentUser: currentUser,
          bytes: avatar.bytes,
          fileName: avatar.fileName,
          contentType: avatar.contentType,
        );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState.guest();
    ref.invalidate(continueReadingProvider);
  }
}

final selectedSourceProvider =
    NotifierProvider<SelectedSourceController, String?>(
      SelectedSourceController.new,
    );

class SelectedSourceController extends Notifier<String?> {
  @override
  String? build() {
    return ref.watch(localStoreProvider).settings.get('selected_source')
        as String?;
  }

  void select(String sourceName) {
    ref.read(localStoreProvider).settings.put('selected_source', sourceName);
    state = sourceName;
  }
}

final sourcesProvider = FutureProvider<List<SourceInfo>>((ref) {
  return ref.watch(catalogRepositoryProvider).getSources();
});

final genresProvider = FutureProvider<List<Genre>>((ref) {
  return ref.watch(catalogRepositoryProvider).getGenres();
});

class HomeData {
  const HomeData({
    required this.sources,
    required this.selectedSource,
    required this.latest,
    required this.popular,
    required this.continueReading,
  });

  final List<SourceInfo> sources;
  final SourceInfo selectedSource;
  final List<ComicSummary> latest;
  final List<ComicSummary> popular;
  final List<ReadingProgress> continueReading;
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final repository = ref.watch(catalogRepositoryProvider);
  final progressRepository = ref.watch(progressRepositoryProvider);
  final sources = await repository.getSources();
  if (sources.isEmpty) {
    throw ApiException('No sources available.');
  }
  final selectedId = ref.watch(selectedSourceProvider);
  final selected = sources.firstWhere(
    (source) => source.id == selectedId,
    orElse: () => sources.first,
  );
  final results = await Future.wait([
    repository.getLatest(selected.id),
    repository.getPopular(selected.id),
    progressRepository.getContinueReading(),
  ]);
  final latest = results[0] as List<ComicSummary>;
  unawaited(
    ref.read(notificationsProvider.notifier).recordLatestChapterUpdates(latest),
  );
  return HomeData(
    sources: sources,
    selectedSource: selected,
    latest: latest,
    popular: results[1] as List<ComicSummary>,
    continueReading: results[2] as List<ReadingProgress>,
  );
});

class ComicRequest {
  const ComicRequest(this.sourceName, this.slug);

  final String sourceName;
  final String slug;

  @override
  bool operator ==(Object other) {
    return other is ComicRequest &&
        other.sourceName == sourceName &&
        other.slug == slug;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug);
}

final comicDetailProvider = FutureProvider.family<ComicDetail, ComicRequest>((
  ref,
  request,
) {
  return ref
      .watch(catalogRepositoryProvider)
      .getComicDetail(request.sourceName, request.slug);
});

final chaptersProvider =
    FutureProvider.family<List<ChapterListItem>, ComicRequest>((ref, request) {
      return ref
          .watch(catalogRepositoryProvider)
          .getChapters(request.sourceName, request.slug);
    });

final progressProvider = FutureProvider.family<ReadingProgress?, ComicRequest>((
  ref,
  request,
) {
  return ref
      .watch(progressRepositoryProvider)
      .getProgress(request.sourceName, request.slug);
});

final continueReadingProvider = FutureProvider<List<ReadingProgress>>((ref) {
  return ref.watch(progressRepositoryProvider).getContinueReading();
});

class ChapterRequest extends ComicRequest {
  const ChapterRequest(super.sourceName, super.slug, this.chapterNumber);

  final double chapterNumber;

  @override
  bool operator ==(Object other) {
    return other is ChapterRequest &&
        other.sourceName == sourceName &&
        other.slug == slug &&
        other.chapterNumber == chapterNumber;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug, chapterNumber);
}

final chapterProvider = FutureProvider.family<ChapterPayload, ChapterRequest>((
  ref,
  request,
) async {
  final offline = await ref
      .watch(offlineRepositoryProvider)
      .getOfflinePayload(
        request.sourceName,
        request.slug,
        request.chapterNumber,
      );
  if (offline != null) return offline;

  try {
    return await ref
        .watch(catalogRepositoryProvider)
        .getChapter(request.sourceName, request.slug, request.chapterNumber);
  } catch (_) {
    final fallback = await ref
        .watch(offlineRepositoryProvider)
        .getOfflinePayload(
          request.sourceName,
          request.slug,
          request.chapterNumber,
        );
    if (fallback != null) return fallback;
    rethrow;
  }
});

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) {
    state = value;
  }
}

final searchResultsProvider = FutureProvider<List<ComicSummary>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (ref.watch(searchQueryProvider).trim() != query) return const [];
  return ref.watch(catalogRepositoryProvider).search(query);
});

final libraryComicStateProvider =
    FutureProvider.family<LibraryComicState, ComicSummary>((ref, comic) {
      return ref.watch(libraryRepositoryProvider).getComicState(comic);
    });

final bookmarksProvider = FutureProvider<List<LibraryComicRef>>((ref) {
  return ref.watch(libraryRepositoryProvider).getBookmarks();
});

final collectionsProvider = FutureProvider<List<CollectionSummary>>((ref) {
  return ref.watch(libraryRepositoryProvider).getCollections();
});

final collectionDetailProvider = FutureProvider.family<CollectionDetail, int>((
  ref,
  collectionId,
) {
  return ref.watch(libraryRepositoryProvider).getCollectionDetail(collectionId);
});

final favoriteScenesProvider = FutureProvider<List<FavoriteScene>>((ref) {
  return ref.watch(libraryRepositoryProvider).getFavoriteScenes();
});

final historyProvider = FutureProvider<List<ReadingProgress>>((ref) {
  return ref.watch(libraryRepositoryProvider).getHistory();
});

final downloadsProvider = FutureProvider<List<DownloadEntry>>((ref) {
  return ref.watch(libraryRepositoryProvider).getDownloads();
});

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
      NotificationsController.new,
    );

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).asData?.value;
  if (notifications == null) return 0;
  return notifications.where((item) => item.unread).length;
});

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() {
    return ref.watch(notificationRepositoryProvider).getNotifications();
  }

  Future<void> add(AppNotification notification) async {
    state = AsyncData(
      await ref.read(notificationRepositoryProvider).add(notification),
    );
  }

  Future<void> markRead(String id) async {
    state = AsyncData(
      await ref.read(notificationRepositoryProvider).markRead(id),
    );
  }

  Future<void> markAllRead() async {
    state = AsyncData(
      await ref.read(notificationRepositoryProvider).markAllRead(),
    );
  }

  Future<void> recordLatestChapterUpdates(List<ComicSummary> comics) async {
    state = AsyncData(
      await ref
          .read(notificationRepositoryProvider)
          .recordLatestChapterUpdates(comics),
    );
  }
}

final offlineChaptersProvider = FutureProvider<List<OfflineChapter>>((ref) {
  return ref.watch(offlineRepositoryProvider).getOfflineChapters();
});

final offlineQueueProvider =
    AsyncNotifierProvider<OfflineQueueController, List<OfflineDownloadBatch>>(
      OfflineQueueController.new,
    );

class OfflineQueueController extends AsyncNotifier<List<OfflineDownloadBatch>> {
  final Map<String, CancelToken> _cancelTokens = {};
  final Set<String> _deletedBatchIds = {};

  @override
  Future<List<OfflineDownloadBatch>> build() {
    return ref.watch(offlineRepositoryProvider).getBatches();
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(offlineRepositoryProvider).getBatches());
  }

  Future<void> startBatch({
    required ComicSummary comic,
    required List<ChapterListItem> chapters,
  }) async {
    if (chapters.isEmpty) return;
    final chapterNumbers = chapters.map((item) => item.chapterNumber).toList();
    final batch = OfflineDownloadBatch.create(
      id: '${comic.sourceName}|${comic.slug}|${DateTime.now().microsecondsSinceEpoch}',
      comic: comic,
      chapterNumbers: chapterNumbers,
    );
    await ref
        .read(libraryRepositoryProvider)
        .enqueueDownloadBatch(comic, chapterNumbers);
    await ref.read(offlineRepositoryProvider).saveBatch(batch);
    await refresh();
    unawaited(_runBatch(batch));
  }

  Future<void> resumeBatch(String batchId) async {
    final batches = state.asData?.value ?? await build();
    OfflineDownloadBatch? batch;
    for (final item in batches) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch == null || !batch.canResume) return;
    unawaited(_runBatch(batch));
  }

  Future<void> resumeRecoverableBatches() async {
    final batches = await ref.read(offlineRepositoryProvider).getBatches();
    state = AsyncData(batches);
    for (final batch in batches.where((batch) => batch.canResume)) {
      unawaited(_runBatch(batch));
    }
  }

  Future<void> cancelBatch(String batchId) async {
    _cancelTokens[batchId]?.cancel('Download batch cancelled.');
    OfflineDownloadBatch? batch;
    for (final item in state.asData?.value ?? const <OfflineDownloadBatch>[]) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch != null) {
      await _upsertRemainingDownloadStatuses(
        batch,
        status: 'cancelled',
        lastError: 'Cancelled by user.',
      );
      final cancelledBatch = batch.copyWith(
        status: 'cancelled',
        clearCurrentChapterNumber: true,
        lastError: 'Cancelled by user.',
      );
      await _saveBatch(cancelledBatch);
      unawaited(
        ref
            .read(downloadNotificationServiceProvider)
            .showCancelled(cancelledBatch),
      );
      unawaited(_addNotificationForCancelled(cancelledBatch));
    }
  }

  Future<void> deleteBatch(String batchId) async {
    _deletedBatchIds.add(batchId);
    _cancelTokens[batchId]?.cancel('Download batch deleted.');
    _cancelTokens.remove(batchId);
    await ref.read(offlineRepositoryProvider).deleteBatch(batchId);
    unawaited(ref.read(downloadNotificationServiceProvider).dismiss(batchId));
    await refresh();
  }

  Future<void> _runBatch(OfflineDownloadBatch initialBatch) async {
    if (_cancelTokens.containsKey(initialBatch.id)) return;
    final token = CancelToken();
    _cancelTokens[initialBatch.id] = token;
    var batch = initialBatch.copyWith(
      status: 'downloading',
      completedChapters: 0,
      progressValue: 0,
      clearLastError: true,
    );
    await _saveBatch(batch);
    unawaited(ref.read(downloadNotificationServiceProvider).showStarted(batch));

    try {
      final startIndex = batch.completedChapters.clamp(
        0,
        batch.chapterNumbers.length,
      );
      for (
        var chapterIndex = startIndex;
        chapterIndex < batch.chapterNumbers.length;
        chapterIndex++
      ) {
        if (token.isCancelled) {
          if (_deletedBatchIds.contains(initialBatch.id)) return;
          final cancelledBatch = batch.copyWith(
            status: 'cancelled',
            clearCurrentChapterNumber: true,
            lastError: 'Cancelled by user.',
          );
          await _saveBatch(cancelledBatch);
          unawaited(
            ref
                .read(downloadNotificationServiceProvider)
                .showCancelled(cancelledBatch),
          );
          unawaited(_addNotificationForCancelled(cancelledBatch));
          return;
        }
        final chapterNumber = batch.chapterNumbers[chapterIndex];
        final existing = await ref
            .read(offlineRepositoryProvider)
            .getOfflineChapter(
              batch.comic.sourceName,
              batch.comic.slug,
              chapterNumber,
            );
        if (existing?.isCompleted == true) {
          await _upsertDownloadStatus(
            batch.comic,
            chapterNumber,
            status: 'completed',
          );
          batch = batch.copyWith(
            completedChapters: chapterIndex + 1,
            progressValue: (chapterIndex + 1) / batch.totalChapters,
          );
          await _saveBatch(batch);
          unawaited(
            ref.read(downloadNotificationServiceProvider).showProgress(batch),
          );
          continue;
        }
        batch = batch.copyWith(
          status: 'downloading',
          currentChapterNumber: chapterNumber,
          completedChapters: chapterIndex,
          progressValue: chapterIndex / batch.totalChapters,
        );
        await _upsertDownloadStatus(
          batch.comic,
          chapterNumber,
          status: 'downloading',
        );
        await _saveBatch(batch);
        unawaited(
          ref.read(downloadNotificationServiceProvider).showProgress(batch),
        );

        final payload = await ref
            .read(catalogRepositoryProvider)
            .getChapter(
              batch.comic.sourceName,
              batch.comic.slug,
              chapterNumber,
            );
        final totalPages = payload.images.length;
        batch = batch.copyWith(totalImages: totalPages);
        await _saveBatch(batch);
        unawaited(
          ref.read(downloadNotificationServiceProvider).showProgress(batch),
        );

        final downloaded = await ref
            .read(offlineRepositoryProvider)
            .downloadChapter(
              comic: batch.comic.toSummary(),
              chapterNumber: chapterNumber,
              payload: payload,
              cancelToken: token,
              onImageProgress: (pageIndex, received, total) {
                final pageFraction = total <= 0 ? 0.0 : received / total;
                final chapterFraction = totalPages == 0
                    ? 1.0
                    : ((pageIndex + pageFraction) / totalPages).clamp(0, 1);
                final overall =
                    ((chapterIndex + chapterFraction) / batch.totalChapters)
                        .clamp(0, 1)
                        .toDouble();
                final live = batch.copyWith(
                  completedChapters: chapterIndex,
                  completedImages: pageIndex,
                  totalImages: totalPages,
                  progressValue: overall,
                );
                unawaited(_saveBatch(live));
                unawaited(
                  ref
                      .read(downloadNotificationServiceProvider)
                      .showProgress(live),
                );
              },
            );
        if (token.isCancelled || downloaded.status == 'cancelled') {
          if (_deletedBatchIds.contains(initialBatch.id)) return;
          await _upsertDownloadStatus(
            batch.comic,
            chapterNumber,
            status: 'cancelled',
            lastError: 'Cancelled by user.',
          );
          final cancelledBatch = batch.copyWith(
            status: 'cancelled',
            clearCurrentChapterNumber: true,
            lastError: 'Cancelled by user.',
          );
          await _saveBatch(cancelledBatch);
          unawaited(
            ref
                .read(downloadNotificationServiceProvider)
                .showCancelled(cancelledBatch),
          );
          unawaited(_addNotificationForCancelled(cancelledBatch));
          return;
        }
        if (!downloaded.isCompleted) {
          await _upsertDownloadStatus(
            batch.comic,
            chapterNumber,
            status: downloaded.status,
            lastError: downloaded.lastError,
          );
          throw ApiException(downloaded.lastError ?? 'Download gagal.');
        }

        await _upsertDownloadStatus(
          batch.comic,
          chapterNumber,
          status: 'completed',
        );
        batch = batch.copyWith(
          completedChapters: chapterIndex + 1,
          progressValue: (chapterIndex + 1) / batch.totalChapters,
        );
        await _saveBatch(batch);
        unawaited(
          ref.read(downloadNotificationServiceProvider).showProgress(batch),
        );
        ref.invalidate(offlineChaptersProvider);
      }

      final completedBatch = batch.copyWith(
        status: 'completed',
        completedChapters: batch.totalChapters,
        progressValue: 1,
        clearCurrentChapterNumber: true,
      );
      await _saveBatch(completedBatch);
      unawaited(
        ref
            .read(downloadNotificationServiceProvider)
            .showCompleted(completedBatch),
      );
      unawaited(_addNotificationForCompleted(completedBatch));
    } on DioException catch (error) {
      final cancelled = CancelToken.isCancel(error);
      if (cancelled && _deletedBatchIds.contains(initialBatch.id)) return;
      await _upsertRemainingDownloadStatuses(
        batch,
        status: cancelled ? 'cancelled' : 'failed',
        lastError: error.message ?? error.toString(),
      );
      final failedBatch = batch.copyWith(
        status: cancelled ? 'cancelled' : 'failed',
        clearCurrentChapterNumber: true,
        lastError: error.message ?? error.toString(),
      );
      await _saveBatch(failedBatch);
      unawaited(
        cancelled
            ? ref
                  .read(downloadNotificationServiceProvider)
                  .showCancelled(failedBatch)
            : ref
                  .read(downloadNotificationServiceProvider)
                  .showFailed(failedBatch),
      );
      unawaited(
        cancelled
            ? _addNotificationForCancelled(failedBatch)
            : _addNotificationForFailed(failedBatch),
      );
    } catch (error) {
      await _upsertRemainingDownloadStatuses(
        batch,
        status: 'failed',
        lastError: error.toString(),
      );
      final failedBatch = batch.copyWith(
        status: 'failed',
        clearCurrentChapterNumber: true,
        lastError: error.toString(),
      );
      await _saveBatch(failedBatch);
      unawaited(
        ref.read(downloadNotificationServiceProvider).showFailed(failedBatch),
      );
      unawaited(_addNotificationForFailed(failedBatch));
    } finally {
      _cancelTokens.remove(initialBatch.id);
      _deletedBatchIds.remove(initialBatch.id);
      ref.invalidate(offlineChaptersProvider);
      ref.invalidate(downloadsProvider);
    }
  }

  Future<void> _upsertDownloadStatus(
    LibraryComicRef comic,
    double chapterNumber, {
    required String status,
    String? lastError,
  }) async {
    try {
      await ref
          .read(libraryRepositoryProvider)
          .upsertDownloadEntryStatus(
            comic: comic,
            chapterNumber: chapterNumber,
            status: status,
            lastError: lastError,
          );
      ref.invalidate(downloadsProvider);
    } catch (_) {
      // Offline files remain the source of truth for local reading.
    }
  }

  Future<void> _upsertRemainingDownloadStatuses(
    OfflineDownloadBatch batch, {
    required String status,
    String? lastError,
  }) async {
    final startIndex = batch.completedChapters.clamp(
      0,
      batch.chapterNumbers.length,
    );
    for (var index = startIndex; index < batch.chapterNumbers.length; index++) {
      await _upsertDownloadStatus(
        batch.comic,
        batch.chapterNumbers[index],
        status: status,
        lastError: lastError,
      );
    }
  }

  Future<void> _saveBatch(OfflineDownloadBatch batch) async {
    await ref.read(offlineRepositoryProvider).saveBatch(batch);
    final current = [...?state.asData?.value];
    final index = current.indexWhere((item) => item.id == batch.id);
    if (index >= 0) {
      current[index] = batch;
    } else {
      current.insert(0, batch);
    }
    current.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncData(current);
  }

  Future<void> _addNotificationForCompleted(OfflineDownloadBatch batch) {
    return ref
        .read(notificationsProvider.notifier)
        .add(ref.read(notificationRepositoryProvider).downloadCompleted(batch));
  }

  Future<void> _addNotificationForFailed(OfflineDownloadBatch batch) {
    return ref
        .read(notificationsProvider.notifier)
        .add(ref.read(notificationRepositoryProvider).downloadFailed(batch));
  }

  Future<void> _addNotificationForCancelled(OfflineDownloadBatch batch) {
    return ref
        .read(notificationsProvider.notifier)
        .add(ref.read(notificationRepositoryProvider).downloadCancelled(batch));
  }
}

final readerPreferencesProvider =
    AsyncNotifierProvider<ReaderPreferencesController, ReaderPreferences>(
      ReaderPreferencesController.new,
    );

class ReaderPreferencesController extends AsyncNotifier<ReaderPreferences> {
  int _saveSerial = 0;

  @override
  Future<ReaderPreferences> build() {
    return ref.watch(libraryRepositoryProvider).getReaderPreferences();
  }

  Future<void> save(ReaderPreferences prefs) async {
    final serial = ++_saveSerial;
    final previous = state.asData?.value;
    state = AsyncData(prefs);

    try {
      final saved = await ref
          .read(libraryRepositoryProvider)
          .saveReaderPreferences(prefs);
      if (serial == _saveSerial) {
        state = AsyncData(saved);
      }
    } catch (error, stackTrace) {
      if (serial == _saveSerial) {
        state = previous == null
            ? AsyncError(error, stackTrace)
            : AsyncData(previous);
      }
      rethrow;
    }
  }
}
