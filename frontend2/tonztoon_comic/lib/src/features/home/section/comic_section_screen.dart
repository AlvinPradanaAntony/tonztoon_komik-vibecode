import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_icons.dart';
import '../../../models/comic.dart';
import '../../../widgets/comic_card.dart';
import '../../../widgets/comic_filter_sort_sheet.dart';

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
  late ComicFilterSortState _filters = ComicFilterSortState(
    sort: ComicSortOption.normalize(widget.initialSort),
  );

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
              tooltip: 'Filter dan sorting',
              onPressed: _showFilterSheet,
              icon: Badge(
                isLabelVisible: _filters.hasActiveFilters,
                smallSize: 8,
                child: const Icon(TonztoonIcons.slidersHorizontal),
              ),
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
          ComicActiveFilterStrip(filters: _filters, onClear: _clearFilters),
          if (_filters.hasActiveFilters) const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                TonztoonIcons.autoAwesome,
                size: 18,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_filters.sort, style: theme.textTheme.titleMedium),
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
                source: comicSourceDisplayName(comic.sourceName),
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
      final type = comicTypeFilterLabel(comic.type);
      final status = comicStatusFilterLabel(comic.status);
      return matchesComicFilters(
        filters: _filters,
        source: comicSourceDisplayName(comic.sourceName),
        type: type,
        status: status,
        genre: type,
      );
    }).toList();

    switch (_filters.sort) {
      case ComicSortOption.updateNewest:
        filtered.sort(
          (a, b) => (b.latestChapterNumber ?? 0).compareTo(
            a.latestChapterNumber ?? 0,
          ),
        );
      case ComicSortOption.popular:
        filtered.sort(
          (a, b) => _popularityRank(b).compareTo(_popularityRank(a)),
        );
      case ComicSortOption.ratingHigh:
        filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case ComicSortOption.az:
        filtered.sort((a, b) => a.title.compareTo(b.title));
      case ComicSortOption.za:
        filtered.sort((a, b) => b.title.compareTo(a.title));
      case ComicSortOption.relevance:
        break;
    }

    return filtered;
  }

  int _popularityRank(ComicSummary comic) {
    final totalView = comic.totalView ?? 0;
    if (totalView > 0) return totalView;
    return ((comic.rating ?? 0) * 1000).round();
  }

  void _clearFilters() {
    setState(
      () => _filters = ComicFilterSortState(
        sort: ComicSortOption.normalize(widget.initialSort),
      ),
    );
  }

  Future<void> _showFilterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final result = await showComicFilterSortSheet(
      context: context,
      initialState: _filters,
      title: 'Filter ${widget.title}',
      resetSort: ComicSortOption.normalize(widget.initialSort),
    );

    if (result == null) return;
    setState(() => _filters = result.normalized());
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

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}
