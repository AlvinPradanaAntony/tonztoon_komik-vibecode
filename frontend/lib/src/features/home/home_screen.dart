import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comic.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restored) {
      _restored = true;
      Future.microtask(
        () => ref.read(authControllerProvider.notifier).restore(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeDataProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TonzToon'),
        actions: [
          IconButton(
            tooltip: auth.isAuthenticated ? 'Account' : 'Login',
            onPressed: () => context.push('/auth'),
            icon: Icon(
              auth.isAuthenticated
                  ? Icons.account_circle
                  : Icons.account_circle_outlined,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeDataProvider);
          await ref.read(homeDataProvider.future);
        },
        child: AppAsyncView<HomeData>(
          value: home,
          onRetry: () => ref.invalidate(homeDataProvider),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Discover',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  DropdownButton<String>(
                    value: data.selectedSource.id,
                    items: data.sources
                        .map(
                          (source) => DropdownMenuItem(
                            value: source.id,
                            child: Text(source.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      ref.read(selectedSourceProvider.notifier).select(value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (data.continueReading.isNotEmpty) ...[
                _SectionTitle(
                  title: 'Continue Reading',
                  actionLabel: '${data.continueReading.length}',
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) =>
                        _ProgressCard(progress: data.continueReading[index]),
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemCount: data.continueReading.length,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              _ComicRail(title: 'New Releases', comics: data.latest),
              const SizedBox(height: 24),
              _ComicRail(title: 'Popular', comics: data.popular),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel});

  final String title;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          Text(actionLabel!, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _ComicRail extends StatelessWidget {
  const _ComicRail({required this.title, required this.comics});

  final String title;
  final List<ComicSummary> comics;

  @override
  Widget build(BuildContext context) {
    if (comics.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 10),
        SizedBox(
          height: 244,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final comic = comics[index];
              return ComicCard(
                comic: comic,
                onTap: () =>
                    context.push('/comic/${comic.sourceName}/${comic.slug}'),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemCount: comics.length,
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ReadingProgress progress;

  @override
  Widget build(BuildContext context) {
    final pageText =
        progress.lastReadPageItemIndex == null ||
            progress.totalPageItems == null
        ? 'Chapter ${formatChapterNumber(progress.chapterNumber)}'
        : '${progress.lastReadPageItemIndex! + 1}/${progress.totalPageItems}';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(
        '/reader/${progress.sourceName}/${progress.comicSlug}/${formatChapterNumber(progress.chapterNumber)}',
      ),
      child: SizedBox(
        width: 260,
        child: Row(
          children: [
            ComicCover(
              imageUrl: progress.coverImageUrl,
              width: 76,
              height: 108,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    progress.comicTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(pageText),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value:
                        progress.lastReadPageItemIndex == null ||
                            progress.totalPageItems == null ||
                            progress.totalPageItems == 0
                        ? null
                        : (progress.lastReadPageItemIndex! + 1) /
                              progress.totalPageItems!,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
