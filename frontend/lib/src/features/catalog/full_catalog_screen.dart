import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../helpers/genre_options.dart';
import '../../helpers/navigation_helpers.dart';
import '../../models/comic.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_filter_sort_sheet.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/load_more_footer.dart';
import '../../widgets/column_grid.dart';
import '../../widgets/scroll_to_top_fab.dart';
import 'controller/catalog_controller.dart';

part 'models/catalog_view_models.dart';
part 'widgets/catalog_hero.dart';
part 'widgets/catalog_lists.dart';
part 'widgets/catalog_states.dart';

class FullCatalogScreen extends ConsumerStatefulWidget {
  const FullCatalogScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<FullCatalogScreen> createState() => _FullCatalogScreenState();
}

class _FullCatalogScreenState extends ConsumerState<FullCatalogScreen> {
  late final ScrollController _scrollController;
  bool _isGrid = true;
  bool _showHeaderShadow = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    unawaited(warmGenreOptionCache(ref));
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
    final filters = ref.watch(catalogFilterProvider);
    final catalogAsync = ref.watch(catalogControllerProvider);
    // `.value` (not `asData?.value`) so the previously loaded catalog stays
    // available while a filter change re-runs `build()` — during that reload the
    // state is AsyncLoading, but Riverpod retains the prior value. This keeps the
    // old list on screen instead of flashing the full shimmer.
    final catalog = catalogAsync.value;
    final comics = _catalogPool(catalog?.comics ?? const []);

    // A first-page reload triggered by a filter change keeps the previous data
    // available, so only a top linear indicator is needed instead of clearing it.
    final isReloadingWithData = catalogAsync.isLoading && catalog != null;

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
                isLabelVisible: filters.hasActiveFilters,
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
            child: catalogAsync.isLoading && catalog == null
                ? const _CatalogLoadingState(key: ValueKey('catalog-loading'))
                : catalogAsync.hasError && catalog == null
                ? _CatalogErrorState(
                    key: const ValueKey('catalog-error'),
                    error: catalogAsync.error!,
                    onRetry: () => ref.invalidate(catalogControllerProvider),
                  )
                : RefreshIndicator(
                    key: const ValueKey('catalog-content'),
                    onRefresh: _refreshCatalog,
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
                                totalCount: catalog?.total ?? 0,
                                sourceLabel:
                                    catalog?.activeSource?.label ??
                                    'Semua Sumber',
                              ),
                              const SizedBox(height: 16),
                              ComicActiveFilterStrip(
                                filters: filters,
                                onClear: _clearFilters,
                              ),
                              if (filters.hasActiveFilters)
                                const SizedBox(height: 10),
                            ]),
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _CatalogListHeaderDelegate(
                            showShadow: _showHeaderShadow,
                            child: _CatalogListHeader(
                              loadedCount: comics.length,
                              sortLabel: filters.sort,
                            ),
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
                        if (catalog?.isLoadingMore ?? false)
                          const SliverPadding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                            sliver: SliverToBoxAdapter(
                              child: _CatalogLoadingMore(),
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
                            child: LoadMoreFooter(
                              hasNextPage: catalog?.hasNextPage ?? false,
                              loadedCount: catalog?.comics.length ?? 0,
                              completeLabel: 'Semua komik sudah dimuat',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          _CatalogReloadingIndicator(visible: isReloadingWithData),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: widget.showBackButton ? 0 : 120),
        child: ScrollToTopFab(controller: _scrollController),
      ),
    );
  }

  Future<void> _refreshCatalog() async {
    try {
      await ref.read(catalogControllerProvider.notifier).refresh();
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Refresh catalog failed',
        fallbackMessage: 'Katalog belum dapat dimuat ulang. Silakan coba lagi.',
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 640) {
      _loadNextPage();
    }

    final showHeaderShadow = _scrollController.offset > 120;
    if (showHeaderShadow != _showHeaderShadow) {
      setState(() {
        _showHeaderShadow = showHeaderShadow;
      });
    }
  }

  Future<void> _loadNextPage() async {
    try {
      await ref.read(catalogControllerProvider.notifier).loadNextPage();
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Load next catalog page failed',
        fallbackMessage: 'Halaman berikutnya belum dapat dimuat.',
      );
    }
  }

  List<_CatalogEntry> _catalogPool(List<ComicSummary> comics) {
    return comics
        .asMap()
        .entries
        .map((entry) => _CatalogEntry.fromSummary(entry.value, entry.key))
        .toList();
  }

  void _clearFilters() {
    ref.read(catalogFilterProvider.notifier).clear();
  }

  Future<void> _showFilterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final cachedGenreOptions = cachedGenreOptionNames(ref);

    final result = await showComicFilterSortSheet(
      context: context,
      initialState: ref.read(catalogFilterProvider),
      resetSort: ComicSortOption.relevance,
      genreOptions: cachedGenreOptions.isEmpty ? null : cachedGenreOptions,
      genreOptionsFuture: cachedGenreOptions.isEmpty
          ? warmGenreOptionCache(ref)
          : null,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
    );

    if (result == null) return;
    ref.read(catalogFilterProvider.notifier).apply(result);
  }

  void _openComicDetail(_CatalogEntry entry) =>
      openComicDetail(context, entry.comic);
}
