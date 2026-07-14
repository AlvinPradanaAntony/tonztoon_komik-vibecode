import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import 'app_loading_placeholder.dart';
import 'comic_card.dart';
import 'choice_chip_group.dart';

class ComicFilterSortState {
  const ComicFilterSortState({
    this.source = ComicFilterOption.all,
    this.type = ComicFilterOption.all,
    this.status = ComicFilterOption.all,
    this.genre = ComicFilterOption.all,
    this.sort = ComicSortOption.relevance,
  });

  final String source;
  final String type;
  final String status;
  final String genre;
  final String sort;

  bool get hasActiveFilters =>
      source != ComicFilterOption.all ||
      type != ComicFilterOption.all ||
      status != ComicFilterOption.all ||
      genre != ComicFilterOption.all;

  List<String> get activeFilterLabels => [
    ...selectedFilterValues(source),
    ...selectedFilterValues(type),
    ...selectedFilterValues(status),
    ...selectedFilterValues(genre),
  ];

  ComicFilterSortState reset({String sort = ComicSortOption.relevance}) {
    return ComicFilterSortState(sort: sort);
  }

  ComicFilterSortState normalized() {
    return ComicFilterSortState(
      source: source,
      type: type,
      status: status,
      genre: genre,
      sort: ComicSortOption.normalize(sort),
    );
  }
}

abstract final class ComicFilterOption {
  static const all = 'Semua';

  static const sources = [
    all,
    'Komiku',
    'Komiku Asia',
    'Komikcast',
    'Shinigami',
  ];

  static const types = [all, 'Manga', 'Manhwa', 'Manhua'];

  static const statuses = [all, 'Ongoing', 'Completed', 'Hiatus'];

  static const genres = [
    all,
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Romance',
    'Slice Of Life',
  ];
}

abstract final class ComicSortOption {
  static const updateNewest = 'Update Terbaru';
  static const popular = 'Populer';
  static const totalViewHigh = 'Total View Tertinggi';
  static const az = 'A-Z';
  static const za = 'Z-A';
  static const ratingHigh = 'Rating Tinggi';
  static const relevance = 'Relevansi';

  static const values = [
    relevance,
    updateNewest,
    popular,
    totalViewHigh,
    az,
    za,
    ratingHigh,
  ];

  static String normalize(String value) {
    return switch (value.trim().toLowerCase()) {
      'update terbaru' => updateNewest,
      'paling populer' || 'populer' => popular,
      'total view tertinggi' ||
      'view tertinggi' ||
      'total_view' ||
      'total_view_high' => totalViewHigh,
      'a-z' => az,
      'z-a' => za,
      'rating tinggi' => ratingHigh,
      'relevansi' => relevance,
      _ => updateNewest,
    };
  }
}

String comicSourceDisplayName(String sourceName) {
  return comicSourceNameLabel(sourceName);
}

String comicTypeFilterLabel(String? type, {String fallback = 'Manga'}) {
  final value = type?.trim() ?? '';
  return value.isEmpty ? fallback : comicBadgeLabel(value);
}

String comicStatusFilterLabel(String? status, {String fallback = 'Ongoing'}) {
  final value = status?.trim() ?? '';
  return value.isEmpty ? fallback : comicBadgeLabel(value);
}

bool matchesComicFilters({
  required ComicFilterSortState filters,
  required String source,
  required String type,
  required String status,
  required String genre,
}) {
  return filterSelectionMatches(filters.source, source) &&
      filterSelectionMatches(filters.type, type) &&
      filterSelectionMatches(filters.status, status) &&
      filterSelectionMatches(filters.genre, genre);
}

