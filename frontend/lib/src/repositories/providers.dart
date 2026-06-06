import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/app_navigation.dart';
import '../core/app_update_service.dart';
import '../core/avatar_image.dart';
import '../core/config.dart';
import '../core/push_notification_service.dart';
import '../core/remote_push_notification_service.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/auth.dart';
import '../models/app_notification.dart';
import '../models/comic.dart';
import '../models/library.dart';
import '../models/progress.dart';
import '../models/push_notification_preferences.dart';
import '../models/source_info.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';
import 'library_repository.dart';
import 'notification_repository.dart';
import 'offline_repository.dart';
import 'progress_repository.dart';
import 'google_auth_client.dart';
import 'helpdesk_repository.dart';
import 'push_device_repository.dart';

final configProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService(
    githubRepository: ref.watch(configProvider).githubRepository,
    store: ref.watch(localStoreProvider),
  );
});

final pushNotificationPreferencesProvider =
    NotifierProvider<
      PushNotificationPreferencesController,
      PushNotificationPreferences
    >(PushNotificationPreferencesController.new);

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(
    readPreferences: () => ref.read(pushNotificationPreferencesProvider),
    onOpenLocation: openLocationFromNotification,
  ),
);

final downloadNotificationServiceProvider = pushNotificationServiceProvider;

final pushDeviceRepositoryProvider = Provider<PushDeviceRepository>((ref) {
  return PushDeviceRepository(ref.watch(apiProvider));
});

final helpdeskRepositoryProvider = Provider<HelpdeskRepository>((ref) {
  return HelpdeskRepository(ref.watch(apiProvider));
});

final remotePushNotificationServiceProvider =
    Provider<RemotePushNotificationService>((ref) {
      final service = RemotePushNotificationService(
        repository: ref.watch(pushDeviceRepositoryProvider),
        store: ref.watch(localStoreProvider),
        localNotifications: ref.watch(pushNotificationServiceProvider),
        readPreferences: () => ref.read(pushNotificationPreferencesProvider),
        readAuth: () => ref.read(authControllerProvider),
        onOpenLocation: openLocationFromNotification,
        onAppNotification: (notification) =>
            ref.read(notificationsProvider.notifier).add(notification),
      );
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });

class PushNotificationPreferencesController
    extends Notifier<PushNotificationPreferences> {
  static const _storageKey = 'push_notification_preferences';

  @override
  PushNotificationPreferences build() {
    final auth = ref.watch(authControllerProvider);
    final remoteEnabled = auth.user?.pushNotificationsEnabled;
    if (auth.isAuthenticated && remoteEnabled != null) {
      return PushNotificationPreferences(enabled: remoteEnabled);
    }

    final raw = ref.watch(localStoreProvider).settings.get(_storageKey);
    return raw is Map
        ? PushNotificationPreferences.fromJson(raw)
        : const PushNotificationPreferences();
  }

  Future<void> setEnabled(bool value) {
    return _setEnabled(value);
  }

  Future<void> _setEnabled(bool value) async {
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated) {
      await ref
          .read(authControllerProvider.notifier)
          .updatePushNotificationsEnabled(value);
    }
    await _save(state.copyWith(enabled: value));
    if (value) {
      unawaited(
        ref.read(remotePushNotificationServiceProvider).syncRegistration(),
      );
    } else {
      unawaited(
        ref.read(remotePushNotificationServiceProvider).unregisterDevice(),
      );
    }
  }

  Future<void> _save(PushNotificationPreferences preferences) async {
    state = preferences;
    await ref
        .read(localStoreProvider)
        .settings
        .put(_storageKey, preferences.toJson());
  }
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
      AppThemeModeController.new,
    );

final homeHelpdeskButtonVisibleProvider =
    NotifierProvider<HomeHelpdeskButtonVisibleController, bool>(
      HomeHelpdeskButtonVisibleController.new,
    );

class HomeHelpdeskButtonVisibleController extends Notifier<bool> {
  static const _storageKey = 'home_helpdesk_button_visible';

