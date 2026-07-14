import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import '../helpers/dynamic_badge_palette.dart';
import '../models/comic.dart';
import 'app_loading_placeholder.dart';
import 'comic_cover.dart';
import 'metadata_separator.dart';

part 'comic_card/comic_list_card.dart';
part 'comic_card/comic_card_shimmers.dart';
part 'comic_card/comic_badges.dart';
part 'comic_card/comic_card_formatters.dart';

/// [ComicCard] adalah kartu yang membungkus [ComicCover] dan menampilkan
/// judul serta metadata (seperti tipe dan chapter terbaru).
/// Dilengkapi dengan interaksi UX: hover effect dan tekan (scale).
class ComicCard extends StatefulWidget {
  const ComicCard({
    super.key,
    required this.comic,
    required this.onTap,
    this.onLongPress,
    this.source,
    this.rating,
    this.width = 138,
    this.showNewBadge = false,
    this.hasNewChapter,
  });

  final ComicSummary comic;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? source;
  final String? rating;
  final double? width;
  final bool showNewBadge;

  /// Overrides the date-based new badge check when the caller has reading
  /// progress data, such as the Bookmark library response.
  final bool? hasNewChapter;

  @override
  State<ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<ComicCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chapterNumber = widget.comic.latestChapterNumber;
    final totalView = widget.comic.totalView;
    final source = widget.source ?? comicSourceLabel(widget.comic);
    final ratingLabel =
        widget.rating ?? widget.comic.rating?.toStringAsFixed(1);
    final showNewBadge =
        widget.hasNewChapter ??
        (widget.showNewBadge && widget.comic.hasNewChapter());

    // MouseRegion untuk mendeteksi kursor mouse (berguna di Desktop/Web)
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),

      // GestureDetector untuk mendeteksi sentuhan jari (berguna di Mobile)
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),

        // Animasi memperbesar/memperkecil kartu
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.02 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,

          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.12,
              child: SizedBox(
                width: widget.width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _hovered ? 0.4 : 0.2,
                            ),
                            blurRadius: _hovered ? 22 : 15,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final overlayScale = _comicCardOverlayScale(
                                constraints.maxWidth,
                              );
                              final overlayInset = 8 * overlayScale;
                              final sourceRightInset = widget.comic.type == null
                                  ? overlayInset
                                  : 44 * overlayScale;

                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ComicCover(
                                    imageUrl: widget.comic.coverImageUrl,
                                    borderRadius: 0,
                                  ),
                                  Positioned(
                                    left: overlayInset,
                                    top: overlayInset,
                                    right: sourceRightInset,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: ComicSourceBadge(
                                        label: source,
                                        scale: overlayScale,
                                      ),
                                    ),
                                  ),
                                  if (widget.comic.type != null)
                                    Positioned(
                                      right: overlayInset,
                                      top: overlayInset,
                                      child: ComicTypeFlagBadge(
                                        type: widget.comic.type!,
                                        scale: overlayScale,
                                      ),
                                    ),
                                  if (showNewBadge && chapterNumber == null)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: ComicNewBadge(scale: overlayScale),
                                    ),
                                  if (chapterNumber != null && !showNewBadge)
                                    Positioned(
                                      key: const ValueKey(
                                        'comic-grid-latest-chapter-position',
                                      ),
                                      left: 0,
                                      bottom: 0,
                                      child: _ComicGridLatestChapterBadge(
                                        chapterNumber: chapterNumber,
                                        scale: overlayScale,
                                      ),
                                    ),
                                  if (chapterNumber != null && showNewBadge)
                                    Positioned(
                                      key: const ValueKey(
                                        'comic-grid-latest-chapter-new-group',
                                      ),
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.bottomLeft,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.bottomLeft,
                                                child:
                                                    _ComicGridLatestChapterBadge(
                                                      chapterNumber:
                                                          chapterNumber,
                                                      scale: overlayScale,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          ComicNewBadge(scale: overlayScale),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      widget.comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (totalView != null)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: ComicMetaBadge(
                                  label: _formatCompactMetric(totalView),
                                  icon: TonztoonIcons.eye,
                                  color: colorScheme.secondary,
                                ),
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (ratingLabel != null)
                          ComicMetaBadge(
                            label: ratingLabel,
                            icon: TonztoonIcons.starFilled,
                            iconColor: Colors.amber,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _comicCardOverlayScale(double coverWidth) {
  if (!coverWidth.isFinite || coverWidth <= 0) return 1;
  return (coverWidth / 138).clamp(0.74, 1).toDouble();
}

TextStyle? _scaledTextStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (style == null || fontSize == null || scale == 1) return style;
  return style.copyWith(fontSize: fontSize * scale);
}

class _ComicGridLatestChapterBadge extends StatelessWidget {
  const _ComicGridLatestChapterBadge({
    required this.chapterNumber,
    this.scale = 1,
  });

  final double chapterNumber;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CustomPaint(
      key: const ValueKey('comic-grid-latest-chapter-shadow'),
      painter: _ComicGridLatestChapterShadowPainter(scale),
      child: ClipPath(
        key: const ValueKey('comic-grid-latest-chapter-badge'),
        clipper: _ComicGridLatestChapterClipper(scale),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                colorScheme.primary,
                Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.45)!,
              ],
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 115 * scale),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                10 * scale,
                6 * scale,
                14 * scale,
                6 * scale,
              ),
              child: Text(
                'Chapter ${formatChapterNumber(chapterNumber)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _scaledTextStyle(
                  Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                  scale,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComicGridLatestChapterShadowPainter extends CustomPainter {
  const _ComicGridLatestChapterShadowPainter(this.scale);

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _ComicGridLatestChapterClipper(
      scale,
    ).getClip(size).shift(Offset(0, -3 * scale));
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * scale);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
    covariant _ComicGridLatestChapterShadowPainter oldDelegate,
  ) => oldDelegate.scale != scale;
}

class _ComicGridLatestChapterClipper extends CustomClipper<Path> {
  const _ComicGridLatestChapterClipper(this.scale);

  final double scale;

  @override
  Path getClip(Size size) {
    final topLeftRadius = 12.0 * scale;
    final bottomRightRadius = 12.0 * scale;
    final tail = 22.0 * scale;
    final diagonalBottomX = size.width - tail;

    return Path()
      ..moveTo(topLeftRadius, 0)
      ..lineTo(size.width, 0)
      ..lineTo(diagonalBottomX + bottomRightRadius, size.height - 4 * scale)
      ..quadraticBezierTo(
        diagonalBottomX + bottomRightRadius - 2,
        size.height,
        diagonalBottomX,
        size.height,
      )
      ..lineTo(0, size.height)
      ..lineTo(0, topLeftRadius)
      ..quadraticBezierTo(0, 0, topLeftRadius, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ComicGridLatestChapterClipper oldClipper) =>
      oldClipper.scale != scale;
}
