part of '../home_screen.dart';

String? _formatTopRankingRating(double? rating) {
  if (rating == null) return null;
  final rounded = rating.toStringAsFixed(1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}

const double _bannerPaddingX = 16;
const double _bannerPaddingY = 10;
const double _bannerMaxTextScale = 1.08;
const double _bannerBaseWidth = 342;
const double _bannerBadgeContentGap = 10;
const double _bannerMainContentGap = 12;
const double _bannerCoverWidth = 86;
const double _bannerCoverHeight = 132;
const double _bannerTitlePillGap = 8;
const double _bannerPillButtonGap = 14;
const double _bannerButtonMinHeight = 48;
const double _bannerPageEndGap = 10;
const double _bannerSingleLineTitleScale = 1.28;
const double _bannerSingleLineWidthTolerance = 1.08;

class _RecommendationBannerMetrics {
  const _RecommendationBannerMetrics({
    required this.scale,
    required this.paddingX,
    required this.paddingY,
    required this.badgeContentGap,
    required this.mainContentGap,
    required this.coverWidth,
    required this.coverHeight,
    required this.coverRadius,
    required this.titlePillGap,
    required this.pillButtonGap,
    required this.buttonMinHeight,
    required this.buttonPaddingX,
    required this.pillSpacing,
  });

  final double scale;
  final double paddingX;
  final double paddingY;
  final double badgeContentGap;
  final double mainContentGap;
  final double coverWidth;
  final double coverHeight;
  final double coverRadius;
  final double titlePillGap;
  final double pillButtonGap;
  final double buttonMinHeight;
  final double buttonPaddingX;
  final double pillSpacing;
}

_RecommendationBannerMetrics _recommendationBannerMetrics(double bannerWidth) {
  final scale = (bannerWidth / _bannerBaseWidth).clamp(0.78, 1.04).toDouble();
  return _RecommendationBannerMetrics(
    scale: scale,
    paddingX: _bannerPaddingX * scale,
    paddingY: _bannerPaddingY * scale,
    badgeContentGap: _bannerBadgeContentGap * scale,
    mainContentGap: _bannerMainContentGap * scale,
    coverWidth: _bannerCoverWidth * scale,
    coverHeight: _bannerCoverHeight * scale,
    coverRadius: 12 * scale,
    titlePillGap: _bannerTitlePillGap * scale,
    pillButtonGap: _bannerPillButtonGap * scale,
    buttonMinHeight: _bannerButtonMinHeight * scale,
    buttonPaddingX: 14 * scale,
    pillSpacing: 8 * scale,
  );
}

double _recommendationCarouselHeight(
  BuildContext context,
  double viewportWidth,
  List<ComicSummary> comics,
) {
  final textScale = _clampedBannerTextScale(context);
  final bannerWidth = math.max(
    0.0,
    (viewportWidth * _RecommendationCarouselState._viewportFraction) -
        (comics.length == 1 ? 0 : _bannerPageEndGap),
  );
  final metrics = _recommendationBannerMetrics(bannerWidth);
  final contentWidth = math.max(0.0, bannerWidth - (metrics.paddingX * 2));
  final textColumnWidth = math.max(
    80.0,
    contentWidth - metrics.mainContentGap - metrics.coverWidth,
  );
  final theme = Theme.of(context);
  final titleStyle = _scaledBannerTextStyle(
    theme.textTheme.titleLarge?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w900,
    ),
    metrics.scale,
  );
  final singleLineTitleStyle = titleStyle?.copyWith(
    fontSize: (titleStyle.fontSize ?? 20) * _bannerSingleLineTitleScale,
    height: 1.05,
  );
  final titleLineHeight = _scaledLineHeight(
    titleStyle,
    fallbackFontSize: 20,
    fallbackHeight: 1.2,
    textScale: textScale,
  );
  final topBadgeHeight = math.max(
    28.0 * metrics.scale,
    _scaledLineHeight(
          _scaledBannerTextStyle(theme.textTheme.labelSmall, metrics.scale),
          fallbackFontSize: 11,
          fallbackHeight: 1.2,
          textScale: textScale,
        ) +
        (10 * metrics.scale),
  );
  final pillHeight =
      _scaledLineHeight(
        _scaledBannerTextStyle(theme.textTheme.labelSmall, metrics.scale),
        fallbackFontSize: 11,
        fallbackHeight: 1.2,
        textScale: textScale,
      ) +
      (10 * metrics.scale);
  final buttonHeight = metrics.buttonMinHeight + ((textScale - 1) * 12);
  var maxLowerRowHeight = metrics.coverHeight;

  for (final comic in comics) {
    final statusLabel = _capitalizeBannerStatus(comic.status);
    final hasPills =
        comic.latestChapterNumber != null ||
        comic.rating != null ||
        statusLabel != null;
    final useLargeTitle = _bannerTitleLooksSingleLine(
      context,
      comic.title,
      titleStyle,
      textColumnWidth,
      textScale,
    );
    final titleHeight = _measureBannerTitleHeight(
      context,
      comic.title,
      useLargeTitle ? singleLineTitleStyle : titleStyle,
      textColumnWidth,
      textScale,
      fallbackLineHeight: titleLineHeight,
    );
    final textColumnHeight =
        titleHeight +
        (hasPills ? metrics.titlePillGap + pillHeight : 0) +
        metrics.pillButtonGap +
        buttonHeight;
    maxLowerRowHeight = math.max(maxLowerRowHeight, textColumnHeight);
  }

  return metrics.paddingY +
      topBadgeHeight +
      metrics.badgeContentGap +
      maxLowerRowHeight +
      metrics.paddingY;
}

