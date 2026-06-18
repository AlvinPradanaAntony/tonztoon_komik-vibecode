part of '../library_shared_panes.dart';

class _DownloadEntryTile extends ConsumerWidget {
  const _DownloadEntryTile({
    required this.entry,
    required this.hasLocalFile,
    required this.allowDelete,
  });

  final DownloadEntry entry;
  final bool hasLocalFile;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queue = ref.watch(offlineQueueProvider).asData?.value ?? const [];
    final queuedBatch = _queuedBatchForEntry(entry, queue);
    final trailing = _trailing(context, ref, queuedBatch);

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, entry.comic.toSummary()),
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: Row(
        children: [
          ComicCover(
            imageUrl: entry.comic.coverImageUrl,
            width: 58,
            height: 82,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  _statusLabel(queuedBatch),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (allowDelete && !hasLocalFile && queuedBatch == null) ...[
            IconButton(
              tooltip: 'Hapus wishlist offline',
              onPressed: () => _deleteEntry(context, ref),
              icon: const Icon(TonztoonIcons.trash),
            ),
            trailing,
          ] else
            trailing,
        ],
      ),
    );
  }

  Widget _trailing(
    BuildContext context,
    WidgetRef ref,
    OfflineDownloadBatch? queuedBatch,
  ) {
    if (hasLocalFile) return const Icon(TonztoonIcons.chevronRight);
    if (queuedBatch == null) {
      return IconButton(
        tooltip: 'Download ke perangkat ini',
        onPressed: () => _downloadToThisDevice(context, ref),
        icon: const Icon(TonztoonIcons.download),
      );
    }
    if (queuedBatch.status == 'paused' || queuedBatch.status == 'failed') {
      return IconButton(
        tooltip: queuedBatch.status == 'failed'
            ? 'Coba lagi download'
            : 'Lanjutkan download',
        onPressed: () =>
            ref.read(offlineQueueProvider.notifier).resumeBatch(queuedBatch.id),
        icon: const Icon(TonztoonIcons.play),
      );
    }

    final progress = _queuedChapterProgress(entry, queuedBatch);
    final progressPercent = (progress * 100).round().clamp(0, 100);
    return Tooltip(
      message: 'Download berlangsung $progressPercent%',
      child: SizedBox.square(
        dimension: 48,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CircularProgressIndicator(
            value: queuedBatch.status == 'pending' ? null : progress,
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }

  String _statusLabel(OfflineDownloadBatch? queuedBatch) {
    final chapter = 'Ch ${formatChapterNumber(entry.chapterNumber)}';
    if (hasLocalFile) return '$chapter tersedia untuk dibaca offline';
    if (queuedBatch?.status == 'paused') {
      return '$chapter dijeda, tekan lanjutkan untuk resume';
    }
    if (queuedBatch?.status == 'failed') {
      return '$chapter gagal diunduh, tekan coba lagi';
    }
    if (queuedBatch?.status == 'pending') {
      return '$chapter menunggu antrean download';
    }
    if (queuedBatch != null) {
      final progress = _queuedChapterProgress(entry, queuedBatch);
      final progressPercent = (progress * 100).round().clamp(0, 100);
      return '$chapter sedang diunduh - $progressPercent%';
    }
    return '$chapter ada di wishlist offline, belum tersedia di perangkat ini';
  }

  Future<void> _downloadToThisDevice(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref
          .read(offlineQueueProvider.notifier)
          .startBatch(
            comic: entry.comic.toSummary(),
            chapters: [
              ChapterListItem(
                chapterNumber: entry.chapterNumber,
                title: 'Chapter ${formatChapterNumber(entry.chapterNumber)}',
                detailUrl: '',
                createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                totalImages: 0,
              ),
            ],
          );
      ref.invalidate(downloadsProvider);
      if (context.mounted) {
        _showMessage(context, 'Chapter masuk antrean download perangkat ini.');
      }
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }

  Future<void> _deleteEntry(BuildContext context, WidgetRef ref) async {
    final chapterLabel = formatChapterNumber(entry.chapterNumber);
    final confirmed = await showTonztoonAsyncConfirmDialog(
      context,
      title: 'Hapus wishlist offline',
      message:
          'Hapus "${entry.comic.title}" chapter $chapterLabel dari wishlist offline?',
      helperText:
          'Status wishlist akan dihapus. File lokal yang sudah tersedia di perangkat tidak ikut terhapus.',
      helperIcon: TonztoonIcons.trash,
      cancelLabel: 'Batal',
      confirmLabel: 'Hapus',
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.trash,
      onConfirm: () async {
        await ref.read(libraryRepositoryProvider).deleteDownloadEntry(entry);
        await _reloadDownloadsAfterDelete(ref);
      },
      onError: (error, stackTrace) {
        if (context.mounted) {
          showLibraryActionError(context, error, stackTrace);
        }
      },
    );
    if (!context.mounted || confirmed != true) return;
    _returnToDownloadsAfterDelete(context, 'Wishlist offline dihapus.');
  }
}

class _DownloadEntryGroupTile extends StatelessWidget {
  const _DownloadEntryGroupTile({
    required this.group,
    required this.localKeys,
    required this.allowDelete,
  });

  final _DownloadEntryGroup group;
  final Set<String> localKeys;
  final bool allowDelete;

  int get _localCount => group.entries
      .where((entry) => localKeys.contains(_downloadEntryKey(entry)))
      .length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localCount = _localCount;
    final total = group.entries.length;

    return AppSurfaceInk(
      onTap: () => _openWishlistGroup(context),
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
                  localCount == total
                      ? '$total chapter tersedia di perangkat ini'
                      : '$total chapter wishlist, $localCount tersedia lokal',
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

  void _openWishlistGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _DownloadEntryGroupScreen(
          group: group,
          localKeys: localKeys,
          allowDelete: allowDelete,
        ),
      ),
    );
  }
}

class _DownloadEntryGroupScreen extends ConsumerWidget {
  const _DownloadEntryGroupScreen({
    required this.group,
    required this.localKeys,
    required this.allowDelete,
  });

  final _DownloadEntryGroup group;
  final Set<String> localKeys;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveLocalKeys =
        ref
            .watch(offlineChaptersProvider)
            .asData
            ?.value
            .where((chapter) => chapter.isCompleted)
            .map(_offlineChapterKey)
            .toSet() ??
        localKeys;

    return Scaffold(
      appBar: AppBar(title: Text(group.comic.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SectionHeader(
            icon: TonztoonIcons.download,
            title: 'Wishlist offline',
            trailing: '${group.entries.length} chapter',
          ),
          const SizedBox(height: 10),
          for (final entry in group.entries) ...[
            _DownloadEntryTile(
              entry: entry,
              hasLocalFile: liveLocalKeys.contains(_downloadEntryKey(entry)),
              allowDelete:
                  allowDelete &&
                  !liveLocalKeys.contains(_downloadEntryKey(entry)),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
