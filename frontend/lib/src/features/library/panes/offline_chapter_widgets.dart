part of '../library_shared_panes.dart';

class _OfflineBatchTile extends ConsumerWidget {
  const _OfflineBatchTile({required this.batch});

  final OfflineDownloadBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progressPercent = (batch.progress * 100).round().clamp(0, 100);

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, batch.comic.toSummary()),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ComicCover(
                imageUrl: batch.comic.coverImageUrl,
                width: 58,
                height: 82,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batch.comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${batch.status} - ${batch.completedChapters}/${batch.totalChapters} chapter',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opsi unduhan',
                icon: const Icon(TonztoonIcons.moreHoriz),
                onSelected: (value) async {
                  final controller = ref.read(offlineQueueProvider.notifier);
                  if (value == 'delete') {
                    final confirmed = await showTonztoonAsyncConfirmDialog(
                      context,
                      title: 'Hapus antrean unduhan',
                      message:
                          'Hapus antrean unduhan "${batch.comic.title}" dari perangkat ini?',
                      helperText:
                          'Progress antrean yang sedang berjalan akan dihentikan dan dihapus.',
                      helperIcon: TonztoonIcons.trash,
                      cancelLabel: 'Batal',
                      confirmLabel: 'Hapus',
                      variant: TonztoonModalVariant.danger,
                      art: TonztoonModalArt.trash,
                      onConfirm: () async {
                        await controller.deleteBatch(batch.id);
                        await _reloadDownloadsAfterDelete(ref);
                      },
                      onError: (error, stackTrace) {
                        if (context.mounted) {
                          showLibraryActionError(context, error, stackTrace);
                        }
                      },
                    );
                    if (!context.mounted || confirmed != true) return;
                    _returnToDownloadsAfterDelete(
                      context,
                      'Antrean unduhan dihapus.',
                    );
                    return;
                  }
                  if (value == 'resume') await controller.resumeBatch(batch.id);
                  if (value == 'cancel') await controller.cancelBatch(batch.id);
                  ref.invalidate(downloadsProvider);
                },
                itemBuilder: (context) => [
                  if (batch.canResume)
                    PopupMenuItem(
                      value: 'resume',
                      child: Text(
                        batch.status == 'failed' ? 'Coba lagi' : 'Lanjutkan',
                      ),
                    ),
                  if (batch.canCancel)
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Batalkan'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Hapus')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Progres unduhan', style: theme.textTheme.labelSmall),
              const Spacer(),
              Text(
                '$progressPercent%',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: batch.progress,
            borderRadius: BorderRadius.circular(99),
          ),
        ],
      ),
    );
  }
}

class _OfflineChapterTile extends ConsumerWidget {
  const _OfflineChapterTile({required this.chapter, required this.allowDelete});

  final OfflineChapter chapter;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ready = chapter.isCompleted;

    return AppSurfaceInk(
      onTap: () => ready
          ? _openOfflineChapter(context, chapter)
          : _openComicDetail(context, chapter.comic.toSummary()),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(
            imageUrl: chapter.comic.coverImageUrl,
            width: 58,
            height: 82,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                ready
                    ? _OfflineReadyBadge(
                        label:
                            'Ch ${formatChapterNumber(chapter.chapterNumber)} tersedia offline',
                      )
                    : Text(
                        '${chapter.status} - Ch ${formatChapterNumber(chapter.chapterNumber)}',
                        style: theme.textTheme.bodySmall,
                      ),
              ],
            ),
          ),
          if (allowDelete)
            IconButton(
              tooltip: 'Hapus file offline',
              onPressed: () => _deleteOfflineChapter(context, ref),
              icon: const Icon(TonztoonIcons.trash),
            )
          else
            const Icon(TonztoonIcons.chevronRight),
        ],
      ),
    );
  }

  Future<void> _deleteOfflineChapter(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final chapterLabel = formatChapterNumber(chapter.chapterNumber);
    final confirmed = await showTonztoonAsyncConfirmDialog(
      context,
      title: 'Hapus unduhan offline',
      message:
          'Hapus "${chapter.comic.title}" chapter $chapterLabel dari perangkat ini?',
      helperText:
          'File offline dan wishlist chapter terkait akan dihapus. Chapter perlu diunduh ulang agar dapat dibaca tanpa internet.',
      helperIcon: TonztoonIcons.trash,
      cancelLabel: 'Batal',
      confirmLabel: 'Hapus',
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.trash,
      onConfirm: () async {
        final matchingDownload = await _matchingDownload(ref, chapter);
        await ref.read(offlineRepositoryProvider).deleteOfflineChapter(chapter);
        if (matchingDownload != null) {
          await ref
              .read(libraryRepositoryProvider)
              .deleteDownloadEntry(matchingDownload);
        }
        await _reloadDownloadsAfterDelete(ref);
      },
      onError: (error, stackTrace) {
        if (context.mounted) {
          showLibraryActionError(context, error, stackTrace);
        }
      },
    );
    if (!context.mounted || confirmed != true) return;
    _returnToDownloadsAfterDelete(context, 'Unduhan offline dihapus.');
  }

  Future<DownloadEntry?> _matchingDownload(
    WidgetRef ref,
    OfflineChapter chapter,
  ) async {
    final downloads = await ref.read(downloadsProvider.future);
    for (final entry in downloads) {
      if (_downloadEntryKey(entry) == _offlineChapterKey(chapter)) {
        return entry;
      }
    }
    return null;
  }
}

class _OfflineChapterGroupTile extends StatelessWidget {
  const _OfflineChapterGroupTile({
    required this.group,
    required this.allowDelete,
  });

  final _OfflineChapterGroup group;
  final bool allowDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapterCount = group.chapters.length;
    final readyCount = group.readyCount;

    return AppSurfaceInk(
      onTap: () => _openOfflineGroup(context),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(
            imageUrl: group.comic.coverImageUrl,
            width: 58,
            height: 82,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  '$readyCount/$chapterCount chapter tersedia offline',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(TonztoonIcons.chevronRight),
        ],
      ),
    );
  }

  void _openOfflineGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            _OfflineChapterGroupScreen(group: group, allowDelete: allowDelete),
      ),
    );
  }
}

class _OfflineChapterGroupScreen extends StatelessWidget {
  const _OfflineChapterGroupScreen({
    required this.group,
    required this.allowDelete,
  });

  final _OfflineChapterGroup group;
  final bool allowDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(group.comic.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SectionHeader(
            icon: TonztoonIcons.download,
            title: 'File lokal',
            trailing: '${group.chapters.length} chapter',
          ),
          const SizedBox(height: 10),
          for (final chapter in group.chapters) ...[
            _OfflineChapterTile(chapter: chapter, allowDelete: allowDelete),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _OfflineReadyBadge extends StatelessWidget {
  const _OfflineReadyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF16A34A);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.badgeCheckFilled, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineHint extends StatelessWidget {
  const _OfflineHint();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(TonztoonIcons.download, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Status cloud dan file offline lokal dipisah agar device lain tidak dianggap punya file yang belum diunduh.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