  @override
  bool build() {
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    return value is bool ? value : true;
  }

  Future<void> setVisible(bool value) async {
    final previous = state;
    state = value;
    try {
      await ref.read(localStoreProvider).settings.put(_storageKey, value);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

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

final googleAuthClientProvider = Provider<GoogleAuthClient>((ref) {
  return NativeGoogleAuthClient(ref.watch(configProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
    googleAuthClient: ref.watch(googleAuthClientProvider),
    clearOfflineFiles: () =>
        ref.read(offlineRepositoryProvider).clearAllOfflineChapters(),
  );
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
    notificationRepository: ref.watch(notificationRepositoryProvider),
    onNotificationsChanged: () => ref.invalidate(notificationsProvider),
    onContinueReadingChanged: (progress) {
      ref.read(paginatedHistoryProvider.notifier).upsertItemAtTop(progress);
      ref.read(continueReadingRefreshSignalProvider.notifier).bump();
    },
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
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
  }

  Future<void> login(String identifier, String password) async {
    state = await ref
        .read(authRepositoryProvider)
        .login(identifier: identifier, password: password);
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
  }

  Future<void> loginWithGoogle() async {
    state = await ref.read(authRepositoryProvider).loginWithGoogle();
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
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
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
  }

  Future<void> verifyPasswordRecovery(String email, String tokenHash) async {
    state = await ref
        .read(authRepositoryProvider)
        .verifyPasswordRecovery(email: email, tokenHash: tokenHash);
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
  }

  Future<void> verifyEmailSignup(String email, String tokenHash) async {
    state = await ref
        .read(authRepositoryProvider)
        .verifyEmailSignup(email: email, tokenHash: tokenHash);
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
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
    unawaited(
      ref.read(remotePushNotificationServiceProvider).syncRegistration(),
    );
  }

  Future<void> updatePassword(String password) {
    return ref.read(authRepositoryProvider).updatePassword(password: password);
  }

  Future<void> updatePushNotificationsEnabled(bool enabled) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .updatePushNotificationsEnabled(
          currentUser: currentUser,
          enabled: enabled,
        );
  }

  Future<void> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
  }) async {
    final currentUser = state.user;
    if (currentUser == null) return;
    state = await ref
        .read(authRepositoryProvider)
        .updateProfile(
          currentUser: currentUser,
          username: username,
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
    await ref.read(remotePushNotificationServiceProvider).unregisterDevice();
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState.guest();
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
    required this.recommendations,
    required this.topRanking,
    required this.continueReading,
  });

  final List<SourceInfo> sources;
  final SourceInfo selectedSource;
  final List<ComicSummary> latest;
  final List<ComicSummary> popular;
  final List<ComicSummary> recommendations;
  final List<ComicSummary> topRanking;
  final List<ReadingProgress> continueReading;
}

const _homePreviewPageSize = 6;

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(authControllerProvider);
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
    repository.getLatest(selected.id, pageSize: _homePreviewPageSize),
    repository.getPopular(selected.id, pageSize: _homePreviewPageSize),
    repository.getRecommendations(selected.id),
    repository.getTopRanking(selected.id),
    progressRepository.getContinueReading(pageSize: _homePreviewPageSize),
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
    recommendations: results[2] as List<ComicSummary>,
    topRanking: results[3] as List<ComicSummary>,
    continueReading: results[4] as List<ReadingProgress>,
  );
});

class TopRankingRequest {
  const TopRankingRequest({required this.sourceName, this.type});

  final String sourceName;
  final String? type;

