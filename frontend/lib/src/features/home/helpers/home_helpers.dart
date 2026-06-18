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
  final contentWidth = math.max(0.0, bannerWidth - (_bannerPaddingX * 2));
  final textColumnWidth = math.max(
    80.0,
    contentWidth - _bannerMainContentGap - _bannerCoverWidth,
  );
  final theme = Theme.of(context);
  final titleStyle = theme.textTheme.titleLarge?.copyWith(
    color: Colors.white,
    fontWeight: FontWeight.w900,
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
    28.0,
    _scaledLineHeight(
          theme.textTheme.labelSmall,
          fallbackFontSize: 11,
          fallbackHeight: 1.2,
          textScale: textScale,
        ) +
        10,
  );
  final pillHeight =
      _scaledLineHeight(
        theme.textTheme.labelSmall,
        fallbackFontSize: 11,
        fallbackHeight: 1.2,
        textScale: textScale,
      ) +
      10;
  final buttonHeight = _bannerButtonMinHeight + ((textScale - 1) * 12);
  var maxLowerRowHeight = _bannerCoverHeight;

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
        (hasPills ? _bannerTitlePillGap + pillHeight : 0) +
        _bannerPillButtonGap +
        buttonHeight;
    maxLowerRowHeight = math.max(maxLowerRowHeight, textColumnHeight);
  }

  return _bannerPaddingY +
      topBadgeHeight +
      _bannerBadgeContentGap +
      maxLowerRowHeight +
      _bannerPaddingY;
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

double _progressValue(ReadingProgress item) => readingProgressValue(item);

String _progressPageText(ReadingProgress item) =>
    readingProgressPageLabel(item);

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
