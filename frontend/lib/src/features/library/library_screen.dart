import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_error.dart';
import '../../core/app_icons.dart';
import '../../core/app_snackbar.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import '../home/section/section_shared.dart';
import 'library_error.dart';
import 'library_shared_panes.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 5,
      initialIndex: initialTabIndex.clamp(0, 4),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Text('Pustaka', style: theme.textTheme.titleLarge),
          centerTitle: false,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(54),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                tabs: [
                  Tab(text: 'Bookmark'),
                  Tab(text: 'Koleksi'),
                  Tab(text: 'Scene'),
                  Tab(text: 'Riwayat'),
                  Tab(text: 'Unduhan'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _BookmarksTab(),
            _CollectionsTab(),
            _ScenesTab(),
            _HistoryTab(),
            _DownloadsTab(),
          ],
        ),
      ),
    );
  }
}

class _BookmarksTab extends ConsumerStatefulWidget {
  const _BookmarksTab();

  @override
  ConsumerState<_BookmarksTab> createState() => _BookmarksTabState();
}

class _BookmarksTabState extends ConsumerState<_BookmarksTab>
    with AutomaticKeepAliveClientMixin<_BookmarksTab> {
  late final ScrollController _scrollController;
  bool _isBookmarkActionLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
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
    super.build(context);
    final theme = Theme.of(context);
    final bookmarksAsync = ref.watch(paginatedBookmarksProvider);
    final bookmarkPage = bookmarksAsync.asData?.value;
    final bookmarks = bookmarkPage?.items ?? const <LibraryComicRef>[];
    final summaryAsync = ref.watch(librarySummaryProvider);
    final downloadsCount =
        ref.watch(downloadsProvider).asData?.value.length ?? 0;

    final totalBookmarks =
        summaryAsync.asData?.value.counts.bookmarks ?? bookmarks.length;
    final trailing = totalBookmarks > bookmarks.length
        ? '${bookmarks.length} dari $totalBookmarks item'
        : '$totalBookmarks item';
    final isInitialLoading =
        bookmarksAsync.isLoading && bookmarksAsync.hasValue == false;
    final isRefreshing =
        (bookmarksAsync.isLoading && bookmarksAsync.hasValue == true) ||
        bookmarkPage?.isRefreshing == true;
    final initialError = bookmarksAsync.hasError && !bookmarksAsync.hasValue
        ? bookmarksAsync.error
        : null;

    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isInitialLoading
              ? const _BookmarkLoadingPane(key: ValueKey('bookmark-loading'))
              : initialError != null
              ? _BookmarkErrorPane(
                  key: const ValueKey('bookmark-error'),
                  error: initialError,
                  onRetry: () => ref.invalidate(paginatedBookmarksProvider),
                )
              : RefreshIndicator(
                  key: const ValueKey('bookmark-content'),
                  onRefresh: _refreshBookmarks,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate.fixed([
                            _LibraryHero(
                              bookmarks: bookmarks,
                              downloadsCount: downloadsCount,
                              totalBookmarks: totalBookmarks,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed:
                                    bookmarks.isEmpty ||
                                        _isBookmarkActionLoading
                                    ? null
                                    : _linkOtherSources,
                                icon: const Icon(TonztoonIcons.link, size: 18),
                                label: const Text(
                                  'Cari komik yang sama di source lain',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SectionHeader(
                              icon: TonztoonIcons.bookmarkAdded,
                              title: 'Komik tersimpan',
                              trailing: trailing,
                            ),
                            const SizedBox(height: 10),
                          ]),
                        ),
                      ),
                      if (bookmarks.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(
                            icon: TonztoonIcons.bookmark,
                            title: 'Belum ada bookmark',
                            message:
                                'Simpan komik dari halaman detail untuk menaruhnya di sini.',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.separated(
                            itemBuilder: (context, index) => _BookmarkTile(
                              comic: bookmarks[index],
                              onRemove: _removeBookmark,
                            ),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemCount: bookmarks.length,
                          ),
                        ),
                      if (bookmarkPage?.isLoadingMore == true)
                        const SliverPadding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate.fixed([
                              _BookmarkTileShimmer(),
                              SizedBox(height: 12),
                              _BookmarkTileShimmer(),
                            ]),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 132),
                        sliver: SliverToBoxAdapter(
                          child: SectionLoadMoreFooter(
                            hasNextPage: bookmarkPage?.hasNextPage ?? false,
                            loadedCount: bookmarks.length,
                            completeLabel: 'Semua bookmark sudah dimuat',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (isRefreshing || _isBookmarkActionLoading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        BottomViewportFade(background: theme.scaffoldBackgroundColor),
      ],
    );
  }

  Future<void> _refreshBookmarks() async {
    try {
      ref.invalidate(librarySummaryProvider);
      ref.invalidate(downloadsProvider);
      await Future.wait([
        ref.read(paginatedBookmarksProvider.notifier).refreshFirstPage(),
        ref.read(librarySummaryProvider.future),
        ref.read(downloadsProvider.future),
      ]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    } catch (error, stackTrace) {
      if (mounted) {
        showAppErrorSnackBar(
          context,
          error: error,
          stackTrace: stackTrace,
          logContext: 'Refresh bookmarks failed',
          fallbackMessage:
              'Bookmark belum dapat dimuat ulang. Silakan coba lagi.',
        );
      }
    }
  }

  Future<void> _removeBookmark(ComicSummary comic) async {
    if (_isBookmarkActionLoading) return;
    setState(() => _isBookmarkActionLoading = true);
    try {
      await ref.read(libraryRepositoryProvider).toggleBookmark(comic, true);
      ref
          .read(paginatedBookmarksProvider.notifier)
          .removeItemByKey('${comic.sourceName}|${comic.slug}');
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(bookmarksProvider);
      ref.invalidate(librarySummaryProvider);
      if (mounted) _showMessage(context, 'Bookmark dihapus.');
    } catch (error, stackTrace) {
      if (mounted) showLibraryActionError(context, error, stackTrace);
    } finally {
      if (mounted) setState(() => _isBookmarkActionLoading = false);
    }
  }

  Future<void> _linkOtherSources() async {
    if (_isBookmarkActionLoading) return;
    setState(() => _isBookmarkActionLoading = true);
    try {
      final summaryTotal =
          ref.read(librarySummaryProvider).asData?.value.counts.bookmarks ?? 0;
      final loadedTotal =
          ref.read(paginatedBookmarksProvider).asData?.value.items.length ?? 0;
      final totalBookmarks = summaryTotal > 0 ? summaryTotal : loadedTotal;
      final candidates = await _scanBookmarkLinkCandidatesWithProgress(
        totalBookmarks,
      );
      if (!mounted) return;
      if (candidates.isEmpty) {
        _showMessage(
          context,
          'Belum ditemukan komik yang cukup mirip di source lain.',
        );
        return;
      }
      final selected = await _showBookmarkLinkCandidates(context, candidates);
      if (!mounted || selected == null || selected.isEmpty) return;
      final result = await _saveBookmarkLinksWithProgress(selected);
      await ref.read(paginatedBookmarksProvider.notifier).refreshFirstPage();
      ref.invalidate(bookmarksProvider);
      for (final candidate in selected) {
        ref.invalidate(libraryComicStateProvider(candidate.comic.toSummary()));
        ref.invalidate(
          libraryComicStateProvider(candidate.bookmark.toSummary()),
        );
      }
      if (mounted) {
        _showMessage(
          context,
          '${result.linkedTotal} source dihubungkan dan '
          '${result.completedPropagated} status selesai disinkronkan.',
        );
      }
    } catch (error, stackTrace) {
      if (mounted) showLibraryActionError(context, error, stackTrace);
    } finally {
      if (mounted) setState(() => _isBookmarkActionLoading = false);
    }
  }

  Future<List<BookmarkLinkCandidate>> _scanBookmarkLinkCandidatesWithProgress(
    int totalBookmarks,
  ) async {
    final progress = ValueNotifier<int>(0);
    final dialogReady = Completer<BuildContext>();
    final dialogFuture = showTonztoonModal<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!dialogReady.isCompleted) {
          dialogReady.complete(dialogContext);
        }
        return PopScope(
          canPop: false,
          child: _BookmarkScanProgressDialog(
            progress: progress,
            totalBookmarks: totalBookmarks,
          ),
        );
      },
    );
    final dialogContext = await dialogReady.future;

    try {
      final candidates = await ref
          .read(libraryRepositoryProvider)
          .scanBookmarkLinkCandidates(
            onProgress: (scanned) => progress.value = scanned,
          );
      await Future<void>.delayed(const Duration(milliseconds: 550));
      return candidates;
    } finally {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await dialogFuture;
      progress.dispose();
    }
  }

  Future<BookmarkLinkSaveResult> _saveBookmarkLinksWithProgress(
    List<BookmarkLinkCandidate> candidates,
  ) async {
    final progress = ValueNotifier<BookmarkLinkSaveProgress>(
      BookmarkLinkSaveProgress(
        stage: BookmarkLinkSaveStage.linking,
        completed: 0,
        total: candidates.length,
      ),
    );
    final dialogReady = Completer<BuildContext>();
    final dialogFuture = showTonztoonModal<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!dialogReady.isCompleted) {
          dialogReady.complete(dialogContext);
        }
        return PopScope(
          canPop: false,
          child: _BookmarkLinkProgressDialog(progress: progress),
        );
      },
    );
    final dialogContext = await dialogReady.future;

    try {
      final result = await ref
          .read(libraryRepositoryProvider)
          .saveBookmarkLinks(
            candidates,
            onProgress: (value) => progress.value = value,
          );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return result;
    } finally {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await dialogFuture;
      progress.dispose();
    }
  }

  Future<void> _loadNextPage() async {
    try {
      await ref.read(paginatedBookmarksProvider.notifier).loadNextPage();
    } catch (error, stackTrace) {
      if (mounted) {
        showAppErrorSnackBar(
          context,
          error: error,
          stackTrace: stackTrace,
          logContext: 'Load next bookmark page failed',
          fallbackMessage: 'Bookmark berikutnya belum dapat dimuat.',
        );
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 640) {
      unawaited(_loadNextPage());
    }
  }

  @override
  bool get wantKeepAlive => true;
}

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);

    return _AsyncPane<List<CollectionSummary>>(
      value: collectionsAsync,
      onRefresh: () => _refreshCollections(ref),
      onRetry: () => ref.invalidate(collectionsProvider),
      builder: (collections) {
        final children = <Widget>[
          _CollectionHeader(
            count: collections.length,
            onAdd: () => _createCollection(context, ref),
          ),
          const SizedBox(height: 10),
          if (collections.isEmpty)
            const _EmptyState(
              icon: TonztoonIcons.library,
              title: 'Belum ada koleksi',
              message:
                  'Buat folder koleksi untuk mengelompokkan komik favorit.',
            )
          else
            for (final collection in collections) ...[
              _CollectionTile(collection: collection),
              const SizedBox(height: 12),
            ],
        ];

        return _LibraryList(
          children: children,
          onRefresh: () => _refreshCollections(ref),
        );
      },
    );
  }

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await _showCollectionNameDialog(
      context,
      title: 'Koleksi baru',
      actionLabel: 'Buat',
    );
    if (!context.mounted || name == null || name.trim().isEmpty) return;

    try {
      final created = await ref
          .read(libraryRepositoryProvider)
          .createCollection(name);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionDetailProvider(created.id));
      if (!context.mounted) return;
      _showMessage(context, 'Koleksi "${created.name}" dibuat.');
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }
}

