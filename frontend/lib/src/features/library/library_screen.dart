import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Bookmarks'),
              Tab(text: 'Collections'),
              Tab(text: 'Scenes'),
              Tab(text: 'History'),
              Tab(text: 'Downloads'),
            ],
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
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final comic = items[index];
                return _ComicRefTile(comic: comic);
              },
              separatorBuilder: (context, index) => const Divider(height: 20),
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
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final collection = items[index];
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.folder_outlined),
                  ),
                  title: Text(collection.name),
                  subtitle: Text('${collection.totalItems} comics'),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 20),
              itemCount: items.length,
            ),
    );
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
              padding: const EdgeInsets.all(16),
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
                          child: ColoredBox(
                            color: Colors.black54,
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
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ComicCover(
                    imageUrl: item.coverImageUrl,
                    width: 52,
                    height: 72,
                  ),
                  title: Text(item.comicTitle),
                  subtitle: Text(
                    'Chapter ${formatChapterNumber(item.chapterNumber)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/reader/${item.sourceName}/${item.comicSlug}/${formatChapterNumber(item.chapterNumber)}',
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 20),
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
    return AppAsyncView<List<DownloadEntry>>(
      value: ref.watch(downloadsProvider),
      onRetry: () => ref.invalidate(downloadsProvider),
      builder: (items) => items.isEmpty
          ? const _LibraryEmpty(message: 'No download wishlist yet.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ComicCover(
                    imageUrl: item.comic.coverImageUrl,
                    width: 52,
                    height: 72,
                  ),
                  title: Text(item.comic.title),
                  subtitle: Text(
                    'Chapter ${formatChapterNumber(item.chapterNumber)} • ${item.status}',
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 20),
              itemCount: items.length,
            ),
    );
  }
}

class _ComicRefTile extends StatelessWidget {
  const _ComicRefTile({required this.comic});

  final LibraryComicRef comic;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ComicCover(imageUrl: comic.coverImageUrl, width: 52, height: 72),
      title: Text(comic.title),
      subtitle: Text(
        [
          comic.sourceName,
          if (comic.type != null) comic.type!,
          if (comic.status != null) comic.status!,
        ].join(' • '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/comic/${comic.sourceName}/${comic.slug}'),
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
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
