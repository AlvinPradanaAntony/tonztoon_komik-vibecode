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
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(14),
              ),
              child: ComicCover(
                imageUrl: entry.comic.coverImageUrl,
                width: 58,
                height: 82,
                borderRadius: 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
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
            ),
            const SizedBox(width: 12),
            if (allowDelete && !hasLocalFile && queuedBatch == null) ...[
              Center(
                child: IconButton(
                  tooltip: 'Hapus wishlist offline',
                  onPressed: () => _deleteEntry(context, ref),
                  icon: const Icon(TonztoonIcons.trash),
                ),
              ),
              Center(child: trailing),
            ] else
              Center(child: trailing),
            const SizedBox(width: 12),
          ],
        ),
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
    this.backgroundColor,
  });

  final _DownloadEntryGroup group;
  final Set<String> localKeys;
  final bool allowDelete;
  final Color? backgroundColor;

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
      color: backgroundColor,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(14),
              ),
              child: ComicCover(
                imageUrl: group.comic.coverImageUrl,
                width: 58,
                height: 82,
                borderRadius: 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
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
            ),
            const SizedBox(width: 12),
            const Center(
              child: Icon(TonztoonIcons.chevronRight),
            ),
            const SizedBox(width: 12),
          ],
        ),
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

extension on _DownloadEntryGroup {
  int localEntryCount(Set<String> localKeys) {
    return entries
        .where((entry) => localKeys.contains(_downloadEntryKey(entry)))
        .length;
  }
}

extension on _WishlistOfflineSection {
  bool get hasLocalFiles {
    return groups.any((group) => group.localEntryCount(localKeys) > 0);
  }
}

class _WishlistOfflineSection extends StatefulWidget {
  const _WishlistOfflineSection({
    required this.groups,
    required this.localKeys,
    required this.allowDelete,
  });

  final List<_DownloadEntryGroup> groups;
  final Set<String> localKeys;
  final bool allowDelete;

  @override
  State<_WishlistOfflineSection> createState() =>
      _WishlistOfflineSectionState();
}

class _WishlistOfflineSectionState extends State<_WishlistOfflineSection> {
  late bool _expanded = !widget.hasLocalFiles;

  @override
  void didUpdateWidget(covariant _WishlistOfflineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasLocalFiles != widget.hasLocalFiles) {
      _expanded = !widget.hasLocalFiles;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalChapters = widget.groups.fold<int>(
      0,
      (total, group) => total + group.entries.length,
    );
    final localChapters = widget.groups.fold<int>(
      0,
      (total, group) => total + group.localEntryCount(widget.localKeys),
    );
    final summary = widget.hasLocalFiles
        ? '$localChapters dari $totalChapters chapter sudah lokal'
        : '$totalChapters chapter menunggu download lokal';

    return Container(
      decoration: BoxDecoration(
        color: _expanded ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          TonztoonIcons.download,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wishlist offline',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(TonztoonIcons.chevronRight),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      children: [
                        for (final group in widget.groups) ...[
                          _DownloadEntryGroupTile(
                            group: group,
                            localKeys: widget.localKeys,
                            allowDelete: widget.allowDelete,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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
      floatingActionButton: allowDelete
          ? Padding(
              padding: const EdgeInsets.only(bottom: 120),
              child: FloatingActionButton(
                onPressed: () => _deleteGroup(context, ref),
                tooltip: 'Hapus semua wishlist offline',
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
                shape: const CircleBorder(),
                child: const Icon(TonztoonIcons.trash),
              ),
            )
          : null,
    );
  }

  Future<void> _deleteGroup(BuildContext context, WidgetRef ref) async {
    final confirmed = await showTonztoonAsyncConfirmDialog(
      context,
      title: 'Hapus semua wishlist offline',
      message: 'Hapus semua ${group.entries.length} wishlist offline untuk komik "${group.comic.title}"?',
      helperText: 'Status wishlist akan dihapus. File lokal yang sudah tersedia di perangkat tidak ikut terhapus.',
      helperIcon: TonztoonIcons.trash,
      cancelLabel: 'Batal',
      confirmLabel: 'Hapus Semua',
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.trash,
      onConfirm: () async {
        for (final entry in group.entries) {
          await ref.read(libraryRepositoryProvider).deleteDownloadEntry(entry);
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
    Navigator.of(context).pop();
    _returnToDownloadsAfterDelete(context, 'Semua wishlist offline dihapus.');
  }
}
