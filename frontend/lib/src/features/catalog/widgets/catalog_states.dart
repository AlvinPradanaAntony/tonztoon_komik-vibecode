part of '../full_catalog_screen.dart';

class _CatalogLoadingState extends StatelessWidget {
  const _CatalogLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CatalogLoadingPlaceholder();
  }
}

class _CatalogReloadingIndicator extends StatelessWidget {
  const _CatalogReloadingIndicator({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return const Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(child: LinearProgressIndicator(minHeight: 3)),
    );
  }
}

class _CatalogLoadingPlaceholder extends StatelessWidget {
  const _CatalogLoadingPlaceholder();

  static const int _placeholderRows = 3;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed(const [
              AppShimmer(
                child: AppShimmerBlock(
                  width: double.infinity,
                  height: 110,
                  borderRadius: 18,
                ),
              ),
              SizedBox(height: 16),
              AppShimmer(
                child: Row(
                  children: [
                    AppShimmerBlock(width: 128, height: 20),
                    Spacer(),
                    AppShimmerBlock(width: 86, height: 28, borderRadius: 16),
                  ],
                ),
              ),
              SizedBox(height: 12),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columnCount = resolveColumnGridColumnCount(
                maxWidth: constraints.crossAxisExtent,
                minColumnWidth: _catalogGridMinColumnWidth,
                maxColumnCount: _catalogGridMaxColumnCount,
                horizontalSpacing: _catalogGridHorizontalSpacing,
              );
              return AppSliverColumnGrid<int>(
                items: List<int>.generate(
                  columnCount * _placeholderRows,
                  (index) => index,
                ),
                minColumnWidth: _catalogGridMinColumnWidth,
                maxColumnCount: _catalogGridMaxColumnCount,
                horizontalSpacing: _catalogGridHorizontalSpacing,
                verticalSpacing: _catalogGridVerticalSpacing,
                itemBuilder: (context, index) => const _CatalogCardShimmer(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CatalogCardShimmer extends StatelessWidget {
  const _CatalogCardShimmer();

  @override
  Widget build(BuildContext context) {
    return const ComicGridCardShimmer();
  }
}

class _CatalogErrorState extends StatelessWidget {
  const _CatalogErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppErrorState(
          error: error,
          fallbackMessage: 'Katalog belum dapat dimuat. Silakan coba lagi.',
          onRetry: onRetry,
          retryLabel: 'Retry',
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
              child: Icon(
                TonztoonIcons.search,
                size: 38,
                color: colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Tidak ada komik',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Coba ubah kata kunci atau filter katalog.',
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
