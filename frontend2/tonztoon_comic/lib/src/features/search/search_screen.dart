import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../widgets/choice_chip_group.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../comic/comic_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _keyboardDismissDuration = Duration(milliseconds: 260);
  static const _sheetEnterDuration = Duration(milliseconds: 300);
  static const _sheetExitDuration = Duration(milliseconds: 220);
  static const _searchDelay = Duration(milliseconds: 420);

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _selectedSource = 'Semua';
  String _selectedStatus = 'Semua';
  String _selectedGenre = 'Semua';
  String _selectedSort = 'Relevansi';
  bool _gridView = false;
  bool _filterButtonActive = false;
  bool _isSearching = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim();
    final results = _visibleResults;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cari Komik', style: theme.textTheme.titleLarge),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: _gridView ? 'Tampilan daftar' : 'Tampilan grid',
              onPressed: () => setState(() => _gridView = !_gridView),
              icon: Icon(
                _gridView ? TonztoonIcons.rows : TonztoonIcons.columns,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
        children: [
          _SearchBox(
            controller: _searchController,
            onChanged: _handleSearchChanged,
            onClear: _clearSearch,
            onFilter: _showFilterSheet,
            filterActive: _filterButtonActive,
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _isSearching
                ? _SearchLoadingPlaceholder(
                    key: ValueKey('search-loading-$_gridView'),
                    gridView: _gridView,
                  )
                : query.isEmpty
                ? const _SearchEmptyState(
                    key: ValueKey('search-empty-initial'),
                    icon: TonztoonIcons.search,
                    title: 'Cari komik',
                    message:
                        'Masukkan judul, author, genre, atau sumber untuk mulai mencari.',
                  )
                : results.isEmpty
                ? _SearchEmptyState(
                    key: const ValueKey('search-empty-results'),
                    icon: TonztoonIcons.search,
                    title: 'Tidak ada hasil',
                    message: 'Tidak ada komik yang cocok untuk "$query".',
                  )
                : Column(
                    key: ValueKey('search-results-$_gridView-$query'),
                    children: [
                      _ResultHeader(query: query, resultCount: results.length),
                      const SizedBox(height: 12),
                      _gridView
                          ? _ResultGrid(comics: results)
                          : _ResultList(comics: results),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<_SearchComicUi> get _visibleResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];

    final filtered = _searchResults.where((comic) {
      final values = [
        comic.summary.title,
        comic.summary.type ?? '',
        comic.source,
        comic.type,
        comic.status,
        comic.genre,
        comic.chapter,
        comic.description,
      ].join(' ').toLowerCase();
      final queryMatches = values.contains(query);
      final sourceMatches =
          _selectedSource == 'Semua' || comic.source == _selectedSource;
      final statusMatches =
          _selectedStatus == 'Semua' || comic.status == _selectedStatus;
      final genreMatches =
          _selectedGenre == 'Semua' || comic.genre == _selectedGenre;

      return queryMatches && sourceMatches && statusMatches && genreMatches;
    }).toList();

    switch (_selectedSort) {
      case 'Rating tinggi':
        filtered.sort((a, b) => b.ratingValue.compareTo(a.ratingValue));
      case 'Chapter terbanyak':
        filtered.sort(
          (a, b) => (b.summary.latestChapterNumber ?? 0).compareTo(
            a.summary.latestChapterNumber ?? 0,
          ),
        );
      case 'Update terbaru':
        filtered.sort((a, b) => b.updateRank.compareTo(a.updateRank));
    }

    return filtered;
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      setState(() => _isSearching = false);
      return;
    }

    setState(() => _isSearching = true);
    _searchDebounce = Timer(_searchDelay, () {
      if (!mounted) return;
      setState(() => _isSearching = false);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _isSearching = false);
  }

  Future<void> _showFilterSheet() async {
    await _dismissKeyboardBeforeSheet();
    if (!mounted) return;

    setState(() => _filterButtonActive = true);

    final result = await showModalBottomSheet<_FilterState>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      requestFocus: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: const AnimationStyle(
        duration: _sheetEnterDuration,
        reverseDuration: _sheetExitDuration,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _FilterSheet(
        initialState: _FilterState(
          source: _selectedSource,
          status: _selectedStatus,
          genre: _selectedGenre,
          sort: _selectedSort,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _filterButtonActive = false);

    if (result == null) return;
    setState(() {
      _selectedSource = result.source;
      _selectedStatus = result.status;
      _selectedGenre = result.genre;
      _selectedSort = result.sort;
    });
  }

  Future<void> _dismissKeyboardBeforeSheet() async {
    final keyboardWasVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await WidgetsBinding.instance.endOfFrame;

    if (keyboardWasVisible) {
      await Future<void>.delayed(_keyboardDismissDuration);
    }
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
    required this.filterActive,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.28 : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Judul, author, atau genre',
          prefixIcon: const Icon(TonztoonIcons.search),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: onClear,
                    icon: const Icon(TonztoonIcons.close),
                  ),
                IconButton(
                  tooltip: 'Filter dan sorting',
                  onPressed: onFilter,
                  icon: const Icon(TonztoonIcons.slidersHorizontal),
                  style: IconButton.styleFrom(
                    backgroundColor: filterActive
                        ? colorScheme.primary.withValues(alpha: 0.16)
                        : Colors.transparent,
                    foregroundColor: filterActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 18,
          ),
        ),
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initialState});

  final _FilterState initialState;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _source = widget.initialState.source;
  late String _status = widget.initialState.status;
  late String _genre = widget.initialState.genre;
  late String _sort = widget.initialState.sort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter dan Sorting',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(TonztoonIcons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Atur hasil pencarian berdasarkan sumber, status, genre, dan urutan.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    ChoiceChipGroup(
                      label: 'Sumber',
                      values: const [
                        'Semua',
                        'Komiku',
                        'Komikcast',
                        'Shinigami',
                      ],
                      selectedValue: _source,
                      onChanged: (value) => setState(() => _source = value),
                    ),
                    const SizedBox(height: 14),
                    ChoiceChipGroup(
                      label: 'Status',
                      values: const ['Semua', 'Ongoing', 'Completed', 'Hiatus'],
                      selectedValue: _status,
                      onChanged: (value) => setState(() => _status = value),
                    ),
                    const SizedBox(height: 14),
                    ChoiceChipGroup(
                      label: 'Genre',
                      values: const [
                        'Semua',
                        'Action',
                        'Fantasy',
                        'Comedy',
                        'Drama',
                        'Adventure',
                      ],
                      selectedValue: _genre,
                      onChanged: (value) => setState(() => _genre = value),
                    ),
                    const SizedBox(height: 14),
                    ChoiceChipGroup(
                      label: 'Urutkan',
                      values: const [
                        'Relevansi',
                        'Update terbaru',
                        'Rating tinggi',
                        'Chapter terbanyak',
                      ],
                      selectedValue: _sort,
                      onChanged: (value) => setState(() => _sort = value),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _source = 'Semua';
                            _status = 'Semua';
                            _genre = 'Semua';
                            _sort = 'Relevansi';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          side: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            _FilterState(
                              source: _source,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterState {
  const _FilterState({
    required this.source,
    required this.status,
    required this.genre,
    required this.sort,
  });

  final String source;
  final String status;
  final String genre;
  final String sort;
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    super.key,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, size: 38, color: colorScheme.secondary),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchLoadingPlaceholder extends StatelessWidget {
  const _SearchLoadingPlaceholder({super.key, required this.gridView});

  final bool gridView;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SearchLoadingHeader(),
        const SizedBox(height: 12),
        gridView ? const _SearchGridShimmer() : const _SearchListShimmer(),
      ],
    );
  }
}

class _SearchLoadingHeader extends StatelessWidget {
  const _SearchLoadingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SectionTitle(
            icon: TonztoonIcons.autoAwesome,
            title: 'Mencari...',
          ),
        ),
      ],
    );
  }
}

