import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../helpers/app_icons.dart';
import '../../../helpers/app_snackbar.dart';
import '../../../helpers/navigation_helpers.dart';
import '../../../models/progress.dart';
import '../../../repositories/providers.dart';
import '../../../widgets/app_edge_fade.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_error_state.dart';
import '../../../widgets/app_loading_placeholder.dart';
import '../../../widgets/load_more_footer.dart';
import '../../../widgets/scroll_to_top_fab.dart';
import '../widgets/continue_reading_progress_card.dart';

class ContinueReadingSectionPayload {
  const ContinueReadingSectionPayload({required this.items});

  final List<ReadingProgress> items;
}

class ContinueReadingSectionScreen extends ConsumerStatefulWidget {
  const ContinueReadingSectionScreen({super.key, required this.initialItems});

  final List<ReadingProgress> initialItems;

  @override
  ConsumerState<ContinueReadingSectionScreen> createState() =>
      _ContinueReadingSectionScreenState();
}

class _ContinueReadingSectionScreenState
    extends ConsumerState<ContinueReadingSectionScreen> {
  static const _pageSize = 20;

  late final ScrollController _scrollController;

  List<ReadingProgress> _items = const [];
  Object? _error;
  int _page = 0;
  int _requestSerial = 0;
  bool _hasNextPage = true;
  bool _hasLoadedSection = false;
  bool _isFirstPageLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems;
    _page = widget.initialItems.isEmpty ? 0 : 1;
    _hasNextPage = widget.initialItems.length >= _pageSize;
    _hasLoadedSection = widget.initialItems.isNotEmpty;
    _isFirstPageLoading = widget.initialItems.isEmpty;
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
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lanjutkan Membaca', style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(TonztoonIcons.arrowBack),
          ),
        ),
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _isFirstPageLoading && !_hasLoadedSection
                ? const _ProgressSectionLoadingState(
                    key: ValueKey('continue-loading'),
                  )
                : _error != null && !_hasLoadedSection
                ? _ProgressSectionErrorState(
                    key: const ValueKey('continue-error'),
                    error: _error!,
                    onRetry: _loadFirstPage,
                  )
                : RefreshIndicator(
                    key: const ValueKey('continue-content'),
                    onRefresh: _loadFirstPage,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate.fixed([
                              _ProgressSectionHero(
                                countLabel: '${_items.length}',
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Progress terbaru',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    '${_items.length} item',
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
                        if (_items.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyProgressSectionState(),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList.separated(
                              itemBuilder: (context, index) => Align(
                                alignment: Alignment.topCenter,
                                child: ContinueReadingProgressCard(
                                  progress: _items[index],
                                  fullWidth: true,
                                  showTrailingArrow: true,
                                  onTap: () => openReaderForProgress(
                                    context,
                                    _items[index],
                                  ),
                                ),
                              ),
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemCount: _items.length,
                            ),
                          ),
                        if (_isLoadingMore)
                          const SliverPadding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate.fixed([
                                _ProgressTileShimmer(),
                                SizedBox(height: 10),
                                _ProgressTileShimmer(),
                              ]),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
                          sliver: SliverToBoxAdapter(
                            child: LoadMoreFooter(
                              hasNextPage: _hasNextPage,
                              loadedCount: _items.length,
                              completeLabel: 'Semua progress sudah dimuat',
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
      floatingActionButton: ScrollToTopFab(controller: _scrollController),
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
        _items = const [];
      }
    });

    try {
      final items = await _loadPage(1);

      if (!mounted || serial != _requestSerial) return;
      final nextItems = hadSection ? _mergeRefreshedFirstPage(items) : items;
      setState(() {
        _items = nextItems;
        _page = 1;
        _hasNextPage = items.length >= _pageSize;
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
          logContext: 'Refresh continue reading section failed',
          fallbackMessage:
              'Daftar lanjut membaca belum dapat dimuat ulang. Silakan coba lagi.',
        );
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isFirstPageLoading || _isLoadingMore || !_hasNextPage) return;

    final serial = _requestSerial;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final items = await _loadPage(nextPage);

      if (!mounted || serial != _requestSerial) return;
      final existingKeys = _items.map(_progressKey).toSet();
      final nextItems = [..._items];
      var addedCount = 0;
      for (final item in items) {
        if (existingKeys.add(_progressKey(item))) {
          nextItems.add(item);
          addedCount++;
        }
      }

      setState(() {
        _items = nextItems;
        _page = nextPage;
        _hasNextPage = items.length >= _pageSize && addedCount > 0;
        _isLoadingMore = false;
      });
    } catch (error, stackTrace) {
      if (!mounted || serial != _requestSerial) return;
      setState(() => _isLoadingMore = false);
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Load next continue reading page failed',
        fallbackMessage: 'Progress berikutnya belum dapat dimuat.',
      );
    }
  }

  Future<List<ReadingProgress>> _loadPage(int page) {
    return ref
        .read(progressRepositoryProvider)
        .getContinueReadingPage(page: page, pageSize: _pageSize);
  }

  List<ReadingProgress> _mergeRefreshedFirstPage(
    List<ReadingProgress> refreshedItems,
  ) {
    final refreshedKeys = refreshedItems.map(_progressKey).toSet();
    return [
      ...refreshedItems,
      for (final item in _items)
        if (!refreshedKeys.contains(_progressKey(item))) item,
    ];
  }

  String _progressKey(ReadingProgress item) {
    return '${item.sourceName}|${item.comicSlug}|${item.chapterNumber}';
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 640) {
      _loadNextPage();
    }
  }
}

class _ProgressSectionHero extends StatelessWidget {
  const _ProgressSectionHero({required this.countLabel});

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
              ? const [Color(0xFF17202A), Color(0xFF1D2520)]
              : const [Color(0xFFEFF7FF), Color(0xFFFFF3DD)],
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
                  Text(
                    'Lanjutkan Membaca',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Progress baca terbaru dari akun dan perangkat ini.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _ProgressCountBadge(label: countLabel),
          ],
        ),
      ),
    );
  }
}

class _ProgressCountBadge extends StatelessWidget {
  const _ProgressCountBadge({required this.label});

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

class _ProgressSectionLoadingState extends StatelessWidget {
  const _ProgressSectionLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: AppShimmer(
              child: AppShimmerBlock(width: double.infinity, height: 124),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _ProgressTileShimmer(),
              SizedBox(height: 10),
              _ProgressTileShimmer(),
              SizedBox(height: 10),
              _ProgressTileShimmer(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ProgressTileShimmer extends StatelessWidget {
  const _ProgressTileShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Row(
        children: [
          AppShimmerBlock(width: 64, height: 90, borderRadius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShimmerBlock(width: double.infinity, height: 18),
                SizedBox(height: 8),
                AppShimmerBlock(width: 110, height: 14),
                SizedBox(height: 12),
                AppShimmerBlock(width: double.infinity, height: 5),
                SizedBox(height: 8),
                AppShimmerBlock(width: 72, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSectionErrorState extends StatelessWidget {
  const _ProgressSectionErrorState({
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
              'Daftar lanjut membaca belum dapat dimuat. Silakan coba lagi.',
          onRetry: onRetry,
          retryLabel: 'Retry',
          icon: TonztoonIcons.warning,
        ),
      ),
    );
  }
}

class _EmptyProgressSectionState extends StatelessWidget {
  const _EmptyProgressSectionState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64, horizontal: 20),
      child: AppEmptyState(
        icon: TonztoonIcons.bookOpen,
        title: 'Belum ada progress',
        message:
            'Mulai membaca chapter untuk memunculkan daftar lanjut membaca.',
      ),
    );
  }
}
