part of '../library_screen.dart';

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
