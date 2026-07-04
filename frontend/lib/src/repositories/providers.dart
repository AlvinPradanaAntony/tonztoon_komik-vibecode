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
// Re-exported so the per-domain `part` extensions on LibraryRepository
// (bookmark links, collections, scenes/downloads, migration) are in scope
// wherever the repository is used via providers.
export 'library_repository.dart';
import 'notification_repository.dart';
import 'offline_repository.dart';
import 'progress_repository.dart';
import 'google_auth_client.dart';
import 'helpdesk_repository.dart';
import 'push_device_repository.dart';

// Domain-specific providers live in `part` files under `providers/`. They all
// share this library's imports and scope, so cross-references between groups
// (e.g. catalog watching auth) resolve without extra wiring, and external
// imports of `providers.dart` continue to see every provider unchanged.
part 'providers/auth_providers.dart';
part 'providers/catalog_providers.dart';
part 'providers/library_providers.dart';
part 'providers/notification_providers.dart';
part 'providers/offline_providers.dart';
part 'providers/search_providers.dart';
part 'providers/settings_providers.dart';

// ---------------------------------------------------------------------------
// Core wiring: configuration, network client, persistent stores, and the
// repository providers every feature builds on. Kept together here because
// they are the foundation the domain providers depend on.
// ---------------------------------------------------------------------------

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

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiProvider = Provider<TonztoonApi>((ref) {
  return TonztoonApi(
    config: ref.watch(configProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final pushDeviceRepositoryProvider = Provider<PushDeviceRepository>((ref) {
  return PushDeviceRepository(ref.watch(apiProvider));
});

final helpdeskRepositoryProvider = Provider<HelpdeskRepository>((ref) {
  return HelpdeskRepository(ref.watch(apiProvider));
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
      if (progress.isCompleted) {
        ref.read(paginatedBookmarksProvider.notifier).updateItems(
          (item) {
            if (item.sourceName == progress.sourceName &&
                item.slug == progress.comicSlug) {
              return true;
            }
            return item.linkedComics.any(
              (linked) =>
                  linked.sourceName == progress.sourceName &&
                  linked.slug == progress.comicSlug,
            );
          },
          (item) => item.copyWith(hasNewChapter: false),
        );
      }
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
