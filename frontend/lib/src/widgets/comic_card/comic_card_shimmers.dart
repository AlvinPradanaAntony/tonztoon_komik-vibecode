part of '../comic_card.dart';

class ComicListCardShimmer extends StatelessWidget {
  const ComicListCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: const AppShimmer(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              AppShimmerBlock(width: 72, height: 104, borderRadius: 10),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppShimmerBlock(width: double.infinity, height: 17),
                    SizedBox(height: 5),
                    AppShimmerBlock(width: 174, height: 20, borderRadius: 12),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        AppShimmerBlock(
                          width: 68,
                          height: 24,
                          borderRadius: 14,
                        ),
                        SizedBox(width: 6),
                        AppShimmerBlock(
                          width: 76,
                          height: 24,
                          borderRadius: 14,
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    AppShimmerBlock(width: 150, height: 22, borderRadius: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmer placeholder for a comic cover card in a grid: a cover block that
/// fills the available height, then a title and a shorter subtitle line.
class ComicGridCardShimmer extends StatelessWidget {
  const ComicGridCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: AppShimmerBlock(width: double.infinity, borderRadius: 12),
          ),
          SizedBox(height: 9),
          AppShimmerBlock(width: double.infinity, height: 14),
          SizedBox(height: 7),
          AppShimmerBlock(width: 112, height: 14),
        ],
      ),
    );
  }
}