  @override
  bool operator ==(Object other) {
    return other is TopRankingRequest &&
        other.sourceName == sourceName &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(sourceName, type);
}

final topRankingProvider =
    FutureProvider.family<List<ComicSummary>, TopRankingRequest>((
      ref,
      request,
    ) {
      return ref
          .watch(catalogRepositoryProvider)
          .getTopRanking(request.sourceName, type: request.type);
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
  ref.watch(authControllerProvider);
  return ref
      .watch(progressRepositoryProvider)
      .getProgress(request.sourceName, request.slug);
});

final continueReadingProvider = FutureProvider<List<ReadingProgress>>((ref) {
  ref.watch(authControllerProvider);
  ref.watch(continueReadingRefreshSignalProvider);
  return ref
      .watch(progressRepositoryProvider)
      .getContinueReading(pageSize: _homePreviewPageSize);
});

final continueReadingRefreshSignalProvider =
    NotifierProvider<ContinueReadingRefreshSignalController, int>(
      ContinueReadingRefreshSignalController.new,
    );

class ContinueReadingRefreshSignalController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

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
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  return ref.watch(libraryRepositoryProvider).getBookmarks();
});

final paginatedBookmarksProvider =
    AsyncNotifierProvider<
      BookmarksPaginationController,
      PaginatedState<LibraryComicRef>
    >(BookmarksPaginationController.new);

class BookmarksPaginationController
    extends PaginatedAsyncController<LibraryComicRef> {
  @override
  void watchDependencies() {
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  }

  @override
  Future<List<LibraryComicRef>> loadPage({
    required int page,
    required int pageSize,
  }) {
    return ref
        .read(libraryRepositoryProvider)
        .getBookmarksPage(page: page, pageSize: pageSize);
  }

  @override
  String itemKey(LibraryComicRef item) {
    return '${item.sourceName}|${item.slug}';
  }
}

