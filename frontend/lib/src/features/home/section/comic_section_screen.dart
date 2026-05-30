import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_error.dart';
import '../../../core/app_icons.dart';
import '../../../core/app_snackbar.dart';
import '../../../models/comic.dart';
import '../../../repositories/providers.dart';
import '../../../widgets/app_loading_placeholder.dart';
import '../../../widgets/comic_card.dart';
import '../../../widgets/comic_cover.dart';
import '../../../widgets/comic_filter_sort_sheet.dart';
import 'section_shared.dart';

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

  bool get _isPopularSection =>
      ComicSortOption.normalize(widget.initialSort) == ComicSortOption.popular;

  @override
  void initState() {
    super.initState();
    _comics = widget.comics;
    _sourceName = _normalizedSource(widget.sourceName);
    _page = widget.comics.isEmpty ? 0 : 1;
    _hasNextPage = widget.comics.length >= _pageSize;
    _hasLoadedSection = widget.comics.isNotEmpty;
    _isFirstPageLoading = widget.comics.isEmpty;
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
                                title: widget.title,
                                subtitle: widget.subtitle,
                                countLabel: '${_comics.length}',
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
                                  Text(
                                    '${_comics.length} komik',
                                    style: theme.textTheme.bodyMedium?.copyWith(
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
                                    onTap: _openComicDetail,
                                  )
                                : _SectionList(
                                    comics: _comics,
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
                            child: SectionLoadMoreFooter(
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
          BottomViewportFade(background: theme.scaffoldBackgroundColor),
        ],
      ),
    );
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    final serial = ++_requestSerial;
    final hadSection = _hasLoadedSection;
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
      });
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

  void _openComicDetail(ComicSummary comic) {
    context.push(
      '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
      extra: comic,
    );
  }
}

class _SectionHero extends StatelessWidget {
  const _SectionHero({
    required this.title,
    required this.subtitle,
    required this.countLabel,
  });

  final String title;
  final String subtitle;
  final String countLabel;

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
            const SizedBox(width: 10),
            _CountBadge(label: countLabel),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

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
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.comics, required this.onTap});

  final List<ComicSummary> comics;
  final ValueChanged<ComicSummary> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final comic = comics[index];
        return ComicCard(
          comic: comic,
          source: comicSourceNameLabel(comic.sourceName),
          width: double.infinity,
          onTap: () => onTap(comic),
        );
      }, childCount: comics.length),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.comics, required this.onTap});

  final List<ComicSummary> comics;
  final ValueChanged<ComicSummary> onTap;

  @override
  Widget build(BuildContext context) {
    final childCount = comics.isEmpty ? 0 : comics.length * 2 - 1;

    return SliverList(
      key: const ValueKey('section-list'),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) return const SizedBox(height: 12);
        final comic = comics[index ~/ 2];
        return _SectionListTile(comic: comic, onTap: () => onTap(comic));
      }, childCount: childCount),
    );
  }
}

class _SectionListTile extends StatelessWidget {
  const _SectionListTile({required this.comic, required this.onTap});

  final ComicSummary comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = comicSourceNameLabel(comic.sourceName);
    final type = comicTypeFilterLabel(comic.type);
    final status = comicStatusFilterLabel(comic.status);
    final genre = comic.genres.isEmpty ? type : comic.genres.first.name;
    final rating = comic.rating;

    return Material(
      color: colorScheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
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
                            '$source • ${comicTypeFlag(comic.type)} $type',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (rating != null) ...[
                          const SizedBox(width: 8),
                          _SectionRatingText(rating: rating),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ComicGenreBadge(genre: genre, compact: true),
                        ComicStatusBadge(status: status),
                      ],
                    ),
                    if (comic.latestChapterNumber != null) ...[
                      const SizedBox(height: 10),
                      ComicMetaBadge(
                        label:
                            'Chapter ${formatChapterNumber(comic.latestChapterNumber!)}',
                        color: colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(TonztoonIcons.chevronRight, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionRatingText extends StatelessWidget {
  const _SectionRatingText({required this.rating});

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
        return const _SectionListTileShimmer();
      }, childCount: 3),
    );
  }
}

class _SectionListTileShimmer extends StatelessWidget {
  const _SectionListTileShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Row(
        children: [
          AppShimmerBlock(width: 74, height: 106, borderRadius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShimmerBlock(width: double.infinity, height: 18),
                SizedBox(height: 8),
                AppShimmerBlock(width: 190, height: 14),
                SizedBox(height: 10),
                Row(
                  children: [
                    AppShimmerBlock(width: 82, height: 24, borderRadius: 14),
                    SizedBox(width: 7),
                    AppShimmerBlock(width: 92, height: 24, borderRadius: 14),
                  ],
                ),
                SizedBox(height: 10),
                AppShimmerBlock(width: 112, height: 24, borderRadius: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCardShimmer extends StatelessWidget {
  const _SectionCardShimmer();

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.warning, size: 40),
            const SizedBox(height: 12),
            Text(
              friendlyErrorMessage(
                error,
                fallbackMessage:
                    'Section komik belum dapat dimuat. Silakan coba lagi.',
              ),
              textAlign: TextAlign.center,
            ),
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

class _EmptySectionState extends StatelessWidget {
  const _EmptySectionState();

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
                TonztoonIcons.bookOpen,
                size: 38,
                color: colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Belum ada komik',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Coba muat ulang daftar ini beberapa saat lagi.',
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