List<String> selectedFilterValues(String selection) {
  if (selection == ComicFilterOption.all || selection.trim().isEmpty) {
    return const [];
  }
  return selection
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

bool filterSelectionMatches(String selection, String value) {
  final selected = selectedFilterValues(selection);
  return selected.isEmpty || selected.contains(value);
}

String toggleFilterSelection(String selection, String value) {
  if (value == ComicFilterOption.all) return ComicFilterOption.all;

  final selected = selectedFilterValues(selection).toSet();
  if (selected.contains(value)) {
    selected.remove(value);
  } else {
    selected.add(value);
  }
  if (selected.isEmpty) return ComicFilterOption.all;
  return selected.join(',');
}

class ComicActiveFilterStrip extends StatelessWidget {
  const ComicActiveFilterStrip({
    super.key,
    required this.filters,
    required this.onClear,
  });

  final ComicFilterSortState filters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!filters.hasActiveFilters) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in filters.activeFilterLabels) ...[
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

Future<ComicFilterSortState?> showComicFilterSortSheet({
  required BuildContext context,
  required ComicFilterSortState initialState,
  String title = 'Filter & Sorting',
  String description =
      'Atur komik berdasarkan sumber, tipe, status, genre, dan urutan.',
  String resetSort = ComicSortOption.relevance,
  List<String>? genreOptions,
  Future<List<String>>? genreOptionsFuture,
  Future<List<String>>? genreOptionsRefreshFuture,
  bool showSource = true,
  bool showType = true,
  bool showStatus = true,
  bool showGenre = true,
  List<String>? typeOptions,
  List<String>? statusOptions,
  List<String>? sortOptions,
  AnimationStyle? animationStyle,
  BoxConstraints? constraints,
}) {
  return showModalBottomSheet<ComicFilterSortState>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    requestFocus: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: constraints,
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: animationStyle,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => ComicFilterSortSheet(
      initialState: initialState.normalized(),
      title: title,
      description: description,
      resetSort: ComicSortOption.normalize(resetSort),
      genreOptions: genreOptions,
      genreOptionsFuture: genreOptionsFuture,
      genreOptionsRefreshFuture: genreOptionsRefreshFuture,
      showSource: showSource,
      showType: showType,
      showStatus: showStatus,
      showGenre: showGenre,
      typeOptions: typeOptions,
      statusOptions: statusOptions,
      sortOptions: sortOptions,
    ),
  );
}

class ComicFilterSortSheet extends StatefulWidget {
  const ComicFilterSortSheet({
    super.key,
    required this.initialState,
    required this.title,
    required this.description,
    required this.resetSort,
    this.genreOptions,
    this.genreOptionsFuture,
    this.genreOptionsRefreshFuture,
    this.showSource = true,
    this.showType = true,
    this.showStatus = true,
    this.showGenre = true,
    this.typeOptions,
    this.statusOptions,
    this.sortOptions,
  });

  final ComicFilterSortState initialState;
  final String title;
  final String description;
  final String resetSort;
  final List<String>? genreOptions;
  final Future<List<String>>? genreOptionsFuture;
  final Future<List<String>>? genreOptionsRefreshFuture;
  final bool showSource;
  final bool showType;
  final bool showStatus;
  final bool showGenre;
  final List<String>? typeOptions;
  final List<String>? statusOptions;
  final List<String>? sortOptions;

  @override
  State<ComicFilterSortSheet> createState() => _ComicFilterSortSheetState();
}

class _ComicFilterSortSheetState extends State<ComicFilterSortSheet> {
  static const _initialGenreVisibleCount = 18;
  static const _genreVisibleIncrement = 18;

  late String _source = widget.initialState.source;
  late String _type = widget.initialState.type;
  late String _status = widget.initialState.status;
  late String _genre = widget.initialState.genre;
  late String _sort = widget.initialState.sort;
  late List<String>? _genreOptions = widget.genreOptions;
  int _visibleGenreCount = _initialGenreVisibleCount;
  bool _genreOptionsLoading = false;

  List<String> get _genreValues {
    final options = _genreOptions ?? const <String>[];
    final values = _filterOptionsWithAll(options, selectedValue: _genre);
    final visibleCount = _visibleGenreCount.clamp(1, values.length);
    final visible = values.take(visibleCount).toList();
    for (final selected in selectedFilterValues(_genre)) {
      if (values.contains(selected) && !visible.contains(selected)) {
        visible.add(selected);
      }
    }
    return visible;
  }