class _ScenesTab extends ConsumerWidget {
  const _ScenesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const FavoriteScenesPane();
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab>
    with AutomaticKeepAliveClientMixin<_HistoryTab> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
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
    super.build(context);
    final theme = Theme.of(context);
    final historyAsync = ref.watch(paginatedHistoryProvider);
    final historyPage = historyAsync.asData?.value;
    final history = historyPage?.items ?? const <ReadingProgress>[];
    final isLoadingWithoutData = historyAsync.isLoading && historyPage == null;
    final summaryAsync = ref.watch(librarySummaryProvider);
    final totalHistory =
        summaryAsync.asData?.value.counts.history ?? history.length;
    final trailing = totalHistory > history.length
        ? '${history.length} dari $totalHistory item'
        : '$totalHistory item';
    final isInitialLoading = isLoadingWithoutData;
    final isRefreshing =
        (historyAsync.isLoading && historyAsync.hasValue == true) ||
        historyPage?.isRefreshing == true;
    final initialError = historyAsync.hasError && !historyAsync.hasValue
        ? historyAsync.error
        : null;

    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isInitialLoading
              ? const _HistoryLoadingPane(key: ValueKey('history-loading'))
              : initialError != null
              ? _BookmarkErrorPane(
                  key: const ValueKey('history-error'),
                  error: initialError,
                  onRetry: () => ref.invalidate(paginatedHistoryProvider),
                )
              : RefreshIndicator(
                  key: const ValueKey('history-content'),
                  onRefresh: _refreshHistory,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate.fixed([
                            _SectionHeader(
                              icon: TonztoonIcons.clock,
                              title: 'Terakhir dibaca',
                              trailing: trailing,
                            ),
                            const SizedBox(height: 10),
                          ]),
                        ),
                      ),
                      if (history.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(
                            icon: TonztoonIcons.clock,
                            title: 'Belum ada riwayat',
                            message:
                                'Mulai membaca chapter untuk melanjutkan dari tab ini.',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.separated(
                            itemBuilder: (context, index) =>
                                _HistoryTile(item: history[index]),
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemCount: history.length,
                          ),
                        ),
                      if (historyPage?.isLoadingMore == true)
                        const SliverPadding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate.fixed([
                              _BookmarkTileShimmer(),
                              SizedBox(height: 12),
                              _BookmarkTileShimmer(),
                            ]),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 132),
                        sliver: SliverToBoxAdapter(
                          child: SectionLoadMoreFooter(
                            hasNextPage: historyPage?.hasNextPage ?? false,
                            loadedCount: history.length,
                            completeLabel: 'Semua riwayat sudah dimuat',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (isRefreshing)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        BottomViewportFade(background: theme.scaffoldBackgroundColor),
      ],
    );
  }

  Future<void> _refreshHistory() async {
    try {
      ref.invalidate(historyProvider);
      ref.invalidate(librarySummaryProvider);
      await Future.wait([
        ref.read(paginatedHistoryProvider.notifier).refreshFirstPage(),
        ref.read(librarySummaryProvider.future),
      ]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    } catch (error, stackTrace) {
      if (mounted) {
        showAppErrorSnackBar(
          context,
          error: error,
          stackTrace: stackTrace,
          logContext: 'Refresh history failed',
          fallbackMessage:
              'Riwayat belum dapat dimuat ulang. Silakan coba lagi.',
        );
      }
    }
  }

  Future<void> _loadNextPage() async {
    try {
      await ref.read(paginatedHistoryProvider.notifier).loadNextPage();
    } catch (error, stackTrace) {
      if (mounted) {
        showAppErrorSnackBar(
          context,
          error: error,
          stackTrace: stackTrace,
          logContext: 'Load next history page failed',
          fallbackMessage: 'Riwayat berikutnya belum dapat dimuat.',
        );
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 640) {
      unawaited(_loadNextPage());
    }
  }

  @override
  bool get wantKeepAlive => true;
}

class _DownloadsTab extends ConsumerWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const OfflineDownloadsPane();
  }
}

