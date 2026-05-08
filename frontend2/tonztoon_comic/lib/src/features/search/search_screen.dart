import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
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

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  ComicFilterSortState _filters = const ComicFilterSortState(
    sort: ComicSortOption.relevance,
  );
  bool _gridView = false;
  bool _filterButtonActive = false;
  bool _isSearching = false;

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
        children: [
          _SearchBox(
            controller: _searchController,
            onChanged: _handleSearchChanged,
            onClear: _clearSearch,
            onFilter: _showFilterSheet,
            filterActive: _filterButtonActive || _filters.hasActiveFilters,
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: isLoading
                ? _SearchLoadingPlaceholder(
                    key: ValueKey('search-loading-$_gridView'),
                    gridView: _gridView,
                  )
                : query.isEmpty
                ? const _SearchEmptyState(
                    key: ValueKey('search-empty-initial'),
                    icon: TonztoonIcons.search,
                    title: 'Cari komik',
                    message:
                        'Masukkan judul, author, genre, atau sumber untuk mulai mencari.',
                  )
                : AppAsyncView<List<ComicSummary>>(
                    key: ValueKey('search-async-$query-$_gridView'),
                    value: searchAsync,
                    onRetry: () => unawaited(_retrySearch()),
                    loadingBuilder: (context) => _SearchLoadingPlaceholder(
                      key: ValueKey('search-async-loading-$_gridView'),
                      gridView: _gridView,
                    ),
                    builder: (items) {
                      final results = _visibleResults(_searchPool(items));
                      return results.isEmpty
                          ? _SearchEmptyState(
                              key: const ValueKey('search-empty-results'),
                              icon: TonztoonIcons.search,
                              title: 'Tidak ada hasil',
                              message:
                                  'Tidak ada komik yang cocok untuk "$query".',
                            )
                          : Column(
                              key: ValueKey('search-results-$_gridView-$query'),
                              children: [
                                _ResultHeader(
                                  query: query,
                                  resultCount: results.length,
                                ),
                                const SizedBox(height: 12),
                                _gridView
                                    ? _ResultGrid(comics: results)
                                    : _ResultList(comics: results),
                              ],
                            );
                    },
                  ),
          ),
        ],
      ),
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Pencarian gagal: $error')));
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
    final genreOptions = await _loadGenreOptions();
    if (!mounted) return;

    final result = await showComicFilterSortSheet(
      context: context,
      initialState: _filters,
      title: 'Filter dan Sorting',
      resetSort: ComicSortOption.relevance,
      genreOptions: genreOptions,
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
    setState(() => _filters = result.normalized());
  }

  Future<List<String>> _loadGenreOptions() async {
    try {
      final genres = await ref.read(genresProvider.future);
      return genres
          .map((genre) => genre.name.trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
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

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    super.key,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
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
        childAspectRatio: 0.51,
      ),
      itemBuilder: (context, index) => const _SearchGridCardShimmer(),
    );
  }
}

class _SearchResultTileShimmer extends StatelessWidget {
  const _SearchResultTileShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _SearchShimmer(
          child: Row(
            children: [
              const _ShimmerBlock(width: 78, height: 110, borderRadius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _ShimmerBlock(width: double.infinity, height: 18),
                    SizedBox(height: 8),
                    _ShimmerBlock(width: 168, height: 14),
                    SizedBox(height: 14),
                    _ShimmerBlock(width: double.infinity, height: 12),
                    SizedBox(height: 7),
                    _ShimmerBlock(width: 210, height: 12),
                    SizedBox(height: 14),
                    _ShimmerBlock(width: 96, height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  const _ShimmerBlock({
    required this.width,
    this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
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
        childAspectRatio: 0.51,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openComicDetail(context, comic.summary),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ComicCover(
                imageUrl: comic.summary.coverImageUrl,
                width: 78,
                height: 110,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.summary.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${comic.source} • ${comicTypeFlag(comic.summary.type)} ${comic.type}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _InlineRating(label: comic.rating),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      comic.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      comic.chapter,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.secondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(TonztoonIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineRating extends StatelessWidget {
  const _InlineRating({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.starFilled, size: 14, color: Colors.amber),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
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
