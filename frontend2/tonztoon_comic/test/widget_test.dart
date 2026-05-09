import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon_comic/src/app.dart';
import 'package:tonztoon_comic/src/core/storage.dart';
import 'package:tonztoon_comic/src/core/token_store.dart';
import 'package:tonztoon_comic/src/features/auth/auth_screen.dart';
import 'package:tonztoon_comic/src/features/comic/comic_detail_screen.dart';
import 'package:tonztoon_comic/src/features/reader/reader_screen.dart';
import 'package:tonztoon_comic/src/models/comic.dart';
import 'package:tonztoon_comic/src/models/library.dart';
import 'package:tonztoon_comic/src/models/source_info.dart';
import 'package:tonztoon_comic/src/repositories/catalog_repository.dart';
import 'package:tonztoon_comic/src/repositories/providers.dart';
import 'package:tonztoon_comic/src/routing/app_router.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('tonztoon_hive_test_');
    Hive.init(hiveDir.path);
    await Future.wait([
      Hive.openBox<dynamic>(HiveBoxes.settings),
      Hive.openBox<dynamic>(HiveBoxes.auth),
      Hive.openBox<dynamic>(HiveBoxes.progress),
      Hive.openBox<dynamic>(HiveBoxes.library),
      Hive.openBox<dynamic>(HiveBoxes.cache),
    ]);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  testWidgets('shows the splash screen on launch', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        child: const TonztoonApp(),
      ),
    );

    expect(find.text('TonzToon'), findsOneWidget);
    expect(find.text('Multisource, all in one.'), findsOneWidget);
    expect(find.text('STARTING'), findsOneWidget);
  });

  testWidgets('opens forgot password route', (tester) async {
    final container = _testContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/auth/forgot-password?email=reader%40tonztoon.test');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TonztoonApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Lupa password?'), findsOneWidget);
  });

  testWidgets('opens comic detail and reader deep links', (tester) async {
    final container = _testContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    const comic = ComicSummary(
      title: 'Solo Leveling',
      slug: 'solo-leveling',
      sourceName: 'komiku',
      latestChapterNumber: 179,
      type: 'Manhwa',
    );

    router.go('/comic/komiku/solo-leveling', extra: comic);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TonztoonApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(ComicDetailScreen), findsOneWidget);
    expect(find.text('Daftar Chapter'), findsOneWidget);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ReaderScreen(
            sourceName: 'komiku',
            slug: 'solo-leveling',
            chapterNumber: 179,
            initialComic: comic,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ReaderScreen), findsOneWidget);
  });
}

ProviderContainer _testContainer() {
  return ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      catalogRepositoryProvider.overrideWithValue(_FakeCatalogRepository()),
      libraryComicStateProvider(_FakeCatalogRepository.comic).overrideWith(
        (ref) async => const LibraryComicState(
          comic: LibraryComicRef(
            sourceName: 'komiku',
            slug: 'solo-leveling',
            title: 'Solo Leveling',
          ),
          bookmarked: false,
          collections: [],
        ),
      ),
      offlineChaptersProvider.overrideWith((ref) async => const []),
      downloadsProvider.overrideWith((ref) async => const []),
      offlineQueueProvider.overrideWith(_FakeOfflineQueueController.new),
    ],
  );
}

class _FakeOfflineQueueController extends OfflineQueueController {
  @override
  Future<List<OfflineDownloadBatch>> build() async => const [];
}

class _FakeCatalogRepository implements CatalogRepository {
  static const comic = ComicSummary(
    title: 'Solo Leveling',
    slug: 'solo-leveling',
    sourceName: 'komiku',
    latestChapterNumber: 179,
    type: 'Manhwa',
  );

  @override
  Future<List<SourceInfo>> getSources() async {
    return const [
      SourceInfo(
        id: 'komiku',
        label: 'Komiku',
        baseUrl: 'https://example.test',
        enabled: true,
        dbComicCount: 1,
      ),
    ];
  }

  @override
  Future<List<ComicSummary>> getLatest(String sourceName) async => const [
    comic,
  ];

  @override
  Future<List<ComicSummary>> getPopular(String sourceName) async => const [
    comic,
  ];

  @override
  Future<List<Genre>> getGenres() async => const [
    Genre(id: 1, name: 'Action', slug: 'action'),
  ];

  @override
  Future<SourceComicPage> getSourceComics({
    required String? sourceName,
    required int page,
    int pageSize = 40,
    String? type,
    String? status,
    String? genre,
    String? sort,
  }) async {
    return const SourceComicPage(
      items: [comic],
      total: 1,
      page: 1,
      pageSize: 40,
      totalPages: 1,
    );
  }

  @override
  Future<List<ComicSummary>> search(String query) async => const [comic];

  @override
  Future<ComicDetail> getComicDetail(String sourceName, String slug) async {
    return const ComicDetail(
      id: 1,
      title: 'Solo Leveling',
      slug: 'solo-leveling',
      sourceName: 'komiku',
      sourceUrl: 'https://example.test/solo-leveling',
      genres: [Genre(id: 1, name: 'Action', slug: 'action')],
      totalChapters: 179,
      type: 'Manhwa',
      status: 'Completed',
      rating: 4.9,
    );
  }

  @override
  Future<List<ChapterListItem>> getChapters(
    String sourceName,
    String slug,
  ) async {
    return [
      ChapterListItem(
        chapterNumber: 179,
        createdAt: DateTime(2026, 1, 1),
        totalImages: 1,
        detailUrl: 'https://example.test/solo-leveling/179',
      ),
    ];
  }

  @override
  Future<ChapterPayload> getChapter(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    return const ChapterPayload(
      sourceName: 'komiku',
      chapterNumber: 179,
      images: [],
      total: 0,
    );
  }
}
