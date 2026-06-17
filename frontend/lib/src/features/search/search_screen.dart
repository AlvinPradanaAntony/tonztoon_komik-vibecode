import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_error.dart';
import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../helpers/genre_options.dart';
import '../../helpers/navigation_helpers.dart';
import '../../models/comic.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_edge_fade.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_filter_sort_sheet.dart';
import 'controller/search_filter_controller.dart';

part 'models/search_view_models.dart';
part 'widgets/search_input.dart';
part 'widgets/search_results.dart';
part 'widgets/search_shimmers.dart';
part 'widgets/search_states.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _keyboardDismissDuration = Duration(milliseconds: 260);
  static const _sheetEnterDuration = Duration(milliseconds: 300);
  static const _sheetExitDuration = Duration(milliseconds: 220);
  static const _searchDelay = Duration(milliseconds: 420);
  static const _searchControlsHeight = 78.0;
  static const _searchFilterStripHeight = 50.0;
  static const _searchContentGap = 22.0;
  static const _searchFadeOverflow = 26.0;
  static const _searchBottomPadding = 132.0;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _gridView = false;
  bool _filterButtonActive = false;
  bool _isSearching = false;
  bool _isFilteringResults = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim();
    final searchAsync = ref.watch(searchResultsProvider);
    final filters = ref.watch(searchFilterProvider);
    final isLoading = _isSearching && !searchAsync.hasValue;
    final controlsHeight =
        _searchControlsHeight +
        (_isFilteringResults ? _searchFilterStripHeight : 0);
    final listTopPadding = controlsHeight + _searchContentGap;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cari Komik', style: theme.textTheme.titleLarge),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: _gridView ? 'Tampilan daftar' : 'Tampilan grid',
              onPressed: () => setState(() => _gridView = !_gridView),
              icon: Icon(
                _gridView ? TonztoonIcons.rows : TonztoonIcons.columns,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableStateHeight =
                    constraints.maxHeight -
                    listTopPadding -
                    _searchBottomPadding;
                final stateHeight = availableStateHeight > 220
                    ? availableStateHeight
                    : 220.0;

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    listTopPadding,
                    16,
                    _searchBottomPadding,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _buildSearchContent(
                        query: query,
                        searchAsync: searchAsync,
                        isLoading: isLoading,
                        stateHeight: stateHeight,
                        filters: filters,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          AppEdgeFade(
            edge: AppFadeEdge.top,
            background: theme.scaffoldBackgroundColor,
            height: listTopPadding + _searchFadeOverflow,
            midStop: 0.58,
            midAlpha: 0.9,
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _SearchStickyControls(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SearchBox(
                    controller: _searchController,
                    onChanged: _handleSearchChanged,
                    onClear: _clearSearch,
                    onFilter: _showFilterSheet,
                    filterActive:
                        _filterButtonActive ||
                        _isFilteringResults ||
                        filters.hasActiveFilters,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: _isFilteringResults
                        ? const Padding(
                            key: ValueKey('search-filter-processing'),
                            padding: EdgeInsets.only(top: 12),
                            child: _SearchFilterProcessingStrip(),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchContent({
    required String query,
    required AsyncValue<List<ComicSummary>> searchAsync,
    required bool isLoading,
    required double stateHeight,
    required ComicFilterSortState filters,
  }) {
    if (isLoading) {
      return _SearchLoadingPlaceholder(
        key: ValueKey('search-loading-$_gridView'),
        gridView: _gridView,
      );
    }

    if (query.isEmpty) {
      return _SearchCenteredState(
        key: const ValueKey('search-empty-initial'),
        height: stateHeight,
        child: const _SearchEmptyState(
          icon: TonztoonIcons.search,
          title: 'Cari komik',
          message:
              'Masukkan judul, author, genre, atau sumber untuk mulai mencari.',
        ),
      );
    }

    return searchAsync.when(
      data: (items) {
        final results = _visibleResults(_searchPool(items), filters);
        if (results.isEmpty) {
          return _SearchCenteredState(
            key: const ValueKey('search-empty-results'),
            height: stateHeight,
            child: _SearchEmptyState(
              icon: TonztoonIcons.search,
              title: 'Tidak ada hasil',
              message: 'Tidak ada komik yang cocok untuk "$query".',
            ),
          );
        }

        return Column(
          key: ValueKey('search-results-$_gridView-$query'),
          children: [
            _ResultHeader(query: query, resultCount: results.length),
            const SizedBox(height: 12),
            _gridView
                ? _ResultGrid(comics: results)
                : _ResultList(comics: results),
          ],
        );
      },
      loading: () => _SearchLoadingPlaceholder(
        key: ValueKey('search-async-loading-$_gridView'),
        gridView: _gridView,
      ),
      error: (error, stackTrace) {
        logAppError(error, stackTrace, context: 'Search provider failed');
        return _SearchCenteredState(
          key: ValueKey('search-error-$query'),
          height: stateHeight,
          child: _SearchErrorState(
            message: friendlyErrorMessage(
              error,
              fallbackMessage: 'Pencarian belum berhasil. Silakan coba lagi.',
            ),
            onRetry: () => unawaited(_retrySearch()),
          ),
        );
      },
    );
  }

  List<_SearchComicUi> _searchPool(List<ComicSummary> liveResults) {
    return liveResults.map(_SearchComicUi.fromSummary).toList();
  }

  List<_SearchComicUi> _visibleResults(
    List<_SearchComicUi> searchPool,
    ComicFilterSortState filters,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];

    final filtered = searchPool.where((comic) {
      final values = [
        comic.summary.title,
        comic.summary.type ?? '',
        comic.source,
        comic.type,
        comic.status,
        comic.genre,
        comic.genres.join(' '),
        comic.chapter,
        comic.description,
      ].join(' ').toLowerCase();
      final queryMatches = values.contains(query);
      final filterMatches = _matchesFilters(comic, filters);

      return queryMatches && filterMatches;
    }).toList();

    switch (filters.sort) {
      case ComicSortOption.ratingHigh:
        filtered.sort((a, b) => b.ratingValue.compareTo(a.ratingValue));
      case ComicSortOption.updateNewest:
        filtered.sort((a, b) => b.updateRank.compareTo(a.updateRank));
      case ComicSortOption.popular:
        filtered.sort((a, b) => b.popularityRank.compareTo(a.popularityRank));
      case ComicSortOption.az:
        filtered.sort((a, b) => a.summary.title.compareTo(b.summary.title));
      case ComicSortOption.za:
        filtered.sort((a, b) => b.summary.title.compareTo(a.summary.title));
      case ComicSortOption.relevance:
        break;
    }

    return filtered;
  }

  bool _matchesFilters(_SearchComicUi comic, ComicFilterSortState filters) {
    final genreMatches =
        filters.genre == ComicFilterOption.all ||
        comic.genres.any((genre) => genre == filters.genre);

    return (filters.source == ComicFilterOption.all ||
            comic.source == filters.source) &&
        (filters.type == ComicFilterOption.all || comic.type == filters.type) &&
        (filters.status == ComicFilterOption.all ||
            comic.status == filters.status) &&
        genreMatches;
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    ref.read(searchQueryProvider.notifier).setQuery(value);
    final query = value.trim();

    if (query.isEmpty) {
      setState(() => _isSearching = false);
      return;
    }

    setState(() => _isSearching = true);
    _searchDebounce = Timer(_searchDelay, () {
      if (!mounted) return;
      setState(() => _isSearching = false);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).setQuery('');
    setState(() => _isSearching = false);
  }

  Future<void> _retrySearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    _searchDebounce?.cancel();

    try {
      ref.invalidate(searchResultsProvider);
      await ref.read(searchResultsProvider.future);
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Retry search failed',
        fallbackMessage: 'Pencarian belum berhasil. Silakan coba lagi.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _showFilterSheet() async {
    await _dismissKeyboardBeforeSheet();
    if (!mounted) return;

    setState(() => _filterButtonActive = true);
    final cachedGenreOptions = cachedGenreOptionNames(ref);

    final result = await showComicFilterSortSheet(
      context: context,
      initialState: ref.read(searchFilterProvider),
      title: 'Filter dan Sorting',
      resetSort: ComicSortOption.relevance,
      genreOptions: cachedGenreOptions.isEmpty ? null : cachedGenreOptions,
      genreOptionsRefreshFuture: refreshGenreOptionNames(
        ref,
        context,
        logContext: 'Refresh search genres failed',
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      animationStyle: const AnimationStyle(
        duration: _sheetEnterDuration,
        reverseDuration: _sheetExitDuration,
      ),
    );

    if (!mounted) return;
    setState(() => _filterButtonActive = false);

    if (result == null) return;
    ref.read(searchFilterProvider.notifier).apply(result);
    setState(() => _isFilteringResults = true);
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) {
      setState(() => _isFilteringResults = false);
    }
  }

  Future<void> _dismissKeyboardBeforeSheet() async {
    final keyboardWasVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await WidgetsBinding.instance.endOfFrame;

    if (keyboardWasVisible) {
      await Future<void>.delayed(_keyboardDismissDuration);
    }
  }
}
