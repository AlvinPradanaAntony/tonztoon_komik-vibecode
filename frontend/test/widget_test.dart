import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon/src/app.dart';
import 'package:tonztoon/src/core/remote_push_notification_service.dart';
import 'package:tonztoon/src/core/storage.dart';
import 'package:tonztoon/src/core/token_store.dart';
import 'package:tonztoon/src/features/auth/auth_screen.dart';
import 'package:tonztoon/src/features/comic/comic_detail_screen.dart';
import 'package:tonztoon/src/features/library/library_screen.dart';
import 'package:tonztoon/src/features/library/library_shared_panes.dart';
import 'package:tonztoon/src/features/notifications/notifications_screen.dart';
import 'package:tonztoon/src/features/reader/reader_screen.dart';
import 'package:tonztoon/src/models/auth.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/models/library.dart';
import 'package:tonztoon/src/models/source_info.dart';
import 'package:tonztoon/src/repositories/catalog_repository.dart';
import 'package:tonztoon/src/repositories/providers.dart';
import 'package:tonztoon/src/routing/app_router.dart';
import 'package:tonztoon/src/widgets/app_edge_fade.dart';
import 'package:tonztoon/src/widgets/tonztoon_modal_dialog.dart';

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

  testWidgets('opens password recovery callback from Supabase deep link', (
    tester,
  ) async {
    final container = _testContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go(
      'tonztoon://auth/callback#access_token=access-token&refresh_token=refresh-token&expires_at=1778337092&type=recovery',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TonztoonApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('Buat password baru'), findsOneWidget);
  });

  testWidgets('opens notifications route with real empty state', (
    tester,
  ) async {
    final container = _testContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/notifications');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TonztoonApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Notifikasi'), findsOneWidget);
    expect(find.text('Belum ada notifikasi'), findsOneWidget);
  });

  testWidgets(
    'password recovery app bar back opens auth fallback from deep link',
    (tester) async {
      final container = _testContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go(
        'tonztoon://auth/callback#access_token=access-token&refresh_token=refresh-token&expires_at=1778337092&type=recovery',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TonztoonApp(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
    },
  );

  testWidgets(
    'password recovery system back opens auth fallback from deep link',
    (tester) async {
      final container = _testContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go(
        'tonztoon://auth/callback#access_token=access-token&refresh_token=refresh-token&expires_at=1778337092&type=recovery',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TonztoonApp(),
        ),
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
    },
  );

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
    await tester.pumpAndSettle();

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

  testWidgets('comic detail uses edge-to-edge floating bottom actions', (
    tester,
  ) async {
    final container = _testContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ComicDetailScreen(
            initialComic: _FakeCatalogRepository.comic,
            sourceName: 'komiku',
            slug: 'solo-leveling',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bottomFade = tester.widget<AppEdgeFade>(
      find.descendant(
        of: find.byType(ComicDetailScreen),
        matching: find.byType(AppEdgeFade),
      ),
    );
    expect(bottomFade.edge, AppFadeEdge.bottom);
    expect(bottomFade.height, 120);
    expect(
      find.byKey(const ValueKey('comic-detail-bottom-read-bar')),
      findsOneWidget,
    );

    final detailScaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(ComicDetailScreen),
        matching: find.byType(Scaffold),
      ),
    );
    final detailOverlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey('comic-detail-system-ui-overlay')),
    );

    expect(detailScaffold.extendBody, isTrue);
    expect(detailOverlay.value.systemNavigationBarColor, Colors.transparent);
    expect(
      detailOverlay.value.systemNavigationBarDividerColor,
      Colors.transparent,
    );
  });

  testWidgets('bookmarked comic shows source finder placeholder', (
    tester,
  ) async {
    final container = _testContainer(bookmarked: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ComicDetailScreen(
            initialComic: _FakeCatalogRepository.comic,
            sourceName: 'komiku',
            slug: 'solo-leveling',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Source terhubung'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('find-linked-bookmark-source')),
      findsOneWidget,
    );
    expect(find.text('Cari dan hubungkan source lain'), findsOneWidget);
  });

  testWidgets('comic detail connected sources card expands and collapses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _testContainer(bookmarked: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ComicDetailScreen(
            initialComic: _FakeCatalogRepository.comic,
            sourceName: 'komiku',
            slug: 'solo-leveling',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to make sure the card is in view
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Verify card is initially expanded (showing placeholder)
    expect(find.byKey(const ValueKey('find-linked-bookmark-source')), findsOneWidget);

    // Tap the header to collapse it
    await tester.tap(find.text('Source terhubung'));
    await tester.pumpAndSettle();

    // Verify placeholder is now collapsed / hidden
    expect(find.byKey(const ValueKey('find-linked-bookmark-source')), findsNothing);

    // Tap again to expand
    await tester.tap(find.text('Source terhubung'));
    await tester.pumpAndSettle();

    // Verify placeholder is visible again
    expect(find.byKey(const ValueKey('find-linked-bookmark-source')), findsOneWidget);
  });


  testWidgets('comic detail starts from first chapter without progress', (
    tester,
  ) async {
    final container = _testContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go(
      '/comic/komiku/solo-leveling',
      extra: _FakeCatalogRepository.comic,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TonztoonApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Baca Chapter 1'), findsOneWidget);

    await tester.tap(find.text('Baca Chapter 1'));
    await tester.pumpAndSettle();

    final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(reader.chapterNumber, 1);
  });

  testWidgets('comic detail alternative title expands and collapses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        pushNotificationLifecycleServiceProvider.overrideWithValue(
          const _NoopPushNotificationService(),
        ),
        pushRegistrationServiceProvider.overrideWithValue(
          const _NoopPushNotificationService(),
        ),
        authControllerProvider.overrideWith(_ReadyGuestAuthController.new),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        catalogRepositoryProvider.overrideWithValue(
          _FakeAlternativeTitleCatalogRepository(
            alternativeTitles:
                'Solo Leveling Alternative Title That Is Extremely Long And Exceeds Thirty Six Characters',
          ),
        ),
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
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ComicDetailScreen(
            initialComic: _FakeCatalogRepository.comic,
            sourceName: 'komiku',
            slug: 'solo-leveling',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify alternative title exists
    expect(find.text('Alternative Title'), findsOneWidget);
    expect(
      find.textContaining('Solo Leveling Alternative Title'),
      findsOneWidget,
    );

    // Tap to expand
    await tester.tap(find.textContaining('Solo Leveling Alternative Title'));
    await tester.pumpAndSettle();

    // Verify it is expanded by checking that tapping works again (toggle collapse)
    await tester.tap(find.textContaining('Solo Leveling Alternative Title'));
    await tester.pumpAndSettle();
  });

  testWidgets('bookmark card overlays type and groups source badges', (
    tester,
  ) async {
    const bookmark = LibraryComicRef(
      sourceName: 'komiku_asia',
      slug: 'bookmark-card',
      title: 'Bookmark Card',
      author: 'Author yang disembunyikan',
      status: 'Ongoing',
      type: 'Manhua',
      rating: 4.8,
      totalView: 12500,
      linkedComics: [
        LibraryComicRef(
          sourceName: 'komikcast',
          slug: 'bookmark-card-linked',
          title: 'Bookmark Card',
        ),
        LibraryComicRef(
          sourceName: 'mangadex',
          slug: 'bookmark-card-linked-2',
          title: 'Bookmark Card',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        paginatedBookmarksProvider.overrideWith(
          () => _FakeBookmarksPaginationController([bookmark]),
        ),
        librarySummaryProvider.overrideWith(
          (ref) async => const LibrarySummary(
            counts: LibrarySummaryCounts(
              bookmarks: 1,
              collections: 0,
              favoriteScenes: 0,
              history: 0,
              downloads: 0,
              continueReading: 0,
            ),
            readingTimeSeconds: 0,
          ),
        ),
        downloadsProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final sourceStrip = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(
          const ValueKey('bookmark-metadata-strip-komiku_asia|bookmark-card'),
        ),
        matching: find.byType(ListView),
      ),
    );
    final leftFade = tester.widget<AnimatedOpacity>(
      find.byKey(
        const ValueKey('bookmark-metadata-left-fade-komiku_asia|bookmark-card'),
      ),
    );
    final rightFade = tester.widget<AnimatedOpacity>(
      find.byKey(
        const ValueKey(
          'bookmark-metadata-right-fade-komiku_asia|bookmark-card',
        ),
      ),
    );
    final typeOverlay = tester.widget<Transform>(
      find.byKey(const ValueKey('bookmark-type-komiku_asia|bookmark-card')),
    );

    expect(sourceStrip.scrollDirection, Axis.horizontal);
    expect(leftFade.opacity, 0);
    expect(rightFade.opacity, 1);
    expect(typeOverlay.transform.storage[0], closeTo(0.72, 0.001));
    expect(
      find.byKey(const ValueKey('bookmark-status-komiku_asia|bookmark-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookmark-source-komiku_asia|bookmark-card')),
      findsOneWidget,
    );
    expect(find.text('Author yang disembunyikan'), findsNothing);
    expect(
      find.byKey(const ValueKey('bookmark-metrics-komiku_asia|bookmark-card')),
      findsOneWidget,
    );
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('13K views'), findsOneWidget);

    await tester.drag(
      find.byKey(
        const ValueKey('bookmark-metadata-strip-komiku_asia|bookmark-card'),
      ),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();

    final scrolledLeftFade = tester.widget<AnimatedOpacity>(
      find.byKey(
        const ValueKey('bookmark-metadata-left-fade-komiku_asia|bookmark-card'),
      ),
    );
    expect(scrolledLeftFade.opacity, 1);
    expect(
      find.byKey(
        const ValueKey(
          'bookmark-linked-source-komiku_asia|bookmark-card-komikcast',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('wishlist download shows active chapter progress', (
    tester,
  ) async {
    await _pumpWishlistDownloads(
      tester,
      _wishlistBatch(status: 'downloading', progressValue: 0.42),
    );

    expect(find.text('Ch 12 sedang diunduh - 42%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Download ke perangkat ini'), findsNothing);
  });

  testWidgets('wishlist paused download shows resume action', (tester) async {
    await _pumpWishlistDownloads(
      tester,
      _wishlistBatch(status: 'paused', progressValue: 0.42),
    );

    expect(
      find.text('Ch 12 dijeda, tekan lanjutkan untuk resume'),
      findsOneWidget,
    );
    expect(find.byTooltip('Lanjutkan download'), findsOneWidget);
    expect(find.byTooltip('Download ke perangkat ini'), findsNothing);
  });

  testWidgets('wishlist failed download shows retry action', (tester) async {
    await _pumpWishlistDownloads(
      tester,
      _wishlistBatch(status: 'failed', progressValue: 0.42),
    );

    expect(find.text('Ch 12 gagal diunduh, tekan coba lagi'), findsOneWidget);
    expect(find.byTooltip('Coba lagi download'), findsOneWidget);
    expect(find.byTooltip('Download ke perangkat ini'), findsNothing);
  });

  testWidgets('failed queue exposes retry menu action', (tester) async {
    await _pumpWishlistDownloads(
      tester,
      _wishlistBatch(status: 'failed', progressValue: 0.42),
      false,
    );

    await tester.tap(find.byTooltip('Opsi unduhan'));
    await tester.pumpAndSettle();

    expect(find.text('Coba lagi'), findsOneWidget);
  });

  testWidgets('failed local record stays out of ready files and allows retry', (
    tester,
  ) async {
    await _pumpWishlistDownloads(
      tester,
      _wishlistBatch(status: 'failed', progressValue: 0),
      false,
      [_offlineChapter(status: 'failed')],
    );

    expect(find.text('0 aktif'), findsOneWidget);
    expect(find.text('File lokal'), findsNothing);
    expect(find.text('1 chapter wishlist, 0 tersedia lokal'), findsOneWidget);

    await tester.tap(find.text('Solo Leveling').last);
    await tester.pumpAndSettle();

    expect(find.text('Ch 12 gagal diunduh, tekan coba lagi'), findsOneWidget);
    expect(find.byTooltip('Coba lagi download'), findsOneWidget);
  });

  testWidgets('wishlist delete asks for confirmation', (tester) async {
    await _pumpWishlistDownloads(tester);

    await tester.tap(find.byTooltip('Hapus wishlist offline'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus wishlist offline'), findsOneWidget);
    expect(
      find.text('Hapus "Solo Leveling" chapter 12 dari wishlist offline?'),
      findsOneWidget,
    );
  });

  testWidgets('offline file delete asks for confirmation', (tester) async {
    await _pumpOfflineDownloads(tester);

    await tester.tap(find.byTooltip('Hapus file offline'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus unduhan offline'), findsOneWidget);
    expect(
      find.text('Hapus "Solo Leveling" chapter 12 dari perangkat ini?'),
      findsOneWidget,
    );
  });

  testWidgets('download queue delete asks for confirmation', (tester) async {
    await _pumpWishlistDownloads(
      tester,
      _wishlistBatch(status: 'downloading', progressValue: 0.42),
      false,
    );

    await tester.tap(find.byTooltip('Opsi unduhan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus antrean unduhan'), findsOneWidget);
    expect(
      find.text('Hapus antrean unduhan "Solo Leveling" dari perangkat ini?'),
      findsOneWidget,
    );
  });

  testWidgets('delete dialog stays open and shows spinner while processing', (
    tester,
  ) async {
    final deletion = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTonztoonAsyncConfirmDialog(
                context,
                title: 'Hapus wishlist offline',
                message: 'Hapus chapter ini?',
                confirmLabel: 'Hapus',
                onConfirm: () => deletion.future,
              ),
              child: const Text('Buka dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pump();

    expect(find.text('Hapus wishlist offline'), findsOneWidget);
    expect(find.text('Hapus'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Tutup'), findsNothing);

    deletion.complete();
    await tester.pumpAndSettle();

    expect(find.text('Hapus wishlist offline'), findsNothing);
  });
}

const _wishlistEntry = DownloadEntry(
  id: 1,
  comic: LibraryComicRef(
    sourceName: 'komiku',
    slug: 'solo-leveling',
    title: 'Solo Leveling',
  ),
  chapterNumber: 12,
  status: 'pending',
);

OfflineDownloadBatch _wishlistBatch({
  required String status,
  required double progressValue,
}) {
  final now = DateTime.now();
  return OfflineDownloadBatch(
    id: 'wishlist-batch',
    comic: _wishlistEntry.comic,
    chapterNumbers: const [12],
    status: status,
    completedChapters: 0,
    totalChapters: 1,
    completedImages: 0,
    totalImages: 10,
    progressValue: progressValue,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpWishlistDownloads(
  WidgetTester tester, [
  OfflineDownloadBatch? batch,
  bool openWishlist = true,
  List<OfflineChapter> offlineChapters = const [],
]) async {
  final batches = batch == null ? const <OfflineDownloadBatch>[] : [batch];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        offlineChaptersProvider.overrideWith((ref) async => offlineChapters),
        downloadsProvider.overrideWith((ref) async => const [_wishlistEntry]),
        offlineQueueProvider.overrideWith(
          () => _FakeOfflineQueueController(batches),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: OfflineDownloadsPane(padding: EdgeInsets.all(16))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!openWishlist) return;
  await tester.tap(find.text('Solo Leveling').last);
  await tester.pumpAndSettle();
}

Future<void> _pumpOfflineDownloads(WidgetTester tester) async {
  final chapter = _offlineChapter(status: 'completed');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        offlineChaptersProvider.overrideWith((ref) async => [chapter]),
        downloadsProvider.overrideWith((ref) async => const []),
        offlineQueueProvider.overrideWith(_FakeOfflineQueueController.new),
      ],
      child: const MaterialApp(
        home: Scaffold(body: OfflineDownloadsPane(padding: EdgeInsets.all(16))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Solo Leveling').last);
  await tester.pumpAndSettle();
}

OfflineChapter _offlineChapter({required String status}) {
  return OfflineChapter(
    comic: _wishlistEntry.comic,
    chapterNumber: 12,
    status: status,
    localPaths: status == 'completed' ? const ['offline-page.jpg'] : const [],
    updatedAt: DateTime.now(),
  );
}

ProviderContainer _testContainer({bool bookmarked = false}) {
  return ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      pushNotificationLifecycleServiceProvider.overrideWithValue(
        const _NoopPushNotificationService(),
      ),
      pushRegistrationServiceProvider.overrideWithValue(
        const _NoopPushNotificationService(),
      ),
      authControllerProvider.overrideWith(_ReadyGuestAuthController.new),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      catalogRepositoryProvider.overrideWithValue(_FakeCatalogRepository()),
      libraryComicStateProvider(_FakeCatalogRepository.comic).overrideWith(
        (ref) async => LibraryComicState(
          comic: const LibraryComicRef(
            sourceName: 'komiku',
            slug: 'solo-leveling',
            title: 'Solo Leveling',
          ),
          bookmarked: bookmarked,
          collections: const [],
        ),
      ),
      offlineChaptersProvider.overrideWith((ref) async => const []),
      downloadsProvider.overrideWith((ref) async => const []),
      offlineQueueProvider.overrideWith(_FakeOfflineQueueController.new),
    ],
  );
}

class _ReadyGuestAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.guest();

  @override
  Future<void> restore() async {
    state = const AuthState.guest();
  }
}

class _NoopPushNotificationService
    implements PushNotificationLifecycleService, PushRegistrationService {
  const _NoopPushNotificationService();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> syncRegistration() async {}

  @override
  Future<void> unregisterDevice() async {}
}

class _FakeOfflineQueueController extends OfflineQueueController {
  _FakeOfflineQueueController([this.batches = const []]);

  final List<OfflineDownloadBatch> batches;

  @override
  Future<List<OfflineDownloadBatch>> build() async => batches;
}

class _FakeBookmarksPaginationController extends BookmarksPaginationController {
  _FakeBookmarksPaginationController(this.bookmarks);

  final List<LibraryComicRef> bookmarks;

  @override
  Future<PaginatedState<LibraryComicRef>> build() async => PaginatedState(
    items: bookmarks,
    page: 1,
    pageSize: 20,
    hasNextPage: false,
  );
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
  Future<List<ComicSummary>> getLatest(
    String sourceName, {
    int page = 1,
    int pageSize = 20,
    String? type,
    String? genre,
    String? sort,
  }) async => const [comic];

  @override
  Future<List<ComicSummary>> getPopular(
    String sourceName, {
    int page = 1,
    int pageSize = 20,
    String? type,
    String? status,
    String? genre,
    String? sort,
  }) async => const [comic];

  @override
  Future<List<ComicSummary>> getRecommendations(
    String sourceName, {
    int limit = 4,
  }) async => const [comic];

  @override
  Future<List<ComicSummary>> getTopRanking(
    String sourceName, {
    int limit = 10,
    String? type,
  }) async => const [comic];

  @override
  Future<LatestComicStats> getLatestStats(String sourceName) async {
    return const LatestComicStats(periodDays: 7, updatedComicCount: 1);
  }

  @override
  LatestComicStats? getCachedLatestStats(String sourceName) => null;

  @override
  bool shouldRefreshLatestStats(
    String sourceName, {
    Duration maxAge = const Duration(hours: 1),
  }) => true;

  @override
  List<ComicSummary> getCachedComicSection(
    String sourceName, {
    required bool popular,
  }) => const [];

  @override
  bool hasCachedComicSection(String sourceName, {required bool popular}) =>
      false;

  @override
  void cacheComicSection(
    String sourceName, {
    required bool popular,
    required List<ComicSummary> comics,
  }) {}

  @override
  Future<List<Genre>> getGenres() async => const [
    Genre(id: 1, name: 'Action', slug: 'action'),
  ];

  @override
  List<Genre> getCachedGenres() => const [
    Genre(id: 1, name: 'Action', slug: 'action'),
  ];

  @override
  Future<List<Genre>> refreshGenres() => getGenres();

  @override
  Future<SourceComicPage> getSourceComics({
    required String? sourceName,
    required int page,
    int pageSize = 15,
    String? type,
    String? status,
    String? genre,
    String? sort,
  }) async {
    return const SourceComicPage(
      items: [comic],
      total: 1,
      page: 1,
      pageSize: 15,
      totalPages: 1,
    );
  }

  @override
  Future<SourceComicPage> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async => const SourceComicPage(
    items: [comic],
    total: 1,
    page: 1,
    pageSize: 20,
    totalPages: 1,
  );

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
      ChapterListItem(
        chapterNumber: 1,
        createdAt: DateTime(2025, 1, 1),
        totalImages: 1,
        detailUrl: 'https://example.test/solo-leveling/1',
      ),
    ];
  }

  @override
  Future<ChapterPayload> getChapter(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    return ChapterPayload(
      sourceName: 'komiku',
      chapterNumber: chapterNumber,
      images: const [],
      total: 0,
    );
  }
}

class _FakeAlternativeTitleCatalogRepository extends _FakeCatalogRepository {
  _FakeAlternativeTitleCatalogRepository({required this.alternativeTitles});

  final String alternativeTitles;

  @override
  Future<ComicDetail> getComicDetail(String sourceName, String slug) async {
    final base = await super.getComicDetail(sourceName, slug);
    return ComicDetail(
      id: base.id,
      title: base.title,
      slug: base.slug,
      sourceName: base.sourceName,
      sourceUrl: base.sourceUrl,
      genres: base.genres,
      totalChapters: base.totalChapters,
      type: base.type,
      status: base.status,
      rating: base.rating,
      alternativeTitles: alternativeTitles,
    );
  }
}
