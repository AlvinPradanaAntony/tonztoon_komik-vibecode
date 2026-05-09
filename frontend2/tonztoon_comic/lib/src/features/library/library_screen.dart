import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 5,
      initialIndex: initialTabIndex.clamp(0, 4),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Text('Pustaka', style: theme.textTheme.titleLarge),
          centerTitle: false,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(54),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                tabs: [
                  Tab(text: 'Bookmark'),
                  Tab(text: 'Koleksi'),
                  Tab(text: 'Scene'),
                  Tab(text: 'Riwayat'),
                  Tab(text: 'Unduhan'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _BookmarksTab(),
            _CollectionsTab(),
            _ScenesTab(),
            _HistoryTab(),
            _DownloadsTab(),
          ],
        ),
      ),
    );
  }
}

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksProvider);
    final downloadsCount =
        ref.watch(downloadsProvider).asData?.value.length ?? 0;

    return _AsyncPane<List<LibraryComicRef>>(
      value: bookmarksAsync,
      onRefresh: () => _refreshBookmarks(ref),
      onRetry: () => ref.invalidate(bookmarksProvider),
      builder: (bookmarks) {
        final children = <Widget>[
          _LibraryHero(bookmarks: bookmarks, downloadsCount: downloadsCount),
          const SizedBox(height: 16),
          _SectionHeader(
            icon: TonztoonIcons.bookmarkAdded,
            title: 'Komik tersimpan',
            trailing: '${bookmarks.length} item',
          ),
          const SizedBox(height: 10),
          if (bookmarks.isEmpty)
            const _EmptyState(
              icon: TonztoonIcons.bookmark,
              title: 'Belum ada bookmark',
              message:
                  'Simpan komik dari halaman detail untuk menaruhnya di sini.',
            )
          else
            for (final comic in bookmarks) ...[
              _BookmarkTile(comic: comic),
              const SizedBox(height: 12),
            ],
        ];

        return _LibraryList(
          children: children,
          onRefresh: () => _refreshBookmarks(ref),
        );
      },
    );
  }
}

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);

    return _AsyncPane<List<CollectionSummary>>(
      value: collectionsAsync,
      onRefresh: () => _refreshCollections(ref),
      onRetry: () => ref.invalidate(collectionsProvider),
      builder: (collections) {
        final children = <Widget>[
          _CollectionHeader(
            count: collections.length,
            onAdd: () => _createCollection(context, ref),
          ),
          const SizedBox(height: 10),
          if (collections.isEmpty)
            const _EmptyState(
              icon: TonztoonIcons.library,
              title: 'Belum ada koleksi',
              message:
                  'Buat folder koleksi untuk mengelompokkan komik favorit.',
            )
          else
            for (final collection in collections) ...[
              _CollectionTile(collection: collection),
              const SizedBox(height: 12),
            ],
        ];

        return _LibraryList(
          children: children,
          onRefresh: () => _refreshCollections(ref),
        );
      },
    );
  }

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await _showCollectionNameDialog(
      context,
      title: 'Koleksi baru',
      actionLabel: 'Buat',
    );
    if (!context.mounted || name == null || name.trim().isEmpty) return;

    try {
      final created = await ref
          .read(libraryRepositoryProvider)
          .createCollection(name);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionDetailProvider(created.id));
      if (!context.mounted) return;
      _showMessage(context, 'Koleksi "${created.name}" dibuat.');
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _ScenesTab extends ConsumerWidget {
  const _ScenesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenesAsync = ref.watch(favoriteScenesProvider);

    return _AsyncPane<List<FavoriteScene>>(
      value: scenesAsync,
      onRefresh: () => _refreshScenes(ref),
      onRetry: () => ref.invalidate(favoriteScenesProvider),
      builder: (scenes) {
        if (scenes.isEmpty) {
          return _LibraryList(
            onRefresh: () => _refreshScenes(ref),
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
          onRefresh: () => _refreshScenes(ref),
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
            itemCount: scenes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) => _SceneCard(scene: scenes[index]),
          ),
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return _AsyncPane<List<ReadingProgress>>(
      value: historyAsync,
      onRefresh: () => _refreshHistory(ref),
      onRetry: () => ref.invalidate(historyProvider),
      builder: (history) {
        final children = <Widget>[
          _SectionHeader(
            icon: TonztoonIcons.clock,
            title: 'Terakhir dibaca',
            trailing: '${history.length} item',
          ),
          const SizedBox(height: 10),
          if (history.isEmpty)
            const _EmptyState(
              icon: TonztoonIcons.clock,
              title: 'Belum ada riwayat',
              message: 'Mulai membaca chapter untuk melanjutkan dari tab ini.',
            )
          else
            for (final item in history) ...[
              _HistoryTile(item: item),
              const SizedBox(height: 12),
            ],
        ];

        return _LibraryList(
          children: children,
          onRefresh: () => _refreshHistory(ref),
        );
      },
    );
  }
}

class _DownloadsTab extends ConsumerWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(offlineQueueProvider);
    final offlineAsync = ref.watch(offlineChaptersProvider);
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
    if (error != null &&
        !queueAsync.hasValue &&
        !offlineAsync.hasValue &&
        !downloadsAsync.hasValue) {
      return _LibraryList(
        onRefresh: () => _refreshDownloads(ref),
        children: [
          _ErrorPane(error: error, onRetry: () => _refreshDownloads(ref)),
        ],
      );
    }

    final queue = queueAsync.asData?.value ?? const <OfflineDownloadBatch>[];
    final offline = offlineAsync.asData?.value ?? const <OfflineChapter>[];
    final downloads = downloadsAsync.asData?.value ?? const <DownloadEntry>[];
    final activeQueue = queue
        .where(
          (item) => item.status != 'completed' && item.status != 'cancelled',
        )
        .toList();

    final children = <Widget>[
      _SectionHeader(
        icon: TonztoonIcons.download,
        title: 'Unduhan offline',
        trailing: '${activeQueue.length} aktif',
      ),
      const SizedBox(height: 10),
      if (activeQueue.isEmpty && offline.isEmpty && downloads.isEmpty)
        const _EmptyState(
          icon: TonztoonIcons.download,
          title: 'Belum ada unduhan',
          message: 'Download chapter dari halaman detail untuk mode offline.',
        )
      else ...[
        if (activeQueue.isNotEmpty) ...[
          const _SubHeader(title: 'Antrean aktif'),
          const SizedBox(height: 8),
          for (final batch in activeQueue) ...[
            _OfflineBatchTile(batch: batch),
            const SizedBox(height: 12),
          ],
        ],
        if (offline.isNotEmpty) ...[
          const _SubHeader(title: 'File lokal'),
          const SizedBox(height: 8),
          for (final chapter in offline) ...[
            _OfflineChapterTile(chapter: chapter),
            const SizedBox(height: 12),
          ],
        ],
        if (downloads.isNotEmpty) ...[
          const _SubHeader(title: 'Status sinkronisasi'),
          const SizedBox(height: 8),
          for (final entry in downloads) ...[
            _DownloadEntryTile(entry: entry),
            const SizedBox(height: 12),
          ],
        ],
      ],
      const _OfflineHint(),
    ];

    return _LibraryList(
      children: children,
      onRefresh: () => _refreshDownloads(ref),
    );
  }
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
  const _LibraryList({required this.children, this.onRefresh = _noopRefresh});

  final List<Widget> children;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
        children: children,
      ),
    );
  }
}

