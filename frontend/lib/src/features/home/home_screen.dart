import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../core/app_icons.dart';
import '../../models/auth.dart';
import '../../models/comic.dart';
import '../../models/progress.dart';
import '../../models/source_info.dart';
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
  bool _migrationPromptShown = false;

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
    _maybePromptMigration(auth);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          AppAssets.logoAppLarge,
          height: 38,
          fit: BoxFit.contain,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton.filledTonal(
              tooltip: auth.isAuthenticated ? 'Notifications' : 'Login',
              onPressed: auth.isAuthenticated
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No new notifications.')),
                      );
                    }
                  : () => context.push('/auth'),
              icon: Icon(
                auth.isAuthenticated
                    ? TonztoonIcons.bell
                    : TonztoonIcons.accountCircle,
              ),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _DiscoverHeader(
                data: data,
                onSourceChanged: (value) {
                  ref.read(selectedSourceProvider.notifier).select(value);
                },
              ),
              const SizedBox(height: 22),
              if (data.continueReading.isNotEmpty) ...[
                _SectionTitle(
                  title: 'Continue Reading',
                  actionLabel: '${data.continueReading.length}',
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 130,
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

  void _maybePromptMigration(AuthState auth) {
    if (_migrationPromptShown || !auth.isAuthenticated) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo.migrationSkipped || !repo.hasMigratableLocalData()) return;
    _migrationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMigrationDialog();
    });
  }

  Future<void> _showMigrationDialog() async {
    final repo = ref.read(libraryRepositoryProvider);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sync guest data?'),
        content: const Text(
          'Progress, bookmarks, collections, favorite scenes, and download wishlist from guest mode can be migrated to your cloud account. Offline files stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop('skip'),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => context.pop('migrate'),
            child: const Text('Migrate & Sync'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'skip') {
      await repo.skipMigration();
      return;
    }

    try {
      await repo.importLocalSnapshotToCloud();
      ref.invalidate(homeDataProvider);
      ref.invalidate(bookmarksProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(favoriteScenesProvider);
      ref.invalidate(downloadsProvider);
      ref.invalidate(historyProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guest data migrated to cloud.')),
      );
    } catch (error) {
      _migrationPromptShown = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Migration failed: $error')));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel});

  final String title;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: colorScheme.secondary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                actionLabel!,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({required this.data, required this.onSourceChanged});

  final HomeData data;
  final ValueChanged<String> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF14262A), Color(0xFF211821)]
              : const [Color(0xFFE7FFFB), Color(0xFFFFF0EA)],
        ),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Discover',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                _SourceSelector(
                  selectedId: data.selectedSource.id,
                  selectedLabel: data.selectedSource.label,
                  sources: data.sources,
                  onChanged: onSourceChanged,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: TonztoonIcons.autoAwesome,
                  label: '${data.latest.length} latest',
                ),
                _MetricChip(
                  icon: TonztoonIcons.localFireDepartment,
                  label: '${data.popular.length} popular',
                ),
                if (data.continueReading.isNotEmpty)
                  _MetricChip(
                    icon: TonztoonIcons.bookmarkAdded,
                    label: '${data.continueReading.length} active',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({
    required this.selectedId,
    required this.selectedLabel,
    required this.sources,
    required this.onChanged,
  });

  final String selectedId;
  final String selectedLabel;
  final List<SourceInfo> sources;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Source',
      initialValue: selectedId,
      onSelected: onChanged,
      itemBuilder: (context) => sources
          .map(
            (source) => PopupMenuItem<String>(
              value: source.id,
              child: Text(source.label),
            ),
          )
          .toList(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.88),
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TonztoonIcons.travelExplore,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 116),
                child: Text(
                  selectedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(TonztoonIcons.keyboardArrowDown, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
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
          height: 284,
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
    final colorScheme = Theme.of(context).colorScheme;
    final chapterText =
        'Chapter ${formatChapterNumber(progress.chapterNumber)}';
    final pageText =
        progress.lastReadPageItemIndex == null ||
            progress.totalPageItems == null
        ? null
        : 'Page ${progress.lastReadPageItemIndex! + 1}/${progress.totalPageItems}';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(
        '/reader/${progress.sourceName}/${progress.comicSlug}/${formatChapterNumber(progress.chapterNumber)}',
      ),
      child: SizedBox(
        width: 260,
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
                      Text(chapterText),
                      if (pageText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          pageText,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(99),
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
        ),
      ),
    );
  }
}
