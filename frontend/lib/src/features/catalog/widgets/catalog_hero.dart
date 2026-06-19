part of '../full_catalog_screen.dart';

class _CatalogHero extends StatelessWidget {
  const _CatalogHero({
    required this.visibleCount,
    required this.totalCount,
    required this.sourceLabel,
  });

  final int visibleCount;
  final int totalCount;
  final String sourceLabel;

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
                    'Semua judul dari $sourceLabel yang tersimpan di katalog.',
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

class _CatalogListHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CatalogListHeaderDelegate({required this.child, required this.showShadow});

  static const double _height = 44;

  final Widget child;
  final bool showShadow;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: (showShadow || overlapsContent)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.38 : 0.16,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
        border: Border(
          bottom: BorderSide(
            color: (showShadow || overlapsContent)
                ? colorScheme.outlineVariant.withValues(alpha: 0.42)
                : Colors.transparent,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CatalogListHeaderDelegate oldDelegate) {
    return child != oldDelegate.child || showShadow != oldDelegate.showShadow;
  }
}

class _CatalogListHeader extends StatelessWidget {
  const _CatalogListHeader({
    required this.loadedCount,
    required this.sortLabel,
  });

  final int loadedCount;
  final String sortLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Jelajahi',
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 18),
        Flexible(
          flex: 3,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$loadedCount komik dimuat',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CatalogSortPill(label: sortLabel, scale: 0.8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogSortPill extends StatelessWidget {
  const _CatalogSortPill({required this.label, this.scale = 1});

  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final clampedScale = scale.clamp(0.76, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16 * clampedScale),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10 * clampedScale,
          vertical: 6 * clampedScale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TonztoonIcons.slidersHorizontal,
              size: 15 * clampedScale,
              color: colorScheme.secondary,
            ),
            SizedBox(width: 6 * clampedScale),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize:
                    (theme.textTheme.labelMedium?.fontSize ?? 12) *
                    clampedScale,
                fontWeight: FontWeight.w800,
                color: colorScheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