class _SearchListShimmer extends StatelessWidget {
  const _SearchListShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < 4; index++) ...[
          const _SearchResultTileShimmer(),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SearchGridShimmer extends StatelessWidget {
  const _SearchGridShimmer();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.51,
      ),
      itemBuilder: (context, index) => const _SearchGridCardShimmer(),
    );
  }
}

class _SearchResultTileShimmer extends StatelessWidget {
  const _SearchResultTileShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _SearchShimmer(
          child: Row(
            children: [
              const _ShimmerBlock(width: 78, height: 110, borderRadius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _ShimmerBlock(width: double.infinity, height: 18),
                    SizedBox(height: 8),
                    _ShimmerBlock(width: 168, height: 14),
                    SizedBox(height: 14),
                    _ShimmerBlock(width: double.infinity, height: 12),
                    SizedBox(height: 7),
                    _ShimmerBlock(width: 210, height: 12),
                    SizedBox(height: 14),
                    _ShimmerBlock(width: 96, height: 14),
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

class _SearchGridCardShimmer extends StatelessWidget {
  const _SearchGridCardShimmer();

  @override
  Widget build(BuildContext context) {
    return _SearchShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(child: _ShimmerBlock(width: double.infinity)),
          SizedBox(height: 9),
          _ShimmerBlock(width: double.infinity, height: 14),
          SizedBox(height: 7),
          _ShimmerBlock(width: 112, height: 14),
        ],
      ),
    );
  }
}

class _SearchShimmer extends StatelessWidget {
  const _SearchShimmer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final highlightColor = colorScheme.surfaceContainerLow;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: child,
    );
  }
}

