import 'package:flutter/material.dart';
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
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              autoFocus: false,
              leading: const Icon(Icons.search),
              hintText: 'Search title or author',
              onChanged: (value) =>
                  ref.read(searchQueryProvider.notifier).setQuery(value),
            ),
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchEmpty(
                    icon: Icons.manage_search,
                    message: 'Search across all comic sources.',
                  )
                : AppAsyncView<List<ComicSummary>>(
                    value: results,
                    onRetry: () => ref.invalidate(searchResultsProvider),
                    builder: (items) => items.isEmpty
                        ? const _SearchEmpty(
                            icon: Icons.search_off,
                            message: 'No comics found.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemBuilder: (context, index) {
                              final comic = items[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ComicCover(
                                  imageUrl: comic.coverImageUrl,
                                  width: 52,
                                  height: 72,
                                ),
                                title: Text(comic.title),
                                subtitle: Text(
                                  [
                                    comic.sourceName,
                                    if (comic.type != null) comic.type!,
                                    if (comic.latestChapterNumber != null)
                                      'Ch ${formatChapterNumber(comic.latestChapterNumber!)}',
                                  ].join(' • '),
                                ),
                                onTap: () => context.push(
                                  '/comic/${comic.sourceName}/${comic.slug}',
                                ),
                              );
                            },
                            separatorBuilder: (context, index) =>
                                const Divider(height: 20),
                            itemCount: items.length,
                          ),
                  ),
          ),
        ],
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
            Icon(icon, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
