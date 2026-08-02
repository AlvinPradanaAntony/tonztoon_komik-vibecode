part of '../library_screen.dart';

class _BookmarkGrid extends StatelessWidget {
  const _BookmarkGrid({
    required this.bookmarks,
    required this.onRemove,
    required this.onChangeStatus,
  });

  final List<LibraryComicRef> bookmarks;
  final Future<void> Function(ComicSummary comic) onRemove;
  final Future<void> Function(ComicSummary comic) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    return AppSliverColumnGrid<LibraryComicRef>(
      key: const ValueKey('bookmark-grid'),
      items: bookmarks,
      minColumnWidth: 98,
      maxColumnCount: 6,
      itemBuilder: (context, bookmark) => _BookmarkGridCard(
        comic: bookmark,
        onRemove: onRemove,
        onChangeStatus: onChangeStatus,
      ),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.bookmarks,
    required this.onRemove,
    required this.onChangeStatus,
  });

  final List<LibraryComicRef> bookmarks;
  final Future<void> Function(ComicSummary comic) onRemove;
  final Future<void> Function(ComicSummary comic) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    return SliverList.separated(
      key: const ValueKey('bookmark-list'),
      itemBuilder: (context, index) => _BookmarkTile(
        comic: bookmarks[index],
        onRemove: onRemove,
        onChangeStatus: onChangeStatus,
      ),
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: bookmarks.length,
    );
  }
}

class _BookmarkGridCard extends StatelessWidget {
  const _BookmarkGridCard({
    required this.comic,
    required this.onRemove,
    required this.onChangeStatus,
  });

  final LibraryComicRef comic;
  final Future<void> Function(ComicSummary comic) onRemove;
  final Future<void> Function(ComicSummary comic) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final summary = comic.toSummary();
    return Stack(
      children: [
        ComicCard(
          comic: summary,
          width: double.infinity,
          hasNewChapter: comic.hasNewChapter,
          onTap: () => _openComicDetail(context, summary),
          onLongPress: () => _showBookmarkGridActions(
            context,
            summary,
            onRemove: onRemove,
            onChangeStatus: onChangeStatus,
          ),
        ),
      ],
    );
  }
}

Future<void> _showBookmarkGridActions(
  BuildContext context,
  ComicSummary comic, {
  required Future<void> Function(ComicSummary comic) onRemove,
  required Future<void> Function(ComicSummary comic) onChangeStatus,
}) async {
  final renderBox = context.findRenderObject() as RenderBox?;
  if (renderBox == null || !renderBox.hasSize) return;

  final offset = renderBox.localToGlobal(Offset.zero);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      offset.dx + 8,
      offset.dy + 42,
      offset.dx + renderBox.size.width - 8,
      offset.dy + renderBox.size.height - 8,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    items: [
      const PopupMenuItem(
        value: 'open',
        child: _BookmarkMenuItem(
          icon: TonztoonIcons.bookOpen,
          label: 'Buka detail',
        ),
      ),
      const PopupMenuItem(
        value: 'status',
        child: _BookmarkMenuItem(
          icon: TonztoonIcons.pencil,
          label: 'Ubah status',
        ),
      ),
      const PopupMenuItem(
        value: 'remove',
        child: _BookmarkMenuItem(
          icon: TonztoonIcons.trash,
          label: 'Hapus bookmark',
        ),
      ),
    ],
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'open':
      _openComicDetail(context, comic);
    case 'status':
      await onChangeStatus(comic);
    case 'remove':
      await onRemove(comic);
  }
}

class _BookmarkMenuItem extends StatelessWidget {
  const _BookmarkMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 19), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.comic,
    required this.onRemove,
    required this.onChangeStatus,
  });

  final LibraryComicRef comic;
  final Future<void> Function(ComicSummary comic) onRemove;
  final Future<void> Function(ComicSummary comic) onChangeStatus;

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
                if (comic.hasNewChapter)
                  const Positioned(
                    top: 4,
                    left: 4,
                    child: ComicNewBadge(compact: true, scale: 0.85),
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
          _BookmarkActionsMenu(
            comic: summary,
            onOpen: () => _openComicDetail(context, summary),
            onRemove: () => onRemove(summary),
            onChangeStatus: onChangeStatus,
          ),
        ],
      ),
    );
  }
}

class _BookmarkActionsMenu extends StatelessWidget {
  const _BookmarkActionsMenu({
    required this.comic,
    required this.onChangeStatus,
    this.onOpen,
    this.onRemove,
  });

  final ComicSummary comic;
  final VoidCallback? onOpen;
  final Future<void> Function()? onRemove;
  final Future<void> Function(ComicSummary comic) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Opsi bookmark',
      icon: const Icon(TonztoonIcons.moreHoriz),
      padding: const EdgeInsets.all(8),
      onSelected: (value) async {
        if (value == 'open') onOpen?.call();
        if (value == 'status') await onChangeStatus(comic);
        if (value == 'remove') await onRemove?.call();
      },
      itemBuilder: (context) => [
        if (onOpen != null)
          const PopupMenuItem(value: 'open', child: Text('Buka detail')),
        const PopupMenuItem(value: 'status', child: Text('Ubah status')),
        if (onRemove != null)
          const PopupMenuItem(value: 'remove', child: Text('Hapus bookmark')),
      ],
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
              separatorBuilder: (context, index) {
                if (hasStatus && index == 0) {
                  return const MetadataSeparator(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                  );
                }
                return const SizedBox(width: 6);
              },
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
                  return SourceTag(
                    key: ValueKey('bookmark-source-${comic.key}'),
                    sourceName: sourceName,
                  );
                }
                return SourceTag(
                  key: ValueKey(
                    'bookmark-linked-source-${comic.key}-$sourceName',
                  ),
                  sourceName: sourceName,
                  style: SourceTagStyle.linked,
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