  int get _remainingGenreCount {
    final options = _genreOptions ?? const <String>[];
    final values = _filterOptionsWithAll(options, selectedValue: _genre);
    return (values.length - _visibleGenreCount).clamp(0, values.length);
  }

  bool get _canLoadMoreGenres => _remainingGenreCount > 0;

  @override
  void initState() {
    super.initState();
    if (widget.showGenre) _resolveGenreOptions();
  }

  Future<void> _resolveGenreOptions() async {
    final future = widget.genreOptionsFuture;
    final refreshFuture = widget.genreOptionsRefreshFuture;
    if (future == null && refreshFuture == null) return;

    if (future != null) {
      _genreOptionsLoading = true;
      try {
        final options = await future;
        if (!mounted) return;
        final cleanOptions = options
            .map((option) => option.trim())
            .where((option) => option.isNotEmpty)
            .toList(growable: false);
        setState(() {
          if (cleanOptions.isNotEmpty) _genreOptions = cleanOptions;
          _ensureSelectedGenreVisible();
          _genreOptionsLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _genreOptionsLoading = false);
      }
    }

    if (refreshFuture != null) {
      await _resolveRefreshedGenreOptions(refreshFuture);
    }
  }

  Future<void> _resolveRefreshedGenreOptions(
    Future<List<String>> future,
  ) async {
    if (!_genreOptionsLoading && mounted) {
      setState(() => _genreOptionsLoading = true);
    }
    try {
      final options = await future;
      if (!mounted) return;
      final cleanOptions = options
          .map((option) => option.trim())
          .where((option) => option.isNotEmpty)
          .toList(growable: false);
      setState(() {
        if (cleanOptions.isNotEmpty) _genreOptions = cleanOptions;
        _ensureSelectedGenreVisible();
        _genreOptionsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _genreOptionsLoading = false);
    }
  }

  void _ensureSelectedGenreVisible() {
    final options = _genreOptions;
    if (options == null || _genre == ComicFilterOption.all) return;

    final values = _filterOptionsWithAll(options, selectedValue: _genre);
    for (final selected in selectedFilterValues(_genre)) {
      final selectedIndex = values.indexOf(selected);
      if (selectedIndex >= _visibleGenreCount) {
        _visibleGenreCount = selectedIndex + 1;
      }
    }
  }

  void _loadMoreGenres() {
    setState(() {
      _visibleGenreCount += _genreVisibleIncrement;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
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
                    Text(widget.description, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 18),
                    if (widget.showSource) ...[
                      ChoiceChipGroup(
                        label: 'Sumber',
                        values: ComicFilterOption.sources,
                        selectedValue: _source,
                        selectedValues: selectedFilterValues(_source).toSet(),
                        multiSelect: true,
                        onChanged: (value) => setState(
                          () => _source = toggleFilterSelection(_source, value),
                        ),
                        scrollable: false,
                        labelStyle: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.showType) ...[
                      Text('Tipe', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ComicTypeCardGrid(
                        types: widget.typeOptions ?? ComicFilterOption.types,
                        selectedType: _type,
                        onChanged: (value) => setState(
                          () => _type = toggleFilterSelection(_type, value),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.showStatus) ...[
                      ChoiceChipGroup(
                        label: 'Status',
                        values:
                            widget.statusOptions ?? ComicFilterOption.statuses,
                        selectedValue: _status,
                        selectedValues: selectedFilterValues(_status).toSet(),
                        multiSelect: true,
                        onChanged: (value) => setState(
                          () => _status = toggleFilterSelection(_status, value),
                        ),
                        scrollable: false,
                        labelStyle: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.showGenre) ...[
                      ChoiceChipGroup(
                        label: 'Genre',
                        values: _genreValues,
                        selectedValue: _genre,
                        selectedValues: selectedFilterValues(_genre).toSet(),
                        multiSelect: true,
                        onChanged: (value) => setState(
                          () => _genre = toggleFilterSelection(_genre, value),
                        ),
                        scrollable: false,
                        labelStyle: theme.textTheme.titleSmall,
                      ),
                      if (_genreOptionsLoading) ...[
                        const SizedBox(height: 10),
                        const _GenreOptionsLoading(),
                      ],
                      if (_canLoadMoreGenres) ...[
                        const SizedBox(height: 8),
                        _LoadMoreGenresButton(
                          remainingCount: _remainingGenreCount,
                          onPressed: _loadMoreGenres,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                    ChoiceChipGroup(
                      label: 'Urutkan',
                      values: widget.sortOptions ?? ComicSortOption.values,
                      selectedValue: _sort,
                      onChanged: (value) => setState(() => _sort = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
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
                          Navigator.of(context).pop(
                            ComicFilterSortState(
                              source: ComicFilterOption.all,
                              type: ComicFilterOption.all,
                              status: ComicFilterOption.all,
                              genre: ComicFilterOption.all,
                              sort: widget.resetSort,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          side: BorderSide(color: colorScheme.outlineVariant),
                          backgroundColor: colorScheme.surfaceContainer,
                          foregroundColor: colorScheme.onSurface,
                        ),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            ComicFilterSortState(
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
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreOptionsLoading extends StatelessWidget {
  const _GenreOptionsLoading();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppShimmerBlock(width: 76, height: 32, borderRadius: 18),
          AppShimmerBlock(width: 92, height: 32, borderRadius: 18),
          AppShimmerBlock(width: 84, height: 32, borderRadius: 18),
        ],
      ),
    );
  }
}

class _LoadMoreGenresButton extends StatelessWidget {
  const _LoadMoreGenresButton({
    required this.remainingCount,
    required this.onPressed,
  });

  final int remainingCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text('Muat genre lainnya ($remainingCount)'),
      ),
    );
  }
}

class ComicTypeCardGrid extends StatelessWidget {
  const ComicTypeCardGrid({
    super.key,
    this.types = ComicFilterOption.types,
    required this.selectedType,
    required this.onChanged,
  });

  final List<String> types;
  final String selectedType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedValues = selectedFilterValues(selectedType).toSet();
    return Row(
      children: [
        for (final type in types) ...[
          if (type != types.first) const SizedBox(width: 8),
          Expanded(
            child: _ComicTypeChoiceCard(
              type: type,
              selected: type == ComicFilterOption.all
                  ? selectedValues.isEmpty
                  : selectedValues.contains(type),
              onTap: () => onChanged(type),
            ),
          ),
        ],
      ],
    );
  }
}

class _ComicTypeChoiceCard extends StatelessWidget {
  const _ComicTypeChoiceCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = selected ? colors.primary : colors.onSurfaceVariant;
    final flag = type == ComicFilterOption.all ? '🌐' : comicTypeFlag(type);

    return Semantics(
      button: true,
      selected: selected,
      label: type,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.11)
            : colors.surfaceContainerHighest.withValues(alpha: 0.58),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.7),
            width: selected ? 1.8 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(
              children: [
                Text(flag, style: const TextStyle(fontSize: 30, height: 1)),
                const SizedBox(height: 9),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    type,
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
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

List<String> _filterOptionsWithAll(
  Iterable<String> options, {
  required String selectedValue,
}) {
  final values = <String>[ComicFilterOption.all];
  final seen = <String>{ComicFilterOption.all.toLowerCase()};

  for (final option in options) {
    final value = option.trim();
    if (value.isEmpty) continue;
    final key = value.toLowerCase();
    if (seen.add(key)) values.add(value);
  }

  for (final selected in selectedFilterValues(selectedValue)) {
    if (seen.add(selected.toLowerCase())) {
      values.add(selected);
    }
  }

  return values;
}
