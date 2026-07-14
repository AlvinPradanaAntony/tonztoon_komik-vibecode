part of '../library_screen.dart';

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _applyingRouteTab = false;
  int _selectedTabIndex = 0;
  bool _isBookmarkGrid = false;

  @override
  void initState() {
    super.initState();
    final initialTabIndex = widget.initialTabIndex.clamp(0, 4);
    _selectedTabIndex = initialTabIndex;
    _tabController = TabController(
      length: 5,
      initialIndex: initialTabIndex,
      vsync: this,
    )..addListener(_syncRouteWithSelectedTab);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeTab = widget.initialTabIndex.clamp(0, 4);
    if (_tabController.index == routeTab) return;

    _applyingRouteTab = true;
    _selectedTabIndex = routeTab;
    _tabController.index = routeTab;
    _applyingRouteTab = false;
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_syncRouteWithSelectedTab)
      ..dispose();
    super.dispose();
  }

  void _syncRouteWithSelectedTab() {
    if (!mounted) return;

    final selectedTabIndex = _tabController.index;
    if (_selectedTabIndex != selectedTabIndex) {
      setState(() => _selectedTabIndex = selectedTabIndex);
    }

    if (_applyingRouteTab || _tabController.indexIsChanging) {
      return;
    }

    final router = GoRouter.of(context);
    final uri = router.routeInformationProvider.value.uri;
    if (uri.path == '/library' &&
        libraryTabIndexFromName(uri.queryParameters['tab']) ==
            _tabController.index) {
      return;
    }

    context.go(libraryLocationForTabIndex(_tabController.index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookmarkOptions = ref.watch(bookmarkBrowseOptionsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text('Pustaka', style: theme.textTheme.titleLarge),
        centerTitle: false,
        actions: _selectedTabIndex == 0
            ? [
                IconButton(
                  tooltip: _isBookmarkGrid
                      ? 'Tampilan daftar'
                      : 'Tampilan grid',
                  onPressed: () =>
                      setState(() => _isBookmarkGrid = !_isBookmarkGrid),
                  icon: Icon(_isBookmarkGrid ? TonztoonIcons.rows : TonztoonIcons.columns),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10, left: 6),
                  child: IconButton(
                    tooltip: 'Filter dan Sorting bookmark',
                    onPressed: () => _showBookmarkFilterSheet(bookmarkOptions),
                    icon: Badge(
                      isLabelVisible: bookmarkOptions.hasActiveFilters,
                      smallSize: 8,
                      child: const Icon(TonztoonIcons.slidersHorizontal),
                    ),
                  ),
                ),
              ]
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              tabs: const [
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _BookmarksTab(isGrid: _isBookmarkGrid),
          _CollectionsTab(),
          _ScenesTab(),
          _HistoryTab(),
          _DownloadsTab(),
        ],
      ),
    );
  }

  Future<void> _showBookmarkFilterSheet(ComicFilterSortState options) async {
    final result = await showComicFilterSortSheet(
      context: context,
      initialState: options,
      title: 'Filter & Sorting Bookmark',
      description: 'Atur bookmark berdasarkan tipe, status, dan urutan.',
      resetSort: ComicSortOption.relevance,
      showSource: false,
      showGenre: false,
      statusOptions: const [
        ComicFilterOption.all,
        'Ongoing',
        'Selesai',
        'Hiatus',
      ],
      sortOptions: const [
        ComicSortOption.updateNewest,
        ComicSortOption.az,
        ComicSortOption.za,
      ],
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
    );
    if (result == null || !mounted) return;
    ref.read(bookmarkBrowseOptionsProvider.notifier).apply(result);
  }
}
