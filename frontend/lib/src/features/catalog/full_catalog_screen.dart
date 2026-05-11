import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../models/source_info.dart';
import '../../repositories/providers.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/comic_filter_sort_sheet.dart';
import '../../widgets/app_loading_placeholder.dart';

class FullCatalogScreen extends ConsumerStatefulWidget {
  const FullCatalogScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<FullCatalogScreen> createState() => _FullCatalogScreenState();
}

class _FullCatalogScreenState extends ConsumerState<FullCatalogScreen> {
  static const _pageSize = 40;

  late final ScrollController _scrollController;

  ComicFilterSortState _filters = const ComicFilterSortState(
    sort: ComicSortOption.relevance,
  );
  List<ComicSummary> _comics = const [];
  SourceInfo? _activeSource;
  Object? _error;
  int _page = 0;
  int _total = 0;
  int _totalPages = 1;
  int _requestSerial = 0;
  bool _isGrid = true;
  bool _isFirstPageLoading = true;
  bool _isLoadingMore = false;
  bool _hasLoadedCatalog = false;

  bool get _hasNextPage => _page < _totalPages;

  String? get _typeQuery => _filters.type == ComicFilterOption.all
      ? null
      : _filters.type.toLowerCase();

  String? get _statusQuery => _filters.status == ComicFilterOption.all
      ? null
      : _filters.status.toLowerCase();

