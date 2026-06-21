import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tonztoon/src/core/app_theme.dart';
import 'package:tonztoon/src/features/library/library_screen.dart';
import 'package:tonztoon/src/features/notifications/notifications_screen.dart';
import 'package:tonztoon/src/models/app_notification.dart';
import 'package:tonztoon/src/repositories/providers.dart';
import 'package:tonztoon/src/routing/library_routes.dart';

void main() {
  testWidgets('summary and system filter update when notification arrives', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        notificationsProvider.overrideWith(_TestNotificationsController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada notifikasi baru'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(
      (container.read(notificationsProvider.notifier)
              as _TestNotificationsController)
          .refreshCount,
      1,
    );

    await container
        .read(notificationsProvider.notifier)
        .add(
          AppNotification(
            id: 'test:system-notification',
            title: 'Uji coba',
            message: 'Notifikasi sistem berhasil diterima.',
            category: 'Testing',
            kind: 'admin_announcement',
            createdAt: DateTime.now(),
          ),
        );
    await tester.pump();

    expect(find.text('1 notifikasi baru'), findsOneWidget);
    expect(find.text('Uji coba'), findsOneWidget);

    await tester.tap(find.text('Sistem'));
    await tester.pumpAndSettle();

    expect(find.text('Uji coba'), findsOneWidget);

    await tester.tap(find.byTooltip('Bersihkan notifikasi'));
    await tester.pumpAndSettle();
    expect(find.text('Bersihkan notifikasi?'), findsOneWidget);

    await tester.tap(find.text('Bersihkan').last);
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada notifikasi baru'), findsOneWidget);
    expect(find.text('Belum ada notifikasi'), findsOneWidget);
  });

  testWidgets('dark theme keeps notification accents readable', (tester) async {
    final container = ProviderContainer(
      overrides: [
        notificationsProvider.overrideWith(
          _PopulatedNotificationsController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: TonztoonTheme.dark(),
          home: const NotificationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final theme = TonztoonTheme.dark();
    final updateChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('notification-filter-Update')),
    );
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    final summary = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('notification-summary')),
    );
    final summaryDecoration = summary.decoration as BoxDecoration;
    final summaryGradient = summaryDecoration.gradient! as LinearGradient;

    expect(updateChip.backgroundColor, theme.colorScheme.surfaceContainer);
    expect(updateChip.backgroundColor, isNot(Colors.white));
    expect(fab.foregroundColor, theme.colorScheme.surface);
    expect(fab.heroTag, 'notifications-clear');
    expect(summaryGradient.colors.first, const Color(0xFF143248));
    expect(summaryGradient.colors.last, const Color(0xFF402515));
    expect(summaryDecoration.border, isNull);
  });

  testWidgets(
    'tapping notification with actionRoute /notifications does not push route',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          notificationsProvider.overrideWith(
            _NotificationsWithRouteController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the notification tile. Since actionRoute is '/notifications',
      // it should NOT call context.push and thus NOT throw GoRouter error.
      await tester.tap(find.text('Chapter baru tersedia'));
      await tester.pumpAndSettle();

      // Verification: The notification should be marked read successfully without throwing GoRouter errors.
      final controller =
          container.read(notificationsProvider.notifier)
              as _NotificationsWithRouteController;
      expect(controller.markedReadId, 'test:notifications-route');
    },
  );

  testWidgets('download notification switches to the library shell branch', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        notificationsProvider.overrideWith(
          _DownloadNotificationsController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => navigationShell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const Scaffold(body: Center(child: Text('Beranda'))),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/library',
                  builder: (context, state) => LibraryScreen(
                    initialTabIndex: libraryTabIndexFromName(
                      state.uri.queryParameters['tab'],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/notifications');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download selesai'));
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 4);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      libraryDownloadsLocation,
    );

    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      libraryBookmarksLocation,
    );

    router.push('/notifications');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download selesai'));
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 4);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      libraryDownloadsLocation,
    );
    expect(tester.takeException(), isNull);
  });
}

class _DownloadNotificationsController extends NotificationsController {
  @override
  Future<List<AppNotification>> build() async => [
    AppNotification(
      id: 'download:completed',
      title: 'Download selesai',
      message: 'Komik sudah tersedia secara offline.',
      category: 'Download',
      kind: 'download_completed',
      actionRoute: '/library?tab=downloads',
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Future<void> markRead(String id) async {
    state = AsyncData([
      AppNotification(
        id: id,
        title: 'Download selesai',
        message: 'Komik sudah tersedia secara offline.',
        category: 'Download',
        kind: 'download_completed',
        actionRoute: '/library?tab=downloads',
        createdAt: DateTime.now(),
        unread: false,
      ),
    ]);
  }
}

class _NotificationsWithRouteController extends NotificationsController {
  String? markedReadId;

  @override
  Future<List<AppNotification>> build() async => [
    AppNotification(
      id: 'test:notifications-route',
      title: 'Chapter baru tersedia',
      message: 'Tampilan notifikasi.',
      category: 'Update',
      kind: 'chapter_update',
      actionRoute: '/notifications',
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Future<void> markRead(String id) async {
    markedReadId = id;
    state = AsyncData([
      AppNotification(
        id: 'test:notifications-route',
        title: 'Chapter baru tersedia',
        message: 'Tampilan notifikasi.',
        category: 'Update',
        kind: 'chapter_update',
        actionRoute: '/notifications',
        createdAt: DateTime.now(),
        unread: false,
      ),
    ]);
  }
}

class _TestNotificationsController extends NotificationsController {
  int refreshCount = 0;

  @override
  Future<List<AppNotification>> build() async => const [];

  @override
  Future<void> refresh() async {
    refreshCount += 1;
  }

  @override
  Future<void> add(AppNotification notification) async {
    state = AsyncData([notification]);
  }

  @override
  Future<void> clear() async {
    state = const AsyncData([]);
  }
}

class _PopulatedNotificationsController extends NotificationsController {
  @override
  Future<List<AppNotification>> build() async => [
    AppNotification(
      id: 'test:dark-theme',
      title: 'Chapter baru tersedia',
      message: 'Tampilan notifikasi tema gelap.',
      category: 'Update',
      kind: 'chapter_update',
      createdAt: DateTime.now(),
    ),
  ];
}
