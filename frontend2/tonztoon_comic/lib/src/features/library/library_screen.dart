import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import 'downloaded_scene_store.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 5,
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

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
      children: [
        const _LibraryHero(),
        const SizedBox(height: 16),
        const _SectionHeader(
          icon: TonztoonIcons.bookmarkAdded,
          title: 'Komik tersimpan',
          trailing: '4 item',
        ),
        const SizedBox(height: 10),
        for (final item in _bookmarkItems) ...[
          _ComicLibraryTile(item: item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CollectionsTab extends StatefulWidget {
  const _CollectionsTab();

  @override
  State<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<_CollectionsTab> {
  late final List<_CollectionItem> _items = List.of(_collections);

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
        children: [
          _CollectionHeader(count: _items.length, onAdd: _createCollection),
          const SizedBox(height: 18),
          const _CollectionEmptyState(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
      children: [
        _CollectionHeader(count: _items.length, onAdd: _createCollection),
        const SizedBox(height: 10),
        for (final collection in _items) ...[
          _CollectionTile(
            collection: collection,
            onOpen: () => _openCollection(collection),
            onRename: () => _renameCollection(collection),
            onDelete: () => _deleteCollection(collection),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _openCollection(_CollectionItem collection) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CollectionDetailScreen(
          collection: collection,
          onChanged: _replaceCollection,
          onDeleted: _removeCollection,
        ),
      ),
    );
  }

  Future<void> _createCollection() async {
    final title = await _showCollectionNameDialog(
      context,
      title: 'Koleksi baru',
      actionLabel: 'Buat',
    );
    if (!mounted || title == null || title.trim().isEmpty) return;

    setState(() {
      _items.insert(
        0,
        _CollectionItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title.trim(),
          comics: const [],
        ),
      );
    });
  }

  Future<void> _renameCollection(_CollectionItem collection) async {
    final title = await _showCollectionNameDialog(
      context,
      title: 'Rename koleksi',
      actionLabel: 'Simpan',
      initialValue: collection.title,
    );
    if (!mounted || title == null || title.trim().isEmpty) return;

    _replaceCollection(collection.copyWith(title: title.trim()));
  }

  Future<void> _deleteCollection(_CollectionItem collection) async {
    final confirmed = await _showDeleteCollectionDialog(context, collection);
    if (!mounted || confirmed != true) return;
    _removeCollection(collection.id);
  }

  void _replaceCollection(_CollectionItem collection) {
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere((item) => item.id == collection.id);
      if (index == -1) return;
      _items[index] = collection;
    });
  }

  void _removeCollection(String id) {
    if (!mounted) return;
    setState(() => _items.removeWhere((item) => item.id == id));
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

class _ScenesTab extends StatelessWidget {
  const _ScenesTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DownloadedSceneItem>>(
      valueListenable: downloadedSceneStore,
      builder: (context, scenes, child) {
        if (scenes.isEmpty) {
          return const _SceneEmptyState();
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
          itemCount: scenes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (context, index) => _SceneCard(scene: scenes[index]),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
      children: [
        const _SectionHeader(
          icon: TonztoonIcons.clock,
          title: 'Terakhir dibaca',
          trailing: 'Minggu ini',
        ),
        const SizedBox(height: 10),
        for (final item in _historyItems) ...[
          _HistoryTile(item: item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 132),
      children: [
        const _SectionHeader(
          icon: TonztoonIcons.download,
          title: 'Unduhan offline',
          trailing: '2 aktif',
        ),
        const SizedBox(height: 10),
        for (final item in _downloadItems) ...[
          _DownloadTile(item: item),
          const SizedBox(height: 12),
        ],
        const _OfflineHint(),
      ],
    );
  }
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero();

  // Hitung stats dari dummy data
  int get _totalBookmarks => _bookmarkItems.length;
  int get _ongoingCount =>
      _bookmarkItems.where((i) => i.status.toLowerCase() == 'ongoing').length;
  int get _completedCount =>
      _bookmarkItems.where((i) => i.status.toLowerCase() == 'completed').length;
  int get _hiatusCount =>
      _bookmarkItems.where((i) => i.status.toLowerCase() == 'hiatus').length;

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
                // ── Header row ──────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                          width: 1,
                        ),
                      ),
                      child: Icon(
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
                            '$_totalBookmarks komik tersimpan',
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
                        '$_totalBookmarks',
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
                // ── Divider subtle ──────────────────────────────────
                Divider(
                  color: primaryOrange.withValues(alpha: 0.12),
                  height: 1,
                ),
                const SizedBox(height: 14),

                // ── Stat grid 2x2 ───────────────────────────────────
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
                        value: '${_downloadItems.length}',
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

/// Satu kolom stat untuk hero banner
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.78),
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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

class _ComicLibraryTile extends StatelessWidget {
  const _ComicLibraryTile({required this.item});

  final _LibraryComicItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openComicDetail(context, item.comic),
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  bottomLeft: Radius.circular(15),
                ),
                child: ComicCover(
                  imageUrl: item.comic.coverImageUrl,
                  width: 72,
                  height: 108,
                  borderRadius: 0,
                ),
              ),

              // ── Konten ──────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Judul
                      Text(
                        item.comic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      // Badges baris
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _TypeFlagBadge(type: item.type),
                          ComicStatusBadge(status: item.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Note / keterangan
                      Row(
                        children: [
                          Icon(
                            TonztoonIcons.bookmark,
                            size: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              item.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Chevron ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 44),
                child: Icon(
                  TonztoonIcons.chevronRight,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.collection,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final _CollectionItem collection;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppSurfaceInk(
      onTap: onOpen,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              children: [
                for (
                  var index = 0;
                  index < collection.comics.take(3).length;
                  index++
                )
                  Positioned(
                    left: index * 13,
                    top: index * 5,
                    child: ComicCover(
                      imageUrl: collection.comics[index].coverImageUrl,
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
                Text(collection.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(collection.subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi koleksi',
            icon: Icon(TonztoonIcons.moreHoriz, color: colorScheme.primary),
            onSelected: (value) {
              if (value == 'open') onOpen();
              if (value == 'rename') onRename();
              if (value == 'delete') onDelete();
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
}

class _CollectionDetailScreen extends StatefulWidget {
  const _CollectionDetailScreen({
    required this.collection,
    required this.onChanged,
    required this.onDeleted,
  });

  final _CollectionItem collection;
  final ValueChanged<_CollectionItem> onChanged;
  final ValueChanged<String> onDeleted;

  @override
  State<_CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<_CollectionDetailScreen> {
  late _CollectionItem _collection = widget.collection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_collection.title, style: theme.textTheme.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Tambah komik',
            onPressed: _addComic,
            icon: const Icon(TonztoonIcons.plus),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opsi koleksi',
            icon: const Icon(TonztoonIcons.moreHoriz),
            onSelected: (value) {
              if (value == 'rename') _renameCollection();
              if (value == 'delete') _deleteCollection();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename koleksi')),
              PopupMenuItem(value: 'delete', child: Text('Hapus koleksi')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _collection.comics.isEmpty
          ? const _CollectionEmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _CollectionDetailHero(collection: _collection),
                const SizedBox(height: 16),
                for (final comic in _collection.comics) ...[
                  _CollectionComicTile(
                    comic: comic,
                    onOpen: () => _openComicDetail(context, comic),
                    onRemove: () => _removeComic(comic),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Future<void> _renameCollection() async {
    final title = await _showCollectionNameDialog(
      context,
      title: 'Rename koleksi',
      actionLabel: 'Simpan',
      initialValue: _collection.title,
    );
    if (!mounted || title == null || title.trim().isEmpty) return;

    _updateCollection(_collection.copyWith(title: title.trim()));
  }

  Future<void> _deleteCollection() async {
    final confirmed = await _showDeleteCollectionDialog(context, _collection);
    if (!mounted || confirmed != true) return;
    widget.onDeleted(_collection.id);
    Navigator.of(context).pop();
  }

  Future<void> _addComic() async {
    final selected = await showModalBottomSheet<ComicSummary>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        const available = <ComicSummary>[];

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
                  child: Center(child: Text('Semua komik sudah ada.')),
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
    if (!mounted || selected == null) return;

    _updateCollection(
      _collection.copyWith(comics: [..._collection.comics, selected]),
    );
  }

  Future<void> _removeComic(ComicSummary comic) async {
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
    if (!mounted || confirmed != true) return;

    _updateCollection(
      _collection.copyWith(
        comics: _collection.comics
            .where((item) => item.title != comic.title)
            .toList(),
      ),
    );
  }

  void _updateCollection(_CollectionItem collection) {
    if (!mounted) return;
    setState(() => _collection = collection);
    widget.onChanged(collection);
  }
}

class _CollectionDetailHero extends StatelessWidget {
  const _CollectionDetailHero({required this.collection});

  final _CollectionItem collection;

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
                collection.subtitle,
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
  const _CollectionComicTile({
    required this.comic,
    required this.onOpen,
    required this.onRemove,
  });

  final ComicSummary comic;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSurfaceInk(
      onTap: onOpen,
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
                  [
                    if (comic.type != null) comic.type!,
                    if (comic.latestChapterNumber != null)
                      'Ch ${formatChapterNumber(comic.latestChapterNumber!)}',
                  ].join(' - '),
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

  final ComicSummary comic;

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

class _CollectionEmptyState extends StatelessWidget {
  const _CollectionEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Icon(TonztoonIcons.library, size: 34),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Belum ada item di koleksi ini.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.scene});

  final DownloadedSceneItem scene;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openComicDetail(context, scene.comic),
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
                      scene.label,
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
}

class _SceneEmptyState extends StatelessWidget {
  const _SceneEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 42, 16, 132),
      children: [
        Center(
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
                    child: Icon(
                      TonztoonIcons.download,
                      size: 34,
                      color: colorScheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Belum ada scene tersimpan',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Text(
                  'Unduh page dari reader untuk mengumpulkannya di tab Scene.',
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
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final _HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, item.comic),
      child: Row(
        children: [
          ComicCover(imageUrl: item.comic.coverImageUrl, width: 58, height: 82),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(item.chapter, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: item.progress,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(TonztoonIcons.play),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.item});

  final _DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isReadyOffline = item.progress >= 1;

    return AppSurfaceInk(
      onTap: () => _openComicDetail(context, item.comic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ComicCover(
                imageUrl: item.comic.coverImageUrl,
                width: 58,
                height: 82,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    if (isReadyOffline)
                      _OfflineReadyBadge(label: item.status)
                    else
                      Text(item.status, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (isReadyOffline)
                const Icon(
                  TonztoonIcons.badgeCheckFilled,
                  color: Color(0xFF16A34A),
                ),
              if (!isReadyOffline)
                Text(
                  '${(item.progress * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.secondary,
                  ),
                ),
            ],
          ),
          if (!isReadyOffline) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: item.progress,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
        ],
      ),
    );
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
                'Chapter offline akan tampil di sini setelah selesai diunduh.',
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
            Text(
              comicTypeFlag(type),
              style: const TextStyle(fontSize: 13, height: 1),
            ),
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

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

Future<String?> _showCollectionNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String? initialValue,
}) async {
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

Future<bool?> _showDeleteCollectionDialog(
  BuildContext context,
  _CollectionItem collection,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hapus koleksi'),
      content: Text('Hapus "${collection.title}" beserta daftar komiknya?'),
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
}

class _LibraryComicItem {
  const _LibraryComicItem({
    required this.comic,
    required this.type,
    required this.status,
    required this.note,
  });

  final ComicSummary comic;
  final String type;
  final String status;
  final String note;
}

class _CollectionItem {
  const _CollectionItem({
    required this.id,
    required this.title,
    required this.comics,
  });

  final String id;
  final String title;
  final List<ComicSummary> comics;

  String get subtitle => '${comics.length} komik tersimpan';

  _CollectionItem copyWith({String? title, List<ComicSummary>? comics}) {
    return _CollectionItem(
      id: id,
      title: title ?? this.title,
      comics: comics ?? this.comics,
    );
  }
}

class _HistoryItem {
  const _HistoryItem({
    required this.comic,
    required this.chapter,
    required this.progress,
  });

  final ComicSummary comic;
  final String chapter;
  final double progress;
}

class _DownloadItem {
  const _DownloadItem({
    required this.comic,
    required this.status,
    required this.progress,
  });

  final ComicSummary comic;
  final String status;
  final double progress;
}

final _bookmarkItems = <_LibraryComicItem>[];

final _collections = <_CollectionItem>[];

final _historyItems = <_HistoryItem>[];

final _downloadItems = <_DownloadItem>[];
