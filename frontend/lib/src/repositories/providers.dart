import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/auth.dart';
import '../models/comic.dart';
import '../models/library.dart';
import '../models/progress.dart';
import '../models/source_info.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';
import 'library_repository.dart';
import 'offline_repository.dart';
import 'progress_repository.dart';

final configProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
      AppThemeModeController.new,
    );

class AppThemeModeController extends Notifier<ThemeMode> {
  static const _storageKey = 'theme_mode';

  @override
  ThemeMode build() {
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    return _themeModeFromName(value is String ? value : null);
  }

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(localStoreProvider).settings.put(_storageKey, mode.name);
    state = mode;
  }

  static ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiProvider = Provider<TonztoonApi>((ref) {
  return TonztoonApi(
    config: ref.watch(configProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(
    ref.watch(apiProvider),
    ref.watch(localStoreProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
  );
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(
    ref.watch(apiProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(localStoreProvider),
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

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.booting();

  Future<void> restore() async {
    state = const AuthState.booting();
    state = await ref.read(authRepositoryProvider).restore();
  }

  Future<void> login(String email, String password) async {
    state = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
  }

  Future<void> register(
    String email,
    String password,
    String? displayName,
  ) async {
    state = await ref
        .read(authRepositoryProvider)
        .register(email: email, password: password, displayName: displayName);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState.guest();
    ref.invalidate(continueReadingProvider);
  }
}

final selectedSourceProvider =
    NotifierProvider<SelectedSourceController, String?>(
      SelectedSourceController.new,
    );

class SelectedSourceController extends Notifier<String?> {
  @override
  String? build() {
    return ref.watch(localStoreProvider).settings.get('selected_source')
        as String?;
  }

  void select(String sourceName) {
    ref.read(localStoreProvider).settings.put('selected_source', sourceName);
    state = sourceName;
  }
}

final sourcesProvider = FutureProvider<List<SourceInfo>>((ref) {
  return ref.watch(catalogRepositoryProvider).getSources();
});

class HomeData {
  const HomeData({
    required this.sources,
    required this.selectedSource,
    required this.latest,
    required this.popular,
    required this.continueReading,
  });

  final List<SourceInfo> sources;
  final SourceInfo selectedSource;
  final List<ComicSummary> latest;
  final List<ComicSummary> popular;
  final List<ReadingProgress> continueReading;
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final repository = ref.watch(catalogRepositoryProvider);
  final progressRepository = ref.watch(progressRepositoryProvider);
  final sources = await repository.getSources();
  if (sources.isEmpty) {
    throw ApiException('No sources available.');
  }
  final selectedId = ref.watch(selectedSourceProvider);
  final selected = sources.firstWhere(
    (source) => source.id == selectedId,
    orElse: () => sources.first,
  );
  final results = await Future.wait([
    repository.getLatest(selected.id),
    repository.getPopular(selected.id),
    progressRepository.getContinueReading(),
  ]);
  return HomeData(
    sources: sources,
    selectedSource: selected,
    latest: results[0] as List<ComicSummary>,
    popular: results[1] as List<ComicSummary>,
    continueReading: results[2] as List<ReadingProgress>,
  );
});

class ComicRequest {
  const ComicRequest(this.sourceName, this.slug);

  final String sourceName;
  final String slug;

  @override
  bool operator ==(Object other) {
    return other is ComicRequest &&
        other.sourceName == sourceName &&
        other.slug == slug;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug);
}

final comicDetailProvider = FutureProvider.family<ComicDetail, ComicRequest>((
  ref,
  request,
) {
  return ref
      .watch(catalogRepositoryProvider)
      .getComicDetail(request.sourceName, request.slug);
});

final chaptersProvider =
    FutureProvider.family<List<ChapterListItem>, ComicRequest>((ref, request) {
      return ref
          .watch(catalogRepositoryProvider)
          .getChapters(request.sourceName, request.slug);
    });

final progressProvider = FutureProvider.family<ReadingProgress?, ComicRequest>((
  ref,
  request,
) {
  return ref
      .watch(progressRepositoryProvider)
      .getProgress(request.sourceName, request.slug);
});

final continueReadingProvider = FutureProvider<List<ReadingProgress>>((ref) {
  return ref.watch(progressRepositoryProvider).getContinueReading();
});

class ChapterRequest extends ComicRequest {
  const ChapterRequest(super.sourceName, super.slug, this.chapterNumber);

  final double chapterNumber;

  @override
  bool operator ==(Object other) {
    return other is ChapterRequest &&
        other.sourceName == sourceName &&
        other.slug == slug &&
        other.chapterNumber == chapterNumber;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug, chapterNumber);
}

final chapterProvider = FutureProvider.family<ChapterPayload, ChapterRequest>((
  ref,
  request,
) async {
  final offline = await ref
      .watch(offlineRepositoryProvider)
      .getOfflinePayload(
        request.sourceName,
        request.slug,
        request.chapterNumber,
      );
  if (offline != null) return offline;

  try {
    return await ref
        .watch(catalogRepositoryProvider)
        .getChapter(request.sourceName, request.slug, request.chapterNumber);
  } catch (_) {
    final fallback = await ref
        .watch(offlineRepositoryProvider)
        .getOfflinePayload(
          request.sourceName,
          request.slug,
          request.chapterNumber,
        );
    if (fallback != null) return fallback;
    rethrow;
  }
});

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) {
    state = value;
  }
}

final searchResultsProvider = FutureProvider<List<ComicSummary>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (ref.watch(searchQueryProvider).trim() != query) return const [];
  return ref.watch(catalogRepositoryProvider).search(query);
});

final libraryComicStateProvider =
    FutureProvider.family<LibraryComicState, ComicSummary>((ref, comic) {
      return ref.watch(libraryRepositoryProvider).getComicState(comic);
    });

final bookmarksProvider = FutureProvider<List<LibraryComicRef>>((ref) {
  return ref.watch(libraryRepositoryProvider).getBookmarks();
});

final collectionsProvider = FutureProvider<List<CollectionSummary>>((ref) {
  return ref.watch(libraryRepositoryProvider).getCollections();
});

final favoriteScenesProvider = FutureProvider<List<FavoriteScene>>((ref) {
  return ref.watch(libraryRepositoryProvider).getFavoriteScenes();
});

final historyProvider = FutureProvider<List<ReadingProgress>>((ref) {
  return ref.watch(libraryRepositoryProvider).getHistory();
});

final downloadsProvider = FutureProvider<List<DownloadEntry>>((ref) {
  return ref.watch(libraryRepositoryProvider).getDownloads();
});

final offlineChaptersProvider = FutureProvider<List<OfflineChapter>>((ref) {
  return ref.watch(offlineRepositoryProvider).getOfflineChapters();
});

final offlineQueueProvider =
    AsyncNotifierProvider<OfflineQueueController, List<OfflineDownloadBatch>>(
      OfflineQueueController.new,
    );

class OfflineQueueController extends AsyncNotifier<List<OfflineDownloadBatch>> {
  final Map<String, CancelToken> _cancelTokens = {};

  @override
  Future<List<OfflineDownloadBatch>> build() {
    return ref.watch(offlineRepositoryProvider).getBatches();
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(offlineRepositoryProvider).getBatches());
  }

  Future<void> startBatch({
    required ComicSummary comic,
    required List<ChapterListItem> chapters,
  }) async {
    if (chapters.isEmpty) return;
    final chapterNumbers = chapters.map((item) => item.chapterNumber).toList();
    final batch = OfflineDownloadBatch.create(
      id: '${comic.sourceName}|${comic.slug}|${DateTime.now().microsecondsSinceEpoch}',
      comic: comic,
      chapterNumbers: chapterNumbers,
    );
    await ref
        .read(libraryRepositoryProvider)
        .enqueueDownloadBatch(comic, chapterNumbers);
    await ref.read(offlineRepositoryProvider).saveBatch(batch);
    await refresh();
    unawaited(_runBatch(batch));
  }

  Future<void> resumeBatch(String batchId) async {
    final batches = state.asData?.value ?? await build();
    OfflineDownloadBatch? batch;
    for (final item in batches) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch == null || !batch.canResume) return;
    unawaited(_runBatch(batch));
  }

  Future<void> resumeRecoverableBatches() async {
    final batches = await ref.read(offlineRepositoryProvider).getBatches();
    state = AsyncData(batches);
    for (final batch in batches.where((batch) => batch.canResume)) {
      unawaited(_runBatch(batch));
    }
  }

  Future<void> cancelBatch(String batchId) async {
    _cancelTokens[batchId]?.cancel('Download batch cancelled.');
    OfflineDownloadBatch? batch;
    for (final item in state.asData?.value ?? const <OfflineDownloadBatch>[]) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch != null) {
      await _saveBatch(
        batch.copyWith(
          status: 'cancelled',
          clearCurrentChapterNumber: true,
          lastError: 'Cancelled by user.',
        ),
      );
    }
  }

  Future<void> deleteBatch(String batchId) async {
    _cancelTokens[batchId]?.cancel('Download batch deleted.');
    _cancelTokens.remove(batchId);
    await ref.read(offlineRepositoryProvider).deleteBatch(batchId);
    await refresh();
  }

  Future<void> _runBatch(OfflineDownloadBatch initialBatch) async {
    if (_cancelTokens.containsKey(initialBatch.id)) return;
    final token = CancelToken();
    _cancelTokens[initialBatch.id] = token;
    var batch = initialBatch.copyWith(
      status: 'downloading',
      completedChapters: 0,
      progressValue: 0,
      clearLastError: true,
    );
    await _saveBatch(batch);

    try {
      final startIndex = batch.completedChapters.clamp(
        0,
        batch.chapterNumbers.length,
      );
      for (
        var chapterIndex = startIndex;
        chapterIndex < batch.chapterNumbers.length;
        chapterIndex++
      ) {
        if (token.isCancelled) {
          await _saveBatch(
            batch.copyWith(
              status: 'cancelled',
              clearCurrentChapterNumber: true,
              lastError: 'Cancelled by user.',
            ),
          );
          return;
        }
        final chapterNumber = batch.chapterNumbers[chapterIndex];
        final existing = await ref
            .read(offlineRepositoryProvider)
            .getOfflineChapter(
              batch.comic.sourceName,
              batch.comic.slug,
              chapterNumber,
            );
        if (existing?.isCompleted == true) {
          batch = batch.copyWith(
            completedChapters: chapterIndex + 1,
            progressValue: (chapterIndex + 1) / batch.totalChapters,
          );
          await _saveBatch(batch);
          continue;
        }
        batch = batch.copyWith(
          status: 'downloading',
          currentChapterNumber: chapterNumber,
          completedChapters: chapterIndex,
          progressValue: chapterIndex / batch.totalChapters,
        );
        await _saveBatch(batch);

        final payload = await ref
            .read(catalogRepositoryProvider)
            .getChapter(
              batch.comic.sourceName,
              batch.comic.slug,
              chapterNumber,
            );
        final totalPages = payload.images.length;
        batch = batch.copyWith(totalImages: totalPages);
        await _saveBatch(batch);

        await ref
            .read(offlineRepositoryProvider)
            .downloadChapter(
              comic: batch.comic.toSummary(),
              chapterNumber: chapterNumber,
              payload: payload,
              cancelToken: token,
              onImageProgress: (pageIndex, received, total) {
                final pageFraction = total <= 0 ? 0.0 : received / total;
                final chapterFraction = totalPages == 0
                    ? 1.0
                    : ((pageIndex + pageFraction) / totalPages).clamp(0, 1);
                final overall =
                    ((chapterIndex + chapterFraction) / batch.totalChapters)
                        .clamp(0, 1)
                        .toDouble();
                final live = batch.copyWith(
                  completedChapters: chapterIndex,
                  completedImages: pageIndex,
                  totalImages: totalPages,
                  progressValue: overall,
                );
                unawaited(_saveBatch(live));
              },
            );

        batch = batch.copyWith(
          completedChapters: chapterIndex + 1,
          progressValue: (chapterIndex + 1) / batch.totalChapters,
        );
        await _saveBatch(batch);
        ref.invalidate(offlineChaptersProvider);
      }

      await _saveBatch(
        batch.copyWith(
          status: 'completed',
          completedChapters: batch.totalChapters,
          progressValue: 1,
          clearCurrentChapterNumber: true,
        ),
      );
    } on DioException catch (error) {
      final cancelled = CancelToken.isCancel(error);
      await _saveBatch(
        batch.copyWith(
          status: cancelled ? 'cancelled' : 'failed',
          clearCurrentChapterNumber: true,
          lastError: error.message ?? error.toString(),
        ),
      );
    } catch (error) {
      await _saveBatch(
        batch.copyWith(
          status: 'failed',
          clearCurrentChapterNumber: true,
          lastError: error.toString(),
        ),
      );
    } finally {
      _cancelTokens.remove(initialBatch.id);
      ref.invalidate(offlineChaptersProvider);
      ref.invalidate(downloadsProvider);
    }
  }

  Future<void> _saveBatch(OfflineDownloadBatch batch) async {
    await ref.read(offlineRepositoryProvider).saveBatch(batch);
    final current = [...?state.asData?.value];
    final index = current.indexWhere((item) => item.id == batch.id);
    if (index >= 0) {
      current[index] = batch;
    } else {
      current.insert(0, batch);
    }
    current.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncData(current);
  }
}

final readerPreferencesProvider = FutureProvider<ReaderPreferences>((ref) {
  return ref.watch(libraryRepositoryProvider).getReaderPreferences();
});
