part of '../providers.dart';

final libraryComicStateProvider =
    FutureProvider.family<LibraryComicState, ComicSummary>((ref, comic) {
      return ref.watch(libraryRepositoryProvider).getComicState(comic);
    });

final bookmarksProvider = FutureProvider<List<LibraryComicRef>>((ref) {
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  return ref.watch(libraryRepositoryProvider).getBookmarks();
});

final paginatedBookmarksProvider =
    AsyncNotifierProvider<
      BookmarksPaginationController,
      PaginatedState<LibraryComicRef>
    >(BookmarksPaginationController.new);

class BookmarksPaginationController
    extends PaginatedAsyncController<LibraryComicRef> {
  @override
  void watchDependencies() {
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  }

  @override
  Future<List<LibraryComicRef>> loadPage({
    required int page,
    required int pageSize,
  }) {
    return ref
        .read(libraryRepositoryProvider)
        .getBookmarksPage(page: page, pageSize: pageSize);
  }

  @override
  String itemKey(LibraryComicRef item) {
    return '${item.sourceName}|${item.slug}';
  }
}

class PaginatedState<T> {
  const PaginatedState({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasNextPage,
    this.isLoadingMore = false,
    this.isRefreshing = false,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final bool hasNextPage;
  final bool isLoadingMore;
  final bool isRefreshing;

  PaginatedState<T> copyWith({
    List<T>? items,
    int? page,
    int? pageSize,
    bool? hasNextPage,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return PaginatedState<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

abstract class PaginatedAsyncController<T>
    extends AsyncNotifier<PaginatedState<T>> {
  int get pageSize => 20;

  void watchDependencies() {}

  Future<List<T>> loadPage({required int page, required int pageSize});

  String itemKey(T item);

  @override
  Future<PaginatedState<T>> build() async {
    watchDependencies();
    return _loadFirstPage();
  }

  Future<void> loadNextPage() async {
    final current = state.asData?.value;
    if (current == null ||
        current.isRefreshing ||
        current.isLoadingMore ||
        current.hasNextPage == false) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.page + 1;
      final nextItems = await loadPage(page: nextPage, pageSize: pageSize);
      final existingKeys = current.items.map(itemKey).toSet();
      final mergedItems = [...current.items];
      var addedCount = 0;

      for (final item in nextItems) {
        if (existingKeys.add(itemKey(item))) {
          mergedItems.add(item);
          addedCount++;
        }
      }

      state = AsyncData(
        current.copyWith(
          items: mergedItems,
          page: nextPage,
          hasNextPage: nextItems.length >= pageSize && addedCount > 0,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> refreshFirstPage() async {
    final current = state.asData?.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    if (current.isRefreshing) return;

    state = AsyncData(
      current.copyWith(isRefreshing: true, isLoadingMore: false),
    );
    try {
      final refreshedItems = await loadPage(page: 1, pageSize: pageSize);

      state = AsyncData(
        current.copyWith(
          items: refreshedItems,
          page: 1,
          hasNextPage: refreshedItems.length >= pageSize,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncData(current.copyWith(isRefreshing: false));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void removeItemByKey(String key) {
    final current = state.asData?.value;
    if (current == null) return;

    final nextItems = current.items
        .where((item) => itemKey(item) != key)
        .toList(growable: false);
    if (nextItems.length == current.items.length) return;

    state = AsyncData(current.copyWith(items: nextItems));
  }

  void upsertItemAtTop(T item) {
    final current = state.asData?.value;
    if (current == null) {
      state = AsyncData(
        PaginatedState<T>(
          items: [item],
          page: 1,
          pageSize: pageSize,
          hasNextPage: false,
        ),
      );
      return;
    }

    final key = itemKey(item);
    state = AsyncData(
      current.copyWith(
        items: [
          item,
          for (final oldItem in current.items)
            if (itemKey(oldItem) != key) oldItem,
        ],
      ),
    );
  }

  Future<PaginatedState<T>> _loadFirstPage() async {
    final items = await loadPage(page: 1, pageSize: pageSize);
    return PaginatedState<T>(
      items: items,
      page: 1,
      pageSize: pageSize,
      hasNextPage: items.length >= pageSize,
    );
  }
}

final librarySummaryProvider = FutureProvider<LibrarySummary>((ref) {
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  return ref.watch(libraryRepositoryProvider).getLibrarySummary();
});

final collectionsProvider = FutureProvider<List<CollectionSummary>>((ref) {
  return ref.watch(libraryRepositoryProvider).getCollections();
});

final collectionDetailProvider = FutureProvider.family<CollectionDetail, int>((
  ref,
  collectionId,
) {
  return ref.watch(libraryRepositoryProvider).getCollectionDetail(collectionId);
});

final favoriteScenesProvider = FutureProvider<List<FavoriteScene>>((ref) {
  return ref.watch(libraryRepositoryProvider).getFavoriteScenes();
});

final historyProvider = FutureProvider<List<ReadingProgress>>((ref) {
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  ref.watch(continueReadingRefreshSignalProvider);
  return ref.watch(libraryRepositoryProvider).getHistory();
});

final paginatedHistoryProvider =
    AsyncNotifierProvider<
      HistoryPaginationController,
      PaginatedState<ReadingProgress>
    >(HistoryPaginationController.new);

class HistoryPaginationController
    extends PaginatedAsyncController<ReadingProgress> {
  @override
  void watchDependencies() {
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  }

  @override
  Future<List<ReadingProgress>> loadPage({
    required int page,
    required int pageSize,
  }) {
    return ref
        .read(libraryRepositoryProvider)
        .getHistoryPage(page: page, pageSize: pageSize);
  }

  @override
  String itemKey(ReadingProgress item) {
    return item.historyStorageKey;
  }
}

final downloadsProvider = FutureProvider<List<DownloadEntry>>((ref) {
  return ref.watch(libraryRepositoryProvider).getDownloads();
});
