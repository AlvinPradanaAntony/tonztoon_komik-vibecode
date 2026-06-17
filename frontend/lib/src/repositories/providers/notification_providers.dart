part of '../providers.dart';

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

final remotePushNotificationServiceProvider =
    Provider<RemotePushNotificationService>((ref) {
      final service = RemotePushNotificationService(
        repository: ref.watch(pushDeviceRepositoryProvider),
        store: ref.watch(localStoreProvider),
        localNotifications: ref.watch(pushNotificationServiceProvider),
        readPreferences: () => ref.read(pushNotificationPreferencesProvider),
        readAuth: () => ref.read(authControllerProvider),
        onOpenLocation: openLocationFromNotification,
        onAppNotification: (notification) async {
          await ref.read(notificationsProvider.notifier).add(notification);
          ref.invalidate(notificationsProvider);
        },
      );
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });

final pushRegistrationServiceProvider = Provider<PushRegistrationService>(
  (ref) => ref.watch(remotePushNotificationServiceProvider),
);

final pushNotificationLifecycleServiceProvider =
    Provider<PushNotificationLifecycleService>(
      (ref) => ref.watch(remotePushNotificationServiceProvider),
    );

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
      unawaited(ref.read(pushRegistrationServiceProvider).syncRegistration());
    } else {
      unawaited(ref.read(pushRegistrationServiceProvider).unregisterDevice());
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

  Future<void> refresh() async {
    state = AsyncData(
      await ref.read(notificationRepositoryProvider).getNotifications(),
    );
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

  Future<void> clear() async {
    state = AsyncData(await ref.read(notificationRepositoryProvider).clear());
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
