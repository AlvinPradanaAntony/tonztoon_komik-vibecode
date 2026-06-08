import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/core/app_theme.dart';
import 'package:tonztoon/src/features/notifications/notifications_screen.dart';
import 'package:tonztoon/src/models/app_notification.dart';
import 'package:tonztoon/src/repositories/providers.dart';

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
    expect(summaryGradient.colors.first, const Color(0xFF143248));
    expect(summaryGradient.colors.last, const Color(0xFF402515));
    expect(summaryDecoration.border, isNull);
  });
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