class _AsyncPane<T> extends StatelessWidget {
  const _AsyncPane({
    required this.value,
    required this.builder,
    required this.onRefresh,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => const _LoadingPane(),
      error: (error, stackTrace) => _LibraryList(
        onRefresh: onRefresh,
        children: [_ErrorPane(error: error, onRetry: onRetry)],
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.children, this.onRefresh = _noopRefresh});

  final List<Widget> children;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _refreshWithSnackBar(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
        children: children,
      ),
    );
  }

  Future<void> _refreshWithSnackBar(BuildContext context) async {
    try {
      await onRefresh();
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Refresh library failed',
        fallbackMessage: 'Pustaka belum dapat dimuat ulang. Silakan coba lagi.',
      );
    }
  }
}

Future<void> _noopRefresh() async {}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();

  @override
  Widget build(BuildContext context) {
    return const AppPageLoadingPlaceholder();
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.error, required this.onRetry});

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
            Text(
              friendlyErrorMessage(
                error,
                fallbackMessage:
                    'Pustaka belum dapat dimuat. Silakan coba lagi.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkLoadingPane extends StatelessWidget {
  const _BookmarkLoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: AppShimmer(
              child: AppShimmerBlock(width: double.infinity, height: 172),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HistoryLoadingPane extends StatelessWidget {
  const _HistoryLoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _BookmarkErrorPane extends StatelessWidget {
  const _BookmarkErrorPane({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorPane(error: error, onRetry: onRetry),
        ),
      ],
    );
  }
}

class _BookmarkTileShimmer extends StatelessWidget {
  const _BookmarkTileShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: const AppShimmer(
        child: Row(
          children: [
            AppShimmerBlock(width: 72, height: 108, borderRadius: 15),
            SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppShimmerBlock(width: double.infinity, height: 18),
                    SizedBox(height: 8),
                    AppShimmerBlock(width: 150, height: 14),
                  ],
                ),
              ),
            ),
            SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({
    required this.bookmarks,
    required this.downloadsCount,
    required this.totalBookmarks,
  });

  final List<LibraryComicRef> bookmarks;
  final int downloadsCount;
  final int totalBookmarks;

  int get _ongoingCount =>
      bookmarks.where((item) => item.status?.toLowerCase() == 'ongoing').length;
  int get _completedCount => bookmarks
      .where((item) => item.status?.toLowerCase() == 'completed')
      .length;
  int get _hiatusCount =>
      bookmarks.where((item) => item.status?.toLowerCase() == 'hiatus').length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryOrange = Color(0xFFFF9D00);
    const accentBlue = Color(0xFF3A86FF);
    final gradientColors = isDark
        ? const [Color(0xFF1A1F2E), Color(0xFF0F1620), Color(0xFF1A1220)]
        : const [Color(0xFFFFF8EC), Color(0xFFF0F7FF), Color(0xFFFFF0F7)];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: gradientColors,
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withValues(alpha: isDark ? 0.18 : 0.12),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        TonztoonIcons.library,
                        color: primaryOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rak Bacaan Saya',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$totalBookmarks komik tersimpan',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '$totalBookmarks',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: primaryOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: primaryOrange.withValues(alpha: 0.12),
                  height: 1,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.clock,
                        value: '$_ongoingCount',
                        label: 'Ongoing',
                        color: accentBlue,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.badgeCheck,
                        value: '$_completedCount',
                        label: 'Selesai',
                        color: const Color(0xFF16A34A),
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.download,
                        value: '$downloadsCount',
                        label: 'Offline',
                        color: primaryOrange,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.circleDotDashed,
                        value: '$_hiatusCount',
                        label: 'Hiatus',
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  const _HeroStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color.withValues(alpha: 0.78),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({required this.comic, required this.onRemove});

  final LibraryComicRef comic;
  final Future<void> Function(ComicSummary comic) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = comic.toSummary();

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, summary),
      padding: EdgeInsets.zero,
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            height: 108,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    bottomLeft: Radius.circular(15),
                  ),
                  child: ComicCover(
                    imageUrl: comic.coverImageUrl,
                    borderRadius: 0,
                  ),
                ),
                if (comic.type != null)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Transform.scale(
                      key: ValueKey('bookmark-type-${comic.key}'),
                      scale: 0.72,
                      alignment: Alignment.topRight,
                      child: ComicTypeFlagBadge(type: comic.type!),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _BookmarkMetadataStrip(comic: comic),
                  const SizedBox(height: 7),
                  _BookmarkMetrics(
                    key: ValueKey('bookmark-metrics-${comic.key}'),
                    rating: comic.rating,
                    totalView: comic.totalView,
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi bookmark',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) async {
              if (value == 'open') {
                _openComicDetail(context, summary);
              }
              if (value == 'remove') {
                await onRemove(summary);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open', child: Text('Buka detail')),
              PopupMenuItem(value: 'remove', child: Text('Hapus bookmark')),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookmarkMetadataStrip extends StatefulWidget {
  const _BookmarkMetadataStrip({required this.comic});

  final LibraryComicRef comic;

  @override
  State<_BookmarkMetadataStrip> createState() => _BookmarkMetadataStripState();
}

class _BookmarkMetadataStripState extends State<_BookmarkMetadataStrip> {
  late final ScrollController _scrollController;
  bool _showLeftFade = false;
  bool _showRightFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_syncFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
  }

  @override
  void didUpdateWidget(covariant _BookmarkMetadataStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comic != widget.comic) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncFades)
      ..dispose();
    super.dispose();
  }

  void _syncFades() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final showLeftFade = position.extentBefore > 1;
    final showRightFade =
        position.maxScrollExtent > 0 && position.extentAfter > 1;
    if (showLeftFade != _showLeftFade || showRightFade != _showRightFade) {
      setState(() {
        _showLeftFade = showLeftFade;
        _showRightFade = showRightFade;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final comic = widget.comic;
    final sources = [
      comic.sourceName,
      ...comic.linkedComics.map((item) => item.sourceName),
    ];
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final hasStatus = comic.status != null && comic.status!.trim().isNotEmpty;
    final itemCount = sources.length + (hasStatus ? 1 : 0);

    return SizedBox(
      key: ValueKey('bookmark-metadata-strip-${comic.key}'),
      height: 25,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                if (hasStatus && index == 0) {
                  return KeyedSubtree(
                    key: ValueKey('bookmark-status-${comic.key}'),
                    child: ComicStatusBadge(status: comic.status!),
                  );
                }
                final sourceIndex = index - (hasStatus ? 1 : 0);
                final sourceName = sources[sourceIndex];
                if (sourceIndex == 0) {
                  return _SourceBadge(
                    key: ValueKey('bookmark-source-${comic.key}'),
                    sourceName: sourceName,
                  );
                }
                return _LinkedSourceBadge(
                  key: ValueKey(
                    'bookmark-linked-source-${comic.key}-$sourceName',
                  ),
                  sourceName: sourceName,
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            width: 30,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: ValueKey('bookmark-metadata-left-fade-${comic.key}'),
                opacity: _showLeftFade ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [surfaceColor, surfaceColor.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 30,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: ValueKey('bookmark-metadata-right-fade-${comic.key}'),
                opacity: _showRightFade ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [surfaceColor.withValues(alpha: 0), surfaceColor],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkMetrics extends StatelessWidget {
  const _BookmarkMetrics({
    super.key,
    required this.rating,
    required this.totalView,
  });

  final double? rating;
  final int? totalView;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _BookmarkMetric(
          icon: TonztoonIcons.starFilled,
          iconColor: const Color(0xFFFFB000),
          label: rating?.toStringAsFixed(1) ?? '-',
        ),
        const SizedBox(width: 12),
        _BookmarkMetric(
          icon: TonztoonIcons.eye,
          iconColor: colorScheme.secondary,
          label: '${_formatBookmarkMetric(totalView ?? 0)} views',
        ),
      ],
    );
  }
}

class _BookmarkMetric extends StatelessWidget {
  const _BookmarkMetric({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({super.key, required this.sourceName});

  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            TonztoonIcons.travelExplore,
            size: 11,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            comicSourceNameLabel(sourceName),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSecondaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedSourceBadge extends StatelessWidget {
  const _LinkedSourceBadge({super.key, required this.sourceName});

  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TonztoonIcons.link, size: 11, color: colors.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            comicSourceNameLabel(sourceName),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onTertiaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBookmarkMetric(int value) {
  if (value >= 1000000000) {
    return '${_formatBookmarkDecimal(value / 1000000000)}B';
  }
  if (value >= 1000000) {
    return '${_formatBookmarkDecimal(value / 1000000)}M';
  }
  if (value >= 1000) {
    return '${_formatBookmarkDecimal(value / 1000)}K';
  }
  return value.toString();
}

String _formatBookmarkDecimal(double value) {
  final formatted = value.toStringAsFixed(value >= 10 ? 0 : 1);
  return formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
}

Future<List<BookmarkLinkCandidate>?> _showBookmarkLinkCandidates(
  BuildContext context,
  List<BookmarkLinkCandidate> candidates,
) {
  final selectedByDestination = <String, BookmarkLinkCandidate>{};
  for (final candidate in candidates) {
    if (candidate.confidence < 0.82) {
      continue;
    }
    final destinationKey =
        '${candidate.bookmark.key}::${candidate.comic.sourceName}';
    final current = selectedByDestination[destinationKey];
    if (current == null || candidate.confidence > current.confidence) {
      selectedByDestination[destinationKey] = candidate;
    }
  }
  final selectedKeys = selectedByDestination.values
      .map((candidate) => candidate.key)
      .toSet();
  return showDialog<List<BookmarkLinkCandidate>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Hubungkan source lain'),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: candidates.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final candidate = candidates[index];
                  final selected = selectedKeys.contains(candidate.key);
                  return CheckboxListTile(
                    value: selected,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          selectedKeys.removeWhere((key) {
                            final selectedCandidate = candidates
                                .where((item) => item.key == key)
                                .firstOrNull;
                            return selectedCandidate != null &&
                                selectedCandidate.bookmark.key ==
                                    candidate.bookmark.key &&
                                selectedCandidate.comic.sourceName ==
                                    candidate.comic.sourceName;
                          });
                          selectedKeys.add(candidate.key);
                        } else {
                          selectedKeys.remove(candidate.key);
                        }
                      });
                    },
                    title: Text(
                      candidate.comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${comicSourceNameLabel(candidate.bookmark.sourceName)}'
                      ' -> ${comicSourceNameLabel(candidate.comic.sourceName)}'
                      ' • kecocokan ${(candidate.confidence * 100).round()}%',
                    ),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: selectedKeys.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      candidates
                          .where(
                            (candidate) => selectedKeys.contains(candidate.key),
                          )
                          .toList(),
                    ),
              child: Text('Hubungkan (${selectedKeys.length})'),
            ),
          ],
        );
      },
    ),
  );
}

