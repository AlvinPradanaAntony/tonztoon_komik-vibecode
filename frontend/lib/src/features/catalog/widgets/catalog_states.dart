part of '../full_catalog_screen.dart';

class _CatalogLoadingState extends StatelessWidget {
  const _CatalogLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CatalogLoadingPlaceholder();
  }
}

class _FilterProcessingIndicator extends StatelessWidget {
  const _FilterProcessingIndicator({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.96),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  minHeight: 3,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Memproses hasil filter...',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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

class _CatalogLoadingPlaceholder extends StatelessWidget {
  const _CatalogLoadingPlaceholder();

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
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.47,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => const _CatalogCardShimmer(),
              childCount: 6,
            ),
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
