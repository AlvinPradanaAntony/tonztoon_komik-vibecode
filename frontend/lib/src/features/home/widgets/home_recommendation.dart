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
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w900,
    );
    final singleLineTitleStyle = titleStyle?.copyWith(
      fontSize: (titleStyle.fontSize ?? 20) * _bannerSingleLineTitleScale,
      height: 1.05,
    );
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.13),
            blurRadius: 20,
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
                ComicCover(imageUrl: comic.coverImageUrl, borderRadius: 18),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: _bannerPaddingX,
                    vertical: _bannerPaddingY,
                  ),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: _bannerMaxTextScale,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ComicSourceBadge(label: source),
                            if (comic.type != null)
                              ComicTypeFlagBadge(type: comic.type!),
                          ],
                        ),
                        const SizedBox(height: _bannerBadgeContentGap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final useLargeTitle =
                                          _bannerTitleLooksSingleLine(
                                            context,
                                            comic.title,
                                            titleStyle,
                                            constraints.maxWidth,
                                            _clampedBannerTextScale(context),
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
                                    const SizedBox(height: _bannerTitlePillGap),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (chapter != null)
                                          _BannerPill(
                                            label:
                                                'Ch ${formatChapterNumber(chapter)}',
                                            color: accent,
                                            solidSoftBackground: true,
                                          ),
                                        if (ratingLabel != null)
                                          _BannerPill(
                                            label: ratingLabel,
                                            color: Colors.amber,
                                            foregroundColor: Colors.amber,
                                            icon: TonztoonIcons.starFilled,
                                          ),
                                        if (statusLabel != null)
                                          _BannerPill(
                                            label: statusLabel,
                                            color: Colors.white,
                                            foregroundColor: Colors.white,
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: _bannerPillButtonGap),
                                  FilledButton.icon(
                                    onPressed: onTap,
                                    icon: const Icon(
                                      TonztoonIcons.play,
                                      size: 17,
                                    ),
                                    label: const Text('Baca sekarang'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(
                                        0,
                                        _bannerButtonMinHeight,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: _bannerMainContentGap),
                            SizedBox(
                              width: _bannerCoverWidth,
                              height: _bannerCoverHeight,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.34),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ComicCover(
                                  imageUrl: comic.coverImageUrl,
                                  borderRadius: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerPill extends StatelessWidget {
  const _BannerPill({
    required this.label,
    required this.color,
    this.foregroundColor,
    this.icon,
    this.solidSoftBackground = false,
  });

  final String label;
  final Color color;
  final Color? foregroundColor;
  final IconData? icon;
  final bool solidSoftBackground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: solidSoftBackground
            ? Color.lerp(Colors.white, color, 0.18)
            : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: icon == null
            ? Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foregroundColor ?? color,
                  fontWeight: FontWeight.w900,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: foregroundColor ?? color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foregroundColor ?? color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
