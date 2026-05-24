import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon/src/core/api_client.dart';
import 'package:tonztoon/src/core/config.dart';
import 'package:tonztoon/src/core/storage.dart';
import 'package:tonztoon/src/core/token_store.dart';
import 'package:tonztoon/src/models/auth.dart';
import 'package:tonztoon/src/models/library.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/models/progress.dart';
import 'package:tonztoon/src/repositories/auth_repository.dart';
import 'package:tonztoon/src/repositories/catalog_repository.dart';
import 'package:tonztoon/src/repositories/google_auth_client.dart';
import 'package:tonztoon/src/repositories/library_repository.dart';
import 'package:tonztoon/src/repositories/notification_repository.dart';
import 'package:tonztoon/src/repositories/progress_repository.dart';
import 'package:tonztoon/src/repositories/providers.dart';

void main() {
  late Directory hiveDir;
  late LocalStore store;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('tonztoon_repo_test_');
    Hive.init(hiveDir.path);
    await Future.wait([
      Hive.openBox<dynamic>(HiveBoxes.settings),
      Hive.openBox<dynamic>(HiveBoxes.auth),
      Hive.openBox<dynamic>(HiveBoxes.progress),
      Hive.openBox<dynamic>(HiveBoxes.library),
      Hive.openBox<dynamic>(HiveBoxes.cache),
    ]);
    store = LocalStore();
  });

  setUp(() async {
    await Future.wait([
      store.settings.clear(),
      store.auth.clear(),
      store.progress.clear(),
      store.library.clear(),
      store.cache.clear(),
    ]);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test('catalog repository parses API list responses', () async {
    final repository = CatalogRepository(
      _apiWithResponses({
        'GET /sources/komiku/comics/latest': [
          {
            'title': 'Solo Leveling',
            'slug': 'solo-leveling',
            'source_name': 'komiku',
            'latest_chapter_number': 179,
          },
        ],
      }),
      store,
    );

    final latest = await repository.getLatest('komiku');

    expect(latest, hasLength(1));
    expect(latest.single.slug, 'solo-leveling');
    expect(latest.single.latestChapterNumber, 179);
  });

  test('catalog repository parses genre responses', () async {
    final repository = CatalogRepository(
      _apiWithResponses({
        'GET /genres': [
          {'id': 1, 'name': 'Action', 'slug': 'action'},
          {'id': 2, 'name': 'Romance', 'slug': 'romance'},
        ],
      }),
      store,
    );

    final genres = await repository.getGenres();

    expect(genres.map((genre) => genre.name), ['Action', 'Romance']);
  });

  test('catalog repository refreshes genres and updates cache', () async {
    final cachedRepository = CatalogRepository(
      _apiWithResponses({
        'GET /genres': [
          {'id': 1, 'name': 'Action', 'slug': 'action'},
        ],
      }),
      store,
    );
    await cachedRepository.getGenres();

    final refreshRepository = CatalogRepository(
      _apiWithResponses({
        'GET /genres': [
          {'id': 1, 'name': 'Action', 'slug': 'action'},
          {'id': 2, 'name': 'Mystery', 'slug': 'mystery'},
        ],
      }),
      store,
    );

    final refreshed = await refreshRepository.refreshGenres();
    final offlineRepository = CatalogRepository(_failingApi(), store);

    expect(refreshed.map((genre) => genre.name), ['Action', 'Mystery']);
    expect(offlineRepository.getCachedGenres().map((genre) => genre.name), [
      'Action',
      'Mystery',
    ]);
    expect(
      await offlineRepository.getGenres().then(
        (genres) => genres.map((genre) => genre.name).toList(),
      ),
      ['Action', 'Mystery'],
    );
  });

  test(
    'catalog repository requests global catalog when source is null',
    () async {
      final repository = CatalogRepository(
        _apiWithResponses({
          'GET /comics': {
            'items': [
              {'title': 'Global Comic', 'slug': 'global-comic'},
            ],
            'total': 1,
            'page': 1,
            'page_size': 40,
            'total_pages': 1,
          },
        }),
        store,
      );

      final page = await repository.getSourceComics(sourceName: null, page: 1);

      expect(page.items.single.title, 'Global Comic');
    },
  );

  test('catalog repository falls back to Hive cache', () async {
    final onlineRepository = CatalogRepository(
      _apiWithResponses({
        'GET /sources/komiku/comics/latest': [
          {'title': 'One Piece', 'slug': 'one-piece', 'source_name': 'komiku'},
        ],
      }),
      store,
    );
    await onlineRepository.getLatest('komiku');

    final offlineRepository = CatalogRepository(_failingApi(), store);
    final cached = await offlineRepository.getLatest('komiku');

    expect(cached.single.title, 'One Piece');
  });

  test('auth repository persists login token', () async {
    final tokenStore = MemoryTokenStore();
    final repository = AuthRepository(
      _apiWithResponses({
        'POST /auth/login': {
          'user': {'id': 'user-1', 'email': 'reader@tonztoon.app'},
          'session': {
            'access_token': 'access-token',
            'refresh_token': 'refresh-token',
            'expires_at': 123,
          },
        },
      }),
      tokenStore,
      store,
    );

    final state = await repository.login(
      email: 'reader@tonztoon.app',
      password: 'secret',
    );

    expect(state.isAuthenticated, isTrue);
    expect(await tokenStore.readAccessToken(), 'access-token');
    expect(store.auth.get('user'), isA<Map>());
  });

  test('auth repository exchanges Google tokens through backend', () async {
    final tokenStore = MemoryTokenStore();
    Map<String, dynamic>? googleRequestBody;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST' && options.path == '/auth/google') {
            googleRequestBody = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'user': {'id': 'google-user-1', 'email': 'reader@gmail.com'},
                  'session': {
                    'access_token': 'google-access-token',
                    'refresh_token': 'google-refresh-token',
                    'expires_at': 456,
                  },
                },
              ),
            );
            return;
          }
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    final repository = AuthRepository(
      TonztoonApi(
        config: const AppConfig(apiBaseUrl: 'https://api.test'),
        tokenStore: tokenStore,
        dio: dio,
      ),
      tokenStore,
      store,
      googleAuthClient: _FakeGoogleAuthClient(
        const GoogleAuthTokens(
          idToken: 'google-id-token',
          accessToken: 'google-oauth-access-token',
        ),
      ),
    );

    final state = await repository.loginWithGoogle();

    expect(state.isAuthenticated, isTrue);
    expect(state.user?.email, 'reader@gmail.com');
    expect(googleRequestBody, {
      'id_token': 'google-id-token',
      'access_token': 'google-oauth-access-token',
    });
    expect(await tokenStore.readAccessToken(), 'google-access-token');
    expect(await tokenStore.readRefreshToken(), 'google-refresh-token');
    expect(await tokenStore.readExpiresAt(), 456);
  });

  test('auth repository updates username through profile endpoint', () async {
    final tokenStore = MemoryTokenStore();
    Map<String, dynamic>? profileRequestBody;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'PATCH' && options.path == '/auth/profile') {
            profileRequestBody = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': 'user-1',
                  'username': 'tonz_reader',
                  'display_name': 'Tonz Reader',
                },
              ),
            );
            return;
          }
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    final repository = AuthRepository(
      TonztoonApi(
        config: const AppConfig(apiBaseUrl: 'https://api.test'),
        tokenStore: tokenStore,
        dio: dio,
      ),
      tokenStore,
      store,
    );

    final state = await repository.updateProfile(
      currentUser: const AuthUser(id: 'user-1', email: 'reader@tonztoon.app'),
      username: 'tonz_reader',
    );

    expect(profileRequestBody, {'username': 'tonz_reader'});
    expect(state.user?.username, 'tonz_reader');
    expect(store.auth.get('user'), containsPair('username', 'tonz_reader'));
  });

  test('auth repository logout clears local user-scoped data', () async {
    final tokenStore = MemoryTokenStore();
    await tokenStore.save(
      const TokenPair(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: 123,
      ),
    );
    await store.auth.put('user', {'id': 'user-1'});
    await store.progress.put('komiku|lookism', {
      'source_name': 'komiku',
      'comic_slug': 'lookism',
    });
    await store.library.put('bookmarks', {'komiku|lookism': {}});
    await store.settings.put('reader_preferences', {
      'reading_direction': 'ltr',
    });
    await store.settings.put('reader_preferences_owner', 'auth_cache');
    await store.settings.put('auth_progress_cache_keys', ['komiku|lookism']);
    await store.settings.put('auth_completed_chapter_cache_keys', [
      'komiku|lookism|1.0',
    ]);
    await store.settings.put('reading_time_total_seconds_guest', 300);
    await store.settings.put('reading_time_total_seconds_user_user-1', 600);
    await store.settings.put('theme_mode', 'dark');
    await store.cache.put('catalog', {'items': []});
    var offlineFilesCleared = false;
    final repository = AuthRepository(
      _apiWithResponses({
        'POST /auth/logout': {'success': true},
      }),
      tokenStore,
      store,
      clearOfflineFiles: () async {
        offlineFilesCleared = true;
      },
    );

    await repository.logout();

    expect(await tokenStore.readAccessToken(), isNull);
    expect(await tokenStore.readRefreshToken(), isNull);
    expect(await tokenStore.readExpiresAt(), isNull);
    expect(offlineFilesCleared, isTrue);
    expect(store.auth.isEmpty, isTrue);
    expect(store.progress.isEmpty, isTrue);
    expect(store.library.isEmpty, isTrue);
    expect(store.settings.get('reader_preferences'), isNull);
    expect(store.settings.get('reader_preferences_owner'), isNull);
    expect(store.settings.get('auth_progress_cache_keys'), isNull);
    expect(store.settings.get('auth_completed_chapter_cache_keys'), isNull);
    expect(store.settings.get('reading_time_total_seconds_guest'), isNull);
    expect(
      store.settings.get('reading_time_total_seconds_user_user-1'),
      isNull,
    );
    expect(store.settings.get('theme_mode'), 'dark');
    expect(store.cache.get('catalog'), {'items': []});
  });

  test('continue reading provider refreshes after login', () async {
    final progressRepository = _FakeProgressRepository()
      ..continueReadingResponses.addAll([
        const [],
        [
          ReadingProgress(
            sourceName: 'komiku',
            comicSlug: 'lookism',
            comicTitle: 'Lookism',
            chapterNumber: 14,
            lastReadAt: DateTime(2026, 1, 1),
          ),
        ],
      ]);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        progressRepositoryProvider.overrideWithValue(progressRepository),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(continueReadingProvider.future), isEmpty);

    await container
        .read(authControllerProvider.notifier)
        .login('reader@tonztoon.app', 'secret');
    final progress = await container.read(continueReadingProvider.future);

    expect(progress, hasLength(1));
    expect(progress.single.comicSlug, 'lookism');
    expect(progressRepository.continueReadingCalls, 2);
  });

  test(
    'logout refreshes continue reading without circular dependency',
    () async {
      final accountProgress = ReadingProgress(
        sourceName: 'komiku',
        comicSlug: 'lookism',
        comicTitle: 'Lookism',
        chapterNumber: 14,
        lastReadAt: DateTime(2026, 1, 1),
      );
      final progressRepository = _FakeProgressRepository()
        ..continueReadingResponses.addAll([
          [accountProgress],
          const [],
        ]);
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          progressRepositoryProvider.overrideWithValue(progressRepository),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login('reader@tonztoon.app', 'secret');
      expect(await container.read(continueReadingProvider.future), [
        accountProgress,
      ]);

      await container.read(authControllerProvider.notifier).logout();

      expect(await container.read(continueReadingProvider.future), isEmpty);
      expect(progressRepository.continueReadingCalls, 2);
    },
  );

  test('logout resets reader preferences provider to defaults', () async {
    await store.settings.put('reader_preferences', {
      'default_reading_mode': 'paged',
      'reading_direction': 'rtl',
      'mark_read_on_complete': true,
      'default_binge_mode': true,
    });
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        localStoreProvider.overrideWithValue(store),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(
          _ClearingAuthRepository(store),
        ),
      ],
    );
    addTearDown(container.dispose);

    final before = await container.read(readerPreferencesProvider.future);
    expect(before.defaultReadingMode, 'paged');
    expect(before.readingDirection, 'rtl');

    await container
        .read(authControllerProvider.notifier)
        .login('reader@tonztoon.app', 'secret');
    await container.read(authControllerProvider.notifier).logout();

    final after = await container.read(readerPreferencesProvider.future);
    expect(after.defaultReadingMode, 'vertical');
    expect(after.readingDirection, 'ltr');
    expect(after.markReadOnComplete, isFalse);
    expect(after.defaultBingeMode, isFalse);
  });

  test('auth repository requests password reset email', () async {
    final repository = AuthRepository(
      _apiWithResponses({
        'POST /auth/password/forgot': {
          'success': true,
          'message': 'Reset email sent.',
        },
      }),
      MemoryTokenStore(),
      store,
    );

    await repository.requestPasswordReset(email: 'reader@tonztoon.app');
  });

  test('notification repository persists download notifications', () async {
    final repository = NotificationRepository(store);
    final batch = OfflineDownloadBatch.create(
      id: 'batch-1',
      comic: const ComicSummary(
        title: 'Solo Leveling',
        slug: 'solo-leveling',
        sourceName: 'komiku',
      ),
      chapterNumbers: const [179],
    );

    await repository.add(repository.downloadCompleted(batch));
    var notifications = await repository.getNotifications();

    expect(notifications, hasLength(1));
    expect(notifications.single.title, 'Download selesai');
    expect(notifications.single.unread, isTrue);
    expect(notifications.single.actionRoute, '/library?tab=downloads');

    notifications = await repository.markAllRead();
    expect(notifications.single.unread, isFalse);
  });

  test(
    'notification repository records chapter update notifications',
    () async {
      final repository = NotificationRepository(store);
      const comic = ComicSummary(
        title: 'Omniscient Reader',
        slug: 'omniscient-reader',
        sourceName: 'komiku',
        latestChapterNumber: 200,
      );

      var notifications = await repository.recordLatestChapterUpdates([comic]);
      expect(notifications, isEmpty);

      notifications = await repository.recordLatestChapterUpdates([
        const ComicSummary(
          title: 'Omniscient Reader',
          slug: 'omniscient-reader',
          sourceName: 'komiku',
          latestChapterNumber: 201,
        ),
      ]);

      expect(notifications, hasLength(1));
      expect(notifications.single.category, 'Update');
      expect(notifications.single.kind, 'chapter_update');
      expect(
        notifications.single.actionRoute,
        '/comic/komiku/omniscient-reader',
      );
    },
  );

  test('progress repository saves guest progress locally', () async {
    final repository = ProgressRepository(
      _failingApi(),
      MemoryTokenStore(),
      store,
    );
    final progress = ReadingProgress.fromReader(
      comic: const ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      ),
      chapterNumber: 12,
      readingMode: 'vertical',
      pageItemIndex: 4,
      totalPageItems: 20,
    );

    await repository.saveProgress(progress);

    expect(store.progress.get('komiku|lookism'), isA<Map>());
  });

  test('guest progress is counted as migratable local data', () async {
    final tokenStore = MemoryTokenStore();
    final progressRepository = ProgressRepository(
      _failingApi(),
      tokenStore,
      store,
    );
    final libraryRepository = LibraryRepository(
      _failingApi(),
      tokenStore,
      store,
    );

    await progressRepository.saveProgress(
      ReadingProgress.fromReader(
        comic: const ComicSummary(
          title: 'Lookism',
          slug: 'lookism',
          sourceName: 'komiku',
        ),
        chapterNumber: 12,
        readingMode: 'vertical',
        pageItemIndex: 4,
        totalPageItems: 20,
      ),
    );

    final summary = libraryRepository.getGuestMigrationSummary();

    expect(summary.progress, 1);
    expect(summary.isEmpty, isFalse);
  });

  test('guest progress tracks multiple completed chapters locally', () async {
    final progressRepository = ProgressRepository(
      _failingApi(),
      MemoryTokenStore(),
      store,
    );
    final libraryRepository = LibraryRepository(
      _failingApi(),
      MemoryTokenStore(),
      store,
    );
    const comic = ComicSummary(
      title: 'Lookism',
      slug: 'lookism',
      sourceName: 'komiku',
    );

    await progressRepository.saveProgress(
      ReadingProgress.fromReader(
        comic: comic,
        chapterNumber: 12,
        readingMode: 'vertical',
        pageItemIndex: 19,
        totalPageItems: 20,
        isCompleted: true,
      ),
    );
    await progressRepository.saveProgress(
      ReadingProgress.fromReader(
        comic: comic,
        chapterNumber: 13,
        readingMode: 'vertical',
        pageItemIndex: 21,
        totalPageItems: 22,
        isCompleted: true,
      ),
    );

    final state = await libraryRepository.getComicState(comic);

    expect(state.completedChapterNumbers, [12.0, 13.0]);
  });

  test(
    'logged-in progress remains visible locally when cloud sync fails',
    () async {
      final tokenStore = MemoryTokenStore();
      await tokenStore.save(const TokenPair(accessToken: 'access-token'));
      final progressRepository = ProgressRepository(
        _failingApi(),
        tokenStore,
        store,
      );
      final libraryRepository = LibraryRepository(
        _failingApi(),
        tokenStore,
        store,
      );
      const comic = ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      );

      await progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 14,
          readingMode: 'vertical',
          pageItemIndex: 19,
          totalPageItems: 20,
          isCompleted: true,
        ),
      );

      final state = await libraryRepository.getComicState(comic);

      expect(state.progress?.chapterNumber, 14);
      expect(state.progress?.isCompleted, isTrue);
      expect(state.completedChapterNumbers, [14.0]);
    },
  );

  test(
    'logged-in progress detail returns local account cache before cloud refresh',
    () async {
      final tokenStore = MemoryTokenStore();
      await tokenStore.save(const TokenPair(accessToken: 'access-token'));
      const comic = ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      );
      final localProgressRepository = ProgressRepository(
        _failingApi(),
        tokenStore,
        store,
      );
      await localProgressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 14,
          readingMode: 'vertical',
          pageItemIndex: 8,
          totalPageItems: 20,
        ),
      );

      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.method == 'GET' &&
                options.path == '/library/progress/komiku/comics/lookism') {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'comic': {
                      'title': 'Lookism',
                      'slug': 'lookism',
                      'source_name': 'komiku',
                    },
                    'chapter': {'chapter_number': 14},
                    'reading_mode': 'vertical',
                    'last_read_page_item_index': 0,
                    'total_page_items': 20,
                    'last_read_at': '2020-01-01T00:00:00.000Z',
                  },
                ),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      final repository = ProgressRepository(
        TonztoonApi(
          config: const AppConfig(apiBaseUrl: 'https://api.test'),
          tokenStore: tokenStore,
          dio: dio,
        ),
        tokenStore,
        store,
      );

      final progress = await repository
          .getProgress('komiku', 'lookism')
          .timeout(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(progress?.lastReadPageItemIndex, 8);
      expect(
        ReadingProgress.fromLocalJson(
          store.progress.get('komiku|lookism') as Map<dynamic, dynamic>,
        ).lastReadPageItemIndex,
        8,
      );
    },
  );

  test(
    'logged-in progress cache is not counted as guest migration data',
    () async {
      final tokenStore = MemoryTokenStore();
      await tokenStore.save(const TokenPair(accessToken: 'access-token'));
      final progressRepository = ProgressRepository(
        _failingApi(),
        tokenStore,
        store,
      );
      final libraryRepository = LibraryRepository(
        _failingApi(),
        tokenStore,
        store,
      );

      await progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: const ComicSummary(
            title: 'Lookism',
            slug: 'lookism',
            sourceName: 'komiku',
          ),
          chapterNumber: 14,
          readingMode: 'vertical',
          pageItemIndex: 19,
          totalPageItems: 20,
          isCompleted: true,
        ),
      );

      final summary = libraryRepository.getGuestMigrationSummary();

      expect(summary.progress, 0);
      expect(summary.isEmpty, isTrue);
    },
  );

  test(
    'guest progress after logout is counted even when auth cache existed',
    () async {
      final tokenStore = MemoryTokenStore();
      await tokenStore.save(const TokenPair(accessToken: 'access-token'));
      final progressRepository = ProgressRepository(
        _failingApi(),
        tokenStore,
        store,
      );
      final libraryRepository = LibraryRepository(
        _failingApi(),
        tokenStore,
        store,
      );
      const comic = ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      );

      await progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 14,
          readingMode: 'vertical',
          pageItemIndex: 19,
          totalPageItems: 20,
          isCompleted: true,
        ),
      );
      await tokenStore.clear();
      await progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 15,
          readingMode: 'vertical',
          pageItemIndex: 4,
          totalPageItems: 20,
        ),
      );

      final summary = libraryRepository.getGuestMigrationSummary();

      expect(summary.progress, 1);
      expect(summary.isEmpty, isFalse);
    },
  );

  test(
    'progress cloud sync failure creates one deduped notification',
    () async {
      final tokenStore = MemoryTokenStore();
      await tokenStore.save(const TokenPair(accessToken: 'access-token'));
      final notificationRepository = NotificationRepository(store);
      final progressRepository = ProgressRepository(
        _failingApi(),
        tokenStore,
        store,
        notificationRepository: notificationRepository,
      );
      const comic = ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      );
      final progress = ReadingProgress.fromReader(
        comic: comic,
        chapterNumber: 14,
        readingMode: 'vertical',
        pageItemIndex: 19,
        totalPageItems: 20,
        isCompleted: true,
      );

      await progressRepository.saveProgress(progress);
      await progressRepository.saveProgress(progress);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final notifications = await notificationRepository.getNotifications();

      expect(notifications, hasLength(1));
      expect(
        notifications.single.id,
        NotificationRepository.progressSyncFailedId,
      );
      expect(notifications.single.kind, 'progress_sync_failed');
      expect(notifications.single.unread, isTrue);
    },
  );

  test('logged-in progress cloud sync is drained sequentially', () async {
    final tokenStore = MemoryTokenStore();
    await tokenStore.save(const TokenPair(accessToken: 'access-token'));
    var activeRequests = 0;
    var maxActiveRequests = 0;
    var completedRequests = 0;
    final allRequestsDone = Completer<void>();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.method == 'PUT' &&
              options.path.startsWith('/library/progress/')) {
            activeRequests++;
            if (activeRequests > maxActiveRequests) {
              maxActiveRequests = activeRequests;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
            activeRequests--;
            completedRequests++;
            if (completedRequests == 3 && !allRequestsDone.isCompleted) {
              allRequestsDone.complete();
            }
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: const {},
              ),
            );
            return;
          }
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    final progressRepository = ProgressRepository(
      TonztoonApi(
        config: const AppConfig(apiBaseUrl: 'https://api.test'),
        tokenStore: tokenStore,
        dio: dio,
      ),
      tokenStore,
      store,
    );
    const comic = ComicSummary(
      title: 'Lookism',
      slug: 'lookism',
      sourceName: 'komiku',
    );

    await Future.wait([
      progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 14,
          readingMode: 'vertical',
          pageItemIndex: 19,
          totalPageItems: 20,
          isCompleted: true,
        ),
      ),
      progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 15,
          readingMode: 'vertical',
          pageItemIndex: 19,
          totalPageItems: 20,
          isCompleted: true,
        ),
      ),
      progressRepository.saveProgress(
        ReadingProgress.fromReader(
          comic: comic,
          chapterNumber: 16,
          readingMode: 'vertical',
          pageItemIndex: 19,
          totalPageItems: 20,
          isCompleted: true,
        ),
      ),
    ]);
    await allRequestsDone.future.timeout(const Duration(seconds: 1));

    expect(completedRequests, 3);
    expect(maxActiveRequests, 1);
  });

  test('logged-in comic state merges local completed chapter cache', () async {
    final tokenStore = MemoryTokenStore();
    await tokenStore.save(const TokenPair(accessToken: 'access-token'));
    const comic = ComicSummary(
      title: 'Lookism',
      slug: 'lookism',
      sourceName: 'komiku',
    );
    final progressRepository = ProgressRepository(
      _failingApi(),
      tokenStore,
      store,
    );
    await progressRepository.saveProgress(
      ReadingProgress.fromReader(
        comic: comic,
        chapterNumber: 14,
        readingMode: 'vertical',
        pageItemIndex: 19,
        totalPageItems: 20,
        isCompleted: true,
      ),
    );
    final libraryRepository = LibraryRepository(
      _apiWithResponses({
        'GET /library/state/komiku/comics/lookism': {
          'comic': {
            'title': 'Lookism',
            'slug': 'lookism',
            'source_name': 'komiku',
          },
          'bookmarked': false,
          'collections': [],
          'completed_chapter_numbers': [],
        },
      }),
      tokenStore,
      store,
    );

    final state = await libraryRepository.getComicState(comic);

    expect(state.completedChapterNumbers, [14.0]);
    expect(state.progress?.chapterNumber, 14);
  });

  test(
    'logged-in reader preferences cache is not counted as guest migration data',
    () async {
      final tokenStore = MemoryTokenStore();
      await tokenStore.save(const TokenPair(accessToken: 'access-token'));
      final repository = LibraryRepository(
        _apiWithResponses({
          'PUT /library/reader-preferences': {
            'default_reading_mode': 'paged',
            'reading_direction': 'rtl',
            'mark_read_on_complete': true,
            'default_binge_mode': true,
          },
        }),
        tokenStore,
        store,
      );

      await repository.saveReaderPreferences(
        const ReaderPreferences(
          defaultReadingMode: 'paged',
          readingDirection: 'rtl',
          markReadOnComplete: true,
          defaultBingeMode: true,
        ),
      );

      final summary = repository.getGuestMigrationSummary();

      expect(summary.hasReaderPreferences, isFalse);
      expect(summary.isEmpty, isTrue);
    },
  );

  test(
    'library repository saves reader preferences without auto_next',
    () async {
      final repository = LibraryRepository(
        _failingApi(),
        MemoryTokenStore(),
        store,
      );
      const prefs = ReaderPreferences(
        defaultReadingMode: 'paged',
        readingDirection: 'rtl',
        markReadOnComplete: false,
        defaultBingeMode: true,
      );

      await repository.saveReaderPreferences(prefs);

      final stored = store.settings.get('reader_preferences');
      expect(stored, isA<Map>());
      expect(stored, {
        'default_reading_mode': 'paged',
        'reading_direction': 'rtl',
        'mark_read_on_complete': false,
        'default_binge_mode': true,
      });
      expect(stored, isNot(contains('auto_next')));
    },
  );
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthState> login({
    required String email,
    required String password,
  }) async {
    return AuthState.authenticated(AuthUser(id: 'user-1', email: email));
  }

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleAuthClient implements GoogleAuthClient {
  _FakeGoogleAuthClient(this.tokens);

  final GoogleAuthTokens tokens;

  @override
  Future<GoogleAuthTokens> signIn() async => tokens;

  @override
  Future<void> signOut() async {}
}

