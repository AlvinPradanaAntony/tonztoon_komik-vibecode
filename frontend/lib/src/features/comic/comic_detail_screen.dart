import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comic.dart';
import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/comic_cover.dart';

class ComicDetailScreen extends ConsumerWidget {
  const ComicDetailScreen({
    super.key,
    required this.sourceName,
    required this.slug,
  });

  final String sourceName;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ComicRequest(sourceName, slug);
    final detail = ref.watch(comicDetailProvider(request));
    final chapters = ref.watch(chaptersProvider(request));
    final progress = ref.watch(progressProvider(request));

    return Scaffold(
      body: AppAsyncView<ComicDetail>(
        value: detail,
        onRetry: () {
          ref.invalidate(comicDetailProvider(request));
          ref.invalidate(chaptersProvider(request));
        },
        builder: (comic) {
          final comicSummary = comic.toSummary();
          final libraryState = ref.watch(
            libraryComicStateProvider(comicSummary),
          );

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 320,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    comic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      ComicCover(
                        imageUrl: comic.coverImageUrl,
                        borderRadius: 0,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xEE111318)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (comic.type != null)
                            Chip(label: Text(_toSentenceCase(comic.type!))),
                          if (comic.status != null)
                            Chip(label: Text(_toSentenceCase(comic.status!))),
                          if (comic.rating != null)
                            Chip(
                              avatar: const Icon(Icons.star, size: 18),
                              label: Text(_formatRating(comic.rating!)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (comic.author != null)
                        Text(
                          'Author: ${comic.author!}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (comic.artist != null)
                        Text(
                          'Artist: ${comic.artist!}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        comic.synopsis?.trim().isNotEmpty == true
                            ? comic.synopsis!
                            : 'No synopsis available.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      if (comic.genres.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: comic.genres
                              .map(
                                (genre) => InputChip(label: Text(genre.name)),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 20),
                      progress.when(
                        data: (item) => FilledButton.icon(
                          onPressed: () {
                            final chapter =
                                item?.chapterNumber ??
                                _firstReadableChapter(chapters.asData?.value);
                            if (chapter == null) return;
                            _openReader(context, ref, request, chapter);
                          },
                          icon: Icon(
                            item == null
                                ? Icons.play_arrow
                                : Icons.play_circle_outline,
                          ),
                          label: Text(item == null ? 'Read' : 'Continue'),
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => FilledButton.icon(
                          onPressed: () {
                            final chapter = _firstReadableChapter(
                              chapters.asData?.value,
                            );
                            if (chapter == null) return;
                            _openReader(context, ref, request, chapter);
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Read'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      libraryState.when(
                        data: (state) => _DetailActions(
                          state: state,
                          onBookmark: () => _toggleBookmark(
                            context,
                            ref,
                            comicSummary,
                            state.bookmarked,
                          ),
                          onCollections: () => _showCollectionPicker(
                            context,
                            ref,
                            comicSummary,
                            state,
                          ),
                          onDownload: () => _enqueueDownload(
                            context,
                            ref,
                            comicSummary,
                            chapters.asData?.value,
                          ),
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => _DetailActions(
                          state: LibraryComicState(
                            comic: LibraryComicRef.fromSummary(comicSummary),
                            bookmarked: false,
                            collections: const [],
                          ),
                          onBookmark: () => _toggleBookmark(
                            context,
                            ref,
                            comicSummary,
                            false,
                          ),
                          onCollections: () => _showCollectionPicker(
                            context,
                            ref,
                            comicSummary,
                            const LibraryComicState(
                              comic: LibraryComicRef(
                                sourceName: '',
                                slug: '',
                                title: '',
                              ),
                              bookmarked: false,
                              collections: [],
                            ),
                          ),
                          onDownload: () => _enqueueDownload(
                            context,
                            ref,
                            comicSummary,
                            chapters.asData?.value,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Chapters',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
              chapters.when(
                data: (items) => SliverList.builder(
                  itemBuilder: (context, index) {
                    final chapter = items[index];
                    final progressItem = progress.asData?.value;
                    final isLastRead =
                        progressItem?.chapterNumber == chapter.chapterNumber;
                    final subtitleParts = [
                      if (chapter.totalImages > 0)
                        '${chapter.totalImages} pages',
                      if (isLastRead &&
                          progressItem?.lastReadPageItemIndex != null &&
                          progressItem?.totalPageItems != null)
                        '${progressItem!.lastReadPageItemIndex! + 1}/${progressItem.totalPageItems}',
                    ];
                    return ListTile(
                      selected: isLastRead,
                      leading: CircleAvatar(
                        child: Text(formatChapterNumber(chapter.chapterNumber)),
                      ),
                      title: Text(
                        chapter.title?.isNotEmpty == true
                            ? chapter.title!
                            : 'Chapter ${formatChapterNumber(chapter.chapterNumber)}',
                      ),
                      subtitle: subtitleParts.isEmpty
                          ? null
                          : Text(subtitleParts.join(' • ')),
                      trailing: isLastRead ? const Icon(Icons.history) : null,
                      onTap: () => _openReader(
                        context,
                        ref,
                        request,
                        chapter.chapterNumber,
                      ),
                    );
                  },
                  itemCount: items.length,
                ),
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, stackTrace) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error.toString()),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double? _firstReadableChapter(List<ChapterListItem>? chapters) {
    if (chapters == null || chapters.isEmpty) return null;
    return chapters.last.chapterNumber;
  }

  String _formatRating(double rating) {
    return rating == rating.roundToDouble()
        ? rating.toStringAsFixed(0)
        : rating.toString();
  }

  String _toSentenceCase(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[_-]+'), ' ');
    if (normalized.isEmpty) return normalized;
    final lower = normalized.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  Future<void> _openReader(
    BuildContext context,
    WidgetRef ref,
    ComicRequest request,
    double chapterNumber,
  ) async {
    await context.push(
      '/reader/$sourceName/$slug/${formatChapterNumber(chapterNumber)}',
    );
    if (!context.mounted) return;
    _refreshChapterState(ref, request);

    // Nearby prefetch berjalan di backend secara background dan bisa selesai
    // beberapa detik setelah user kembali dari reader.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (context.mounted) _refreshChapterState(ref, request);
    });
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (context.mounted) _refreshChapterState(ref, request);
    });
  }

  void _refreshChapterState(WidgetRef ref, ComicRequest request) {
    ref.invalidate(chaptersProvider(request));
    ref.invalidate(progressProvider(request));
  }

  Future<void> _toggleBookmark(
    BuildContext context,
    WidgetRef ref,
    ComicSummary comic,
    bool bookmarked,
  ) async {
    try {
      await ref
          .read(libraryRepositoryProvider)
          .toggleBookmark(comic, bookmarked);
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(bookmarksProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bookmarked ? 'Bookmark removed.' : 'Bookmarked.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _showCollectionPicker(
    BuildContext context,
    WidgetRef ref,
    ComicSummary comic,
    LibraryComicState state,
  ) async {
    final repo = ref.read(libraryRepositoryProvider);
    var collections = await repo.getCollections();
    final selected = state.collections.map((item) => item.id).toSet();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Collections',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final created = await _createCollectionDialog(
                            context,
                            repo,
                          );
                          if (created == null) return;
                          collections = await repo.getCollections();
                          selected.add(created.id);
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                  Flexible(
                    child: collections.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No collections yet.'),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: collections
                                .map(
                                  (collection) => CheckboxListTile(
                                    value: selected.contains(collection.id),
                                    title: Text(collection.name),
                                    subtitle: Text(
                                      '${collection.totalItems} comics',
                                    ),
                                    onChanged: (checked) {
                                      if (checked == true) {
                                        selected.add(collection.id);
                                      } else {
                                        selected.remove(collection.id);
                                      }
                                      setSheetState(() {});
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await repo.setComicCollections(comic, selected);
                        ref.invalidate(collectionsProvider);
                        ref.invalidate(libraryComicStateProvider(comic));
                        if (context.mounted) context.pop();
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<CollectionDetail?> _createCollectionDialog(
    BuildContext context,
    dynamic repo,
  ) async {
    final controller = TextEditingController();
    try {
      return showDialog<CollectionDetail>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create Collection'),
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
              onPressed: () async {
                try {
                  final created = await repo.createCollection(controller.text);
                  if (context.mounted) context.pop(created);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _enqueueDownload(
    BuildContext context,
    WidgetRef ref,
    ComicSummary comic,
    List<ChapterListItem>? chapters,
  ) async {
    if (chapters == null || chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter list is still loading.')),
      );
      return;
    }
    try {
      await ref
          .read(libraryRepositoryProvider)
          .enqueueDownloadBatch(
            comic,
            chapters.map((item) => item.chapterNumber).toList(),
          );
      ref.invalidate(downloadsProvider);
      ref.invalidate(libraryComicStateProvider(comic));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download wishlist queued.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.state,
    required this.onBookmark,
    required this.onCollections,
    required this.onDownload,
  });

  final LibraryComicState state;
  final VoidCallback onBookmark;
  final VoidCallback onCollections;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onBookmark,
          icon: Icon(
            state.bookmarked ? Icons.bookmark : Icons.bookmark_outline,
          ),
          label: Text(state.bookmarked ? 'Bookmarked' : 'Bookmark'),
        ),
        OutlinedButton.icon(
          onPressed: onCollections,
          icon: const Icon(Icons.folder_copy_outlined),
          label: Text(
            state.collections.isEmpty
                ? 'Collection'
                : '${state.collections.length} Collections',
          ),
        ),
        OutlinedButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.download_outlined),
          label: state.downloadStatusCounts.isEmpty
              ? const Text('Download')
              : Text(
                  '${state.downloadStatusCounts.values.fold<int>(0, (a, b) => a + b)} Queued',
                ),
        ),
      ],
    );
  }
}
