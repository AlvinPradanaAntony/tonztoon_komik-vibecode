part of '../comic_detail_screen.dart';

class _LinkedSourcesCard extends StatelessWidget {
  const _LinkedSourcesCard({required this.state, required this.currentComic});

  final LibraryComicState state;
  final ComicSummary currentComic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final origin = state.bookmarkOrigin;
    final alternatives = state.linkedComics;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(TonztoonIcons.link, size: 17, color: colors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.bookmarkRelation == BookmarkRelation.linked &&
                            origin != null
                        ? 'Terhubung lewat ${comicSourceNameLabel(origin.sourceName)}'
                        : 'Source terhubung',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (alternatives.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: alternatives.map((comic) {
                  return ActionChip(
                    avatar: const Icon(TonztoonIcons.bookOpen, size: 14),
                    label: Text(comicSourceNameLabel(comic.sourceName)),
                    onPressed:
                        comic.sourceName == currentComic.sourceName &&
                            comic.slug == currentComic.slug
                        ? null
                        : () => openComicDetail(context, comic.toSummary()),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
