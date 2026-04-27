import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.menu_book_outlined)),
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
