part of '../comic_card.dart';

class ComicListCard extends StatelessWidget {
  const ComicListCard({
    super.key,
    required this.comic,
    required this.onTap,
    this.source,
    this.rating,
    this.showNewBadge = false,
  });

  final ComicSummary comic;
  final VoidCallback onTap;
  final String? source;
  final double? rating;
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sourceLabel = source ?? comicSourceLabel(comic);
    final statusLabel = _comicStatusLabel(comic.status);
    final ratingValue = rating ?? comic.rating;

    return Material(
      color: colorScheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 34, 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 104,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ComicCover(
                          imageUrl: comic.coverImageUrl,
                          borderRadius: 10,
                        ),
                        if (comic.type != null)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Transform.scale(
                              scale: 0.78,
                              alignment: Alignment.topRight,
                              child: ComicTypeFlagBadge(type: comic.type!),
                            ),
                          ),
                        if (showNewBadge && comic.hasNewChapter())
                          const Positioned(
                            right: 5,
                            bottom: 5,
                            child: ComicNewBadge(compact: true),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            right: ratingValue == null ? 0 : 42,
                          ),
                          child: Text(
                            comic.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              height: 1.08,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: _ComicListSource(source: sourceLabel),
                            ),
                            const SizedBox(width: 6),
                            ComicStatusBadge(status: statusLabel),
                          ],
                        ),
                        if (comic.genres.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _ComicListGenreStrip(genres: comic.genres),
                        ],
                        if (comic.latestChapterNumber != null ||
                            comic.totalView != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (comic.latestChapterNumber != null)
                                _ComicLatestChapterBadge(
                                  chapterNumber: comic.latestChapterNumber!,
                                ),
                              if (comic.latestChapterReleaseDate != null) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _ComicUpdateTime(
                                    releaseDate:
                                        comic.latestChapterReleaseDate!,
                                  ),
                                ),
                              ] else
                                const Spacer(),
                              if (comic.totalView != null) ...[
                                const SizedBox(width: 6),
                                _ComicListViewCount(
                                  totalView: comic.totalView!,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (ratingValue != null)
              Positioned(
                top: 0,
                right: 0,
                child: _ComicListRatingBadge(rating: ratingValue),
              ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Icon(
                  TonztoonIcons.chevronRight,
                  size: 19,
                  color: colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicListSource extends StatelessWidget {
  const _ComicListSource({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          TonztoonIcons.travelExplore,
          size: 14,
          color: colorScheme.secondary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComicListGenreStrip extends StatefulWidget {
  const _ComicListGenreStrip({required this.genres});

  final List<Genre> genres;

  @override
  State<_ComicListGenreStrip> createState() => _ComicListGenreStripState();
}

class _ComicListGenreStripState extends State<_ComicListGenreStrip> {
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
  void didUpdateWidget(covariant _ComicListGenreStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.genres != widget.genres) {
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
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return SizedBox(
      key: const ValueKey('comic-list-genre-strip'),
      height: 26,
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
              itemCount: widget.genres.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) => ComicGenreBadge(
                genre: widget.genres[index].name,
                compact: true,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            width: 30,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: const ValueKey('comic-list-genre-left-fade'),
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
                key: const ValueKey('comic-list-genre-right-fade'),
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

class _ComicUpdateTime extends StatelessWidget {
  const _ComicUpdateTime({required this.releaseDate});

  final DateTime releaseDate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          TonztoonIcons.clock,
          size: 13,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _relativeComicUpdateTime(releaseDate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComicListViewCount extends StatelessWidget {
  const _ComicListViewCount({required this.totalView});

  final int totalView;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      key: const ValueKey('comic-list-total-view'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(TonztoonIcons.eye, size: 13, color: colorScheme.secondary),
        const SizedBox(width: 4),
        Text(
          _formatCompactMetric(totalView),
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ComicLatestChapterBadge extends StatelessWidget {
  const _ComicLatestChapterBadge({required this.chapterNumber});

  final double chapterNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(colorScheme.secondary, Colors.black, 0.16)!,
            colorScheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colorScheme.secondary.withValues(alpha: 0.26),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          'Chapter ${formatChapterNumber(chapterNumber)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ComicListRatingBadge extends StatelessWidget {
  const _ComicListRatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFC400),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(15),
          bottomLeft: Radius.circular(13),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 7,
            offset: const Offset(-2, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                TonztoonIcons.starFilled,
                size: 14,
                color: Color(0xFF5C4300),
              ),
              const SizedBox(width: 3),
              Text(
                rating.toStringAsFixed(1),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF3D2E00),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
