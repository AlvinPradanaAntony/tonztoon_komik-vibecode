import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/app_icons.dart';

/// [ComicCover] adalah komponen UI khusus untuk merender gambar sampul komik.
/// Ini menangani:
/// 1. Shimmer effect (animasi loading) saat gambar sedang diunduh.
/// 2. Fallback UI jika gambar gagal dimuat atau URL kosong.
class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.fit = BoxFit.cover,
    this.fallbackIconSize,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final double? fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Fallback UI jika gambar tidak ada/error
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
          size: fallbackIconSize,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );

    // Shimmer effect (skeleton loading)
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
                fit: fit,
                placeholder: (context, url) =>
                    shimmer, // Ditampilkan saat loading
                errorWidget: (context, url, error) =>
                    fallback, // Ditampilkan saat error
              ),
      ),
    );
  }
}

// Widget internal (private) untuk membuat efek Shimmer (gelap-terang)
class _CoverShimmer extends StatelessWidget {
  const _CoverShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Dibuat agak gelap agar kontras shimer lebih terlihat jelas
    final baseColor = isDark ? Colors.grey[850]! : Colors.grey[350]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[200]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(color: baseColor),
    );
  }
}
