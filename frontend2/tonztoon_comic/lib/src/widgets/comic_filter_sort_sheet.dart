import 'package:flutter/material.dart';

import '../core/app_icons.dart';
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
    if (source != ComicFilterOption.all) source,
    if (type != ComicFilterOption.all) type,
    if (status != ComicFilterOption.all) status,
    if (genre != ComicFilterOption.all) genre,
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
  static const az = 'A-Z';
  static const za = 'Z-A';
  static const ratingHigh = 'Rating Tinggi';
  static const relevance = 'Relevansi';

  static const values = [relevance, updateNewest, popular, az, za, ratingHigh];

  static String normalize(String value) {
    return switch (value.trim().toLowerCase()) {
      'update terbaru' => updateNewest,
      'paling populer' || 'populer' => popular,
      'a-z' => az,
      'z-a' => za,
      'rating tinggi' => ratingHigh,
      'relevansi' => relevance,
      _ => updateNewest,
    };
  }
}

String comicSourceDisplayName(String sourceName) {
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
  return (filters.source == ComicFilterOption.all ||
          source == filters.source) &&
      (filters.type == ComicFilterOption.all || type == filters.type) &&
      (filters.status == ComicFilterOption.all || status == filters.status) &&
      (filters.genre == ComicFilterOption.all || genre == filters.genre);
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
  String title = 'Filter dan Sorting',
  String description =
      'Atur komik berdasarkan sumber, tipe, status, genre, dan urutan.',
  String resetSort = ComicSortOption.relevance,
  List<String>? genreOptions,
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
  });

  final ComicFilterSortState initialState;
  final String title;
  final String description;
  final String resetSort;
  final List<String>? genreOptions;

  @override
  State<ComicFilterSortSheet> createState() => _ComicFilterSortSheetState();
}

class _ComicFilterSortSheetState extends State<ComicFilterSortSheet> {
  late String _source = widget.initialState.source;
  late String _type = widget.initialState.type;
  late String _status = widget.initialState.status;
  late String _genre = widget.initialState.genre;
  late String _sort = widget.initialState.sort;

  List<String> get _genreValues {
    final options = widget.genreOptions ?? ComicFilterOption.genres;
    return _filterOptionsWithAll(options, selectedValue: _genre);
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                    ChoiceChipGroup(
                      label: 'Sumber',
                      values: ComicFilterOption.sources,
                      selectedValue: _source,
                      onChanged: (value) => setState(() => _source = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Tipe',
                      values: ComicFilterOption.types,
                      selectedValue: _type,
                      onChanged: (value) => setState(() => _type = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Status',
                      values: ComicFilterOption.statuses,
                      selectedValue: _status,
                      onChanged: (value) => setState(() => _status = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Genre',
                      values: _genreValues,
                      selectedValue: _genre,
                      onChanged: (value) => setState(() => _genre = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Urutkan',
                      values: ComicSortOption.values,
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
                          setState(() {
                            _source = ComicFilterOption.all;
                            _type = ComicFilterOption.all;
                            _status = ComicFilterOption.all;
                            _genre = ComicFilterOption.all;
                            _sort = widget.resetSort;
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

  final selected = selectedValue.trim();
  if (selected.isNotEmpty &&
      selected != ComicFilterOption.all &&
      seen.add(selected.toLowerCase())) {
    values.add(selected);
  }

  return values;
}
