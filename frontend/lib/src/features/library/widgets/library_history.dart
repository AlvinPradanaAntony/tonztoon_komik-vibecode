part of '../library_screen.dart';

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final ReadingProgress item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comic = ComicSummary(
      title: item.comicTitle,
      slug: item.comicSlug,
      sourceName: item.sourceName,
      coverImageUrl: item.coverImageUrl,
    );

    return AppSurfaceInk(
      onTap: () => _openReader(context, item),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(imageUrl: item.coverImageUrl, width: 58, height: 82),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.comicTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Chapter ${formatChapterNumber(item.chapterNumber)} - ${_dateLabel(item.lastReadAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (item.isCompleted) const _HistoryCompletedBadge(),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _progressValue(item),
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Buka detail',
            onPressed: () => _openComicDetail(context, comic),
            icon: const Icon(TonztoonIcons.chevronRight),
          ),
        ],
      ),
    );
  }
}

class _HistoryCompletedBadge extends StatelessWidget {
  const _HistoryCompletedBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF16A34A);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.badgeCheckFilled, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              'Sudah dibaca',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
