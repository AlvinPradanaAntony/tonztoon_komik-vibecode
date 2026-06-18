import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../helpers/app_icons.dart';
import '../../../helpers/app_snackbar.dart';
import '../../../helpers/navigation_helpers.dart';
import '../../../models/comic.dart';
import '../../../repositories/providers.dart';
import '../../../widgets/app_edge_fade.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_error_state.dart';
import '../../../widgets/app_loading_placeholder.dart';
import '../../../widgets/comic_card.dart';
import '../../../widgets/comic_filter_sort_sheet.dart';
import '../../../widgets/load_more_footer.dart';
import '../../../widgets/column_grid.dart';

class ComicSectionPayload {
  const ComicSectionPayload({
    required this.title,
    required this.subtitle,
    this.sourceName,
    required this.comics,
    required this.initialSort,
  });

  final String title;
  final String subtitle;
  final String? sourceName;
  final List<ComicSummary> comics;
  final String initialSort;
}

class ComicSectionScreen extends ConsumerStatefulWidget {
  const ComicSectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.sourceName,
    required this.comics,
    required this.initialSort,
  });

  final String title;
  final String subtitle;
  final String? sourceName;
  final List<ComicSummary> comics;
  final String initialSort;

  @override
  ConsumerState<ComicSectionScreen> createState() => _ComicSectionScreenState();
}

class _ComicSectionScreenState extends ConsumerState<ComicSectionScreen> {
  static const _pageSize = 20;

  late final ScrollController _scrollController;

  List<ComicSummary> _comics = const [];
  String? _sourceName;
  Object? _error;
  int _page = 0;
  int _requestSerial = 0;
  bool _hasNextPage = true;
  bool _hasLoadedSection = false;
  bool _isFirstPageLoading = true;
  bool _isLoadingMore = false;
  bool _isGrid = true;
  bool _isLatestStatsLoading = false;
  bool _hasLoadedComicSectionPage = false;
  LatestComicStats? _latestStats;

  bool get _isPopularSection =>
      ComicSortOption.normalize(widget.initialSort) == ComicSortOption.popular;

