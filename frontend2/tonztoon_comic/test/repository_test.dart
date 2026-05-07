import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon_comic/src/core/api_client.dart';
import 'package:tonztoon_comic/src/core/config.dart';
import 'package:tonztoon_comic/src/core/storage.dart';
import 'package:tonztoon_comic/src/core/token_store.dart';
import 'package:tonztoon_comic/src/models/comic.dart';
import 'package:tonztoon_comic/src/models/progress.dart';
import 'package:tonztoon_comic/src/repositories/auth_repository.dart';
import 'package:tonztoon_comic/src/repositories/catalog_repository.dart';
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
