part of '../library_screen.dart';

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _applyingRouteTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      initialIndex: widget.initialTabIndex.clamp(0, 4),
      vsync: this,
    )..addListener(_syncRouteWithSelectedTab);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeTab = widget.initialTabIndex.clamp(0, 4);
    if (_tabController.index == routeTab) return;

    _applyingRouteTab = true;
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
    if (_applyingRouteTab || _tabController.indexIsChanging || !mounted) {
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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text('Pustaka', style: theme.textTheme.titleLarge),
        centerTitle: false,
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
          _BookmarksTab(),
          _CollectionsTab(),
          _ScenesTab(),
          _HistoryTab(),
          _DownloadsTab(),
        ],
      ),
    );
  }
}
