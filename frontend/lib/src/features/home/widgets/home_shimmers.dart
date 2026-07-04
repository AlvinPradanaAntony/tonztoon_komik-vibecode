part of '../home_screen.dart';

class _HomeLoadingPlaceholder extends StatelessWidget {
  const _HomeLoadingPlaceholder({
    required this.controller,
    required this.topPadding,
  });

  final ScrollController controller;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 128),
      children: const [
        _HomeDiscoverHeaderShimmer(),
        SizedBox(height: 20),
        _HomeSkeletonSectionTitle(width: 136),
        SizedBox(height: 10),
        _HomeRecommendationShimmer(),
        SizedBox(height: 24),
        _HomeSkeletonSectionTitle(width: 164),
        SizedBox(height: 10),
        _HomeTopRankingRailShimmer(),
        SizedBox(height: 24),
        _HomeSkeletonSectionTitle(width: 108),
        SizedBox(height: 10),
        _HomeRailShimmer(),
      ],
    );
  }
}

class _HomeDiscoverHeaderShimmer extends StatelessWidget {
  const _HomeDiscoverHeaderShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardColor = isDark
        ? const Color(0xFF1E2433)
        : const Color(0xFFFFFDF9);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: AppShimmer(
        child: Row(
          children: [
            const AppShimmerBlock(
              width: 4,
              height: 22,
              borderRadius: 4,
            ),
            const SizedBox(width: 10),
            const AppShimmerBlock(
              width: 100,
              height: 22,
              borderRadius: 4,
            ),
            const Spacer(),
            AppShimmerBlock(
              width: 130,
              height: 32,
              borderRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSkeletonSectionTitle extends StatelessWidget {
  const _HomeSkeletonSectionTitle({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        children: [
          const AppShimmerBlock(width: 4, height: 22, borderRadius: 4),
          const SizedBox(width: 10),
          AppShimmerBlock(width: width, height: 22),
          const Spacer(),
          const AppShimmerBlock(width: 74, height: 18),
        ],
      ),
    );
  }
}

class _HomeRecommendationShimmer extends StatelessWidget {
  const _HomeRecommendationShimmer();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerWidth = math.max(
          0.0,
          (constraints.maxWidth *
                  _RecommendationCarouselState._viewportFraction) -
              _bannerPageEndGap,
        );
        final metrics = _recommendationBannerMetrics(bannerWidth);
        final height =
            metrics.paddingY +
            (28 * metrics.scale) +
            metrics.badgeContentGap +
            metrics.coverHeight +
            metrics.paddingY;

        return SizedBox(
          height: height,
          child: const AppShimmer(
            child: AppShimmerBlock(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 18,
            ),
          ),
        );
      },
    );
  }
}

class _HomeRailShimmer extends StatelessWidget {
  const _HomeRailShimmer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => const SizedBox(
          width: 138,
          child: AppShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppShimmerBlock(
                    width: double.infinity,
                    borderRadius: 12,
                  ),
                ),
                SizedBox(height: 9),
                AppShimmerBlock(width: double.infinity, height: 14),
                SizedBox(height: 7),
                AppShimmerBlock(width: 112, height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTopRankingRailShimmer extends StatelessWidget {
  const _HomeTopRankingRailShimmer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => const SizedBox(
          width: 138,
          child: AppShimmer(
            child: AppShimmerBlock(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 12,
            ),
          ),
        ),
      ),
    );
  }
}
