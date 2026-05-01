import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/app_icons.dart';
import 'package:shimmer/shimmer.dart';

class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 16,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerHighest,
            colorScheme.primary.withValues(alpha: 0.16),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          TonztoonIcons.menuBook,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    const shimmer = _CoverShimmer();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: imageUrl == null || imageUrl!.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => shimmer,
                errorWidget: (context, url, error) => fallback,
              ),
      ),
    );
  }
}

class _CoverShimmer extends StatelessWidget {
  const _CoverShimmer();

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlightColor = Theme.of(context).colorScheme.surfaceContainerLow;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(color: baseColor),
    );
  }
}