  @override
  void initState() {
    super.initState();
    _comics = widget.comics;
    _sourceName = _normalizedSource(widget.sourceName);
    _hasLoadedComicSectionPage = false;
    _loadCachedComicSection();
    _loadCachedLatestStats();
    _page = _comics.isEmpty ? 0 : 1;
    _hasNextPage = _comics.length >= _pageSize;
    _hasLoadedSection = _comics.isNotEmpty;
    _isFirstPageLoading = _comics.isEmpty;
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void didUpdateWidget(covariant ComicSectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceName == widget.sourceName &&
        oldWidget.initialSort == widget.initialSort) {
      return;
    }
    _sourceName = _normalizedSource(widget.sourceName);
    _comics = widget.comics;
    _hasLoadedComicSectionPage = false;
    _loadCachedComicSection();
    _latestStats = null;
    _loadCachedLatestStats();
    _loadFirstPage();
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
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(TonztoonIcons.arrowBack),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _isGrid ? 'Tampilan daftar' : 'Tampilan grid',
            onPressed: () => setState(() => _isGrid = !_isGrid),
            icon: Icon(_isGrid ? TonztoonIcons.rows : TonztoonIcons.columns),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _isFirstPageLoading && !_hasLoadedSection
                ? const _SectionLoadingState(key: ValueKey('section-loading'))
                : _error != null && !_hasLoadedSection
                ? _SectionErrorState(
                    key: const ValueKey('section-error'),
                    error: _error!,
                    onRetry: _loadFirstPage,
                  )
                : RefreshIndicator(
                    key: const ValueKey('section-content'),
                    onRefresh: _loadFirstPage,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate.fixed([
                              _SectionHero(
                                title: _isPopularSection
                                    ? 'Sedang Hangat di Kalangan Pembaca'
                                    : widget.title,
                                subtitle: _isPopularSection
                                    ? 'Temukan komik yang sedang ramai dibaca dan menjadi favorit pembaca saat ini.'
                                    : widget.subtitle,
                                countLabel: _isPopularSection
                                    ? null
                                    : '${_latestStats?.updatedComicCount ?? '-'}',
                                countCaption: _isPopularSection
                                    ? null
                                    : 'update / ${_latestStats?.periodDays ?? 7} hari',
                                countLoading:
                                    !_isPopularSection && _latestStats == null,
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  if (_isFirstPageLoading &&
                                      !_hasLoadedComicSectionPage)
                                    const AppShimmer(
                                      child: AppShimmerBlock(
                                        width: 112,
                                        height: 16,
                                        borderRadius: 8,
                                      ),
                                    )
                                  else
                                    Text(
                                      '${_comics.length} komik dimuat',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.secondary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ]),
                          ),
                        ),
                        if (_comics.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptySectionState(),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: _isGrid
                                ? _SectionGrid(
                                    comics: _comics,
                                    showNewBadges: !_isPopularSection,
                                    onTap: _openComicDetail,
                                  )
                                : _SectionList(
                                    comics: _comics,
                                    showNewBadges: !_isPopularSection,
                                    onTap: _openComicDetail,
                                  ),
                          ),
                        if (_isLoadingMore)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            sliver: _isGrid
                                ? const _SectionLoadingMoreGrid()
                                : const _SectionLoadingMoreList(),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
                          sliver: SliverToBoxAdapter(
                            child: LoadMoreFooter(
                              hasNextPage: _hasNextPage,
                              loadedCount: _comics.length,
                              completeLabel: 'Semua komik sudah dimuat',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (_isFirstPageLoading && _hasLoadedSection)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          AppEdgeFade(background: theme.scaffoldBackgroundColor),
        ],
      ),
    );
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    final serial = ++_requestSerial;
    final hadSection = _hasLoadedSection;
    final previousComics = _comics;
    setState(() {
      _isFirstPageLoading = true;
      _isLoadingMore = false;
      _error = null;
      if (!hadSection) {
        _page = 0;
        _hasNextPage = true;
        _comics = const [];
      }
    });

    try {
      final sourceName = await _resolveSourceName();
      _loadCachedLatestStats(sourceName);
      final comics = await _loadPage(sourceName, 1);

      if (!mounted || serial != _requestSerial) return;
      final nextComics = hadSection ? _mergeRefreshedFirstPage(comics) : comics;
      setState(() {
        _sourceName = sourceName;
        _comics = nextComics;
        _page = 1;
        _hasNextPage = comics.length >= _pageSize;
        _isFirstPageLoading = false;
        _hasLoadedSection = true;
        _hasLoadedComicSectionPage = true;
      });
      _cacheComicSection(sourceName);
      if (!_isPopularSection) {
        final latestChanged = !_sameLatestPage(previousComics, comics);
        if (_latestStats == null ||
            latestChanged ||
            ref
                .read(catalogRepositoryProvider)
                .shouldRefreshLatestStats(sourceName)) {
          unawaited(_refreshLatestStats(sourceName, serial));
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    } catch (error, stackTrace) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _error = error;
        _isFirstPageLoading = false;
      });
      if (hadSection) {
        showAppErrorSnackBar(
          context,
          error: error,
          stackTrace: stackTrace,
          logContext: 'Refresh comic section failed',
          fallbackMessage:
              'Section komik belum dapat dimuat ulang. Silakan coba lagi.',
        );
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isFirstPageLoading || _isLoadingMore || !_hasNextPage) return;

    final serial = _requestSerial;
    final sourceName = _sourceName;
    if (sourceName == null || sourceName.isEmpty) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final comics = await _loadPage(sourceName, nextPage);

      if (!mounted || serial != _requestSerial) return;
      final existingKeys = _comics
          .map((comic) => '${comic.sourceName}|${comic.slug}|${comic.title}')
          .toSet();
      final nextComics = [..._comics];
      var addedCount = 0;
      for (final comic in comics) {
        final key = '${comic.sourceName}|${comic.slug}|${comic.title}';
        if (existingKeys.add(key)) {
          nextComics.add(comic);
          addedCount++;
        }
      }

      setState(() {
        _comics = nextComics;
        _page = nextPage;
        _hasNextPage = comics.length >= _pageSize && addedCount > 0;
        _isLoadingMore = false;
      });
      _cacheComicSection(sourceName);
    } catch (error, stackTrace) {
      if (!mounted || serial != _requestSerial) return;
      setState(() => _isLoadingMore = false);
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Load next comic section page failed',
        fallbackMessage: 'Halaman berikutnya belum dapat dimuat.',
      );
    }
  }

  List<ComicSummary> _mergeRefreshedFirstPage(
    List<ComicSummary> refreshedComics,
  ) {
    final refreshedKeys = refreshedComics
        .map((comic) => '${comic.sourceName}|${comic.slug}|${comic.title}')
        .toSet();
    return [
      ...refreshedComics,
      for (final comic in _comics)
        if (!refreshedKeys.contains(
          '${comic.sourceName}|${comic.slug}|${comic.title}',
        ))
          comic,
    ];
  }

  Future<List<ComicSummary>> _loadPage(String sourceName, int page) {
    final repository = ref.read(catalogRepositoryProvider);
    if (_isPopularSection) {
      return repository.getPopular(sourceName, page: page, pageSize: _pageSize);
    }
    return repository.getLatest(sourceName, page: page, pageSize: _pageSize);
  }

  Future<void> _refreshLatestStats(String sourceName, int serial) async {
    if (_isLatestStatsLoading) return;
    setState(() => _isLatestStatsLoading = true);
    try {
      final stats = await ref
          .read(catalogRepositoryProvider)
          .getLatestStats(sourceName);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _latestStats = stats;
        _isLatestStatsLoading = false;
      });
    } catch (_) {
      // Daftar rilis tetap berguna walau statistik tambahan belum tersedia.
      if (mounted && serial == _requestSerial) {
        setState(() => _isLatestStatsLoading = false);
      }
    }
  }

  void _loadCachedLatestStats([String? sourceName]) {
    if (_isPopularSection) return;
    final source = _normalizedSource(sourceName ?? _sourceName);
    if (source == null) return;
    final cached = ref
        .read(catalogRepositoryProvider)
        .getCachedLatestStats(source);
    if (cached == null || cached == _latestStats) return;
    _latestStats = cached;
  }

  void _loadCachedComicSection([String? sourceName]) {
    final source = _normalizedSource(sourceName ?? _sourceName);
    if (source == null) return;
    final cached = ref
        .read(catalogRepositoryProvider)
        .getCachedComicSection(source, popular: _isPopularSection);
    if (ref
        .read(catalogRepositoryProvider)
        .hasCachedComicSection(source, popular: _isPopularSection)) {
      _hasLoadedComicSectionPage = true;
    }
    if (cached.length > _comics.length) {
      _comics = cached;
    }
  }

  void _cacheComicSection(String sourceName) {
    ref
        .read(catalogRepositoryProvider)
        .cacheComicSection(
          sourceName,
          popular: _isPopularSection,
          comics: _comics,
        );
  }

  bool _sameLatestPage(List<ComicSummary> previous, List<ComicSummary> next) {
    if (previous.isEmpty || next.isEmpty) {
      return previous.isEmpty && next.isEmpty;
    }
    final comparableLength = previous.length < next.length
        ? previous.length
        : next.length;
    for (var index = 0; index < comparableLength; index++) {
      final oldComic = previous[index];
      final newComic = next[index];
      if (oldComic.sourceName != newComic.sourceName ||
          oldComic.slug != newComic.slug ||
          oldComic.latestChapterNumber != newComic.latestChapterNumber ||
          oldComic.latestChapterReleaseDate !=
              newComic.latestChapterReleaseDate) {
        return false;
      }
    }
    return true;
  }

  Future<String> _resolveSourceName() async {
    final cachedSource = _normalizedSource(_sourceName);
    if (cachedSource != null) return cachedSource;

    final selectedSource = _normalizedSource(ref.read(selectedSourceProvider));
    if (selectedSource != null) return selectedSource;

    final sources = await ref.read(catalogRepositoryProvider).getSources();
    if (sources.isEmpty) {
      throw Exception('No sources available.');
    }
    return sources.first.id;
  }

  String? _normalizedSource(String? sourceName) {
    final value = sourceName?.trim();
    if (value == null || value.isEmpty || value == 'home') return null;
    return value;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 640) {
      _loadNextPage();
    }
  }

  void _openComicDetail(ComicSummary comic) => openComicDetail(context, comic);
}

