import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: colorScheme.surfaceContainerHighest,
      highlightColor: colorScheme.surfaceContainerLow,
      child: child,
    );
  }
}

class AppShimmerBlock extends StatelessWidget {
  const AppShimmerBlock({
    super.key,
    required this.width,
    this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class AppPageLoadingPlaceholder extends StatelessWidget {
  const AppPageLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 128),
      children: const [
        AppShimmer(child: AppShimmerBlock(width: double.infinity, height: 132)),
        SizedBox(height: 22),
        _SkeletonRow(width: 180),
        SizedBox(height: 12),
        _SkeletonTile(),
        SizedBox(height: 12),
        _SkeletonTile(),
        SizedBox(height: 22),
        _SkeletonRow(width: 148),
        SizedBox(height: 12),
        _SkeletonTile(compact: true),
        SizedBox(height: 12),
        _SkeletonTile(compact: true),
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        children: [
          AppShimmerBlock(width: width, height: 20),
          const Spacer(),
          const AppShimmerBlock(width: 72, height: 18),
        ],
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AppShimmer(
          child: Row(
            children: [
              AppShimmerBlock(
                width: compact ? 58 : 74,
                height: compact ? 82 : 106,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppShimmerBlock(width: double.infinity, height: 18),
                    const SizedBox(height: 8),
                    AppShimmerBlock(width: compact ? 126 : 168, height: 14),
                    const SizedBox(height: 14),
                    const AppShimmerBlock(width: double.infinity, height: 12),
                    const SizedBox(height: 7),
                    AppShimmerBlock(width: compact ? 160 : 210, height: 12),
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