Future<void> _noopRefresh() async {}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
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
            Text(error.toString(), textAlign: TextAlign.center),
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

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({required this.bookmarks, required this.downloadsCount});

  final List<LibraryComicRef> bookmarks;
  final int downloadsCount;

  int get _ongoingCount =>
      bookmarks.where((item) => item.status?.toLowerCase() == 'ongoing').length;
  int get _completedCount => bookmarks
      .where((item) => item.status?.toLowerCase() == 'completed')
      .length;
  int get _hiatusCount =>
      bookmarks.where((item) => item.status?.toLowerCase() == 'hiatus').length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryOrange = Color(0xFFFF9D00);
    const accentBlue = Color(0xFF3A86FF);
    final gradientColors = isDark
        ? const [Color(0xFF1A1F2E), Color(0xFF0F1620), Color(0xFF1A1220)]
        : const [Color(0xFFFFF8EC), Color(0xFFF0F7FF), Color(0xFFFFF0F7)];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: gradientColors,
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withValues(alpha: isDark ? 0.18 : 0.12),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        TonztoonIcons.library,
                        color: primaryOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rak Bacaan Saya',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${bookmarks.length} komik tersimpan',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${bookmarks.length}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: primaryOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: primaryOrange.withValues(alpha: 0.12),
                  height: 1,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.clock,
                        value: '$_ongoingCount',
                        label: 'Ongoing',
                        color: accentBlue,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.badgeCheck,
                        value: '$_completedCount',
                        label: 'Selesai',
                        color: const Color(0xFF16A34A),
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.download,
                        value: '$downloadsCount',
                        label: 'Offline',
                        color: primaryOrange,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.circleDotDashed,
                        value: '$_hiatusCount',
                        label: 'Hiatus',
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  const _HeroStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color.withValues(alpha: 0.78),
                height: 1,
              ),
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