double _measureBannerTitleHeight(
  BuildContext context,
  String title,
  TextStyle? style,
  double maxWidth,
  double textScale, {
  required double fallbackLineHeight,
}) {
  if (maxWidth <= 0) return fallbackLineHeight * 2;
  final painter = TextPainter(
    text: TextSpan(text: title, style: style),
    maxLines: 2,
    ellipsis: '...',
    textDirection: Directionality.of(context),
    textScaler: TextScaler.linear(textScale),
  )..layout(maxWidth: maxWidth);
  return math.max(fallbackLineHeight, painter.size.height);
}

bool _bannerTitleLooksSingleLine(
  BuildContext context,
  String title,
  TextStyle? style,
  double maxWidth,
  double textScale,
) {
  if (maxWidth <= 0) return false;
  final width = _measureBannerTextWidth(context, title, style, textScale);
  return width <= maxWidth * _bannerSingleLineWidthTolerance;
}

double _measureBannerTextWidth(
  BuildContext context,
  String text,
  TextStyle? style,
  double textScale,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: TextScaler.linear(textScale),
  )..layout();
  return painter.size.width;
}

double _scaledLineHeight(
  TextStyle? style, {
  required double fallbackFontSize,
  required double fallbackHeight,
  required double textScale,
}) {
  final fontSize = style?.fontSize ?? fallbackFontSize;
  final height = style?.height ?? fallbackHeight;
  return fontSize * height * textScale;
}

TextStyle? _scaledBannerTextStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (style == null || fontSize == null || scale == 1) return style;
  return style.copyWith(fontSize: fontSize * scale);
}

double _clampedBannerTextScale(BuildContext context) {
  return MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, _bannerMaxTextScale).toDouble();
}

String? _capitalizeBannerStatus(String? status) {
  final value = status?.trim();
  if (value == null || value.isEmpty) return null;
  return value
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      })
      .join(' ');
}

void _openComicDetail(BuildContext context, ComicSummary comic) =>
    openComicDetail(context, comic);

void _openReaderProgress(BuildContext context, ReadingProgress progress) =>
    openReaderForProgress(context, progress);

void _openContinueReadingSection(
  BuildContext context,
  List<ReadingProgress> items,
) {
  context.push(
    '/library/continue-reading',
    extra: ContinueReadingSectionPayload(items: items),
  );
}

void _openNotifications(BuildContext context) {
  context.push('/notifications');
}

void _openComicSection(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String sourceName,
  required List<ComicSummary> comics,
  required String initialSort,
}) {
  final section =
      ComicSortOption.normalize(initialSort) == ComicSortOption.popular
      ? 'popular'
      : 'latest';
  context.push(
    '/comic/${Uri.encodeComponent(sourceName)}/$section/section/$section',
    extra: ComicSectionPayload(
      title: title,
      subtitle: subtitle,
      sourceName: sourceName,
      comics: comics,
      initialSort: initialSort,
    ),
  );
}
