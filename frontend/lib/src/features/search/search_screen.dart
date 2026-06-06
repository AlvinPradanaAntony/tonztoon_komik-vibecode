import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/app_error.dart';
import '../../core/app_icons.dart';
import '../../core/app_snackbar.dart';
import '../../models/comic.dart';
import '../../repositories/providers.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_filter_sort_sheet.dart';

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
  ComicFilterSortState _filters = const ComicFilterSortState(
    sort: ComicSortOption.relevance,
  );
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
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: listTopPadding + _searchFadeOverflow,
            child: const IgnorePointer(child: _SearchTopFade()),
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
                        _filters.hasActiveFilters,
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
        final results = _visibleResults(_searchPool(items));
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

  List<_SearchComicUi> _visibleResults(List<_SearchComicUi> searchPool) {
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
      final filterMatches = _matchesFilters(comic);

      return queryMatches && filterMatches;
    }).toList();

    switch (_filters.sort) {
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

  bool _matchesFilters(_SearchComicUi comic) {
    final genreMatches =
        _filters.genre == ComicFilterOption.all ||
        comic.genres.any((genre) => genre == _filters.genre);

    return (_filters.source == ComicFilterOption.all ||
            comic.source == _filters.source) &&
        (_filters.type == ComicFilterOption.all ||
            comic.type == _filters.type) &&
        (_filters.status == ComicFilterOption.all ||
            comic.status == _filters.status) &&
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
    final cachedGenreOptions = _cachedGenreOptions();

    final result = await showComicFilterSortSheet(
      context: context,
      initialState: _filters,
      title: 'Filter dan Sorting',
      resetSort: ComicSortOption.relevance,
      genreOptions: cachedGenreOptions.isEmpty ? null : cachedGenreOptions,
      genreOptionsRefreshFuture: _refreshGenreOptions(),
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
    setState(() {
      _filters = result.normalized();
      _isFilteringResults = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) {
      setState(() => _isFilteringResults = false);
    }
  }

  List<String> _cachedGenreOptions() {
    final genres = ref.read(catalogRepositoryProvider).getCachedGenres();
    return _genreNames(genres);
  }

  Future<List<String>> _refreshGenreOptions() async {
    try {
      final genres = await ref.read(catalogRepositoryProvider).refreshGenres();
      ref.invalidate(genresProvider);
      return _genreNames(genres);
    } catch (error, stackTrace) {
      if (mounted) {
        showAppErrorSnackBar(
          context,
          error: error,
          stackTrace: stackTrace,
          logContext: 'Refresh search genres failed',
          fallbackMessage: 'Daftar genre belum dapat dimuat.',
        );
      }
      return const [];
    }
  }

  List<String> _genreNames(List<Genre> genres) {
    return genres
        .map((genre) => genre.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
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

class _SearchStickyControls extends StatelessWidget {
  const _SearchStickyControls({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: child,
    );
  }
}

class _SearchTopFade extends StatelessWidget {
  const _SearchTopFade();

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.58, 1.0],
          colors: [
            background,
            background.withValues(alpha: 0.9),
            background.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
    required this.filterActive,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.28 : 0.06,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Judul, author, atau genre',
                prefixIcon: const Icon(TonztoonIcons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: onClear,
                        icon: const Icon(TonztoonIcons.close),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 18,
                ),
              ),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: filterActive
              ? colorScheme.primary.withValues(alpha: 0.16)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onFilter,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: filterActive
                      ? colorScheme.primary.withValues(alpha: 0.42)
                      : colorScheme.outlineVariant,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.05,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                TonztoonIcons.slidersHorizontal,
                color: filterActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchCenteredState extends StatelessWidget {
  const _SearchCenteredState({
    super.key,
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(child: child),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Icon(icon, size: 38, color: colorScheme.secondary),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.38,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Transform.translate(
        offset: const Offset(0, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchLoadingPlaceholder extends StatelessWidget {
  const _SearchLoadingPlaceholder({super.key, required this.gridView});

  final bool gridView;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SearchLoadingHeader(),
        const SizedBox(height: 12),
        gridView ? const _SearchGridShimmer() : const _SearchListShimmer(),
      ],
    );
  }
}

class _SearchLoadingHeader extends StatelessWidget {
  const _SearchLoadingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SectionTitle(
            icon: TonztoonIcons.autoAwesome,
            title: 'Mencari...',
          ),
        ),
      ],
    );
  }
}

class _SearchFilterProcessingStrip extends StatelessWidget {
  const _SearchFilterProcessingStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Memproses hasil filter...',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchListShimmer extends StatelessWidget {
  const _SearchListShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < 4; index++) ...[
          const _SearchResultTileShimmer(),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SearchGridShimmer extends StatelessWidget {
  const _SearchGridShimmer();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
      itemBuilder: (context, index) => const _SearchGridCardShimmer(),
    );
  }
}

class _SearchResultTileShimmer extends StatelessWidget {
  const _SearchResultTileShimmer();

  @override
  Widget build(BuildContext context) {
    return const ComicListCardShimmer();
  }
}

class _SearchGridCardShimmer extends StatelessWidget {
  const _SearchGridCardShimmer();

  @override
  Widget build(BuildContext context) {
    return _SearchShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(child: _ShimmerBlock(width: double.infinity)),
          SizedBox(height: 9),
          _ShimmerBlock(width: double.infinity, height: 14),
          SizedBox(height: 7),
          _ShimmerBlock(width: 112, height: 14),
        ],
      ),
    );
  }
}

