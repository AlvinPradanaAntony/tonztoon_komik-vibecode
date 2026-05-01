import 'package:flutter/material.dart';
import '../../core/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comic.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/comic_cover.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: SearchBar(
              autoFocus: false,
              leading: const Icon(TonztoonIcons.search),
              hintText: 'Search title or author',
              onChanged: (value) =>
                  ref.read(searchQueryProvider.notifier).setQuery(value),
            ),
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchEmpty(
                    icon: TonztoonIcons.manageSearch,
                    message: 'Search across all comic sources.',
                  )
                : AppAsyncView<List<ComicSummary>>(
                    value: results,
                    onRetry: () => ref.invalidate(searchResultsProvider),
                    builder: (items) => items.isEmpty
                        ? const _SearchEmpty(
                            icon: TonztoonIcons.searchOff,
                            message: 'No comics found.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            itemBuilder: (context, index) {
                              final comic = items[index];
                              return _SearchResultTile(
                                comic: comic,
                                onTap: () => context.push(
                                  '/comic/${comic.sourceName}/${comic.slug}',
                                ),
                              );
                            },
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemCount: items.length,
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.comic, required this.onTap});

  final ComicSummary comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final meta = [
      comic.sourceName,
      if (comic.type != null) comic.type!,
      if (comic.latestChapterNumber != null)
        'Ch ${formatChapterNumber(comic.latestChapterNumber!)}',
    ].join(' • ');

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
              ComicCover(imageUrl: comic.coverImageUrl, width: 58, height: 82),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                TonztoonIcons.chevronRight,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.icon, required this.message});

  final IconData icon;
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
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(icon, size: 38),
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
