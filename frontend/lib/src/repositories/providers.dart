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
import 'progress_repository.dart';

final configProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());

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
) {
  return ref
      .watch(catalogRepositoryProvider)
      .getChapter(request.sourceName, request.slug, request.chapterNumber);
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

final readerPreferencesProvider = FutureProvider<ReaderPreferences>((ref) {
  return ref.watch(libraryRepositoryProvider).getReaderPreferences();
});
