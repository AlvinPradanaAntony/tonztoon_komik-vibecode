import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_icons.dart';
import '../../../models/comic.dart';
import '../../../widgets/choice_chip_group.dart';
import '../../../widgets/comic_card.dart';

class ComicSectionPayload {
  const ComicSectionPayload({
    required this.title,
    required this.subtitle,
    required this.comics,
    required this.initialSort,
  });

  final String title;
  final String subtitle;
  final List<ComicSummary> comics;
  final String initialSort;
}

class ComicSectionScreen extends StatefulWidget {
  const ComicSectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.comics,
    required this.initialSort,
  });

  final String title;
  final String subtitle;
  final List<ComicSummary> comics;
  final String initialSort;

  @override
  State<ComicSectionScreen> createState() => _ComicSectionScreenState();
}

class _ComicSectionScreenState extends State<ComicSectionScreen> {
  late String _selectedSort = widget.initialSort;
  String _selectedSource = 'Semua';
  String _selectedType = 'Semua';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final comics = _visibleComics;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(TonztoonIcons.arrowBack),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: 'Urutkan',
              onPressed: _showSortSheet,
              icon: const Icon(TonztoonIcons.slidersHorizontal),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _SectionHero(
            title: widget.title,
            subtitle: widget.subtitle,
            count: comics.length,
          ),
          const SizedBox(height: 18),
          _FilterBar(
            selectedSource: _selectedSource,
            selectedType: _selectedType,
            onSourceChanged: (value) => setState(() => _selectedSource = value),
            onTypeChanged: (value) => setState(() => _selectedType = value),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                TonztoonIcons.autoAwesome,
                size: 18,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_selectedSort, style: theme.textTheme.titleMedium),
              ),
              Text(
                '${comics.length} komik',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
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
                comic: comic,
                source: comicSourceLabel(comic),
                width: double.infinity,
                onTap: () => _openComicDetail(context, comic),
              );
            },
          ),
        ],
      ),
    );
  }

  List<ComicSummary> get _visibleComics {
    final filtered = widget.comics.where((comic) {
      final sourceMatches =
          _selectedSource == 'Semua' ||
          comic.title.length % 2 == _sourceSeed(_selectedSource);
      final typeMatches =
          _selectedType == 'Semua' || comic.type == _selectedType;
      return sourceMatches && typeMatches;
    }).toList();

    if (_selectedSort == 'Chapter terbanyak') {
      filtered.sort(
        (a, b) =>
            (b.latestChapterNumber ?? 0).compareTo(a.latestChapterNumber ?? 0),
      );
    } else if (_selectedSort == 'A-Z') {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    }

    return filtered;
  }

  int _sourceSeed(String source) {
    return switch (source) {
      'Komiku' => 0,
      'Komikcast' => 1,
      'Shinigami' => 0,
      _ => 0,
    };
  }

  Future<void> _showSortSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _SortSheet(selectedSort: _selectedSort),
    );

    if (result == null) return;
    setState(() => _selectedSort = result);
  }
}

class _SectionHero extends StatelessWidget {
  const _SectionHero({
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String title;
  final String subtitle;
  final int count;

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
              ? const [Color(0xFF18202B), Color(0xFF241A19)]
              : const [Color(0xFFFFF3DD), Color(0xFFE8F7FF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.76),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(TonztoonIcons.bookOpen, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 5),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _CountBadge(count: count),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          '$count',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedSource,
    required this.selectedType,
    required this.onSourceChanged,
    required this.onTypeChanged,
  });

  final String selectedSource;
  final String selectedType;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceChipGroup(
          label: 'Sumber',
          values: const ['Semua', 'Komiku', 'Komikcast', 'Shinigami'],
          selectedValue: selectedSource,
          onChanged: onSourceChanged,
        ),
        const SizedBox(height: 12),
        ChoiceChipGroup(
          label: 'Tipe',
          values: const ['Semua', 'Manga', 'Manhwa'],
          selectedValue: selectedType,
          onChanged: onTypeChanged,
        ),
      ],
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.selectedSort});

  final String selectedSort;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Urutkan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final sort in const [
              'Update terbaru',
              'Paling populer',
              'Chapter terbanyak',
              'A-Z',
            ])
              _SortOption(
                label: sort,
                selected: selectedSort == sort,
                onTap: () => Navigator.of(context).pop(sort),
              ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (selected)
                Icon(TonztoonIcons.check, color: colorScheme.primary),
            ],
          ),
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
