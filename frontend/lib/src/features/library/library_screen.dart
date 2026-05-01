import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/comic_cover.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(52),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                tabs: [
                  Tab(text: 'Bookmarks'),
                  Tab(text: 'Collections'),
                  Tab(text: 'Scenes'),
                  Tab(text: 'History'),
                  Tab(text: 'Downloads'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _BookmarksTab(ref: ref),
            _CollectionsTab(ref: ref),
            _ScenesTab(ref: ref),
            _HistoryTab(ref: ref),
            _DownloadsTab(ref: ref),
          ],
        ),
      ),
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return AppAsyncView<List<LibraryComicRef>>(
      value: ref.watch(bookmarksProvider),
      onRetry: () => ref.invalidate(bookmarksProvider),
      builder: (items) => items.isEmpty
          ? const _LibraryEmpty(message: 'No bookmarks yet.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemBuilder: (context, index) {
                final comic = items[index];
                return _ComicRefTile(comic: comic);
              },
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemCount: items.length,
            ),
    );
  }
}

class _CollectionsTab extends StatelessWidget {
  const _CollectionsTab({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return AppAsyncView<List<CollectionSummary>>(
      value: ref.watch(collectionsProvider),
      onRetry: () => ref.invalidate(collectionsProvider),
      builder: (items) => items.isEmpty
          ? const _LibraryEmpty(message: 'No collections yet.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemBuilder: (context, index) {
                final collection = items[index];
                return _SurfaceTile(
                  leading: const _TileIcon(icon: TonztoonIcons.folder),
                  title: collection.name,
                  subtitle: '${collection.totalItems} comics',
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(TonztoonIcons.moreHoriz),
                    onSelected: (value) {
                      if (value == 'rename') {
                        _renameCollection(context, ref, collection);
                      } else if (value == 'delete') {
                        _deleteCollection(context, ref, collection);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemCount: items.length,
            ),
    );
  }

  Future<void> _renameCollection(
    BuildContext context,
    WidgetRef ref,
    CollectionSummary collection,
  ) async {
    final controller = TextEditingController(text: collection.name);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename Collection'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name == null) return;
      await ref
          .read(libraryRepositoryProvider)
          .renameCollection(collection.id, name);
      ref.invalidate(collectionsProvider);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteCollection(
    BuildContext context,
    WidgetRef ref,
    CollectionSummary collection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection'),
        content: Text('Delete "${collection.name}"?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(libraryRepositoryProvider).deleteCollection(collection.id);
    ref.invalidate(collectionsProvider);
  }
}

class _ScenesTab extends StatelessWidget {
  const _ScenesTab({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return AppAsyncView<List<FavoriteScene>>(
      value: ref.watch(favoriteScenesProvider),
      onRetry: () => ref.invalidate(favoriteScenesProvider),
      builder: (items) => items.isEmpty
          ? const _LibraryEmpty(message: 'No favorite scenes saved.')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, index) {
                final scene = items[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push(
                    '/reader/${scene.comic.sourceName}/${scene.comic.slug}/${formatChapterNumber(scene.chapterNumber)}',
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (scene.imageUrl == null)
                          const ColoredBox(color: Color(0xFF22252B))
                        else
                          CachedNetworkImage(
                            imageUrl: scene.imageUrl!,
                            fit: BoxFit.cover,
                          ),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.64),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                '${scene.comic.title}\nPage ${scene.pageItemIndex + 1}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              itemCount: items.length,
            ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return AppAsyncView<List<ReadingProgress>>(
      value: ref.watch(historyProvider),
      onRetry: () => ref.invalidate(historyProvider),
      builder: (items) => items.isEmpty
          ? const _LibraryEmpty(message: 'No reading history yet.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemBuilder: (context, index) {
                final item = items[index];
                return _SurfaceTile(
                  leading: ComicCover(
                    imageUrl: item.coverImageUrl,
                    width: 54,
                    height: 76,
                  ),
                  title: item.comicTitle,
                  subtitle:
                      'Chapter ${formatChapterNumber(item.chapterNumber)}',
                  trailing: const Icon(TonztoonIcons.chevronRight),
                  onTap: () => context.push(
                    '/reader/${item.sourceName}/${item.comicSlug}/${formatChapterNumber(item.chapterNumber)}',
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemCount: items.length,
            ),
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(offlineQueueProvider);
    final offline =
        ref.watch(offlineChaptersProvider).asData?.value ?? const [];
    return AppAsyncView<List<OfflineDownloadBatch>>(
      value: queue,
      onRetry: () => ref.invalidate(offlineQueueProvider),
      builder: (batches) => batches.isEmpty && offline.isEmpty
          ? const _LibraryEmpty(message: 'No offline downloads yet.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (batches.isNotEmpty) ...[
                  Text('Queue', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final batch in batches) ...[
                    _BatchTile(batch: batch, ref: ref),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                ],
                if (offline.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Offline Chapters',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await ref
                              .read(offlineRepositoryProvider)
                              .clearAllOfflineChapters();
                          ref.invalidate(offlineChaptersProvider);
                        },
                        icon: const Icon(TonztoonIcons.deleteSweep),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final item in offline) ...[
                    _SurfaceTile(
                      leading: ComicCover(
                        imageUrl: item.comic.coverImageUrl,
                        width: 54,
                        height: 76,
                      ),
                      title: item.comic.title,
                      subtitle:
                          'Chapter ${formatChapterNumber(item.chapterNumber)} • ${item.status}',
                      trailing: IconButton(
                        tooltip: 'Delete offline chapter',
                        icon: const Icon(TonztoonIcons.deleteOutline),
                        onPressed: () async {
                          await ref
                              .read(offlineRepositoryProvider)
                              .deleteOfflineChapter(item);
                          ref.invalidate(offlineChaptersProvider);
                        },
                      ),
                      onTap: item.isCompleted
                          ? () => context.push(
                              '/reader/${item.comic.sourceName}/${item.comic.slug}/${formatChapterNumber(item.chapterNumber)}',
                            )
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.batch, required this.ref});

  final OfflineDownloadBatch batch;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final percent = (batch.progress * 100).clamp(0, 100).round();
    final currentChapter = batch.currentChapterNumber == null
        ? null
        : 'Ch ${formatChapterNumber(batch.currentChapterNumber!)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    batch.comic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('$percent%'),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              borderRadius: BorderRadius.circular(99),
              value: batch.progress,
            ),
            const SizedBox(height: 8),
            Text(
              [
                batch.status,
                '${batch.completedChapters}/${batch.totalChapters} chapters',
                ?currentChapter,
              ].join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (batch.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                batch.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (batch.canCancel)
                  FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(offlineQueueProvider.notifier)
                        .cancelBatch(batch.id),
                    icon: const Icon(TonztoonIcons.cancel),
                    label: const Text('Cancel'),
                  )
                else if (batch.canResume)
                  FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(offlineQueueProvider.notifier)
                        .resumeBatch(batch.id),
                    icon: const Icon(TonztoonIcons.playArrow),
                    label: const Text('Resume'),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove batch',
                  onPressed: batch.canCancel
                      ? null
                      : () => ref
                            .read(offlineQueueProvider.notifier)
                            .deleteBatch(batch.id),
                  icon: const Icon(TonztoonIcons.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicRefTile extends StatelessWidget {
  const _ComicRefTile({required this.comic});

  final LibraryComicRef comic;

  @override
  Widget build(BuildContext context) {
    return _SurfaceTile(
      leading: ComicCover(imageUrl: comic.coverImageUrl, width: 54, height: 76),
      title: comic.title,
      subtitle: [
        comic.sourceName,
        if (comic.type != null) comic.type!,
        if (comic.status != null) comic.status!,
      ].join(' • '),
      trailing: const Icon(TonztoonIcons.chevronRight),
      onTap: () => context.push('/comic/${comic.sourceName}/${comic.slug}'),
    );
  }
}

class _SurfaceTile extends StatelessWidget {
  const _SurfaceTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: colorScheme.primary),
      ),
    );
  }
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Icon(TonztoonIcons.libraryBooks, size: 36),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