class _SectionHero extends StatelessWidget {
  const _SectionHero({
    required this.title,
    required this.subtitle,
    this.countLabel,
    this.countCaption,
    this.countLoading = false,
  });

  final String title;
  final String subtitle;
  final String? countLabel;
  final String? countCaption;
  final bool countLoading;

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
              ? const [Color(0xFF18202B), Color(0xFF241A19)]
              : const [Color(0xFFFFF3DD), Color(0xFFE8F7FF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.76),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(TonztoonIcons.bookOpen, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 5),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (countLabel != null) ...[
              const SizedBox(width: 10),
              _CountBadge(
                label: countLabel!,
                caption: countCaption,
                loading: countLoading,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, this.caption, this.loading = false});

  final String label;
  final String? caption;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: loading
            ? const AppShimmer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppShimmerBlock(width: 28, height: 13, borderRadius: 5),
                    SizedBox(height: 3),
                    AppShimmerBlock(width: 66, height: 9, borderRadius: 4),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({
    required this.comics,
    required this.showNewBadges,
    required this.onTap,
  });

  final List<ComicSummary> comics;
  final bool showNewBadges;
  final ValueChanged<ComicSummary> onTap;

  @override
  Widget build(BuildContext context) {
    return AppSliverColumnGrid<ComicSummary>(
      items: comics,
      minColumnWidth: 104,
      maxColumnCount: 6,
      itemBuilder: (context, comic) {
        return ComicCard(
          comic: comic,
          source: comicSourceNameLabel(comic.sourceName),
          width: double.infinity,
          showNewBadge: showNewBadges,
          onTap: () => onTap(comic),
        );
      },
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.comics,
    required this.showNewBadges,
    required this.onTap,
  });

  final List<ComicSummary> comics;
  final bool showNewBadges;
  final ValueChanged<ComicSummary> onTap;

  @override
  Widget build(BuildContext context) {
    final childCount = comics.isEmpty ? 0 : comics.length * 2 - 1;

    return SliverList(
      key: const ValueKey('section-list'),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) return const SizedBox(height: 12);
        final comic = comics[index ~/ 2];
        return ComicListCard(
          comic: comic,
          showNewBadge: showNewBadges,
          onTap: () => onTap(comic),
        );
      }, childCount: childCount),
    );
  }
}

