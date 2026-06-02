import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_error.dart';
import '../../core/app_icons.dart';
import '../../core/app_navigation.dart';
import '../../core/app_snackbar.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import 'library_error.dart';

class FavoriteScenesPane extends ConsumerWidget {
  const FavoriteScenesPane({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 132),
    this.allowDelete = true,
  });

  final EdgeInsetsGeometry padding;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenesAsync = ref.watch(favoriteScenesProvider);

    return _AsyncPane<List<FavoriteScene>>(
      value: scenesAsync,
      onRefresh: () => refreshFavoriteScenes(ref),
      onRetry: () => ref.invalidate(favoriteScenesProvider),
      builder: (scenes) {
        if (scenes.isEmpty) {
          return _LibraryList(
            padding: padding,
            onRefresh: () => refreshFavoriteScenes(ref),
            children: const [
              _EmptyState(
                icon: TonztoonIcons.heart,
                title: 'Belum ada scene favorit',
                message:
                    'Tandai panel favorit dari reader untuk melihatnya lagi.',
              ),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: () => refreshFavoriteScenes(ref),
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            itemCount: scenes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) =>
                _SceneCard(scene: scenes[index], allowDelete: allowDelete),
          ),
        );
      },
    );
  }
}

class OfflineDownloadsPane extends ConsumerWidget {
  const OfflineDownloadsPane({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 132),
    this.readyOnly = false,
    this.allowDelete = true,
  });

  final EdgeInsetsGeometry padding;
  final bool readyOnly;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineAsync = ref.watch(offlineChaptersProvider);

    final offline = offlineAsync.asData?.value ?? const <OfflineChapter>[];
    if (readyOnly) {
      return _readyOnlyPane(ref, offlineAsync, offline);
    }

    final queueAsync = ref.watch(offlineQueueProvider);
    final downloadsAsync = ref.watch(downloadsProvider);

    if (queueAsync.isLoading && !queueAsync.hasValue) {
      return const _LoadingPane();
    }
    if (offlineAsync.isLoading && !offlineAsync.hasValue) {
      return const _LoadingPane();
    }
    if (downloadsAsync.isLoading && !downloadsAsync.hasValue) {
      return const _LoadingPane();
    }

    final error =
        queueAsync.error ?? offlineAsync.error ?? downloadsAsync.error;
    final hasData =
        queueAsync.hasValue || offlineAsync.hasValue || downloadsAsync.hasValue;
    if (error != null && !hasData) {
      return _LibraryList(
        padding: padding,
        onRefresh: () => refreshDownloads(ref),
        children: [
          _ErrorPane(error: error, onRetry: () => refreshDownloads(ref)),
        ],
      );
    }

    final queue = queueAsync.asData?.value ?? const <OfflineDownloadBatch>[];
    final downloads = downloadsAsync.asData?.value ?? const <DownloadEntry>[];
    final visibleQueue = queue
        .where(
          (item) => item.status != 'completed' && item.status != 'cancelled',
        )
        .toList();
    final activeQueueCount = visibleQueue
        .where(
          (item) => item.status == 'pending' || item.status == 'downloading',
        )
        .length;
    return _LibraryList(
      padding: padding,
      children: _libraryDownloadChildren(
        visibleQueue,
        activeQueueCount,
        offline,
        downloads,
      ),
      onRefresh: () => refreshDownloads(ref),
    );
  }

  Widget _readyOnlyPane(
    WidgetRef ref,
    AsyncValue<List<OfflineChapter>> offlineAsync,
    List<OfflineChapter> offline,
  ) {
    if (offlineAsync.isLoading && !offlineAsync.hasValue) {
      return const _LoadingPane();
    }
    final error = offlineAsync.error;
    if (error != null && !offlineAsync.hasValue) {
      return _LibraryList(
        padding: padding,
        onRefresh: () => refreshReadyDownloads(ref),
        children: [
          _ErrorPane(error: error, onRetry: () => refreshReadyDownloads(ref)),
        ],
      );
    }

    final readyOffline = offline
        .where((chapter) => chapter.isCompleted)
        .toList();
    return _LibraryList(
      padding: padding,
      children: _readyOfflineChildren(readyOffline),
      onRefresh: () => refreshReadyDownloads(ref),
    );
  }

  List<Widget> _readyOfflineChildren(List<OfflineChapter> readyOffline) {
    final groups = _groupOfflineChaptersByComic(readyOffline);
    return [
      _SectionHeader(
        icon: TonztoonIcons.download,
        title: 'Comic/Chapter Offline',
        trailing: '${groups.length} komik',
      ),
      const SizedBox(height: 10),
      if (readyOffline.isEmpty)
        const _EmptyState(
          icon: TonztoonIcons.download,
          title: 'Belum ada unduhan offline yang tersedia',
          message: 'Download chapter dari Pustaka agar bisa dibaca offline.',
        )
      else
        for (final group in groups) ...[
          _OfflineChapterGroupTile(group: group, allowDelete: allowDelete),
          const SizedBox(height: 12),
        ],
    ];
  }

  List<Widget> _libraryDownloadChildren(
    List<OfflineDownloadBatch> visibleQueue,
    int activeQueueCount,
    List<OfflineChapter> offline,
    List<DownloadEntry> downloads,
  ) {
    final readyOffline = offline
        .where((chapter) => chapter.isCompleted)
        .toList();
    final localKeys = readyOffline.map(_offlineChapterKey).toSet();
    final localGroups = _groupOfflineChaptersByComic(readyOffline);
    final downloadGroups = _groupDownloadEntriesByComic(downloads);

    return [
      _SectionHeader(
        icon: TonztoonIcons.download,
        title: 'Unduhan offline',
        trailing: '$activeQueueCount aktif',
      ),
      const SizedBox(height: 10),
      if (visibleQueue.isEmpty && readyOffline.isEmpty && downloads.isEmpty)
        const _EmptyState(
          icon: TonztoonIcons.download,
          title: 'Belum ada unduhan',
          message: 'Download chapter dari halaman detail untuk mode offline.',
        )
      else ...[
        if (visibleQueue.isNotEmpty) ...[
          const _SubHeader(title: 'Antrean unduhan'),
          const SizedBox(height: 8),
          for (final batch in visibleQueue) ...[
            _OfflineBatchTile(batch: batch),
            const SizedBox(height: 12),
          ],
        ],
        if (readyOffline.isNotEmpty) ...[
          const _SubHeader(title: 'File lokal'),
          const SizedBox(height: 8),
          for (final group in localGroups) ...[
            _OfflineChapterGroupTile(group: group, allowDelete: allowDelete),
            const SizedBox(height: 12),
          ],
        ],
        if (downloads.isNotEmpty) ...[
          const _SubHeader(title: 'Wishlist offline'),
          const SizedBox(height: 8),
          for (final group in downloadGroups) ...[
            _DownloadEntryGroupTile(
              group: group,
              localKeys: localKeys,
              allowDelete: allowDelete,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
      const _OfflineHint(),
    ];
  }
}

List<_OfflineChapterGroup> _groupOfflineChaptersByComic(
  List<OfflineChapter> chapters,
) {
  final groups = <String, _OfflineChapterGroup>{};
  for (final chapter in chapters) {
    final key = chapter.comic.key;
    groups.putIfAbsent(key, () => _OfflineChapterGroup(comic: chapter.comic));
    groups[key]!.chapters.add(chapter);
  }
  for (final group in groups.values) {
    group.chapters.sort((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
  }
  return groups.values.toList();
}

List<_DownloadEntryGroup> _groupDownloadEntriesByComic(
  List<DownloadEntry> entries,
) {
  final groups = <String, _DownloadEntryGroup>{};
  for (final entry in entries) {
    final key = entry.comic.key;
    groups.putIfAbsent(key, () => _DownloadEntryGroup(comic: entry.comic));
    groups[key]!.entries.add(entry);
  }
  for (final group in groups.values) {
    group.entries.sort((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
  }
  return groups.values.toList();
}

class _OfflineChapterGroup {
  _OfflineChapterGroup({required this.comic});

  final LibraryComicRef comic;
  final List<OfflineChapter> chapters = [];

  int get readyCount => chapters.where((chapter) => chapter.isCompleted).length;
}

class _DownloadEntryGroup {
  _DownloadEntryGroup({required this.comic});

  final LibraryComicRef comic;
  final List<DownloadEntry> entries = [];
}

String _offlineChapterKey(OfflineChapter chapter) {
  return '${chapter.comic.key}|${chapter.chapterNumber}';
}

String _downloadEntryKey(DownloadEntry entry) {
  return '${entry.comic.key}|${entry.chapterNumber}';
}

OfflineDownloadBatch? _queuedBatchForEntry(
  DownloadEntry entry,
  List<OfflineDownloadBatch> batches,
) {
  for (final status in const ['downloading', 'pending', 'paused', 'failed']) {
    for (final batch in batches) {
      if (batch.status == status &&
          batch.comic.key == entry.comic.key &&
          batch.chapterNumbers.contains(entry.chapterNumber)) {
        return batch;
      }
    }
  }
  return null;
}

double _queuedChapterProgress(DownloadEntry entry, OfflineDownloadBatch batch) {
  final chapterIndex = batch.chapterNumbers.indexOf(entry.chapterNumber);
  if (chapterIndex < 0 || batch.totalChapters <= 0) return 0;
  return (batch.progress * batch.totalChapters - chapterIndex)
      .clamp(0, 1)
      .toDouble();
}

Future<void> refreshFavoriteScenes(WidgetRef ref) async {
  ref.invalidate(favoriteScenesProvider);
  await ref.read(favoriteScenesProvider.future);
}

Future<void> refreshDownloads(WidgetRef ref) async {
  ref.invalidate(downloadsProvider);
  ref.invalidate(offlineChaptersProvider);
  ref.invalidate(offlineQueueProvider);
  await Future.wait([
    ref.read(downloadsProvider.future),
    ref.read(offlineChaptersProvider.future),
    ref.read(offlineQueueProvider.future),
  ]);
}

Future<void> refreshReadyDownloads(WidgetRef ref) async {
  ref.invalidate(offlineChaptersProvider);
  await ref.read(offlineChaptersProvider.future);
}

class _AsyncPane<T> extends StatelessWidget {
  const _AsyncPane({
    required this.value,
    required this.builder,
    required this.onRefresh,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => const _LoadingPane(),
      error: (error, stackTrace) => _LibraryList(
        onRefresh: onRefresh,
        children: [_ErrorPane(error: error, onRetry: onRetry)],
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 132),
    this.onRefresh = _noopRefresh,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _refreshWithSnackBar(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: children,
      ),
    );
  }

  Future<void> _refreshWithSnackBar(BuildContext context) async {
    try {
      await onRefresh();
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Refresh offline data failed',
        fallbackMessage: 'Gagal memperbarui data offline. Silakan coba lagi.',
      );
    }
  }
}

Future<void> _noopRefresh() async {}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();

  @override
  Widget build(BuildContext context) {
    return const AppPageLoadingPlaceholder();
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(
              friendlyErrorMessage(
                error,
                fallbackMessage:
                    'Gagal memuat data offline. Silakan coba lagi.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _SceneCard extends ConsumerWidget {
  const _SceneCard({required this.scene, required this.allowDelete});

  final FavoriteScene scene;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showScenePreview(context, scene),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ComicCover(imageUrl: scene.imageUrl, borderRadius: 0),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: List.generate(9, (index) {
                      final p = index / 8;
                      return Colors.black.withValues(
                        alpha: math.pow(p, 1.5).toDouble(),
                      );
                    }),
                  ),
                ),
              ),
              if (allowDelete)
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    tooltip: 'Hapus scene',
                    onPressed: () => _deleteScene(context, ref),
                    icon: const Icon(TonztoonIcons.trash, size: 18),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scene.comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Ch ${formatChapterNumber(scene.chapterNumber)} - Page ${scene.pageItemIndex + 1}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteScene(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(libraryRepositoryProvider).deleteFavoriteScene(scene.id);
      ref.invalidate(favoriteScenesProvider);
      if (context.mounted) _showMessage(context, 'Scene favorit dihapus.');
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }
}

Future<void> _showScenePreview(BuildContext context, FavoriteScene scene) {
  final comic = scene.comic.toSummary();
  final chapterLabel = formatChapterNumber(scene.chapterNumber);

  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);

      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: scene.imageUrl == null || scene.imageUrl!.isEmpty
                      ? const Icon(
                          Icons.broken_image_rounded,
                          size: 56,
                          color: Colors.white54,
                        )
                      : Image.network(
                          scene.imageUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.cloud_off_rounded,
                              size: 56,
                              color: Colors.white54,
                            );
                          },
                        ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(TonztoonIcons.close),
                        color: Colors.white,
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: List.generate(9, (index) {
                      final p = index / 8;
                      return Colors.black.withValues(
                        alpha: math.pow(p, 1.5).toDouble(),
                      );
                    }),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scene.comic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chapter $chapterLabel - Page ${scene.pageItemIndex + 1}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.76),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _openComicDetail(context, comic);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                                icon: const Icon(TonztoonIcons.bookOpen),
                                label: const Text('Detail'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _openSceneReader(context, scene);
                                },
                                icon: const Icon(TonztoonIcons.play),
                                label: const Text('Baca dari scene'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Icon(icon, size: 34, color: colorScheme.secondary),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

void _openSceneReader(BuildContext context, FavoriteScene scene) {
  final comic = scene.comic.toSummary();
  context.push(
    '/reader/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}/${formatChapterNumber(scene.chapterNumber)}',
    extra: comic,
  );
}

void _openOfflineChapter(BuildContext context, OfflineChapter chapter) {
  context.push(
    '/reader/${Uri.encodeComponent(chapter.comic.sourceName)}/${Uri.encodeComponent(chapter.comic.slug)}/${formatChapterNumber(chapter.chapterNumber)}',
    extra: chapter.comic.toSummary(),
  );
}

void _showMessage(BuildContext context, String message) {
  showAppSnackBar(
    context,
    message: message,
    type: AppSnackBarType.success,
    hideCurrent: false,
  );
}

void _returnToDownloadsAfterDelete(BuildContext context, String message) {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  _showMessage(context, message);
  navigator.popUntil((route) => route.isFirst);
  router.go(libraryDownloadsLocation);
}

Future<void> _reloadDownloadsAfterDelete(WidgetRef ref) async {
  ref.invalidate(downloadsProvider);
  ref.invalidate(offlineChaptersProvider);
  ref.invalidate(librarySummaryProvider);
  await Future.wait([
    ref.read(downloadsProvider.future),
    ref.read(offlineChaptersProvider.future),
    ref.read(librarySummaryProvider.future),
  ]);
}
