import 'package:flutter/material.dart';

import '../../../helpers/app_icons.dart';
import '../../../widgets/app_loading_placeholder.dart';
import '../../../widgets/choice_chip_group.dart';
import '../../../widgets/comic_card.dart';
import '../../../widgets/comic_filter_sort_sheet.dart';

class SectionComicFilterSortState {
  const SectionComicFilterSortState({
    this.type = ComicFilterOption.all,
    this.status = ComicFilterOption.all,
    this.genre = ComicFilterOption.all,
    required this.sort,
  });

  final String type;
  final String status;
  final String genre;
  final String sort;

  bool hasActiveControls(String defaultSort, {required bool includeStatus}) {
    return type != ComicFilterOption.all ||
        (includeStatus && status != ComicFilterOption.all) ||
        genre != ComicFilterOption.all ||
        sort != defaultSort;
  }

  bool get hasActiveFilters =>
      type != ComicFilterOption.all ||
      status != ComicFilterOption.all ||
      genre != ComicFilterOption.all;

  List<String> activeFilterLabels({required bool includeStatus}) => [
    if (type != ComicFilterOption.all) type,
    if (includeStatus && status != ComicFilterOption.all) status,
    if (genre != ComicFilterOption.all) genre,
  ];

  SectionComicFilterSortState reset(String defaultSort) {
    return SectionComicFilterSortState(sort: defaultSort);
  }
}

Future<SectionComicFilterSortState?> showSectionComicFilterSortSheet({
  required BuildContext context,
  required SectionComicFilterSortState initialState,
  required String defaultSort,
  required bool includeStatus,
  required String excludedSort,
  List<String>? genreOptions,
  Future<List<String>>? genreOptionsFuture,
  Future<List<String>>? genreOptionsRefreshFuture,
  BoxConstraints? constraints,
}) {
  return showModalBottomSheet<SectionComicFilterSortState>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    requestFocus: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: constraints,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SectionComicFilterSortSheet(
      initialState: initialState,
      defaultSort: defaultSort,
      includeStatus: includeStatus,
      excludedSort: excludedSort,
      genreOptions: genreOptions,
      genreOptionsFuture: genreOptionsFuture,
      genreOptionsRefreshFuture: genreOptionsRefreshFuture,
    ),
  );
}

class SectionComicFilterSortSheet extends StatefulWidget {
  const SectionComicFilterSortSheet({
    super.key,
    required this.initialState,
    required this.defaultSort,
    required this.includeStatus,
    required this.excludedSort,
    this.genreOptions,
    this.genreOptionsFuture,
    this.genreOptionsRefreshFuture,
  });

  final SectionComicFilterSortState initialState;
  final String defaultSort;
  final bool includeStatus;
  final String excludedSort;
  final List<String>? genreOptions;
  final Future<List<String>>? genreOptionsFuture;
  final Future<List<String>>? genreOptionsRefreshFuture;

  @override
  State<SectionComicFilterSortSheet> createState() =>
      _SectionComicFilterSortSheetState();
}

class _SectionComicFilterSortSheetState
    extends State<SectionComicFilterSortSheet> {
  static const _initialGenreVisibleCount = 18;
  static const _genreVisibleIncrement = 18;

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
    if (_genre != ComicFilterOption.all &&
        values.contains(_genre) &&
        !visible.contains(_genre)) {
      visible.add(_genre);
    }
    return visible;
  }

  int get _remainingGenreCount {
    final options = _genreOptions ?? const <String>[];
    final values = _filterOptionsWithAll(options, selectedValue: _genre);
    return (values.length - _visibleGenreCount).clamp(0, values.length);
  }

  bool get _canLoadMoreGenres => _remainingGenreCount > 0;

  List<String> get _sortValues {
    return ComicSortOption.values
        .where((value) => value != widget.excludedSort)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _resolveGenreOptions();
  }

  Future<void> _resolveGenreOptions() async {
    final future = widget.genreOptionsFuture;
    final refreshFuture = widget.genreOptionsRefreshFuture;
    if (future == null && refreshFuture == null) return;

    if (future != null) {
      setState(() => _genreOptionsLoading = true);
      await _applyGenreOptions(future);
    }

    if (refreshFuture != null) {
      if (!_genreOptionsLoading && mounted) {
        setState(() => _genreOptionsLoading = true);
      }
      await _applyGenreOptions(refreshFuture);
    }
  }

  Future<void> _applyGenreOptions(Future<List<String>> future) async {
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
    final selectedIndex = values.indexOf(_genre);
    if (selectedIndex >= _visibleGenreCount) {
      _visibleGenreCount = selectedIndex + 1;
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
        heightFactor: 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter & Sorting',
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
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tipe', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _TypeCardGrid(
                      selectedType: _type,
                      onChanged: (value) => setState(() => _type = value),
                    ),
                    if (widget.includeStatus) ...[
                      const SizedBox(height: 16),
                      ChoiceChipGroup(
                        label: 'Status',
                        values: ComicFilterOption.statuses,
                        selectedValue: _status,
                        onChanged: (value) => setState(() => _status = value),
                        scrollable: false,
                        labelStyle: theme.textTheme.titleSmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Genre',
                      values: _genreValues,
                      selectedValue: _genre,
                      onChanged: (value) => setState(() => _genre = value),
                      scrollable: false,
                      labelStyle: theme.textTheme.titleSmall,
                    ),
                    if (_genreOptionsLoading) ...[
                      const SizedBox(height: 10),
                      const _SectionGenreOptionsLoading(),
                    ],
                    if (_canLoadMoreGenres) ...[
                      const SizedBox(height: 8),
                      _SectionLoadMoreGenresButton(
                        remainingCount: _remainingGenreCount,
                        onPressed: _loadMoreGenres,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ChoiceChipGroup(
                      label: 'Urutkan',
                      values: _sortValues,
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
                            SectionComicFilterSortState(
                              type: ComicFilterOption.all,
                              status: ComicFilterOption.all,
                              genre: ComicFilterOption.all,
                              sort: widget.defaultSort,
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
                            SectionComicFilterSortState(
                              type: _type,
                              status: widget.includeStatus
                                  ? _status
                                  : ComicFilterOption.all,
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

class SectionActiveFilterStrip extends StatelessWidget {
  const SectionActiveFilterStrip({
    super.key,
    required this.filters,
    required this.includeStatus,
    required this.onClear,
  });

  final SectionComicFilterSortState filters;
  final bool includeStatus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final labels = filters.activeFilterLabels(includeStatus: includeStatus);
    if (labels.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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

class _TypeCardGrid extends StatelessWidget {
  const _TypeCardGrid({required this.selectedType, required this.onChanged});

  final String selectedType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final type in ComicFilterOption.types) ...[
          if (type != ComicFilterOption.types.first) const SizedBox(width: 8),
          Expanded(
            child: _TypeChoiceCard(
              type: type,
              selected: selectedType == type,
              onTap: () => onChanged(type),
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeChoiceCard extends StatelessWidget {
  const _TypeChoiceCard({
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

class _SectionGenreOptionsLoading extends StatelessWidget {
  const _SectionGenreOptionsLoading();

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

class _SectionLoadMoreGenresButton extends StatelessWidget {
  const _SectionLoadMoreGenresButton({
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
