part of '../home_screen.dart';

class _RecommendationCarousel extends StatefulWidget {
  const _RecommendationCarousel({
    required this.comics,
    required this.onComicTap,
  });

  final List<ComicSummary> comics;
  final ValueChanged<ComicSummary> onComicTap;

  @override
  State<_RecommendationCarousel> createState() =>
      _RecommendationCarouselState();
}

class _RecommendationCarouselState extends State<_RecommendationCarousel> {
  static const _viewportFraction = 0.94;
  static const _autoSlideDuration = Duration(seconds: 4);
  static const _slideAnimationDuration = Duration(milliseconds: 520);

  late PageController _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 0;
  int _virtualPage = 0;

  @override
  void initState() {
    super.initState();
    _resetController();
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant _RecommendationCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comics.length == widget.comics.length) return;
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    _resetController();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comics.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final carouselHeight = _recommendationCarouselHeight(
          context,
          constraints.maxWidth,
          widget.comics,
        );

        return Column(
          children: [
            SizedBox(
              height: carouselHeight,
              child: PageView.builder(
                controller: _pageController,
                clipBehavior: Clip.none,
                onPageChanged: _handlePageChanged,
                itemCount: widget.comics.length > 1
                    ? null
                    : widget.comics.length,
                itemBuilder: (context, index) {
                  final comicIndex = index % widget.comics.length;
                  final comic = widget.comics[comicIndex];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: widget.comics.length == 1 ? 0 : 10,
                    ),
                    child: _RecommendationBanner(
                      comic: comic,
                      index: comicIndex,
                      onTap: () => widget.onComicTap(comic),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.comics.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: _currentPage == i ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _resetController() {
    final hasMultipleItems = widget.comics.length > 1;
    _virtualPage = hasMultipleItems ? widget.comics.length * 1000 : 0;
    _currentPage = 0;
    _pageController = PageController(
      viewportFraction: _viewportFraction,
      initialPage: _virtualPage,
    );
  }

  void _handlePageChanged(int index) {
    if (widget.comics.isEmpty) return;
    setState(() {
      _virtualPage = index;
      _currentPage = index % widget.comics.length;
    });
  }

  void _startAutoSlide() {
    if (widget.comics.length < 2) return;
    _autoSlideTimer = Timer.periodic(_autoSlideDuration, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = _virtualPage + 1;
      _pageController.animateToPage(
        nextPage,
        duration: _slideAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _RecommendationBanner extends StatelessWidget {
  const _RecommendationBanner({
    required this.comic,
    required this.index,
    required this.onTap,
  });

  final ComicSummary comic;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final source = comicSourceLabel(comic);
    final accentColors = const [
      Color(0xFFFF9D00),
      Color(0xFF3A86FF),
      Color(0xFFFF5A5A),
      Color(0xFF20B486),
    ];
    final accent = accentColors[index % accentColors.length];
    final chapter = comic.latestChapterNumber;
    final ratingLabel = comic.rating?.toStringAsFixed(1);
    final statusLabel = _capitalizeBannerStatus(comic.status);
    final hasPills =
        chapter != null || ratingLabel != null || statusLabel != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _recommendationBannerMetrics(constraints.maxWidth);
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
        final buttonTextStyle = _scaledBannerTextStyle(
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          metrics.scale,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.4 : 0.25),
                blurRadius: 45,
                spreadRadius: -2,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.23),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ComicCover(
                      imageUrl: comic.coverImageUrl,
                      borderRadius: 18,
                      fit: BoxFit.cover,
                    ),
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: const SizedBox.shrink(),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: List.generate(9, (index) {
                            final p = index / 8;
                            return Colors.black.withValues(
                              alpha: 0.84 * (1 - p * p),
                            );
                          }),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.paddingX,
                        vertical: metrics.paddingY,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: math.max(
                            0.0,
                            constraints.maxWidth - (metrics.paddingX * 2),
                          ),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: _bannerMaxTextScale,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: metrics.pillSpacing,
                                  runSpacing: metrics.pillSpacing,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ComicSourceBadge(
                                      label: source,
                                      scale: metrics.scale,
                                    ),
                                    if (comic.type != null)
                                      ComicTypeFlagBadge(
                                        type: comic.type!,
                                        scale: metrics.scale,
                                      ),
                                  ],
                                ),
                                SizedBox(height: metrics.badgeContentGap),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final useLargeTitle =
                                                  _bannerTitleLooksSingleLine(
                                                    context,
                                                    comic.title,
                                                    titleStyle,
                                                    constraints.maxWidth,
                                                    _clampedBannerTextScale(
                                                      context,
                                                    ),
                                                  );
                                              return Text(
                                                comic.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: useLargeTitle
                                                    ? singleLineTitleStyle
                                                    : titleStyle,
                                              );
                                            },
                                          ),
                                          if (hasPills) ...[
                                            SizedBox(
                                              height: metrics.titlePillGap,
                                            ),
                                            Wrap(
                                              spacing: metrics.pillSpacing,
                                              runSpacing: metrics.pillSpacing,
                                              children: [
                                                if (chapter != null)
                                                  _BannerPill(
                                                    label:
                                                        'Ch ${formatChapterNumber(chapter)}',
                                                    color: accent,
                                                    scale: metrics.scale,
                                                    solidSoftBackground: true,
                                                  ),
                                                if (ratingLabel != null)
                                                  _BannerPill(
                                                    label: ratingLabel,
                                                    color: Colors.amber,
                                                    foregroundColor:
                                                        Colors.amber,
                                                    icon: TonztoonIcons
                                                        .starFilled,
                                                    scale: metrics.scale,
                                                  ),
                                                if (statusLabel != null)
                                                  _BannerPill(
                                                    label: statusLabel,
                                                    color: Colors.white,
                                                    foregroundColor:
                                                        Colors.white,
                                                    scale: metrics.scale,
                                                  ),
                                              ],
                                            ),
                                          ],
                                          SizedBox(
                                            height: metrics.pillButtonGap,
                                          ),
                                          FilledButton.icon(
                                            onPressed: onTap,
                                            icon: Icon(
                                              TonztoonIcons.play,
                                              size: 17 * metrics.scale,
                                            ),
                                            label: const Text('Baca sekarang'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: accent,
                                              foregroundColor: Colors.white,
                                              textStyle: buttonTextStyle,
                                              minimumSize: Size(
                                                0,
                                                metrics.buttonMinHeight,
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                horizontal:
                                                    metrics.buttonPaddingX,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: metrics.mainContentGap),
                                    SizedBox(
                                      width: metrics.coverWidth,
                                      height: metrics.coverHeight,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            metrics.coverRadius,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.34,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.28,
                                              ),
                                              blurRadius: 14 * metrics.scale,
                                              offset: Offset(
                                                0,
                                                8 * metrics.scale,
                                              ),
                                            ),
                                          ],
                                        ),
                                        child: ComicCover(
                                          imageUrl: comic.coverImageUrl,
                                          borderRadius: metrics.coverRadius,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BannerPill extends StatelessWidget {
  const _BannerPill({
    required this.label,
    required this.color,
    this.foregroundColor,
    this.icon,
    this.scale = 1,
    this.solidSoftBackground = false,
  });

  final String label;
  final Color color;
  final Color? foregroundColor;
  final IconData? icon;
  final double scale;
  final bool solidSoftBackground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: solidSoftBackground
            ? Color.lerp(Colors.white, color, 0.18)
            : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 9 * scale,
          vertical: 5 * scale,
        ),
        child: icon == null
            ? Text(
                label,
                style: _scaledBannerTextStyle(
                  Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foregroundColor ?? color,
                    fontWeight: FontWeight.w900,
                  ),
                  scale,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12 * scale, color: foregroundColor ?? color),
                  SizedBox(width: 4 * scale),
                  Text(
                    label,
                    style: _scaledBannerTextStyle(
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foregroundColor ?? color,
                        fontWeight: FontWeight.w900,
                      ),
                      scale,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
