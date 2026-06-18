part of '../comic_detail_screen.dart';

class _LinkedSourcesCard extends StatefulWidget {
  const _LinkedSourcesCard({required this.state, required this.currentComic});

  final LibraryComicState state;
  final ComicSummary currentComic;

  @override
  State<_LinkedSourcesCard> createState() => _LinkedSourcesCardState();
}

class _LinkedSourcesCardState extends State<_LinkedSourcesCard>
    with SingleTickerProviderStateMixin {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final origin = widget.state.bookmarkOrigin;
    final alternatives = widget.state.linkedComics;
    final canExpand = alternatives.isNotEmpty;

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
                        Text(
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
                  if (canExpand) ...[
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
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LinkedSourceTile(
                                comic: comic,
                                isCurrent: isCurrent,
                                onTap: isCurrent
                                    ? null
                                    : () => openComicDetail(
                                        context,
                                        comic.toSummary(),
                                      ),
                              ),
                            );
                          }),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
          ],
        ),
      ),
    );
  }

  String _linkedSourcesSubtitle(
    LibraryComicState state,
    LibraryComicRef? origin,
    List<LibraryComicRef> alternatives,
  ) {
    if (state.bookmarkRelation == BookmarkRelation.linked && origin != null) {
      return 'Bookmark ini mengikuti ${comicSourceNameLabel(origin.sourceName)} dan tersedia di source lain.';
    }
    if (alternatives.isEmpty) {
      return 'Komik ini ditautkan dengan bookmark dari source lain.';
    }
    return 'Buka versi komik dari sumber berbeda tanpa mencari ulang.';
  }
}

class _LinkedSourceTile extends StatelessWidget {
  const _LinkedSourceTile({
    required this.comic,
    required this.isCurrent,
    required this.onTap,
  });

  final LibraryComicRef comic;
  final bool isCurrent;
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
