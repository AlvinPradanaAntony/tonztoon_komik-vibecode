part of '../reader_screen.dart';

class _PreparingChapterView extends StatefulWidget {
  const _PreparingChapterView({
    required this.comicSummary,
    required this.chapterTitle,
  });

  final ComicSummary comicSummary;
  final String chapterTitle;

  @override
  State<_PreparingChapterView> createState() => _PreparingChapterViewState();
}

class _PreparingChapterViewState extends State<_PreparingChapterView> {
  bool _showProgress = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Delay showing progress indicator slightly to prevent flickering on fast loads
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showProgress = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = widget.comicSummary.coverImageUrl;
    return Stack(
      children: [
        // Blurred Cover Background
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: ComicCover(
              imageUrl: coverUrl,
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
              fit: BoxFit.cover,
              fallbackIconSize: 72,
              showShimmer: false,
              size: ComicCoverSize.reader,
            ),
          ),
        ),

        // Dark Premium Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.88),
                ],
              ),
            ),
          ),
        ),

        // Content
        SafeArea(
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.9 + (value * 0.1),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 130,
                      height: 185,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 24,
                            spreadRadius: 2,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Hero(
                        tag: comicCoverHeroTag(
                          widget.comicSummary.sourceName,
                          widget.comicSummary.slug,
                        ),
                        child: ComicCover(
                          imageUrl: coverUrl,
                          width: 130,
                          height: 185,
                          borderRadius: 14,
                          fit: BoxFit.cover,
                          fallbackIconSize: 32,
                          showShimmer: false,
                          size: ComicCoverSize.reader,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      widget.comicSummary.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.comicSummary.sourceName.toUpperCase()} • ${widget.chapterTitle}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    AnimatedOpacity(
                      opacity: _showProgress ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Menyiapkan halaman...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