class _BookmarkTile extends ConsumerWidget {
  const _BookmarkTile({required this.comic});

  final LibraryComicRef comic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = comic.toSummary();

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, summary),
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              bottomLeft: Radius.circular(15),
            ),
            child: ComicCover(
              imageUrl: comic.coverImageUrl,
              width: 72,
              height: 108,
              borderRadius: 0,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (comic.type != null) _TypeFlagBadge(type: comic.type!),
                      if (comic.status != null)
                        ComicStatusBadge(status: comic.status!),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [comic.author, comic.sourceName]
                        .where((item) => item != null && item.isNotEmpty)
                        .join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi bookmark',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) async {
              if (value == 'open') {
                _openComicDetail(context, summary);
              }
              if (value == 'remove') {
                await _removeBookmark(context, ref, summary);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open', child: Text('Buka detail')),
              PopupMenuItem(value: 'remove', child: Text('Hapus bookmark')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _removeBookmark(
    BuildContext context,
    WidgetRef ref,
    ComicSummary comic,
  ) async {
    try {
      await ref.read(libraryRepositoryProvider).toggleBookmark(comic, true);
      ref.invalidate(libraryComicStateProvider(comic));
      await _refreshBookmarks(ref);
      if (context.mounted) _showMessage(context, 'Bookmark dihapus.');
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(TonztoonIcons.library, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Koleksi pribadi',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text(
          '$count folder',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Tambah koleksi',
          onPressed: onAdd,
          icon: const Icon(TonztoonIcons.plus),
        ),
      ],
    );
  }
}

class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({required this.collection});

  final CollectionSummary collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = ref
        .watch(collectionDetailProvider(collection.id))
        .asData
        ?.value;
    final covers = detail?.items.take(3).toList() ?? const <LibraryComicRef>[];

    return AppSurfaceInk(
      onTap: () => _open(context),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: covers.isEmpty
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(TonztoonIcons.library),
                  )
                : Stack(
                    children: [
                      for (var index = 0; index < covers.length; index++)
                        Positioned(
                          left: index * 13,
                          top: index * 5,
                          child: ComicCover(
                            imageUrl: covers[index].coverImageUrl,
                            width: 42,
                            height: 58,
                            borderRadius: 8,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(collection.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(
                  '${collection.totalItems} komik tersimpan',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi koleksi',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) async {
              if (value == 'open') {
                _open(context);
                return;
              }
              if (value == 'rename') {
                await _renameCollection(context, ref, collection);
                return;
              }
              if (value == 'delete') {
                await _deleteCollection(context, ref, collection);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open', child: Text('Buka')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CollectionDetailScreen(
          collectionId: collection.id,
          initialName: collection.name,
        ),
      ),
    );
  }
}

class _CollectionDetailScreen extends ConsumerWidget {
  const _CollectionDetailScreen({
    required this.collectionId,
    required this.initialName,
  });

  final int collectionId;
  final String initialName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(collectionDetailProvider(collectionId));
    final detail = detailAsync.asData?.value;
    final title = detail?.name ?? initialName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Tambah komik',
            onPressed: detail == null
                ? null
                : () => _addComic(context, ref, detail),
            icon: const Icon(TonztoonIcons.plus),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi koleksi',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) async {
              final current = detail;
              if (current == null) return;
              if (value == 'rename') {
                await _renameCollection(context, ref, current);
                return;
              }
              if (value == 'delete') {
                final deleted = await _deleteCollection(context, ref, current);
                if (deleted && context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename koleksi')),
              PopupMenuItem(value: 'delete', child: Text('Hapus koleksi')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _AsyncPane<CollectionDetail>(
        value: detailAsync,
        onRefresh: () => _refreshCollectionDetail(ref, collectionId),
        onRetry: () => ref.invalidate(collectionDetailProvider(collectionId)),
        builder: (collection) {
          final children = <Widget>[
            _CollectionDetailHero(collection: collection),
            const SizedBox(height: 16),
            if (collection.items.isEmpty)
              const _EmptyState(
                icon: TonztoonIcons.library,
                title: 'Belum ada item di koleksi ini',
                message: 'Tambahkan komik dari bookmark yang sudah tersimpan.',
              )
            else
              for (final comic in collection.items) ...[
                _CollectionComicTile(
                  comic: comic,
                  onRemove: () => _removeComic(context, ref, collection, comic),
                ),
                const SizedBox(height: 12),
              ],
          ];

          return _LibraryList(
            children: children,
            onRefresh: () => _refreshCollectionDetail(ref, collectionId),
          );
        },
      ),
    );
  }

  Future<void> _addComic(
    BuildContext context,
    WidgetRef ref,
    CollectionDetail collection,
  ) async {
    try {
      final bookmarks = await ref.read(bookmarksProvider.future);
      if (!context.mounted) return;
      final existingKeys = collection.items.map((item) => item.key).toSet();
      final available = bookmarks
          .where((comic) => !existingKeys.contains(comic.key))
          .toList();

      final selected = await showModalBottomSheet<LibraryComicRef>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            top: false,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Text(
                  'Tambah komik',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Semua bookmark sudah masuk.')),
                  )
                else
                  for (final comic in available) ...[
                    _AddComicTile(comic: comic),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      );
      if (!context.mounted || selected == null) return;

      await ref
          .read(libraryRepositoryProvider)
          .addComicToCollection(collection.id, selected.toSummary());
      ref.invalidate(collectionDetailProvider(collection.id));
      ref.invalidate(collectionsProvider);
      if (!context.mounted) return;
      _showMessage(context, 'Komik ditambahkan.');
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _removeComic(
    BuildContext context,
    WidgetRef ref,
    CollectionDetail collection,
    LibraryComicRef comic,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus komik'),
        content: Text('Hapus "${comic.title}" dari koleksi ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;

    try {
      await ref
          .read(libraryRepositoryProvider)
          .removeComicFromCollection(collection.id, comic.toSummary());
      ref.invalidate(collectionDetailProvider(collection.id));
      ref.invalidate(collectionsProvider);
      if (!context.mounted) return;
      _showMessage(context, 'Komik dihapus dari koleksi.');
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _CollectionDetailHero extends StatelessWidget {
  const _CollectionDetailHero({required this.collection});

  final CollectionDetail collection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(TonztoonIcons.library, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${collection.items.length} komik tersimpan',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionComicTile extends StatelessWidget {
  const _CollectionComicTile({required this.comic, required this.onRemove});

  final LibraryComicRef comic;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = comic.toSummary();

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, summary),
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
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  [comic.type, comic.status]
                      .where((item) => item != null && item.isNotEmpty)
                      .join(' - '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hapus dari koleksi',
            onPressed: onRemove,
            icon: const Icon(TonztoonIcons.close),
          ),
        ],
      ),
    );
  }
}

class _AddComicTile extends StatelessWidget {
  const _AddComicTile({required this.comic});

  final LibraryComicRef comic;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceInk(
      onTap: () => Navigator.of(context).pop(comic),
      child: Row(
        children: [
          ComicCover(imageUrl: comic.coverImageUrl, width: 58, height: 82),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              comic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(TonztoonIcons.plus),
        ],
      ),
    );
  }
}

class _SceneCard extends ConsumerWidget {
  const _SceneCard({required this.scene});

  final FavoriteScene scene;

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
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
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
    } catch (error) {
      if (context.mounted) _showError(context, error);
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
                    stops: const [0.0, 0.75, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.88),
                      Colors.black,
                    ],
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final ReadingProgress item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comic = ComicSummary(
      title: item.comicTitle,
      slug: item.comicSlug,
      sourceName: item.sourceName,
      coverImageUrl: item.coverImageUrl,
    );

    return AppSurfaceInk(
      onTap: () => _openReader(context, item),
      child: Row(
        children: [
          ComicCover(imageUrl: item.coverImageUrl, width: 58, height: 82),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.comicTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  'Chapter ${formatChapterNumber(item.chapterNumber)} - ${_dateLabel(item.lastReadAt)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _progressValue(item),
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Buka detail',
            onPressed: () => _openComicDetail(context, comic),
            icon: const Icon(TonztoonIcons.chevronRight),
          ),
        ],
      ),
    );
  }
}

class _OfflineBatchTile extends ConsumerWidget {
  const _OfflineBatchTile({required this.batch});

  final OfflineDownloadBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, batch.comic.toSummary()),
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
                  if (value == 'resume') await controller.resumeBatch(batch.id);
                  if (value == 'cancel') await controller.cancelBatch(batch.id);
                  if (value == 'delete') await controller.deleteBatch(batch.id);
                  ref.invalidate(downloadsProvider);
                },
                itemBuilder: (context) => [
                  if (batch.canResume)
                    const PopupMenuItem(
                      value: 'resume',
                      child: Text('Lanjutkan'),
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
  const _OfflineChapterTile({required this.chapter});

  final OfflineChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ready = chapter.isCompleted;

    return AppSurfaceInk(
      onTap: () => ready
          ? _openOfflineChapter(context, chapter)
          : _openComicDetail(context, chapter.comic.toSummary()),
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
                            'Ch ${formatChapterNumber(chapter.chapterNumber)} siap offline',
                      )
                    : Text(
                        '${chapter.status} - Ch ${formatChapterNumber(chapter.chapterNumber)}',
                        style: theme.textTheme.bodySmall,
                      ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hapus file offline',
            onPressed: () => _deleteOfflineChapter(context, ref),
            icon: const Icon(TonztoonIcons.trash),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOfflineChapter(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref.read(offlineRepositoryProvider).deleteOfflineChapter(chapter);
      ref.invalidate(offlineChaptersProvider);
      if (context.mounted) _showMessage(context, 'File offline dihapus.');
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _DownloadEntryTile extends ConsumerWidget {
  const _DownloadEntryTile({required this.entry});

  final DownloadEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, entry.comic.toSummary()),
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
                  '${entry.status} - Ch ${formatChapterNumber(entry.chapterNumber)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hapus status download',
            onPressed: () => _deleteEntry(context, ref),
            icon: const Icon(TonztoonIcons.trash),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(libraryRepositoryProvider).deleteDownloadEntry(entry);
      ref.invalidate(downloadsProvider);
      if (context.mounted) _showMessage(context, 'Entry download dihapus.');
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
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

class _TypeFlagBadge extends StatelessWidget {
  const _TypeFlagBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(comicTypeFlag(type), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              type,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
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

Future<String?> _showCollectionNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String? initialValue,
}) {
  var value = initialValue ?? '';

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nama koleksi',
          hintText: 'Contoh: Favorit Utama',
        ),
        textInputAction: TextInputAction.done,
        onChanged: (text) => value = text,
        onFieldSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(value),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

Future<void> _renameCollection(
  BuildContext context,
  WidgetRef ref,
  CollectionSummary collection,
) async {
  final name = await _showCollectionNameDialog(
    context,
    title: 'Rename koleksi',
    actionLabel: 'Simpan',
    initialValue: collection.name,
  );
  if (!context.mounted || name == null || name.trim().isEmpty) return;

  try {
    final updated = await ref
        .read(libraryRepositoryProvider)
        .renameCollection(collection.id, name);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionDetailProvider(collection.id));
    if (!context.mounted) return;
    _showMessage(context, 'Koleksi menjadi "${updated.name}".');
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

Future<bool> _deleteCollection(
  BuildContext context,
  WidgetRef ref,
  CollectionSummary collection,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hapus koleksi'),
      content: Text('Hapus "${collection.name}" beserta daftar komiknya?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) return false;

  try {
    await ref.read(libraryRepositoryProvider).deleteCollection(collection.id);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionDetailProvider(collection.id));
    if (!context.mounted) return false;
    _showMessage(context, 'Koleksi dihapus.');
    return true;
  } catch (error) {
    if (context.mounted) _showError(context, error);
    return false;
  }
}

Future<void> _refreshBookmarks(WidgetRef ref) async {
  ref.invalidate(bookmarksProvider);
  ref.invalidate(downloadsProvider);
  await Future.wait([
    ref.read(bookmarksProvider.future),
    ref.read(downloadsProvider.future),
  ]);
}

Future<void> _refreshCollections(WidgetRef ref) async {
  ref.invalidate(collectionsProvider);
  await ref.read(collectionsProvider.future);
}

Future<void> _refreshCollectionDetail(WidgetRef ref, int collectionId) async {
  ref.invalidate(collectionDetailProvider(collectionId));
  ref.invalidate(collectionsProvider);
  await Future.wait([
    ref.read(collectionDetailProvider(collectionId).future),
    ref.read(collectionsProvider.future),
  ]);
}

Future<void> _refreshScenes(WidgetRef ref) async {
  ref.invalidate(favoriteScenesProvider);
  await ref.read(favoriteScenesProvider.future);
}

Future<void> _refreshHistory(WidgetRef ref) async {
  ref.invalidate(historyProvider);
  await ref.read(historyProvider.future);
}

Future<void> _refreshDownloads(WidgetRef ref) async {
  ref.invalidate(downloadsProvider);
  ref.invalidate(offlineChaptersProvider);
  ref.invalidate(offlineQueueProvider);
  await Future.wait([
    ref.read(downloadsProvider.future),
    ref.read(offlineChaptersProvider.future),
    ref.read(offlineQueueProvider.future),
  ]);
}

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

void _openReader(BuildContext context, ReadingProgress progress) {
  final comic = ComicSummary(
    title: progress.comicTitle,
    slug: progress.comicSlug,
    sourceName: progress.sourceName,
    coverImageUrl: progress.coverImageUrl,
  );
  context.push(
    '/reader/${Uri.encodeComponent(progress.sourceName)}/${Uri.encodeComponent(progress.comicSlug)}/${formatChapterNumber(progress.chapterNumber)}',
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

double _progressValue(ReadingProgress item) {
  final total = item.totalPageItems;
  if (total == null || total <= 0) return item.isCompleted ? 1 : 0;
  final current = (item.lastReadPageItemIndex ?? item.pageIndex ?? 0) + 1;
  return (current / total).clamp(0, 1).toDouble();
}

String _dateLabel(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'baru saja';
  if (difference.inHours < 1) return '${difference.inMinutes} menit lalu';
  if (difference.inDays < 1) return '${difference.inHours} jam lalu';
  if (difference.inDays < 7) return '${difference.inDays} hari lalu';
  return '${value.day}/${value.month}/${value.year}';
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.toString())));
}
