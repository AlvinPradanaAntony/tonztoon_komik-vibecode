part of '../home_screen.dart';

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _floatingAppBarEnterOffset = 16;
  static const double _floatingAppBarExitOffset = 4;

  bool _migrationPromptShown = false;
  bool _showFloatingAppBar = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeAsync = ref.watch(homeDataProvider);
    final continueReadingAsync = ref.watch(continueReadingProvider);
    final auth = ref.watch(authControllerProvider);
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);
    final showHelpdeskButton = ref.watch(homeHelpdeskButtonVisibleProvider);
    _maybePromptMigration(auth);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _HomeTopAppBar(
        floating: _showFloatingAppBar,
        authenticated: auth.isAuthenticated,
        unreadNotifications: unreadNotifications,
        onActionPressed: auth.isAuthenticated
            ? () => _openNotifications(context)
            : () => context.push('/auth'),
      ),
      // Gunakan ListView dengan padding bawah besar (128) agar
      // tidak terpotong efek fade-mask dan floating navbar.
      body: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
              onRefresh: () => _retryHomeData(showErrorSnackBar: true),
              child: AppAsyncView<HomeData>(
                value: homeAsync,
                skipLoadingOnRefresh: true,
                skipError: true,
                loadingBuilder: (context) => _HomeLoadingPlaceholder(
                  controller: _scrollController,
                  topPadding: _homeContentTopPadding(context),
                ),
                onRetry: () => unawaited(_retryHomeData()),
                builder: (home) {
                  final latestComics = home.latest;
                  final popularComics = home.popular;
                  final recommendationComics = home.recommendations;
                  final topRankingComics = home.topRanking;
                  final continueProgress =
                      (continueReadingAsync.asData?.value ??
                              home.continueReading)
                          .take(6)
                          .toList();
                  final hasHomeContent =
                      latestComics.isNotEmpty ||
                      popularComics.isNotEmpty ||
                      recommendationComics.isNotEmpty ||
                      topRankingComics.isNotEmpty ||
                      continueProgress.isNotEmpty;

                  return ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      _homeContentTopPadding(context),
                      16,
                      128,
                    ),
                    children: [
                      _DiscoverHeader(
                        data: home,
                        onSourceChanged: (value) {
                          ref
                              .read(selectedSourceProvider.notifier)
                              .select(value);
                        },
                      ),
                      const SizedBox(height: 20),
                      if (recommendationComics.isNotEmpty) ...[
                        const _SectionTitle(title: 'Rekomendasi'),
                        const SizedBox(height: 10),
                        _RecommendationCarousel(
                          comics: recommendationComics,
                          onComicTap: (comic) =>
                              _openComicDetail(context, comic),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (topRankingComics.isNotEmpty) ...[
                        _TopRankingRail(
                          comics: topRankingComics.take(10).toList(),
                          sourceName: home.selectedSource.id,
                          onComicTap: (comic) =>
                              _openComicDetail(context, comic),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (continueProgress.isNotEmpty) ...[
                        _SectionTitle(
                          title: 'Lanjutkan Membaca',
                          actionLabel: 'Lihat semua',
                          onAction: () => _openContinueReadingSection(
                            context,
                            continueProgress,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 154,
                          child: ListView.separated(
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.only(bottom: 24),
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (context, index) => _ProgressCard(
                              progress: continueProgress[index],
                            ),
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 12),
                            itemCount: continueProgress.length,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _ComicRail(
                        title: 'Rilis Terbaru',
                        comics: latestComics.take(6).toList(),
                        showNewBadges: true,
                        actionLabel: 'Lihat semua',
                        onAction: () => _openComicSection(
                          context,
                          title: 'Rilis Terbaru',
                          subtitle:
                              'Chapter baru dari berbagai sumber favorit.',
                          sourceName: home.selectedSource.id,
                          comics: latestComics,
                          initialSort: ComicSortOption.updateNewest,
                        ),
                      ),
                      if (hasHomeContent) const SizedBox(height: 24),
                      _ComicRail(
                        title: 'Populer',
                        comics: popularComics.take(6).toList(),
                        actionLabel: 'Lihat semua',
                        onAction: () => _openComicSection(
                          context,
                          title: 'Populer',
                          subtitle: 'Komik yang ramai dibaca minggu ini.',
                          sourceName: home.selectedSource.id,
                          comics: popularComics,
                          initialSort: ComicSortOption.popular,
                        ),
                      ),
                      if (!hasHomeContent) const _HomeEmptyState(),
                    ],
                  );
                },
              ),
            ),
          ),
          AppEdgeFade(
            edge: AppFadeEdge.top,
            background: Theme.of(context).scaffoldBackgroundColor,
            height: MediaQuery.paddingOf(context).top + 40,
            midStop: 0.45,
            midAlpha: 0.75,
            opacity: _showFloatingAppBar ? 1 : 0,
            opacityDuration: const Duration(milliseconds: 380),
          ),
        ],
      ),
      floatingActionButton: showHelpdeskButton
          ? Padding(
              padding: const EdgeInsets.only(bottom: 120),
              child: FloatingActionButton(
                key: const ValueKey('home-helpdesk-button'),
                tooltip: 'Buka helpdesk',
                heroTag: 'home-helpdesk',
                onPressed: _openHelpdesk,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.surface,
                shape: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SvgPicture.asset(
                    key: const ValueKey('home-helpdesk-button-icon'),
                    AppAssets.logoAppSmallSvg,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.surface,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  double _homeContentTopPadding(BuildContext context) {
    return MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final shouldFloat = _showFloatingAppBar
        ? offset > _floatingAppBarExitOffset
        : offset > _floatingAppBarEnterOffset;
    if (shouldFloat == _showFloatingAppBar) return;

    setState(() => _showFloatingAppBar = shouldFloat);
  }

  Future<void> _openHelpdesk() async {
    final receipt = await showHelpdeskDialog(
      context,
      onSubmit: ref.read(helpdeskRepositoryProvider).submit,
    );
    if (!mounted || receipt == null) return;
    showAppSnackBar(
      context,
      title: 'Terkirim',
      message: 'Terima kasih. Kode laporan kamu: ${receipt.referenceCode}.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _retryHomeData({bool showErrorSnackBar = false}) async {
    try {
      ref.invalidate(homeDataProvider);
      await ref.read(homeDataProvider.future);
    } catch (error, stackTrace) {
      if (!mounted || !showErrorSnackBar) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Refresh home failed',
        fallbackMessage: 'Beranda belum dapat dimuat ulang. Silakan coba lagi.',
      );
    }
  }

  void _maybePromptMigration(AuthState auth) {
    if (_migrationPromptShown || !auth.isAuthenticated) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo.migrationSkipped || !repo.hasMigratableLocalData()) return;
    _migrationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMigrationDialog();
    });
  }

  Future<void> _showMigrationDialog() async {
    final repo = ref.read(libraryRepositoryProvider);
    final summary = repo.getGuestMigrationSummary();
    final action = await showGuestMigrationDialog(
      context,
      summary: summary,
      title: 'Sinkronkan data guest?',
      message:
          'Data dari mode guest berikut bisa dipindahkan ke akun cloud. File offline tetap tersimpan di perangkat ini.',
      barrierDismissible: false,
      secondaryLabel: 'Lewati',
      secondaryAction: GuestMigrationDialogAction.skip,
    );
    if (!mounted || action == null) return;

    if (action == GuestMigrationDialogAction.skip) {
      await repo.skipMigration();
      return;
    }

    var loadingShown = false;
    try {
      _showMigrationLoadingDialog();
      loadingShown = true;
      await repo.importLocalSnapshotToCloud();
      ref.invalidate(homeDataProvider);
      ref.invalidate(bookmarksProvider);
      ref.invalidate(paginatedBookmarksProvider);
      ref.invalidate(librarySummaryProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(favoriteScenesProvider);
      ref.invalidate(downloadsProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(paginatedHistoryProvider);
      ref.invalidate(readingTimeProvider);
      unawaited(ref.read(readingTimeProvider.notifier).refreshFromCloud());
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingShown = false;
      showAppSnackBar(
        context,
        message: 'Data guest berhasil disinkronkan.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      _migrationPromptShown = false;
      if (!mounted) return;
      if (loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Home guest migration failed',
        fallbackMessage:
            'Migrasi data guest belum berhasil. Silakan coba lagi.',
      );
    }
  }

  void _showMigrationLoadingDialog() {
    unawaited(
      showTonztoonModal<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const PopScope(canPop: false, child: GuestMigrationLoadingDialog()),
      ),
    );
  }
}