class _ClearingAuthRepository implements AuthRepository {
  _ClearingAuthRepository(this.store);

  final LocalStore store;

  @override
  Future<AuthState> login({
    required String email,
    required String password,
  }) async {
    return AuthState.authenticated(AuthUser(id: 'user-1', email: email));
  }

  @override
  Future<void> logout() {
    return store.clearUserScopedData();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProgressRepository implements ProgressRepository {
  final continueReadingResponses = <List<ReadingProgress>>[];
  int continueReadingCalls = 0;

  @override
  Future<List<ReadingProgress>> getContinueReading() async {
    continueReadingCalls++;
    if (continueReadingResponses.isEmpty) return const [];
    return continueReadingResponses.removeAt(0);
  }

  @override
  Future<ReadingProgress?> getProgress(String sourceName, String slug) async {
    return null;
  }

  @override
  Future<void> saveProgress(ReadingProgress progress) async {}
}

TonztoonApi _apiWithResponses(Map<String, Object?> responses) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final key = '${options.method} ${options.path}';
        if (!responses.containsKey(key)) {
          handler.reject(DioException(requestOptions: options));
          return;
        }
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: responses[key],
          ),
        );
      },
    ),
  );
  return TonztoonApi(
    config: const AppConfig(apiBaseUrl: 'https://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: dio,
  );
}

TonztoonApi _failingApi() {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
      },
    ),
  );
  return TonztoonApi(
    config: const AppConfig(apiBaseUrl: 'https://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: dio,
  );
}
