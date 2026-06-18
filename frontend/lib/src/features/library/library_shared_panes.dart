import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/app_icons.dart';
import '../../core/app_navigation.dart';
import '../../helpers/app_snackbar.dart';
import '../../helpers/navigation_helpers.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import 'library_error.dart';
import 'widgets/library_async_pane.dart';

part 'panes/offline_pane_scaffold.dart';
part 'panes/offline_groups.dart';
part 'panes/scene_widgets.dart';
part 'panes/offline_chapter_widgets.dart';
part 'panes/download_entry_widgets.dart';
part 'panes/offline_actions.dart';

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
