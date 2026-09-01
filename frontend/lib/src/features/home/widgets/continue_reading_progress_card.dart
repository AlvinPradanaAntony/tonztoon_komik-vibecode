import 'package:flutter/material.dart';

import '../../../helpers/app_icons.dart';
import '../../../models/comic.dart';
import '../../../models/progress.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/comic_card.dart' show comicSourceNameLabel;
import '../../../widgets/comic_cover.dart';
import '../../../widgets/metadata_separator.dart';
import '../../../widgets/source_tag.dart';

class ContinueReadingProgressCard extends StatelessWidget {
  const ContinueReadingProgressCard({
    super.key,
    required this.progress,
    required this.onTap,
    this.fullWidth = false,
    this.showTrailingArrow = false,
  });

  final ReadingProgress progress;
  final VoidCallback onTap;
  final bool fullWidth;
  final bool showTrailingArrow;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final chapterText =
        'Chapter ${formatChapterNumber(progress.chapterNumber)}';
    final pageText = readingProgressPageLabel(progress);
    final progressValue = readingProgressValue(progress);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _progressCardWidth(context, constraints, chapterText);
        final metrics = _progressCardMetrics(cardWidth);

        return SizedBox(
          width: cardWidth,
          height: metrics.totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: metrics.bodyLeft,
                right: 0,
                top: metrics.bodyTop,
                height: metrics.bodyHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(metrics.cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.3
                              : 0.08,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(metrics.cardRadius),
                      onTap: onTap,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          metrics.contentLeftPadding,
                          metrics.contentTopPadding,
                          metrics.contentRightPadding,
                          metrics.contentBottomPadding,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) => FittedBox(
                            key: const ValueKey(
                              'continue-reading-content-scale',
                            ),
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: _ProgressCardContent(
                                progress: progress,
                                chapterText: chapterText,
                                pageText: pageText,
                                progressValue: progressValue,
                                progressHeight: metrics.progressHeight,
                                showTrailingArrow: showTrailingArrow,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: metrics.coverLeft,
                top: metrics.coverTop,
                child: Container(
                  width: metrics.coverWidth,
                  height: metrics.coverHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.45
                              : 0.3,
                        ),
                        blurRadius: 5,
                        spreadRadius: -0.5,
                        offset: const Offset(4, 0),
                      ),
                    ],
                  ),
                  child: Hero(
                    tag: comicCoverHeroTag(
                      progress.sourceName,
                      progress.comicSlug,
                    ),
                    child: ComicCover(
                      imageUrl: progress.coverImageUrl,
                      width: metrics.coverWidth,
                      height: metrics.coverHeight,
                      size: ComicCoverSize.reader,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(metrics.cardRadius),
                    onTap: onTap,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _ProgressCardMetrics _progressCardMetrics(double cardWidth) {
    final scale = ((cardWidth - 270) / 90).clamp(0.0, 1.0);
    final coverWidth = 76.0 + (8.0 * scale);
    final coverHeight = 114.0 + (12.0 * scale);

    final overflowTop = 16.0 + (2.0 * scale);
    final paddingLeft = 8.0 + (2.0 * scale);
    final paddingBottom = 8.0 + (2.0 * scale);

    final totalHeight = coverHeight + paddingBottom;
    final bodyTop = overflowTop;
    final bodyHeight = totalHeight - bodyTop;

    return _ProgressCardMetrics(
      totalHeight: totalHeight,
      bodyLeft: 0,
      bodyTop: bodyTop,
      bodyHeight: bodyHeight,
      coverLeft: paddingLeft,
      coverTop: 0,
      coverWidth: coverWidth,
      coverHeight: coverHeight,
      cardRadius: 14.0 + (2.0 * scale),
      contentLeftPadding: paddingLeft + coverWidth + 12.0,
      contentTopPadding: 8.0,
      contentRightPadding: 14.0,
      contentBottomPadding: 8.0,
      progressHeight: 6.0,
    );
  }

  double _progressCardWidth(
    BuildContext context,
    BoxConstraints constraints,
    String chapterText,
  ) {
    if (fullWidth && constraints.hasBoundedWidth) {
      return constraints.maxWidth;
    }

    final theme = Theme.of(context);
    final chapterWidth = _textWidth(chapterText, theme.textTheme.bodyMedium);
    final sourceWidth =
        _textWidth(
          comicSourceNameLabel(progress.sourceName),
          theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        ) +
        31;
    final metadataWidth = chapterWidth + 18 + sourceWidth;

    final screenWidth = MediaQuery.sizeOf(context).width;
    const coverOverlapWidth = 100.0;
    const horizontalPadding = 30.0;
    const safety = 26.0;
    final contentWidth =
        horizontalPadding + coverOverlapWidth + metadataWidth + safety;
    return contentWidth.clamp(240.0, (screenWidth - 100).clamp(240.0, 310.0));
  }

  double _textWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}

class _ProgressCardContent extends StatelessWidget {
  const _ProgressCardContent({
    required this.progress,
    required this.chapterText,
    required this.pageText,
    required this.progressValue,
    required this.progressHeight,
    required this.showTrailingArrow,
  });

  final ReadingProgress progress;
  final String chapterText;
  final String pageText;
  final double progressValue;
  final double progressHeight;
  final bool showTrailingArrow;

  @override
  Widget build(BuildContext context) {
    final details = _ProgressCardDetails(
      progress: progress,
      chapterText: chapterText,
      pageText: pageText,
      progressValue: progressValue,
      progressHeight: progressHeight,
    );

    if (!showTrailingArrow) {
      return details;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: details),
        const SizedBox(width: 10),
        Icon(
          TonztoonIcons.chevronRight,
          size: 22,
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _ProgressCardDetails extends StatelessWidget {
  const _ProgressCardDetails({
    required this.progress,
    required this.chapterText,
    required this.pageText,
    required this.progressValue,
    required this.progressHeight,
  });

  final ReadingProgress progress;
  final String chapterText;
  final String pageText;
  final double progressValue;
  final double progressHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          progress.comicTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                chapterText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 6),
            MetadataSeparator(
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SourceTag(sourceName: progress.sourceName),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          pageText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          borderRadius: BorderRadius.circular(99),
          value: progressValue,
          minHeight: progressHeight,
        ),
      ],
    );
  }
}

class _ProgressCardMetrics {
  const _ProgressCardMetrics({
    required this.totalHeight,
    required this.bodyLeft,
    required this.bodyTop,
    required this.bodyHeight,
    required this.coverLeft,
    required this.coverTop,
    required this.coverWidth,
    required this.coverHeight,
    required this.cardRadius,
    required this.contentLeftPadding,
    required this.contentTopPadding,
    required this.contentRightPadding,
    required this.contentBottomPadding,
    required this.progressHeight,
  });

  final double totalHeight;
  final double bodyLeft;
  final double bodyTop;
  final double bodyHeight;
  final double coverLeft;
  final double coverTop;
  final double coverWidth;
  final double coverHeight;
  final double cardRadius;
  final double contentLeftPadding;
  final double contentTopPadding;
  final double contentRightPadding;
  final double contentBottomPadding;
  final double progressHeight;
}
