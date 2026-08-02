part of '../library_screen.dart';

String _bookmarkStatusLabel(String status) => switch (status) {
  'ongoing' => 'Ongoing',
  'completed' => 'Selesai',
  'hiatus' => 'Hiatus',
  _ => status,
};

IconData _bookmarkStatusIcon(String status) => switch (status) {
  'ongoing' => TonztoonIcons.clock,
  'completed' => TonztoonIcons.badgeCheck,
  'hiatus' => TonztoonIcons.circleDotDashed,
  _ => TonztoonIcons.bookmark,
};

class _BookmarksTab extends ConsumerStatefulWidget {
  const _BookmarksTab({required this.isGrid});

  final bool isGrid;

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
    final bookmarkOptions = ref.watch(bookmarkBrowseOptionsProvider);
    final summaryAsync = ref.watch(librarySummaryProvider);
    final downloadsCount =
        ref.watch(downloadsProvider).asData?.value.length ?? 0;

    final totalBookmarks =
        summaryAsync.asData?.value.counts.bookmarks ?? bookmarks.length;
    final bookmarkStatusCounts =
        summaryAsync.asData?.value.counts.bookmarkStatusCounts;
    final trailing = bookmarkOptions.hasActiveBookmarkControls
        ? '${bookmarks.length}${bookmarkPage?.hasNextPage == true ? '+' : ''} hasil'
        : totalBookmarks > bookmarks.length
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
                              bookmarkStatusCounts:
                                  bookmarkStatusCounts ?? const <String, int>{},
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
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(
                            icon: TonztoonIcons.bookmark,
                            title: bookmarkOptions.hasActiveBookmarkControls
                                ? 'Tidak ada bookmark yang cocok'
                                : 'Belum ada bookmark',
                            message: bookmarkOptions.hasActiveBookmarkControls
                                ? 'Coba ubah atau reset filter bookmark.'
                                : 'Simpan komik dari halaman detail untuk menaruhnya di sini.',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: widget.isGrid
                              ? _BookmarkGrid(
                                  bookmarks: bookmarks,
                                  onRemove: _removeBookmark,
                                  onChangeStatus: _showBookmarkStatusPicker,
                                )
                              : _BookmarkList(
                                  bookmarks: bookmarks,
                                  onRemove: _removeBookmark,
                                  onChangeStatus: _showBookmarkStatusPicker,
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
                          child: LoadMoreFooter(
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
        AppEdgeFade(background: theme.scaffoldBackgroundColor),
        Positioned(
          right: 16,
          bottom: 120,
          child: ScrollToTopFab(controller: _scrollController),
        ),
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
      ref.invalidate(paginatedBookmarksProvider);
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

  Future<void> _showBookmarkStatusPicker(ComicSummary comic) async {
    final selectedStatus = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ubah status komik',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  comic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final status in const ['ongoing', 'completed', 'hiatus'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_bookmarkStatusIcon(status)),
                    title: Text(_bookmarkStatusLabel(status)),
                    trailing: comic.status?.trim().toLowerCase() == status
                        ? const Icon(TonztoonIcons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(status),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Saat source menemukan chapter baru, status otomatis kembali ke Ongoing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selectedStatus == null ||
        comic.status?.trim().toLowerCase() == selectedStatus) {
      return;
    }

    await _updateBookmarkStatus(comic, selectedStatus);
  }

  Future<void> _updateBookmarkStatus(ComicSummary comic, String status) async {
    if (_isBookmarkActionLoading) return;
    setState(() => _isBookmarkActionLoading = true);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .updateBookmarkStatus(comic, status);
      // Patch the visible item in-place so the current page and scroll offset
      // stay intact while the server-backed providers refresh in the background.
      final pagination = ref.read(paginatedBookmarksProvider.notifier);
      final filters = ref.read(bookmarkBrowseOptionsProvider);
      if (filters.bookmarkStatusQuery != null &&
          filters.bookmarkStatusQuery != status) {
        pagination.removeItemByKey('${comic.sourceName}|${comic.slug}');
      } else {
        pagination.updateItems(
          (item) =>
              item.sourceName == comic.sourceName && item.slug == comic.slug,
          (item) => item.copyWith(status: status),
        );
      }
      ref.invalidate(bookmarksProvider);
      ref.invalidate(librarySummaryProvider);
      ref.invalidate(libraryComicStateProvider(comic));
      if (mounted) {
        _showMessage(
          context,
          'Status ${comic.title} diubah menjadi ${_bookmarkStatusLabel(status)}.',
        );
      }
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
      final selected = await showBookmarkLinkCandidatesDialog(
        context,
        candidates,
      );
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
          child: BookmarkLinkProgressDialog(progress: progress),
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
                          child: LoadMoreFooter(
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
        AppEdgeFade(background: theme.scaffoldBackgroundColor),
        Positioned(
          right: 16,
          bottom: 120,
          child: ScrollToTopFab(controller: _scrollController),
        ),
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