  String? get _genreQuery => _filters.genre == ComicFilterOption.all
      ? null
      : _filters.genre.toLowerCase();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _catalogPool(_comics);
    final comics = _visibleEntries(entries);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Katalog Komik', style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: widget.showBackButton
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  tooltip: 'Kembali',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(TonztoonIcons.arrowBack),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: _isGrid ? 'Tampilan daftar' : 'Tampilan grid',
            onPressed: () => setState(() => _isGrid = !_isGrid),
            icon: Icon(_isGrid ? TonztoonIcons.rows : TonztoonIcons.columns),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 6),
            child: IconButton(
              tooltip: 'Filter dan Sorting katalog',
              onPressed: _showFilterSheet,
              icon: Badge(
                isLabelVisible: _filters.hasActiveFilters,
                smallSize: 8,
                child: const Icon(TonztoonIcons.slidersHorizontal),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _isFirstPageLoading && !_hasLoadedCatalog
                ? const _CatalogLoadingState(key: ValueKey('catalog-loading'))
                : _error != null && !_hasLoadedCatalog
                ? _CatalogErrorState(
                    key: const ValueKey('catalog-error'),
                    error: _error!,
                    onRetry: _loadFirstPage,
                  )
                : RefreshIndicator(
                    key: const ValueKey('catalog-content'),
                    onRefresh: _loadFirstPage,
                    child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate.fixed([
                          _CatalogHero(
                            visibleCount: comics.length,
                            totalCount: _total,
                            sourceLabel: _activeSource?.label ?? 'Semua Sumber',
                          ),
                          const SizedBox(height: 16),
                          ComicActiveFilterStrip(
                            filters: _filters,
                            onClear: _clearFilters,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${comics.length} komik dimuat',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              _SortPill(label: _filters.sort),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ]),
                      ),
                    ),
                    if (comics.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyCatalogState(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: _isGrid
                            ? _CatalogGrid(
                                entries: comics,
                                onTap: _openComicDetail,
                              )
                            : _CatalogList(
                                entries: comics,
                                onTap: _openComicDetail,
                              ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        widget.showBackButton ? 28 : 132,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _LoadMoreFooter(
                          loading: _isLoadingMore,
                          hasNextPage: _hasNextPage,
                          loadedCount: _comics.length,
                          totalCount: _total,
                        ),
                      ),
                    ),
                  ],
                    ),
                  ),
          ),
          _FilterProcessingIndicator(
            visible: _isFirstPageLoading && _hasLoadedCatalog,
          ),
        ],
      ),
    );
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    final serial = ++_requestSerial;
    final hadCatalog = _hasLoadedCatalog;
    setState(() {
      _isFirstPageLoading = true;
      _isLoadingMore = false;
      _error = null;
      if (!hadCatalog) {
        _page = 0;
        _total = 0;
        _totalPages = 1;
        _comics = const [];
      }
    });

    try {
      final repository = ref.read(catalogRepositoryProvider);
      final sources = await repository.getSources();
      if (sources.isEmpty) {
        throw Exception('No sources available.');
      }

      final source = _sourceFromFilter(sources);
      final page = await repository.getSourceComics(
        sourceName: source?.id,
        page: 1,
        pageSize: _pageSize,
        type: _typeQuery,
        status: _statusQuery,
        genre: _genreQuery,
        sort: _filters.sort,
      );

      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _activeSource = source;
        _comics = page.items;
        _page = page.page;
        _total = page.total;
        _totalPages = page.totalPages < 1 ? 1 : page.totalPages;
        _isFirstPageLoading = false;
        _hasLoadedCatalog = true;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _error = error;
        _isFirstPageLoading = false;
      });
      if (hadCatalog) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Gagal memuat ulang katalog: $error')),
          );
      }
    }
  }

  Future<void> _loadNextPage() async {
    final source = _activeSource;
    if (_isFirstPageLoading || _isLoadingMore || !_hasNextPage) {
      return;
    }

    final serial = _requestSerial;
    setState(() => _isLoadingMore = true);

    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .getSourceComics(
            sourceName: source?.id,
            page: _page + 1,
            pageSize: _pageSize,
            type: _typeQuery,
            status: _statusQuery,
            genre: _genreQuery,
            sort: _filters.sort,
          );

      if (!mounted || serial != _requestSerial) return;
      final existingKeys = _comics
          .map((comic) => '${comic.sourceName}|${comic.slug}|${comic.title}')
          .toSet();
      final nextComics = [..._comics];
      for (final comic in page.items) {
        final key = '${comic.sourceName}|${comic.slug}|${comic.title}';
        if (existingKeys.add(key)) {
          nextComics.add(comic);
        }
      }

      setState(() {
        _comics = nextComics;
        _page = page.page;
        _total = page.total;
        _totalPages = page.totalPages < 1 ? 1 : page.totalPages;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Gagal memuat halaman berikutnya: $error')),
        );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 640) {
      _loadNextPage();
    }
  }

  List<_CatalogEntry> _catalogPool(List<ComicSummary> comics) {
    return comics
        .asMap()
        .entries
        .map((entry) => _CatalogEntry.fromSummary(entry.value, entry.key))
        .toList();
  }

  List<_CatalogEntry> _visibleEntries(List<_CatalogEntry> entries) {
    return entries;
  }

  void _clearFilters() {
    setState(
      () => _filters = const ComicFilterSortState(
        sort: ComicSortOption.relevance,
      ),
    );
    _loadFirstPage();
  }

  Future<void> _showFilterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final genreOptions = await _loadGenreOptions();
    if (!mounted) return;

    final result = await showComicFilterSortSheet(
      context: context,
      initialState: _filters,
      title: 'Filter Katalog',
      resetSort: ComicSortOption.relevance,
      genreOptions: genreOptions,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
    );

    if (result == null) return;
    final filters = result.normalized();
    setState(() => _filters = filters);
    await _loadFirstPage();
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

  void _openComicDetail(_CatalogEntry entry) {
    context.push(
      '/comic/${Uri.encodeComponent(comicRouteSource(entry.comic))}/${Uri.encodeComponent(comicRouteSlug(entry.comic))}',
      extra: entry.comic,
    );
  }

  SourceInfo? _sourceFromFilter(
    List<SourceInfo> sources, {
    ComicFilterSortState? filters,
  }) {
    final selectedSource = (filters ?? _filters).source;
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

class _CatalogHero extends StatelessWidget {
  const _CatalogHero({
    required this.visibleCount,
    required this.totalCount,
    required this.sourceLabel,
  });

  final int visibleCount;
  final int totalCount;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF172126), Color(0xFF251B22)]
              : const [Color(0xFFE7FFFB), Color(0xFFFFF1E8)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.78),
                shape: BoxShape.circle,
              ),
              child: Icon(
                TonztoonIcons.bookOpen,
                color: colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Full Katalog', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 5),
                  Text(
                    'Semua judul dari $sourceLabel yang tersimpan di katalog.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                child: Text(
                  '$visibleCount/$totalCount',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogLoadingState extends StatelessWidget {
  const _CatalogLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CatalogLoadingPlaceholder();
  }
}

class _FilterProcessingIndicator extends StatelessWidget {
  const _FilterProcessingIndicator({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.96),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  minHeight: 3,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Memproses hasil filter...',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogLoadingPlaceholder extends StatelessWidget {
  const _CatalogLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed(const [
              AppShimmer(
                child: AppShimmerBlock(
                  width: double.infinity,
                  height: 110,
                  borderRadius: 18,
                ),
              ),
              SizedBox(height: 16),
              AppShimmer(
                child: Row(
                  children: [
                    AppShimmerBlock(width: 128, height: 20),
                    Spacer(),
                    AppShimmerBlock(width: 86, height: 28, borderRadius: 16),
                  ],
                ),
              ),
              SizedBox(height: 12),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.51,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => const _CatalogCardShimmer(),
              childCount: 6,
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogCardShimmer extends StatelessWidget {
  const _CatalogCardShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppShimmerBlock(width: double.infinity, borderRadius: 12),
          ),
          SizedBox(height: 9),
          AppShimmerBlock(width: double.infinity, height: 14),
          SizedBox(height: 7),
          AppShimmerBlock(width: 112, height: 14),
        ],
      ),
    );
  }
}

