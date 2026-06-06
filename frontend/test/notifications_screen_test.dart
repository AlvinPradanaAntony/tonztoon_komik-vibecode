import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
