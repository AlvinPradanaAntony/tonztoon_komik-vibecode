part of '../full_catalog_screen.dart';

const double _catalogGridMinColumnWidth = 98;
const int _catalogGridMaxColumnCount = 6;
const double _catalogGridHorizontalSpacing = 12;
const double _catalogGridVerticalSpacing = 10;

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.entries, required this.onTap});

  final List<_CatalogEntry> entries;
  final ValueChanged<_CatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return AppSliverColumnGrid<_CatalogEntry>(
      key: const ValueKey('catalog-grid'),
      items: entries,
      minColumnWidth: _catalogGridMinColumnWidth,
      maxColumnCount: _catalogGridMaxColumnCount,
      horizontalSpacing: _catalogGridHorizontalSpacing,
      verticalSpacing: _catalogGridVerticalSpacing,
      itemBuilder: (context, entry) {
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
    final childCount = entries.isEmpty ? 0 : entries.length * 2 - 1;

    return SliverList(
      key: const ValueKey('catalog-list'),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) return const SizedBox(height: 12);
        final entry = entries[index ~/ 2];
        return ComicListCard(
          comic: entry.comic,
          source: entry.source,
          rating: entry.rating,
          onTap: () => onTap(entry),
        );
      }, childCount: childCount),
    );
  }
}

/// In-flight indicator shown above [LoadMoreFooter] while the next catalog page
/// is loading. Rendered as a separate sliver so the footer itself stays a
/// text-only "all loaded" message shared across the app.
class _CatalogLoadingMore extends StatelessWidget {
  const _CatalogLoadingMore();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: colorScheme.secondary,
          ),
        ),
      ),
    );
  }
}
