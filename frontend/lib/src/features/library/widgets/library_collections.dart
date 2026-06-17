part of '../library_screen.dart';

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
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
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
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }

  Future<void> _removeComic(
    BuildContext context,
    WidgetRef ref,
    CollectionDetail collection,
    LibraryComicRef comic,
  ) async {
    final confirmed = await showTonztoonConfirmDialog(
      context,
      title: 'Hapus komik',
      message: 'Hapus "${comic.title}" dari koleksi ini?',
      helperText:
          'Komik hanya dihapus dari koleksi ini. Bookmark dan progress baca tidak ikut terhapus.',
      helperIcon: TonztoonIcons.trash,
      cancelLabel: 'Batal',
      confirmLabel: 'Hapus',
      variant: TonztoonModalVariant.danger,
      art: TonztoonModalArt.trash,
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
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
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
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
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
      showBorder: false,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
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