class _SearchShimmer extends StatelessWidget {
  const _SearchShimmer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final highlightColor = colorScheme.surfaceContainerLow;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: child,
    );
  }
}

class _ShimmerBlock extends StatelessWidget {
  const _ShimmerBlock({required this.width, this.height});

  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.query, required this.resultCount});

  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final text = query.trim().isEmpty ? 'Rekomendasi' : 'Hasil untuk "$query"';

    return Row(
      children: [
        Expanded(
          child: _SectionTitle(icon: TonztoonIcons.autoAwesome, title: text),
        ),
        Text(
          '$resultCount komik',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.comics});

  final List<_SearchComicUi> comics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final comic in comics) ...[
          _SearchResultTile(comic: comic),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.comics});

  final List<_SearchComicUi> comics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
      itemBuilder: (context, index) {
        final comic = comics[index];
        return ComicCard(
          comic: comic.summary,
          source: comic.source,
          rating: comic.rating,
          width: double.infinity,
          onTap: () => _openComicDetail(context, comic.summary),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.comic});

  final _SearchComicUi comic;

  @override
  Widget build(BuildContext context) {
    return ComicListCard(
      comic: comic.summary,
      source: comic.source,
      rating: comic.ratingValue,
      onTap: () => _openComicDetail(context, comic.summary),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

class _SearchComicUi {
  const _SearchComicUi({
    required this.summary,
    required this.source,
    required this.type,
    required this.rating,
    required this.status,
    required this.genre,
    required this.genres,
    required this.chapter,
    required this.description,
    required this.updateRank,
    required this.popularityRank,
  });

  factory _SearchComicUi.fromSummary(ComicSummary summary) {
    final source = comicSourceDisplayName(summary.sourceName);
    final chapterNumber = summary.latestChapterNumber;
    final type = comicTypeFilterLabel(summary.type, fallback: 'Komik');
    final genres = summary.genres
        .map((genre) => genre.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final ratingValue = summary.rating ?? 0;
    final totalView = summary.totalView ?? 0;
    return _SearchComicUi(
      summary: summary,
      source: source,
      type: type,
      rating: ratingValue.toStringAsFixed(1),
      status: comicStatusFilterLabel(summary.status),
      genre: genres.isEmpty ? 'Genre' : genres.first,
      genres: genres,
      chapter: chapterNumber == null
          ? 'Chapter terbaru'
          : 'Chapter ${formatChapterNumber(chapterNumber)}',
      description:
          'Komik dari $source dengan pembaruan chapter dan informasi katalog terbaru.',
      updateRank: chapterNumber?.round() ?? totalView,
      popularityRank: totalView > 0 ? totalView : (ratingValue * 1000).round(),
    );
  }

  final ComicSummary summary;
  final String source;
  final String type;
  final String rating;
  final String status;
  final String genre;
  final List<String> genres;
  final String chapter;
  final String description;
  final int updateRank;
  final int popularityRank;

  double get ratingValue => double.tryParse(rating) ?? 0;
}