class _BookmarkScanProgressDialog extends StatefulWidget {
  const _BookmarkScanProgressDialog({
    required this.progress,
    required this.totalBookmarks,
  });

  final ValueListenable<int> progress;
  final int totalBookmarks;

  @override
  State<_BookmarkScanProgressDialog> createState() =>
      _BookmarkScanProgressDialogState();
}

class _BookmarkScanProgressDialogState
    extends State<_BookmarkScanProgressDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  double get _target => widget.progress.value.toDouble();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _animation = AlwaysStoppedAnimation<double>(_target);
    widget.progress.addListener(_animateToProgress);
  }

  @override
  void didUpdateWidget(covariant _BookmarkScanProgressDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress == widget.progress) return;
    oldWidget.progress.removeListener(_animateToProgress);
    widget.progress.addListener(_animateToProgress);
    _animateToProgress();
  }

  void _animateToProgress() {
    final begin = _animation.value;
    final end = _target;
    if (begin == end) return;

    final itemDelta = (end - begin).abs().ceil();
    _controller
      ..stop()
      ..duration = Duration(milliseconds: (itemDelta * 90).clamp(180, 500));
    _animation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_animateToProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TonztoonModalDialog(
      title: 'Memindai source lain',
      message:
          'Tunggu sampai pemindaian selesai agar hasil kandidat dapat ditampilkan.',
      eyebrow: 'Bookmark multi-source',
      helperText:
          'Tetap di halaman ini. Jika koneksi gagal, progres sementara dapat dilanjutkan.',
      helperIcon: TonztoonIcons.clock,
      art: TonztoonModalArt.cloudSync,
      showActions: false,
      showCloseButton: false,
      content: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final safeTotal = widget.totalBookmarks > 0
              ? widget.totalBookmarks
              : 1;
          final animatedScanned = _animation.value.clamp(0, safeTotal);
          final completed = animatedScanned.floor();
          final value = (animatedScanned / safeTotal).clamp(0.0, 1.0);
          final percentage = (value * 100).round();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.totalBookmarks > 0
                          ? '$completed dari ${widget.totalBookmarks} bookmark'
                          : '$completed bookmark dipindai',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookmarkLinkProgressDialog extends StatelessWidget {
  const _BookmarkLinkProgressDialog({required this.progress});

  final ValueListenable<BookmarkLinkSaveProgress> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BookmarkLinkSaveProgress>(
      valueListenable: progress,
      builder: (context, value, _) {
        final safeTotal = value.total > 0 ? value.total : 1;
        final completed = value.completed.clamp(0, safeTotal);
        final progressValue = (completed / safeTotal).clamp(0.0, 1.0);
        final syncing = value.stage == BookmarkLinkSaveStage.syncingCompleted;

        return TonztoonModalDialog(
          title: syncing
              ? 'Menyinkronkan chapter selesai'
              : 'Menghubungkan kandidat',
          message: syncing
              ? 'Status completed/read sedang diterapkan ke source yang terhubung.'
              : 'Relasi komik terpilih sedang disimpan secara bertahap.',
          eyebrow: 'Bookmark multi-source',
          helperText:
              'Setiap batch disimpan terpisah dan otomatis dicoba ulang jika koneksi melambat.',
          helperIcon: TonztoonIcons.clock,
          art: TonztoonModalArt.cloudSync,
          showActions: false,
          showCloseButton: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      syncing
                          ? '$completed dari ${value.total} grup'
                          : '$completed dari ${value.total} kandidat',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${(progressValue * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: progressValue),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, animatedValue, _) {
                  return LinearProgressIndicator(
                    value: animatedValue,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(99),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(TonztoonIcons.library, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Koleksi pribadi',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text(
          '$count folder',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Tambah koleksi',
          onPressed: onAdd,
          icon: const Icon(TonztoonIcons.plus),
        ),
      ],
    );
  }
}

class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({required this.collection});

  final CollectionSummary collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = ref
        .watch(collectionDetailProvider(collection.id))
        .asData
        ?.value;
    final covers = detail?.items.take(3).toList() ?? const <LibraryComicRef>[];

    return AppSurfaceInk(
      onTap: () => _open(context),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: covers.isEmpty
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(TonztoonIcons.library),
                  )
                : Stack(
                    children: [
                      for (var index = 0; index < covers.length; index++)
                        Positioned(
                          left: index * 13,
                          top: index * 5,
                          child: ComicCover(
                            imageUrl: covers[index].coverImageUrl,
                            width: 42,
                            height: 58,
                            borderRadius: 8,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(collection.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(
                  '${collection.totalItems} komik tersimpan',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi koleksi',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) async {
              if (value == 'open') {
                _open(context);
                return;
              }
              if (value == 'rename') {
                await _renameCollection(context, ref, collection);
                return;
              }
              if (value == 'delete') {
                await _deleteCollection(context, ref, collection);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open', child: Text('Buka')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CollectionDetailScreen(
          collectionId: collection.id,
          initialName: collection.name,
        ),
      ),
    );
  }
}

class _CollectionDetailScreen extends ConsumerWidget {
  const _CollectionDetailScreen({
    required this.collectionId,
    required this.initialName,
  });

  final int collectionId;
  final String initialName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(collectionDetailProvider(collectionId));
    final detail = detailAsync.asData?.value;
    final title = detail?.name ?? initialName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Tambah komik',
            onPressed: detail == null
                ? null
                : () => _addComic(context, ref, detail),
            icon: const Icon(TonztoonIcons.plus),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi koleksi',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) async {
              final current = detail;
              if (current == null) return;
              if (value == 'rename') {
                await _renameCollection(context, ref, current);
                return;
              }
              if (value == 'delete') {
                final deleted = await _deleteCollection(context, ref, current);
                if (deleted && context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename koleksi')),
              PopupMenuItem(value: 'delete', child: Text('Hapus koleksi')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _AsyncPane<CollectionDetail>(
        value: detailAsync,
        onRefresh: () => _refreshCollectionDetail(ref, collectionId),
        onRetry: () => ref.invalidate(collectionDetailProvider(collectionId)),
        builder: (collection) {
          final children = <Widget>[
            _CollectionDetailHero(collection: collection),
            const SizedBox(height: 16),
            if (collection.items.isEmpty)
              const _EmptyState(
                icon: TonztoonIcons.library,
                title: 'Belum ada item di koleksi ini',
                message: 'Tambahkan komik dari bookmark yang sudah tersimpan.',
              )
            else
              for (final comic in collection.items) ...[
                _CollectionComicTile(
                  comic: comic,
                  onRemove: () => _removeComic(context, ref, collection, comic),
                ),
                const SizedBox(height: 12),
              ],
          ];

          return _LibraryList(
            children: children,
            onRefresh: () => _refreshCollectionDetail(ref, collectionId),
          );
        },
      ),
    );
  }

  Future<void> _addComic(
    BuildContext context,
    WidgetRef ref,
    CollectionDetail collection,
  ) async {
    try {
      final bookmarks = await ref.read(bookmarksProvider.future);
      if (!context.mounted) return;
      final existingKeys = collection.items.map((item) => item.key).toSet();
      final available = bookmarks
          .where((comic) => !existingKeys.contains(comic.key))
          .toList();

      final selected = await showModalBottomSheet<LibraryComicRef>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            top: false,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Text(
                  'Tambah komik',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Semua bookmark sudah masuk.')),
                  )
                else
                  for (final comic in available) ...[
                    _AddComicTile(comic: comic),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      );
      if (!context.mounted || selected == null) return;

      await ref
          .read(libraryRepositoryProvider)
          .addComicToCollection(collection.id, selected.toSummary());
      ref.invalidate(collectionDetailProvider(collection.id));
      ref.invalidate(collectionsProvider);
      if (!context.mounted) return;
      _showMessage(context, 'Komik ditambahkan.');
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }

  Future<void> _removeComic(
    BuildContext context,
    WidgetRef ref,
    CollectionDetail collection,
    LibraryComicRef comic,
  ) async {
    final confirmed = await showTonztoonConfirmDialog(
      context,
      title: 'Hapus komik',
      message: 'Hapus "${comic.title}" dari koleksi ini?',
      helperText:
          'Komik hanya dihapus dari koleksi ini. Bookmark dan progress baca tidak ikut terhapus.',
      helperIcon: TonztoonIcons.trash,
      cancelLabel: 'Batal',
      confirmLabel: 'Hapus',
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.trash,
    );
    if (!context.mounted || confirmed != true) return;

    try {
      await ref
          .read(libraryRepositoryProvider)
          .removeComicFromCollection(collection.id, comic.toSummary());
      ref.invalidate(collectionDetailProvider(collection.id));
      ref.invalidate(collectionsProvider);
      if (!context.mounted) return;
      _showMessage(context, 'Komik dihapus dari koleksi.');
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }
}

class _CollectionDetailHero extends StatelessWidget {
  const _CollectionDetailHero({required this.collection});

  final CollectionDetail collection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(TonztoonIcons.library, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${collection.items.length} komik tersimpan',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionComicTile extends StatelessWidget {
  const _CollectionComicTile({required this.comic, required this.onRemove});

  final LibraryComicRef comic;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = comic.toSummary();

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, summary),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(imageUrl: comic.coverImageUrl, width: 58, height: 82),
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
                const SizedBox(height: 5),
                Text(
                  [comic.type, comic.status]
                      .where((item) => item != null && item.isNotEmpty)
                      .join(' - '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hapus dari koleksi',
            onPressed: onRemove,
            icon: const Icon(TonztoonIcons.close),
          ),
        ],
      ),
    );
  }
}

class _AddComicTile extends StatelessWidget {
  const _AddComicTile({required this.comic});

  final LibraryComicRef comic;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceInk(
      onTap: () => Navigator.of(context).pop(comic),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(imageUrl: comic.coverImageUrl, width: 58, height: 82),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              comic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(TonztoonIcons.plus),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final ReadingProgress item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comic = ComicSummary(
      title: item.comicTitle,
      slug: item.comicSlug,
      sourceName: item.sourceName,
      coverImageUrl: item.coverImageUrl,
    );

    return AppSurfaceInk(
      onTap: () => _openReader(context, item),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(imageUrl: item.coverImageUrl, width: 58, height: 82),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.comicTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Chapter ${formatChapterNumber(item.chapterNumber)} - ${_dateLabel(item.lastReadAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (item.isCompleted) const _HistoryCompletedBadge(),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _progressValue(item),
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Buka detail',
            onPressed: () => _openComicDetail(context, comic),
            icon: const Icon(TonztoonIcons.chevronRight),
          ),
        ],
      ),
    );
  }
}

class _HistoryCompletedBadge extends StatelessWidget {
  const _HistoryCompletedBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF16A34A);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.badgeCheckFilled, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              'Sudah dibaca',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Icon(icon, size: 34, color: colorScheme.secondary),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _showCollectionNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String? initialValue,
}) {
  var value = initialValue ?? '';

  return showTonztoonModal<String>(
    context: context,
    builder: (context) => TonztoonModalDialog(
      title: title,
      message:
          'Beri nama koleksi supaya daftar komik lebih mudah ditemukan nanti.',
      helperText: 'Gunakan nama singkat dan jelas, misalnya Favorit Utama.',
      helperIcon: TonztoonIcons.library,
      art: TonztoonModalArt.folder,
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nama koleksi',
          hintText: 'Contoh: Favorit Utama',
        ),
        textInputAction: TextInputAction.done,
        onChanged: (text) => value = text,
        onFieldSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      secondaryLabel: 'Batal',
      onSecondaryPressed: () => Navigator.of(context).pop(),
      primaryLabel: actionLabel,
      onPrimaryPressed: () => Navigator.of(context).pop(value),
    ),
  );
}

Future<void> _renameCollection(
  BuildContext context,
  WidgetRef ref,
  CollectionSummary collection,
) async {
  final name = await _showCollectionNameDialog(
    context,
    title: 'Rename koleksi',
    actionLabel: 'Simpan',
    initialValue: collection.name,
  );
  if (!context.mounted || name == null || name.trim().isEmpty) return;

  try {
    final updated = await ref
        .read(libraryRepositoryProvider)
        .renameCollection(collection.id, name);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionDetailProvider(collection.id));
    if (!context.mounted) return;
    _showMessage(context, 'Koleksi menjadi "${updated.name}".');
  } catch (error, stackTrace) {
    if (context.mounted) showLibraryActionError(context, error, stackTrace);
  }
}

Future<bool> _deleteCollection(
  BuildContext context,
  WidgetRef ref,
  CollectionSummary collection,
) async {
  final confirmed = await showTonztoonConfirmDialog(
    context,
    title: 'Hapus koleksi',
    message: 'Hapus "${collection.name}" beserta daftar komiknya?',
    helperText:
        'Koleksi akan hilang dari pustaka. Komik, bookmark, dan progress baca tetap aman.',
    helperIcon: TonztoonIcons.trash,
    cancelLabel: 'Batal',
    confirmLabel: 'Hapus',
    variant: TonztoonModalVariant.danger,
    art: TonztoonModalArt.trash,
  );
  if (!context.mounted || confirmed != true) return false;

  try {
    await ref.read(libraryRepositoryProvider).deleteCollection(collection.id);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionDetailProvider(collection.id));
    if (!context.mounted) return false;
    _showMessage(context, 'Koleksi dihapus.');
    return true;
  } catch (error, stackTrace) {
    if (context.mounted) showLibraryActionError(context, error, stackTrace);
    return false;
  }
}

