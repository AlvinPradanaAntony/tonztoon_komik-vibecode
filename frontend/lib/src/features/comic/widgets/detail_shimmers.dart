part of '../comic_detail_screen.dart';

class _ComicDetailLoadingPlaceholder extends StatelessWidget {
  const _ComicDetailLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: AppResponsive.heroHeaderHeight(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surfaceContainerHigh,
                        colorScheme.surfaceContainerHighest,
                        colorScheme.surfaceContainerLowest,
                      ],
                      stops: const [0, 0.62, 1],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _DetailIconButtonShimmer(),
                        Spacer(),
                        _DetailIconButtonShimmer(),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const verticalPadding = 60.0;
                      const badgeHeight = 30.0;
                      const gap = 12.0;
                      final coverHeight =
                          (constraints.maxHeight -
                                  verticalPadding -
                                  badgeHeight -
                                  gap)
                              .clamp(180.0, 268.0)
                              .toDouble();

                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 46),
                          child: AppShimmer(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppShimmerBlock(
                                  width: 104,
                                  height: badgeHeight,
                                  borderRadius: 18,
                                ),
                                const SizedBox(height: gap),
                                AppShimmerBlock(
                                  width: 182,
                                  height: coverHeight,
                                  borderRadius: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _DetailTitleBlockShimmer(),
                  SizedBox(height: 18),
                  _DetailStatsShimmer(),
                  SizedBox(height: 20),
                  _DetailSectionHeaderShimmer(width: 96),
                  SizedBox(height: 10),
                  _DetailParagraphShimmer(),
                  SizedBox(height: 22),
                  _DetailSectionHeaderShimmer(width: 76),
                  SizedBox(height: 10),
                  _DetailGenreShimmer(),
                  SizedBox(height: 24),
                  _DetailChapterPanelShimmer(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailIconButtonShimmer extends StatelessWidget {
  const _DetailIconButtonShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: AppShimmerBlock(width: 44, height: 44, borderRadius: 22),
    );
  }
}

class _DetailTitleBlockShimmer extends StatelessWidget {
  const _DetailTitleBlockShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Column(
        children: [
          Center(
            child: AppShimmerBlock(width: 260, height: 30, borderRadius: 10),
          ),
          SizedBox(height: 10),
          Center(
            child: AppShimmerBlock(width: 184, height: 24, borderRadius: 10),
          ),
          SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppShimmerBlock(width: 74, height: 32, borderRadius: 20),
              AppShimmerBlock(width: 92, height: 32, borderRadius: 20),
              AppShimmerBlock(width: 70, height: 32, borderRadius: 20),
            ],
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _DetailCreatorTileShimmer()),
              SizedBox(width: 10),
              Expanded(child: _DetailCreatorTileShimmer()),
            ],
          ),
          SizedBox(height: 10),
          _DetailCreatorTileShimmer(wide: true),
        ],
      ),
    );
  }
}

class _DetailCreatorTileShimmer extends StatelessWidget {
  const _DetailCreatorTileShimmer({this.wide = false});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const AppShimmerBlock(width: 34, height: 34, borderRadius: 12),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppShimmerBlock(width: 62, height: 12),
                  const SizedBox(height: 7),
                  AppShimmerBlock(
                    width: wide ? double.infinity : 110,
                    height: 15,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStatsShimmer extends StatelessWidget {
  const _DetailStatsShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Row(
        children: [
          Expanded(child: _DetailStatTileShimmer()),
          SizedBox(width: 10),
          Expanded(child: _DetailStatTileShimmer()),
          SizedBox(width: 10),
          Expanded(child: _DetailStatTileShimmer()),
        ],
      ),
    );
  }
}

class _DetailStatTileShimmer extends StatelessWidget {
  const _DetailStatTileShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            AppShimmerBlock(width: 20, height: 20, borderRadius: 10),
            SizedBox(height: 8),
            AppShimmerBlock(width: 54, height: 16),
            SizedBox(height: 6),
            AppShimmerBlock(width: 46, height: 12),
          ],
        ),
      ),
    );
  }
}

class _DetailSectionHeaderShimmer extends StatelessWidget {
  const _DetailSectionHeaderShimmer({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        children: [
          const AppShimmerBlock(width: 28, height: 28, borderRadius: 14),
          const SizedBox(width: 8),
          AppShimmerBlock(width: width, height: 20),
        ],
      ),
    );
  }
}

class _DetailParagraphShimmer extends StatelessWidget {
  const _DetailParagraphShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppShimmerBlock(width: double.infinity, height: 14),
          SizedBox(height: 9),
          AppShimmerBlock(width: double.infinity, height: 14),
          SizedBox(height: 9),
          AppShimmerBlock(width: 280, height: 14),
          SizedBox(height: 9),
          AppShimmerBlock(width: 210, height: 14),
        ],
      ),
    );
  }
}

class _DetailGenreShimmer extends StatelessWidget {
  const _DetailGenreShimmer();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppShimmerBlock(width: 82, height: 34, borderRadius: 18),
          AppShimmerBlock(width: 96, height: 34, borderRadius: 18),
          AppShimmerBlock(width: 74, height: 34, borderRadius: 18),
          AppShimmerBlock(width: 88, height: 34, borderRadius: 18),
        ],
      ),
    );
  }
}

class _DetailChapterPanelShimmer extends StatelessWidget {
  const _DetailChapterPanelShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          children: const [
            AppShimmer(
              child: Row(
                children: [
                  AppShimmerBlock(width: 28, height: 28, borderRadius: 14),
                  SizedBox(width: 8),
                  AppShimmerBlock(width: 132, height: 20),
                  Spacer(),
                  AppShimmerBlock(width: 62, height: 14),
                ],
              ),
            ),
            SizedBox(height: 10),
            _ChapterListShimmer(),
          ],
        ),
      ),
    );
  }
}

class _ChapterListShimmer extends StatelessWidget {
  const _ChapterListShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AppShimmer(
        child: Column(
          children: [
            for (var index = 0; index < 5; index++) ...[
              const _ChapterRowShimmer(),
              if (index != 4) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChapterRowShimmer extends StatelessWidget {
  const _ChapterRowShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            AppShimmerBlock(width: 42, height: 42, borderRadius: 12),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppShimmerBlock(width: double.infinity, height: 16),
                  SizedBox(height: 6),
                  AppShimmerBlock(width: 132, height: 12),
                ],
              ),
            ),
            SizedBox(width: 10),
            AppShimmerBlock(width: 18, height: 18, borderRadius: 9),
          ],
        ),
      ),
    );
  }
}
