import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon_comic/src/core/api_client.dart';
import 'package:tonztoon_comic/src/core/config.dart';
import 'package:tonztoon_comic/src/core/storage.dart';
import 'package:tonztoon_comic/src/core/token_store.dart';
import 'package:tonztoon_comic/src/models/library.dart';
import 'package:tonztoon_comic/src/models/comic.dart';
import 'package:tonztoon_comic/src/models/progress.dart';
import 'package:tonztoon_comic/src/repositories/auth_repository.dart';
import 'package:tonztoon_comic/src/repositories/catalog_repository.dart';
import 'package:tonztoon_comic/src/repositories/library_repository.dart';
import 'package:tonztoon_comic/src/repositories/notification_repository.dart';
import 'package:tonztoon_comic/src/repositories/progress_repository.dart';

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