class _ShimmerBlock extends StatelessWidget {
  const _ShimmerBlock({
    required this.width,
    this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.query, required this.resultCount});

  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final text = query.trim().isEmpty ? 'Rekomendasi' : 'Hasil untuk "$query"';

    return Row(
      children: [
        Expanded(
          child: _SectionTitle(icon: TonztoonIcons.autoAwesome, title: text),
        ),
        Text(
          '$resultCount komik',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.comics});

  final List<_SearchComicUi> comics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final comic in comics) ...[
          _SearchResultTile(comic: comic),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.comics});

  final List<_SearchComicUi> comics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.51,
      ),
      itemBuilder: (context, index) {
        final comic = comics[index];
        return ComicCard(
          comic: comic.summary,
          source: comic.source,
          rating: comic.rating,
          width: double.infinity,
          onTap: () => _openComicDetail(context, comic.summary),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.comic});

  final _SearchComicUi comic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openComicDetail(context, comic.summary),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ComicCover(
                imageUrl: comic.summary.coverImageUrl,
                width: 78,
                height: 110,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.summary.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${comic.source} • ${comicTypeFlag(comic.summary.type)} ${comic.type}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _InlineRating(label: comic.rating),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      comic.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      comic.chapter,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.secondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(TonztoonIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineRating extends StatelessWidget {
  const _InlineRating({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(TonztoonIcons.starFilled, size: 14, color: Colors.amber),
            const SizedBox(width: 5),
            Text(
              label,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

void _openComicDetail(BuildContext context, ComicSummary comic) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ComicDetailScreen(comic: comic),
    ),
  );
}

class _SearchComicUi {
  const _SearchComicUi({
    required this.summary,
    required this.source,
    required this.type,
    required this.rating,
    required this.status,
    required this.genre,
    required this.chapter,
    required this.description,
    required this.updateRank,
  });

  final ComicSummary summary;
  final String source;
  final String type;
  final String rating;
  final String status;
  final String genre;
  final String chapter;
  final String description;
  final int updateRank;

  double get ratingValue => double.tryParse(rating) ?? 0;
}

final List<_SearchComicUi> _searchResults = [
  _SearchComicUi(
    summary: dummyComics[0],
    source: 'Komiku',
    type: 'Manhwa',
    rating: '4.9',
    status: 'Completed',
    genre: 'Action',
    chapter: 'Chapter 179',
    description:
        'Hunter paling lemah mendapat sistem misterius dan tumbuh menjadi kekuatan yang menembus batas dunia dungeon.',
    updateRank: 98,
  ),
  _SearchComicUi(
    summary: dummyComics[2],
    source: 'Shinigami',
    type: 'Manhwa',
    rating: '4.8',
    status: 'Ongoing',
    genre: 'Fantasy',
    chapter: 'Chapter 200',
    description:
        'Pembaca tunggal novel apokaliptik memakai pengetahuannya untuk bertahan saat cerita berubah menjadi kenyataan.',
    updateRank: 100,
  ),
  _SearchComicUi(
    summary: dummyComics[3],
    source: 'Komikcast',
    type: 'Manga',
    rating: '4.6',
    status: 'Ongoing',
    genre: 'Action',
    chapter: 'Chapter 24',
    description:
        'Pemburu pedang sihir mengejar kelompok kriminal dalam dunia bawah yang penuh dendam dan teknik berbahaya.',
    updateRank: 97,
  ),
  _SearchComicUi(
    summary: dummyComics[1],
    source: 'Komiku Asia',
    type: 'Manga',
    rating: '4.8',
    status: 'Ongoing',
    genre: 'Adventure',
    chapter: 'Chapter 1111',
    description:
        'Kru Topi Jerami berlayar dari pulau ke pulau, membuka rahasia besar sambil mengejar harta legendaris.',
    updateRank: 99,
  ),
];
