import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/comic.dart';
import '../../../models/source_info.dart';
import '../../../repositories/providers.dart';
import '../../../widgets/comic_filter_sort_sheet.dart';

/// Page size for catalog requests. Kept here so the controller is the single
/// owner of pagination concerns.
const _catalogPageSize = 15;

/// Immutable snapshot of the catalog list: the loaded comics plus the
/// server-side pagination cursor. The first-load / error states are carried by
/// the surrounding [AsyncValue] (see [catalogControllerProvider]); this object
/// only describes a *successful* page set and the "load more" progress on top
/// of it.
class CatalogState {
  const CatalogState({
    this.comics = const [],
    this.activeSource,
    this.page = 0,
    this.total = 0,
    this.totalPages = 1,
    this.isLoadingMore = false,
  });

  final List<ComicSummary> comics;
  final SourceInfo? activeSource;
  final int page;
  final int total;
  final int totalPages;
  final bool isLoadingMore;

  bool get hasNextPage => page < totalPages;

  CatalogState copyWith({
    List<ComicSummary>? comics,
    SourceInfo? activeSource,
    bool clearActiveSource = false,
    int? page,
    int? total,
    int? totalPages,
    bool? isLoadingMore,
  }) {
    return CatalogState(
      comics: comics ?? this.comics,
      activeSource: clearActiveSource
          ? null
          : (activeSource ?? this.activeSource),
      page: page ?? this.page,
      total: total ?? this.total,
      totalPages: totalPages ?? this.totalPages,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Holds the active filter/sort selection for the full catalog screen.
/// Changing it causes [catalogControllerProvider] to reload its first page.
final catalogFilterProvider =
    NotifierProvider<CatalogFilterController, ComicFilterSortState>(
      CatalogFilterController.new,
    );

class CatalogFilterController extends Notifier<ComicFilterSortState> {
  @override
  ComicFilterSortState build() {
    return const ComicFilterSortState(sort: ComicSortOption.relevance);
  }

  void apply(ComicFilterSortState filters) {
    state = filters.normalized();
  }

  void clear() {
    state = const ComicFilterSortState(sort: ComicSortOption.relevance);
  }
}

/// Owns catalog list state: first-page load, infinite-scroll pagination, and
/// pull-to-refresh. Watches [catalogFilterProvider] so any filter change
/// re-runs [build] and fetches a fresh first page — which also removes the
/// manual request-serial race guard the screen used to keep.
final catalogControllerProvider =
    AsyncNotifierProvider<CatalogController, CatalogState>(
      CatalogController.new,
    );

class CatalogController extends AsyncNotifier<CatalogState> {
  @override
  Future<CatalogState> build() async {
    // Re-fetch whenever the filter selection changes.
    final filters = ref.watch(catalogFilterProvider);
    return _fetchFirstPage(filters);
  }

  Future<CatalogState> _fetchFirstPage(ComicFilterSortState filters) async {
    final repository = ref.read(catalogRepositoryProvider);
    final sources = await repository.getSources();
    if (sources.isEmpty) {
      throw Exception('No sources available.');
    }

    final source = _sourceFromFilter(sources, filters);
    final page = await repository.getSourceComics(
      sourceName: source?.id,
      page: 1,
      pageSize: _catalogPageSize,
      type: _queryFor(filters.type),
      status: _queryFor(filters.status),
      genre: _queryFor(filters.genre),
      sort: filters.sort,
    );

    return CatalogState(
      comics: page.items,
      activeSource: source,
      page: page.page,
      total: page.total,
      totalPages: page.totalPages < 1 ? 1 : page.totalPages,
    );
  }

  /// Pull-to-refresh that keeps the currently shown comics on top while the
  /// refreshed first page is merged in (so the list never visibly empties).
  ///
  /// On failure the previously loaded data is restored (the list stays
  /// visible) and the error is rethrown so the screen can surface a snackbar.
  Future<void> refresh() async {
    final filters = ref.read(catalogFilterProvider);
    final previous = state.asData?.value;
    try {
      final fresh = await _fetchFirstPage(filters);
      state = AsyncData(
        previous == null
            ? fresh
            : fresh.copyWith(
                comics: _mergeRefreshedFirstPage(fresh.comics, previous.comics),
              ),
      );
    } catch (error, stackTrace) {
      if (previous != null) {
        // Keep the existing list on screen instead of flipping to an error
        // view; the screen shows a snackbar from the rethrown error.
        state = AsyncData(previous);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Loads the next page and appends de-duplicated results. No-op while the
  /// first page is still loading, another append is in flight, or the cursor
  /// is exhausted.
  Future<void> loadNextPage() async {
    final current = state.asData?.value;
    if (current == null || current.isLoadingMore || !current.hasNextPage) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final filters = ref.read(catalogFilterProvider);
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .getSourceComics(
            sourceName: current.activeSource?.id,
            page: current.page + 1,
            pageSize: _catalogPageSize,
            type: _queryFor(filters.type),
            status: _queryFor(filters.status),
            genre: _queryFor(filters.genre),
            sort: filters.sort,
          );

      // A filter change (or refresh) may have replaced the state while we were
      // awaiting; bail out so we don't append onto a stale list.
      final latest = state.asData?.value;
      if (latest == null || !latest.isLoadingMore) return;

      state = AsyncData(
        latest.copyWith(
          comics: _appendDeduplicated(latest.comics, page.items),
          page: page.page,
          total: page.total,
          totalPages: page.totalPages < 1 ? 1 : page.totalPages,
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

  List<ComicSummary> _mergeRefreshedFirstPage(
    List<ComicSummary> refreshed,
    List<ComicSummary> previous,
  ) {
    final refreshedKeys = refreshed.map(_comicKey).toSet();
    return [
      ...refreshed,
      for (final comic in previous)
        if (!refreshedKeys.contains(_comicKey(comic))) comic,
    ];
  }

  String _comicKey(ComicSummary comic) =>
      '${comic.sourceName}|${comic.slug}|${comic.title}';

  String? _queryFor(String option) =>
      option == ComicFilterOption.all ? null : option.toLowerCase();

  SourceInfo? _sourceFromFilter(
    List<SourceInfo> sources,
    ComicFilterSortState filters,
  ) {
    final selectedSource = filters.source;
    if (selectedSource == ComicFilterOption.all) return null;
    for (final source in sources) {
      if (source.label == selectedSource ||
          comicSourceDisplayName(source.id) == selectedSource) {
        return source;
      }
    }
    return null;
  }
}
