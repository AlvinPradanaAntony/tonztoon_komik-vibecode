import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/choice_chip_group.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';

class FullCatalogScreen extends ConsumerStatefulWidget {
  const FullCatalogScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<FullCatalogScreen> createState() => _FullCatalogScreenState();
}

class _FullCatalogScreenState extends ConsumerState<FullCatalogScreen> {
  _CatalogFilters _filters = const _CatalogFilters();
  bool _isGrid = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogAsync = ref.watch(catalogDataProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Katalog Komik', style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: widget.showBackButton
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  tooltip: 'Kembali',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(TonztoonIcons.arrowBack),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: _isGrid ? 'Tampilan daftar' : 'Tampilan grid',
            onPressed: () => setState(() => _isGrid = !_isGrid),
            icon: Icon(_isGrid ? TonztoonIcons.rows : TonztoonIcons.columns),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 6),
            child: IconButton(
              tooltip: 'Filter katalog',
              onPressed: _showFilterSheet,
              icon: Badge(
                isLabelVisible: _filters.isActive,
                smallSize: 8,
                child: const Icon(TonztoonIcons.slidersHorizontal),
              ),
            ),
          ),
        ],
      ),
      body: AppAsyncView<CatalogData>(
        value: catalogAsync,
        onRetry: () => ref.invalidate(catalogDataProvider),
        builder: (catalog) {
          final entries = _catalogPool(catalog.comics);
          final comics = _visibleEntries(entries);

          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              widget.showBackButton ? 28 : 132,
            ),
            children: [
              _CatalogHero(
                visibleCount: comics.length,
                totalCount: entries.length,
              ),
              const SizedBox(height: 16),
              _ActiveFilterStrip(filters: _filters, onClear: _clearFilters),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${comics.length} komik ditemukan',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  _SortPill(label: _filters.sort),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: comics.isEmpty
                    ? const _EmptyCatalogState()
                    : _isGrid
                    ? _CatalogGrid(entries: comics, onTap: _openComicDetail)
                    : _CatalogList(entries: comics, onTap: _openComicDetail),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_CatalogEntry> _catalogPool(List<ComicSummary> comics) {
    return comics
        .asMap()
        .entries
        .map((entry) => _CatalogEntry.fromSummary(entry.value, entry.key))
        .toList();
  }

  List<_CatalogEntry> _visibleEntries(List<_CatalogEntry> entries) {
    final filtered = entries.where((entry) {
      final comic = entry.comic;
      final sourceMatches =
          _filters.source == 'Semua' || entry.source == _filters.source;
      final typeMatches =
          _filters.type == 'Semua' || comic.type == _filters.type;
      final statusMatches =
          _filters.status == 'Semua' || entry.status == _filters.status;
      final genreMatches =
          _filters.genre == 'Semua' || entry.genre == _filters.genre;

      return sourceMatches && typeMatches && statusMatches && genreMatches;
    }).toList();

    switch (_filters.sort) {
      case 'Paling populer':
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
      case 'Chapter terbanyak':
        filtered.sort(
          (a, b) => (b.comic.latestChapterNumber ?? 0).compareTo(
            a.comic.latestChapterNumber ?? 0,
          ),
        );
      case 'A-Z':
        filtered.sort((a, b) => a.comic.title.compareTo(b.comic.title));
      default:
        filtered.sort((a, b) => b.updateRank.compareTo(a.updateRank));
    }

    return filtered;
  }

  void _clearFilters() {
    setState(() => _filters = const _CatalogFilters());
  }

  Future<void> _showFilterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final result = await showModalBottomSheet<_CatalogFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _CatalogFilterSheet(filters: _filters),
    );

    if (result == null) return;
    setState(() => _filters = result);
  }

  void _openComicDetail(_CatalogEntry entry) {
    context.push(
      '/comic/${Uri.encodeComponent(comicRouteSource(entry.comic))}/${Uri.encodeComponent(comicRouteSlug(entry.comic))}',
      extra: entry.comic,
    );
  }
}

class _CatalogHero extends StatelessWidget {
  const _CatalogHero({required this.visibleCount, required this.totalCount});

  final int visibleCount;
  final int totalCount;

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
              ? const [Color(0xFF172126), Color(0xFF251B22)]
              : const [Color(0xFFE7FFFB), Color(0xFFFFF1E8)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.78),
                shape: BoxShape.circle,
              ),
              child: Icon(
                TonztoonIcons.bookOpen,
                color: colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Full Katalog', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 5),
                  Text(
                    'Semua judul dari sumber favorit dalam satu tempat.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                child: Text(
                  '$visibleCount/$totalCount',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilterStrip extends StatelessWidget {
  const _ActiveFilterStrip({required this.filters, required this.onClear});

  final _CatalogFilters filters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!filters.isActive) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labels = [
      if (filters.source != 'Semua') filters.source,
      if (filters.type != 'Semua') filters.type,
      if (filters.status != 'Semua') filters.status,
      if (filters.genre != 'Semua') filters.genre,
    ];

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in labels) ...[
                  Chip(
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                    side: BorderSide.none,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Reset')),
      ],
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TonztoonIcons.slidersHorizontal,
              size: 15,
              color: colorScheme.secondary,
            ),
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

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.entries, required this.onTap});

  final List<_CatalogEntry> entries;
  final ValueChanged<_CatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const ValueKey('catalog-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.51,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ComicCard(
          comic: entry.comic,
          source: entry.source,
          rating: entry.rating.toStringAsFixed(1),
          width: double.infinity,
          onTap: () => onTap(entry),
        );
      },
    );
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.entries, required this.onTap});

  final List<_CatalogEntry> entries;
  final ValueChanged<_CatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('catalog-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _CatalogListTile(entry: entry, onTap: () => onTap(entry));
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: entries.length,
    );
  }
}

