import 'package:flutter/material.dart';

import '../core/app_icons.dart';
import '../models/comic.dart';
import 'app_loading_placeholder.dart';
import 'comic_cover.dart';

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

class ComicListCard extends StatelessWidget {
  const ComicListCard({
    super.key,
    required this.comic,
    required this.onTap,
    this.source,
    this.rating,
    this.showNewBadge = false,
  });

  final ComicSummary comic;
  final VoidCallback onTap;
  final String? source;
  final double? rating;
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sourceLabel = source ?? comicSourceLabel(comic);
    final statusLabel = _comicStatusLabel(comic.status);
    final ratingValue = rating ?? comic.rating;

    return Material(
      color: colorScheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 34, 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 104,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ComicCover(
                          imageUrl: comic.coverImageUrl,
                          borderRadius: 10,
                        ),
                        if (comic.type != null)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Transform.scale(
                              scale: 0.78,
                              alignment: Alignment.topRight,
                              child: ComicTypeFlagBadge(type: comic.type!),
                            ),
                          ),
                        if (showNewBadge && comic.hasNewChapter())
                          const Positioned(
                            right: 5,
                            bottom: 5,
                            child: ComicNewBadge(compact: true),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            right: ratingValue == null ? 0 : 42,
                          ),
                          child: Text(
                            comic.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              height: 1.08,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: _ComicListSource(source: sourceLabel),
                            ),
                            const SizedBox(width: 6),
                            ComicStatusBadge(status: statusLabel),
                          ],
                        ),
                        if (comic.genres.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _ComicListGenreStrip(genres: comic.genres),
                        ],
                        if (comic.latestChapterNumber != null ||
                            comic.totalView != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (comic.latestChapterNumber != null)
                                _ComicLatestChapterBadge(
                                  chapterNumber: comic.latestChapterNumber!,
                                ),
                              if (comic.latestChapterReleaseDate != null) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _ComicUpdateTime(
                                    releaseDate:
                                        comic.latestChapterReleaseDate!,
                                  ),
                                ),
                              ] else
                                const Spacer(),
                              if (comic.totalView != null) ...[
                                const SizedBox(width: 6),
                                _ComicListViewCount(
                                  totalView: comic.totalView!,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (ratingValue != null)
              Positioned(
                top: 0,
                right: 0,
                child: _ComicListRatingBadge(rating: ratingValue),
              ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Icon(
                  TonztoonIcons.chevronRight,
                  size: 19,
                  color: colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _ComicListSource extends StatelessWidget {
  const _ComicListSource({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          TonztoonIcons.travelExplore,
          size: 14,
          color: colorScheme.secondary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComicListGenreStrip extends StatefulWidget {
  const _ComicListGenreStrip({required this.genres});

  final List<Genre> genres;

  @override
  State<_ComicListGenreStrip> createState() => _ComicListGenreStripState();
}

class _ComicListGenreStripState extends State<_ComicListGenreStrip> {
  late final ScrollController _scrollController;
  bool _showLeftFade = false;
  bool _showRightFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_syncFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
  }

  @override
  void didUpdateWidget(covariant _ComicListGenreStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.genres != widget.genres) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncFades)
      ..dispose();
    super.dispose();
  }

  void _syncFades() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final showLeftFade = position.extentBefore > 1;
    final showRightFade =
        position.maxScrollExtent > 0 && position.extentAfter > 1;
    if (showLeftFade != _showLeftFade || showRightFade != _showRightFade) {
      setState(() {
        _showLeftFade = showLeftFade;
        _showRightFade = showRightFade;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return SizedBox(
      key: const ValueKey('comic-list-genre-strip'),
      height: 26,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.genres.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) => ComicGenreBadge(
                genre: widget.genres[index].name,
                compact: true,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            width: 30,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: const ValueKey('comic-list-genre-left-fade'),
                opacity: _showLeftFade ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [surfaceColor, surfaceColor.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 30,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: const ValueKey('comic-list-genre-right-fade'),
                opacity: _showRightFade ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [surfaceColor.withValues(alpha: 0), surfaceColor],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComicUpdateTime extends StatelessWidget {
  const _ComicUpdateTime({required this.releaseDate});

  final DateTime releaseDate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          TonztoonIcons.clock,
          size: 13,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _relativeComicUpdateTime(releaseDate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComicListViewCount extends StatelessWidget {
  const _ComicListViewCount({required this.totalView});

  final int totalView;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      key: const ValueKey('comic-list-total-view'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(TonztoonIcons.eye, size: 13, color: colorScheme.secondary),
        const SizedBox(width: 4),
        Text(
          _formatCompactMetric(totalView),
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ComicLatestChapterBadge extends StatelessWidget {
  const _ComicLatestChapterBadge({required this.chapterNumber});

  final double chapterNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(colorScheme.secondary, Colors.black, 0.16)!,
            colorScheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colorScheme.secondary.withValues(alpha: 0.26),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          'Chapter ${formatChapterNumber(chapterNumber)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ComicListRatingBadge extends StatelessWidget {
  const _ComicListRatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFC400),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(15),
          bottomLeft: Radius.circular(13),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 7,
            offset: const Offset(-2, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                TonztoonIcons.starFilled,
                size: 14,
                color: Color(0xFF5C4300),
              ),
              const SizedBox(width: 3),
              Text(
                rating.toStringAsFixed(1),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF3D2E00),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _comicStatusLabel(String? status) {
  final value = status?.trim() ?? '';
  return value.isEmpty ? 'Ongoing' : comicBadgeLabel(value);
}

String _formatCompactMetric(int value) {
  if (value >= 1000000000) {
    return '${_formatCompactDecimal(value / 1000000000)}B';
  }
  if (value >= 1000000) {
    return '${_formatCompactDecimal(value / 1000000)}M';
  }
  if (value >= 1000) {
    return '${_formatCompactDecimal(value / 1000)}K';
  }
  return value.toString();
}

String _formatCompactDecimal(double value) {
  final formatted = value.toStringAsFixed(value >= 10 ? 0 : 1);
  return formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
}

String _relativeComicUpdateTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.isNegative || difference.inMinutes < 1) return 'Baru saja';
  if (difference.inMinutes < 60) return '${difference.inMinutes} menit lalu';
  if (difference.inHours < 24) return '${difference.inHours} jam lalu';
  if (difference.inDays < 7) return '${difference.inDays} hari lalu';
  if (difference.inDays < 30) return '${difference.inDays ~/ 7} minggu lalu';
  if (difference.inDays < 365) return '${difference.inDays ~/ 30} bulan lalu';
  return '${difference.inDays ~/ 365} tahun lalu';
}

class ComicNewBadge extends StatelessWidget {
  const ComicNewBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: compact ? 5 : 8,
            offset: Offset(0, compact ? 2 : 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 3 : 5,
        ),
        child: Text(
          'NEW',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: compact ? 9 : null,
            letterSpacing: compact ? 0.5 : 0.7,
          ),
        ),
      ),
    );
  }
}

class ComicSourceBadge extends StatelessWidget {
  const ComicSourceBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              TonztoonIcons.travelExplore,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComicMetaBadge extends StatelessWidget {
  const ComicMetaBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.iconColor,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeColor = color ?? colorScheme.secondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: icon == null
            ? Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: iconColor ?? badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ComicTypeFlagBadge extends StatelessWidget {
  const ComicTypeFlagBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 28,
        child: Center(
          child: Text(
            comicTypeFlag(type),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1),
          ),
        ),
      ),
    );
  }
}

class ComicGenreBadge extends StatelessWidget {
  const ComicGenreBadge({super.key, required this.genre, this.compact = false});

  final String genre;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = comicGenreColor(genre);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 5 : 8,
        ),
        child: Text(
          comicBadgeLabel(genre),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class ComicStatusBadge extends StatelessWidget {
  const ComicStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = comicStatusStyle(theme.colorScheme, status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 13, color: style.color),
            const SizedBox(width: 5),
            Text(
              comicBadgeLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: style.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String comicSourceLabel(ComicSummary comic) {
  return comicSourceNameLabel(comic.sourceName);
}

String comicSourceNameLabel(String sourceName) {
  final value = sourceName.trim();
  if (value.isEmpty) return 'Komiku';
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map(_capitalizeBadgeWord)
      .join(' ');
}

String comicTypeFlag(String? type) {
  return switch (type?.toLowerCase()) {
    'manhwa' => '🇰🇷',
    'manga' => '🇯🇵',
    'manhua' => '🇨🇳',
    _ => '🏳️',
  };
}

String comicBadgeLabel(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
  if (normalized.isEmpty) return value;
  return normalized
      .split(' ')
      .map((word) => word.split('-').map(_capitalizeBadgeWord).join('-'))
      .join(' ');
}

String _capitalizeBadgeWord(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}

Color comicGenreColor(String genre) {
  return switch (genre.toLowerCase()) {
    'action' => const Color(0xFFE11D48),
    'adventure' => const Color(0xFF2563EB),
    'fantasy' => const Color(0xFF7C3AED),
    'drama' => const Color(0xFFDB2777),
    'system' => const Color(0xFF0891B2),
    'comedy' => const Color(0xFFF59E0B),
    'shounen' => const Color(0xFFEA580C),
    'apocalypse' => const Color(0xFF475569),
    'psychological' => const Color(0xFF9333EA),
    'supernatural' => const Color(0xFF059669),
    'swordplay' => const Color(0xFFDC2626),
    'sports' => const Color(0xFF16A34A),
    'romance' => const Color(0xFFEC4899),
    _ => const Color(0xFF3A86FF),
  };
}

ComicStatusStyle comicStatusStyle(ColorScheme colorScheme, String status) {
  final normalized = status.trim().toLowerCase();
  return switch (normalized) {
    'completed' ||
    'complete' ||
    'end' ||
    'ended' ||
    'tamat' ||
    'finish' ||
    'finished' => const ComicStatusStyle(
      icon: TonztoonIcons.badgeCheckFilled,
      color: Color(0xFF16A34A),
    ),
    'hiatus' => const ComicStatusStyle(
      icon: TonztoonIcons.circleDotDashed,
      color: Color(0xFFF59E0B),
    ),
    _ => ComicStatusStyle(
      icon: TonztoonIcons.clock,
      color: colorScheme.secondary,
    ),
  };
}

class ComicStatusStyle {
  const ComicStatusStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}
