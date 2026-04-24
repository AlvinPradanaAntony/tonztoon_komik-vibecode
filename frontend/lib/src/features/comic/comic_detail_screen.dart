import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comic.dart';
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
        builder: (comic) => CustomScrollView(
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
                    ComicCover(imageUrl: comic.coverImageUrl, borderRadius: 0),
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
                        if (comic.type != null) Chip(label: Text(comic.type!)),
                        if (comic.status != null)
                          Chip(label: Text(comic.status!)),
                        if (comic.rating != null)
                          Chip(label: Text('Rating ${comic.rating}')),
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
                            .map((genre) => InputChip(label: Text(genre.name)))
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
                          context.push(
                            '/reader/$sourceName/$slug/${formatChapterNumber(chapter)}',
                          );
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
                          context.push(
                            '/reader/$sourceName/$slug/${formatChapterNumber(chapter)}',
                          );
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Read'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.bookmark_outline),
                          label: const Text('Bookmark'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download'),
                        ),
                      ],
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
                    subtitle: Text(
                      [
                        '${chapter.totalImages} pages',
                        if (isLastRead &&
                            progressItem?.lastReadPageItemIndex != null &&
                            progressItem?.totalPageItems != null)
                          '${progressItem!.lastReadPageItemIndex! + 1}/${progressItem.totalPageItems}',
                      ].join(' • '),
                    ),
                    trailing: isLastRead ? const Icon(Icons.history) : null,
                    onTap: () => context.push(
                      '/reader/$sourceName/$slug/${formatChapterNumber(chapter.chapterNumber)}',
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
        ),
      ),
    );
  }

  double? _firstReadableChapter(List<ChapterListItem>? chapters) {
    if (chapters == null || chapters.isEmpty) return null;
    return chapters.last.chapterNumber;
  }
}