class _CatalogListTile extends StatelessWidget {
  const _CatalogListTile({required this.entry, required this.onTap});

  final _CatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final comic = entry.comic;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ComicCover(
                  imageUrl: comic.coverImageUrl,
                  width: 74,
                  height: 106,
                  borderRadius: 10,
                ),
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
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.source} • ${comicTypeFlag(comic.type)} ${comic.type ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.secondary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _RatingText(rating: entry.rating),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ComicGenreBadge(genre: entry.genre, compact: true),
                          ComicStatusBadge(status: entry.status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          ComicMetaBadge(
                            label:
                                'Ch ${formatChapterNumber(comic.latestChapterNumber ?? 0)}',
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(TonztoonIcons.chevronRight, color: colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalogState extends StatelessWidget {
  const _EmptyCatalogState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(TonztoonIcons.search, size: 44, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text('Tidak ada komik', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Coba ubah kata kunci atau filter katalog.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RatingText extends StatelessWidget {
  const _RatingText({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(TonztoonIcons.starFilled, size: 15, color: Colors.amber),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CatalogFilterSheet extends StatefulWidget {
  const _CatalogFilterSheet({required this.filters});

  final _CatalogFilters filters;

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  late String _source = widget.filters.source;
  late String _type = widget.filters.type;
  late String _status = widget.filters.status;
  late String _genre = widget.filters.genre;
  late String _sort = widget.filters.sort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.42,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    Text('Filter Katalog', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 14),
                    ChoiceChipGroup(
                      label: 'Sumber',
                      values: _sources,
                      selectedValue: _source,
                      onChanged: (value) => setState(() => _source = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Tipe',
                      values: _types,
                      selectedValue: _type,
                      onChanged: (value) => setState(() => _type = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Status',
                      values: _statuses,
                      selectedValue: _status,
                      onChanged: (value) => setState(() => _status = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Genre',
                      values: _genres,
                      selectedValue: _genre,
                      onChanged: (value) => setState(() => _genre = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Urutkan',
                      values: _sorts,
                      selectedValue: _sort,
                      onChanged: (value) => setState(() => _sort = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _source = 'Semua';
                            _type = 'Semua';
                            _status = 'Semua';
                            _genre = 'Semua';
                            _sort = 'Update terbaru';
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            _CatalogFilters(
                              source: _source,
                              type: _type,
                              status: _status,
                              genre: _genre,
                              sort: _sort,
                            ),
                          );
                        },
                        child: const Text('Terapkan'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CatalogFilters {
  const _CatalogFilters({
    this.source = 'Semua',
    this.type = 'Semua',
    this.status = 'Semua',
    this.genre = 'Semua',
    this.sort = 'Update terbaru',
  });

  final String source;
  final String type;
  final String status;
  final String genre;
  final String sort;

  bool get isActive =>
      source != 'Semua' ||
      type != 'Semua' ||
      status != 'Semua' ||
      genre != 'Semua';
}

class _CatalogEntry {
  const _CatalogEntry({
    required this.comic,
    required this.source,
    required this.status,
    required this.genre,
    required this.rating,
    required this.updateRank,
  });

  factory _CatalogEntry.fromSummary(ComicSummary comic, int index) {
    final source = _sourceLabel(comic.sourceName);
    final type = comic.type?.trim().isNotEmpty == true
        ? comic.type!.trim()
        : 'Manga';
    final status = comic.status?.trim().isNotEmpty == true
        ? comic.status!.trim()
        : 'Ongoing';
    return _CatalogEntry(
      comic: comic,
      source: source,
      status: status,
      genre: type,
      rating: comic.rating ?? 0,
      updateRank: comic.latestChapterNumber?.round() ?? (1000 - index),
    );
  }

  final ComicSummary comic;
  final String source;
  final String status;
  final String genre;
  final double rating;
  final int updateRank;
}

String _sourceLabel(String sourceName) {
  final value = sourceName.trim();
  if (value.isEmpty) return 'Komiku';
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

const List<String> _sources = [
  'Semua',
  'Komiku',
  'Komikcast',
  'Shinigami',
  'Webtoon',
];

const List<String> _types = ['Semua', 'Manga', 'Manhwa'];

const List<String> _statuses = ['Semua', 'Ongoing', 'Completed', 'Hiatus'];

const List<String> _genres = [
  'Semua',
  'Action',
  'Adventure',
  'Comedy',
  'Fantasy',
  'Romance',
  'Sports',
  'Supernatural',
];

const List<String> _sorts = [
  'Update terbaru',
  'Paling populer',
  'Chapter terbanyak',
  'A-Z',
];