class _SectionLoadingState extends StatelessWidget {
  const _SectionLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SectionLoadingPlaceholder();
  }
}

class _SectionLoadingPlaceholder extends StatelessWidget {
  const _SectionLoadingPlaceholder();

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
                  height: 108,
                  borderRadius: 18,
                ),
              ),
              SizedBox(height: 18),
              AppShimmer(
                child: Row(
                  children: [
                    AppShimmerBlock(width: 132, height: 22),
                    Spacer(),
                    AppShimmerBlock(width: 72, height: 18),
                  ],
                ),
              ),
              SizedBox(height: 12),
            ]),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          sliver: _SectionLoadingMoreGrid(itemCount: 6),
        ),
      ],
    );
  }
}

class _SectionLoadingMoreGrid extends StatelessWidget {
  const _SectionLoadingMoreGrid({this.itemCount = 2});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => const _SectionCardShimmer(),
        childCount: itemCount,
      ),
    );
  }
}

class _SectionLoadingMoreList extends StatelessWidget {
  const _SectionLoadingMoreList();

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) return const SizedBox(height: 12);
        return const ComicListCardShimmer();
      }, childCount: 3),
    );
  }
}

class _SectionCardShimmer extends StatelessWidget {
  const _SectionCardShimmer();

  @override
  Widget build(BuildContext context) {
    return const ComicGridCardShimmer();
  }
}

class _SectionErrorState extends StatelessWidget {
  const _SectionErrorState({
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
        child: AppErrorState(
          error: error,
          fallbackMessage:
              'Section komik belum dapat dimuat. Silakan coba lagi.',
          onRetry: onRetry,
          retryLabel: 'Retry',
          icon: TonztoonIcons.warning,
        ),
      ),
    );
  }
}

class _EmptySectionState extends StatelessWidget {
  const _EmptySectionState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: AppEmptyState(
        icon: TonztoonIcons.bookOpen,
        title: 'Belum ada komik',
        message: 'Coba muat ulang daftar ini beberapa saat lagi.',
      ),
    );
  }
}
