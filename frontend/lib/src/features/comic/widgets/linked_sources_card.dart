part of '../comic_detail_screen.dart';

class _LinkedSourcesCard extends StatefulWidget {
  const _LinkedSourcesCard({
    required this.state,
    required this.currentComic,
    required this.isFindingSources,
    required this.onFindSources,
  });

  final LibraryComicState state;
  final ComicSummary currentComic;
  final bool isFindingSources;
  final VoidCallback? onFindSources;

  @override
  State<_LinkedSourcesCard> createState() => _LinkedSourcesCardState();
}

class _LinkedSourcesCardState extends State<_LinkedSourcesCard>
    with SingleTickerProviderStateMixin {
  var _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.state.linkedComics.isEmpty;
  }

  @override
  void didUpdateWidget(covariant _LinkedSourcesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onFindSources == null &&
        widget.onFindSources != null &&
        widget.state.linkedComics.isEmpty) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final origin = widget.state.bookmarkOrigin;
    final alternatives = widget.state.linkedComics;
    final showFinder = widget.onFindSources != null || widget.isFindingSources;
    final canExpand = alternatives.isNotEmpty || showFinder;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surfaceContainer,
            colors.secondaryContainer.withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.secondary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canExpand
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Icon(
                        TonztoonIcons.link,
                        size: 18,
                        color: colors.onSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Source terhubung',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          _linkedSourcesSubtitle(
                            widget.state,
                            origin,
                            alternatives,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (alternatives.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.52),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Text(
                          '${alternatives.length} source',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (canExpand) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        TonztoonIcons.chevronRight,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canExpand)
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Column(
                        children: [
                          const SizedBox(height: 12),
                          ...alternatives.map((comic) {
                            final isCurrent =
                                comic.sourceName ==
                                    widget.currentComic.sourceName &&
                                comic.slug == widget.currentComic.slug;
                            final isPrimary = (widget.state.bookmarkRelation == BookmarkRelation.direct && isCurrent) ||
                                (widget.state.bookmarkOrigin != null &&
                                    comic.sourceName == widget.state.bookmarkOrigin!.sourceName &&
                                    comic.slug == widget.state.bookmarkOrigin!.slug);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LinkedSourceTile(
                                comic: comic,
                                isCurrent: isCurrent,
                                isPrimary: isPrimary,
                                onTap: isCurrent
                                    ? null
                                    : () => openComicDetail(
                                        context,
                                        comic.toSummary(),
                                      ),
                              ),
                            );
                          }),
                          if (showFinder)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: alternatives.isEmpty ? 0 : 8,
                              ),
                              child: _FindLinkedSourcePlaceholder(
                                isLoading: widget.isFindingSources,
                                onTap: widget.onFindSources,
                              ),
                            ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
          ],
        ),
      ),
    );
  }

  InlineSpan _linkedSourcesSubtitle(
    LibraryComicState state,
    LibraryComicRef? origin,
    List<LibraryComicRef> alternatives,
  ) {
    final colors = Theme.of(context).colorScheme;
    if (state.bookmarkRelation == BookmarkRelation.linked && origin != null) {
      return TextSpan(
        children: [
          const TextSpan(text: 'Bookmark ini mengikuti '),
          TextSpan(
            text: comicSourceNameLabel(origin.sourceName),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
          const TextSpan(text: ' dan tersedia di source lain.'),
        ],
      );
    }
    if (alternatives.isEmpty) {
      return const TextSpan(
        text: 'Cari dan hubungkan versi komik ini dari source lain.',
      );
    }
    return const TextSpan(
      text: 'Buka versi komik dari sumber berbeda tanpa mencari ulang.',
    );
  }
}

class _FindLinkedSourcePlaceholder extends StatelessWidget {
  const _FindLinkedSourcePlaceholder({
    required this.isLoading,
    required this.onTap,
  });

  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return CustomPaint(
      foregroundPainter: _DashedRoundedBorderPainter(
        color: colors.secondary.withValues(alpha: 0.62),
        radius: 16,
      ),
      child: Material(
        color: colors.surface.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('find-linked-bookmark-source'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  else
                    Icon(
                      TonztoonIcons.search,
                      size: 20,
                      color: colors.secondary,
                    ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      isLoading
                          ? 'Mencari source lain...'
                          : 'Cari dan hubungkan source lain',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.secondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 7, metric.length)),
          paint,
        );
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}


class _LinkedSourceTile extends StatelessWidget {
  const _LinkedSourceTile({
    required this.comic,
    required this.isCurrent,
    required this.isPrimary,
    required this.onTap,
  });

  final LibraryComicRef comic;
  final bool isCurrent;
  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surface.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? colors.primary.withValues(alpha: 0.42)
                  : colors.outlineVariant.withValues(alpha: 0.58),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ComicCover(
                  imageUrl: comic.coverImageUrl,
                  width: 44,
                  height: 58,
                  borderRadius: 11,
                  fallbackIconSize: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: SourceTag(
                              sourceName: comic.sourceName,
                              style: SourceTagStyle.linked,
                            ),
                          ),
                          if (isPrimary) ...[
                            const SizedBox(width: 6),
                            const _PrimarySourceBadge(),
                          ],
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            const _CurrentSourceBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        comic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isCurrent
                      ? TonztoonIcons.badgeCheckFilled
                      : TonztoonIcons.chevronRight,
                  size: 20,
                  color: isCurrent ? colors.primary : colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentSourceBadge extends StatelessWidget {
  const _CurrentSourceBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          'Aktif',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PrimarySourceBadge extends StatelessWidget {
  const _PrimarySourceBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.32),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TonztoonIcons.bookmarkFilled,
              size: 10,
              color: colors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'Utama',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
