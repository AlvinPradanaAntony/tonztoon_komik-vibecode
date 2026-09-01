import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../helpers/app_icons.dart';

/// Ukuran network image sesuai konteks pemakaian cover.
/// Nilai ini diterjemahkan menjadi resize/compress pada image proxy.
enum ComicCoverSize { small, large, reader }

String comicCoverHeroTag(String sourceName, String slug) {
  return 'comic-cover:${sourceName.trim().toLowerCase()}:${slug.trim().toLowerCase()}';
}

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
    this.showShimmer = true,
    this.size = ComicCoverSize.small,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final double? fallbackIconSize;
  final bool showShimmer;

  final ComicCoverSize size;

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
            : LayoutBuilder(
                builder: (context, constraints) {
                  final devicePixelRatio = MediaQuery.devicePixelRatioOf(
                    context,
                  );
                  final optimizedImageUrl = _optimizedImageUrl(
                    imageUrl!,
                    constraints.maxWidth,
                    devicePixelRatio,
                  );

                  return CachedNetworkImage(
                    imageUrl: optimizedImageUrl,
                    fit: fit,
                    placeholder: (context, url) => showShimmer
                        ? shimmer
                        : fallback, // Fallback stabil saat shimmer dimatikan
                    errorWidget: (context, url, error) =>
                        fallback, // Ditampilkan saat error
                  );
                },
              ),
      ),
    );
  }

  String _optimizedImageUrl(
    String sourceUrl,
    double logicalPixels,
    double devicePixelRatio,
  ) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !uri.path.endsWith('/api/v1/images/proxy')) {
      return sourceUrl;
    }

    final safeDpr = devicePixelRatio.isFinite
        ? devicePixelRatio.clamp(1.0, 3.0)
        : 1.0;
    final safeWidth = logicalPixels.isFinite && logicalPixels > 0
        ? logicalPixels
        : (size == ComicCoverSize.small ? 240.0 : 720.0);
    final rawWidth = (safeWidth * safeDpr).round();
    final width = switch (size) {
      ComicCoverSize.small => rawWidth.clamp(160, 320),
      ComicCoverSize.large => rawWidth.clamp(640, 1440),
      // Keep the reader Hero source and destination on one stable cache key.
      ComicCoverSize.reader => 320,
    };
    final quality = switch (size) {
      ComicCoverSize.large => 88,
      ComicCoverSize.small || ComicCoverSize.reader => 80,
    };

    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'width': '$width',
            'quality': '$quality',
          },
        )
        .toString();
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