Future<void> _refreshCollections(WidgetRef ref) async {
  ref.invalidate(collectionsProvider);
  await ref.read(collectionsProvider.future);
}

Future<void> _refreshCollectionDetail(WidgetRef ref, int collectionId) async {
  ref.invalidate(collectionDetailProvider(collectionId));
  ref.invalidate(collectionsProvider);
  await Future.wait([
    ref.read(collectionDetailProvider(collectionId).future),
    ref.read(collectionsProvider.future),
  ]);
}

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

void _openReader(BuildContext context, ReadingProgress progress) {
  final comic = ComicSummary(
    title: progress.comicTitle,
    slug: progress.comicSlug,
    sourceName: progress.sourceName,
    coverImageUrl: progress.coverImageUrl,
  );
  context.push(
    '/reader/${Uri.encodeComponent(progress.sourceName)}/${Uri.encodeComponent(progress.comicSlug)}/${formatChapterNumber(progress.chapterNumber)}',
    extra: comic,
  );
}

double _progressValue(ReadingProgress item) {
  final total = item.totalPageItems;
  if (total == null || total <= 0) return item.isCompleted ? 1 : 0;
  final current = (item.lastReadPageItemIndex ?? item.pageIndex ?? 0) + 1;
  return (current / total).clamp(0, 1).toDouble();
}

String _dateLabel(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'baru saja';
  if (difference.inHours < 1) return '${difference.inMinutes} menit lalu';
  if (difference.inDays < 1) return '${difference.inHours} jam lalu';
  if (difference.inDays < 7) return '${difference.inDays} hari lalu';
  return '${value.day}/${value.month}/${value.year}';
}

void _showMessage(BuildContext context, String message) {
  showAppSnackBar(
    context,
    message: message,
    type: AppSnackBarType.success,
    hideCurrent: false,
  );
}
