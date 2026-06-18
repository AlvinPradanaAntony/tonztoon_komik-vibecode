part of '../providers.dart';

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

final searchResultsProvider =
    AsyncNotifierProvider<SearchResultsController, SearchResultsState>(
      SearchResultsController.new,
    );

class SearchResultsState {
  const SearchResultsState({
    this.query = '',
    this.comics = const [],
    this.page = 0,
    this.pageSize = SearchResultsController.pageSize,
    this.total = 0,
    this.totalPages = 0,
    this.hasNextPage = false,
    this.isLoadingMore = false,
  });

  final String query;
  final List<ComicSummary> comics;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNextPage;
  final bool isLoadingMore;

  SearchResultsState copyWith({
    String? query,
    List<ComicSummary>? comics,
    int? page,
    int? pageSize,
    int? total,
    int? totalPages,
    bool? hasNextPage,
    bool? isLoadingMore,
  }) {
    return SearchResultsState(
      query: query ?? this.query,
      comics: comics ?? this.comics,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      total: total ?? this.total,
      totalPages: totalPages ?? this.totalPages,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class SearchResultsController extends AsyncNotifier<SearchResultsState> {
  static const pageSize = 20;

  @override
  Future<SearchResultsState> build() async {
    final query = ref.watch(searchQueryProvider).trim();
    if (query.isEmpty) return const SearchResultsState();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (ref.watch(searchQueryProvider).trim() != query) {
      return const SearchResultsState();
    }

    final page = await ref
        .watch(catalogRepositoryProvider)
        .search(query, page: 1, pageSize: pageSize);
    return SearchResultsState(
      query: query,
      comics: page.items,
      page: page.page,
      pageSize: page.pageSize,
      total: page.total,
      totalPages: page.totalPages,
      hasNextPage: page.hasNextPage,
    );
  }

  Future<void> loadNextPage() async {
    final current = state.asData?.value;
    if (current == null ||
        current.query.isEmpty ||
        current.isLoadingMore ||
        !current.hasNextPage) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.page + 1;
      final page = await ref
          .read(catalogRepositoryProvider)
          .search(current.query, page: nextPage, pageSize: current.pageSize);
      final latest = state.asData?.value;
      if (latest == null || !latest.isLoadingMore) return;

      state = AsyncData(
        latest.copyWith(
          comics: _appendDeduplicated(latest.comics, page.items),
          page: page.page,
          pageSize: page.pageSize,
          total: page.total,
          totalPages: page.totalPages,
          hasNextPage: page.hasNextPage,
          isLoadingMore: false,
        ),
      );
    } catch (error) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(isLoadingMore: false));
      }
      rethrow;
    }
  }

  List<ComicSummary> _appendDeduplicated(
    List<ComicSummary> existing,
    List<ComicSummary> incoming,
  ) {
    final keys = existing.map(_comicKey).toSet();
    final merged = [...existing];
    for (final comic in incoming) {
      if (keys.add(_comicKey(comic))) merged.add(comic);
    }
    return merged;
  }

  String _comicKey(ComicSummary comic) =>
      '${comic.sourceName}|${comic.slug}|${comic.title}';
}
