import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import '../models/comic.dart';
import 'app_loading_placeholder.dart';
import 'comic_cover.dart';

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
    this.source,
    this.rating,
    this.width = 138,
    this.showNewBadge = false,
  });

  final ComicSummary comic;
  final VoidCallback onTap;
  final String? source;
  final String? rating;
  final double? width;
  final bool showNewBadge;

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
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.12,
              child: SizedBox(
                width: widget.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _hovered ? 0.2 : 0.12,
                            ),
                            blurRadius: _hovered ? 22 : 14,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ComicCover(
                              imageUrl: widget.comic.coverImageUrl,
                              borderRadius: 12,
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: ComicSourceBadge(label: source),
                            ),
                            if (widget.comic.type != null)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: ComicTypeFlagBadge(
                                  type: widget.comic.type!,
                                ),
                              ),
                            if (widget.showNewBadge &&
                                widget.comic.hasNewChapter())
                              const Positioned(
                                right: 8,
                                bottom: 8,
                                child: ComicNewBadge(),
                              ),
                            if (chapterNumber != null)
                              Positioned(
                                key: const ValueKey(
                                  'comic-grid-latest-chapter-position',
                                ),
                                left: 0,
                                bottom: 0,
                                child: _ComicGridLatestChapterBadge(
                                  chapterNumber: chapterNumber,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Flexible(
                      child: Text(
                        widget.comic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
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

class _ComicGridLatestChapterBadge extends StatelessWidget {
  const _ComicGridLatestChapterBadge({required this.chapterNumber});

  final double chapterNumber;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CustomPaint(
      key: const ValueKey('comic-grid-latest-chapter-shadow'),
      painter: const _ComicGridLatestChapterShadowPainter(),
      child: ClipPath(
        key: const ValueKey('comic-grid-latest-chapter-badge'),
        clipper: const _ComicGridLatestChapterClipper(),
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
            constraints: const BoxConstraints(minWidth: 86, maxWidth: 124),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 20, 6),
              child: Text(
                'Chapter ${formatChapterNumber(chapterNumber)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w900,
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
  const _ComicGridLatestChapterShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = const _ComicGridLatestChapterClipper()
        .getClip(size)
        .shift(const Offset(0, -3));
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
    covariant _ComicGridLatestChapterShadowPainter oldDelegate,
  ) => false;
}

class _ComicGridLatestChapterClipper extends CustomClipper<Path> {
  const _ComicGridLatestChapterClipper();

  @override
  Path getClip(Size size) {
    const topLeftRadius = 12.0;
    const bottomRightRadius = 12.0;
    const tail = 15.0;
    final diagonalBottomX = size.width - tail;

    return Path()
      ..moveTo(topLeftRadius, 0)
      ..lineTo(size.width, 0)
      ..lineTo(diagonalBottomX + bottomRightRadius, size.height - 4)
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
      false;
}
