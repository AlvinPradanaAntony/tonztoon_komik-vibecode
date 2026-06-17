part of '../full_catalog_screen.dart';

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.entries, required this.onTap});

  final List<_CatalogEntry> entries;
  final ValueChanged<_CatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      key: const ValueKey('catalog-grid'),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = entries[index];
        return ComicCard(
          comic: entry.comic,
          source: entry.source,
          rating: entry.rating.toStringAsFixed(1),
          width: double.infinity,
          onTap: () => onTap(entry),
        );
      }, childCount: entries.length),
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