class PaginatedState<T> {
  const PaginatedState({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasNextPage,
    this.isLoadingMore = false,
    this.isRefreshing = false,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final bool hasNextPage;
  final bool isLoadingMore;
  final bool isRefreshing;

  PaginatedState<T> copyWith({
    List<T>? items,
    int? page,
    int? pageSize,
    bool? hasNextPage,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return PaginatedState<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

abstract class PaginatedAsyncController<T>
    extends AsyncNotifier<PaginatedState<T>> {
  int get pageSize => 20;

  void watchDependencies() {}

  Future<List<T>> loadPage({required int page, required int pageSize});

  String itemKey(T item);

  @override
  Future<PaginatedState<T>> build() async {
    watchDependencies();
    return _loadFirstPage(previous: state.asData?.value);
  }

  Future<void> loadNextPage() async {
    final current = state.asData?.value;
    if (current == null ||
        current.isRefreshing ||
        current.isLoadingMore ||
        current.hasNextPage == false) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.page + 1;
      final nextItems = await loadPage(page: nextPage, pageSize: pageSize);
      final existingKeys = current.items.map(itemKey).toSet();
      final mergedItems = [...current.items];
      var addedCount = 0;

      for (final item in nextItems) {
        if (existingKeys.add(itemKey(item))) {
          mergedItems.add(item);
          addedCount++;
        }
      }

      state = AsyncData(
        current.copyWith(
          items: mergedItems,
          page: nextPage,
          hasNextPage: nextItems.length >= pageSize && addedCount > 0,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> refreshFirstPage() async {
    final current = state.asData?.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    if (current.isRefreshing) return;

    state = AsyncData(
      current.copyWith(isRefreshing: true, isLoadingMore: false),
    );
    try {
      final refreshedItems = await loadPage(page: 1, pageSize: pageSize);
      final mergedItems = _mergeRefreshedFirstPage(
        refreshedItems,
        current.items,
      );

      state = AsyncData(
        current.copyWith(
          items: mergedItems,
          page: 1,
          hasNextPage: refreshedItems.length >= pageSize,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncData(current.copyWith(isRefreshing: false));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void removeItemByKey(String key) {
    final current = state.asData?.value;
    if (current == null) return;

    final nextItems = current.items
        .where((item) => itemKey(item) != key)
        .toList(growable: false);
    if (nextItems.length == current.items.length) return;

    state = AsyncData(current.copyWith(items: nextItems));
  }

  void upsertItemAtTop(T item) {
    final current = state.asData?.value;
    if (current == null) {
      state = AsyncData(
        PaginatedState<T>(
          items: [item],
          page: 1,
          pageSize: pageSize,
          hasNextPage: false,
        ),
      );
      return;
    }

    final key = itemKey(item);
    state = AsyncData(
      current.copyWith(
        items: [
          item,
          for (final oldItem in current.items)
            if (itemKey(oldItem) != key) oldItem,
        ],
      ),
    );
  }

  Future<PaginatedState<T>> _loadFirstPage({
    PaginatedState<T>? previous,
  }) async {
    final items = await loadPage(page: 1, pageSize: pageSize);
    final nextItems = previous == null
        ? items
        : _mergeRefreshedFirstPage(items, previous.items);
    return PaginatedState<T>(
      items: nextItems,
      page: 1,
      pageSize: pageSize,
      hasNextPage: items.length >= pageSize,
    );
  }

  List<T> _mergeRefreshedFirstPage(List<T> refreshedItems, List<T> oldItems) {
    final refreshedKeys = refreshedItems.map(itemKey).toSet();
    return [
      ...refreshedItems,
      for (final item in oldItems)
        if (!refreshedKeys.contains(itemKey(item))) item,
    ];
  }
}

final librarySummaryProvider = FutureProvider<LibrarySummary>((ref) {
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  return ref.watch(libraryRepositoryProvider).getLibrarySummary();
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
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  ref.watch(continueReadingRefreshSignalProvider);
  return ref.watch(libraryRepositoryProvider).getHistory();
});

final paginatedHistoryProvider =
    AsyncNotifierProvider<
      HistoryPaginationController,
      PaginatedState<ReadingProgress>
    >(HistoryPaginationController.new);

class HistoryPaginationController
    extends PaginatedAsyncController<ReadingProgress> {
  @override
  void watchDependencies() {
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  }

  @override
  Future<List<ReadingProgress>> loadPage({
    required int page,
    required int pageSize,
  }) {
    return ref
        .read(libraryRepositoryProvider)
        .getHistoryPage(page: page, pageSize: pageSize);
  }

  @override
  String itemKey(ReadingProgress item) {
    return item.historyStorageKey;
  }
}

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
    final repository = ref.read(notificationRepositoryProvider);
    final previous = state.asData?.value ?? await repository.getNotifications();
    final knownIds = previous.map((item) => item.id).toSet();
    final notifications = await repository.recordLatestChapterUpdates(comics);
    state = AsyncData(notifications);

    for (final notification in notifications) {
      if (knownIds.contains(notification.id)) continue;
      unawaited(
        ref
            .read(pushNotificationServiceProvider)
            .showAppNotification(notification),
      );
    }
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
  final Set<String> _startingChapterKeys = {};

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
    final batches = state.asData?.value ?? await build();
    final comicKey = '${comic.sourceName}|${comic.slug}';
    final activeChapterNumbers = batches
        .where(
          (batch) =>
              batch.comic.key == comicKey &&
              (batch.status == 'pending' ||
                  batch.status == 'downloading' ||
                  batch.status == 'paused'),
        )
        .expand((batch) => batch.chapterNumbers)
        .toSet();
    final queuedChapters = <ChapterListItem>[];
    final queuedKeys = <String>{};
    for (final chapter in chapters) {
      final key = '$comicKey|${chapter.chapterNumber}';
      if (activeChapterNumbers.contains(chapter.chapterNumber) ||
          _startingChapterKeys.contains(key) ||
          !queuedKeys.add(key)) {
        continue;
      }
      queuedChapters.add(chapter);
    }
    if (queuedChapters.isEmpty) return;

    _startingChapterKeys.addAll(queuedKeys);
    try {
      final chapterNumbers = queuedChapters
          .map((item) => item.chapterNumber)
          .toList();
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
    } finally {
      _startingChapterKeys.removeAll(queuedKeys);
    }
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
    for (final batch in batches.where((batch) => batch.canAutoResume)) {
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
      completedImages: 0,
      totalImages: 0,
      progressValue: initialBatch.totalChapters == 0
          ? 0
          : initialBatch.completedChapters / initialBatch.totalChapters,
      clearCurrentChapterNumber: true,
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
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
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