class _CatalogErrorState extends StatelessWidget {
  const _CatalogErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
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

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.hasNextPage,
    required this.loadedCount,
    required this.totalCount,
  });

  final bool loading;
  final bool hasNextPage;
  final int loadedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: colorScheme.secondary,
            ),
          ),
        ),
      );
    }

    if (!hasNextPage && totalCount > 0 && loadedCount >= totalCount) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Semua komik sudah dimuat',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return const SizedBox(height: 20);
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TonztoonIcons.slidersHorizontal,
              size: 15,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.entries, required this.onTap});

  final List<_CatalogEntry> entries;
  final ValueChanged<_CatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      key: const ValueKey('catalog-grid'),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.51,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = entries[index];
        return ComicCard(
          comic: entry.comic,
          source: entry.source,
          rating: entry.rating.toStringAsFixed(1),
          width: double.infinity,
          onTap: () => onTap(entry),
        );
      }, childCount: entries.length),
    );
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.entries, required this.onTap});

  final List<_CatalogEntry> entries;
  final ValueChanged<_CatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final childCount = entries.isEmpty ? 0 : entries.length * 2 - 1;

    return SliverList(
      key: const ValueKey('catalog-list'),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) return const SizedBox(height: 12);
        final entry = entries[index ~/ 2];
        return _CatalogListTile(entry: entry, onTap: () => onTap(entry));
      }, childCount: childCount),
    );
  }
}

class _CatalogListTile extends StatelessWidget {
  const _CatalogListTile({required this.entry, required this.onTap});

  final _CatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final comic = entry.comic;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ComicCover(
                  imageUrl: comic.coverImageUrl,
                  width: 74,
                  height: 106,
                  borderRadius: 10,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.source} • ${comicTypeFlag(comic.type)} ${entry.type}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.secondary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _RatingText(rating: entry.rating),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ComicGenreBadge(genre: entry.genre, compact: true),
                          ComicStatusBadge(status: entry.status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          ComicMetaBadge(
                            label:
                                'Ch ${formatChapterNumber(comic.latestChapterNumber ?? 0)}',
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(TonztoonIcons.chevronRight, color: colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalogState extends StatelessWidget {
  const _EmptyCatalogState();

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
              child: Icon(
                TonztoonIcons.search,
                size: 38,
                color: colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Tidak ada komik',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Coba ubah kata kunci atau filter katalog.',
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

class _RatingText extends StatelessWidget {
  const _RatingText({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(TonztoonIcons.starFilled, size: 15, color: Colors.amber),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CatalogEntry {
  const _CatalogEntry({
    required this.comic,
    required this.source,
    required this.type,
    required this.status,
    required this.genre,
    required this.rating,
    required this.updateRank,
    required this.popularityRank,
  });

  factory _CatalogEntry.fromSummary(ComicSummary comic, int index) {
    final source = comicSourceDisplayName(comic.sourceName);
    final type = comicTypeFilterLabel(comic.type);
    final status = comicStatusFilterLabel(comic.status);
    final genre = comic.genres.isEmpty ? type : comic.genres.first.name;
    final rating = comic.rating ?? 0;
    final totalView = comic.totalView ?? 0;
    return _CatalogEntry(
      comic: comic,
      source: source,
      type: type,
      status: status,
      genre: genre,
      rating: rating,
      updateRank: comic.latestChapterNumber?.round() ?? (1000 - index),
      popularityRank: totalView > 0 ? totalView : (rating * 1000).round(),
    );
  }

  final ComicSummary comic;
  final String source;
  final String type;
  final String status;
  final String genre;
  final double rating;
  final int updateRank;
  final int popularityRank;
}
