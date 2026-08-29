part of '../comic_detail_screen.dart';

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.detail});

  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Transform.scale(
              scale:
                  1.1, // Scale up to hide blur bleed/white edges at the boundaries
              child: ComicCover(
                imageUrl: detail.coverImageUrl,
                borderRadius: 0,
                fit: BoxFit.cover,
                size: ComicCoverSize.large,
                fallbackIconSize: 36,
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: List.generate(9, (index) {
                final p = index / 8;
                final curve = math.pow(p, 1.5).toDouble();
                return Color.lerp(
                  Colors.black.withValues(alpha: 0.42),
                  colorScheme.surfaceContainerLowest,
                  curve,
                )!;
              }),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverSize = AppResponsive.detailCoverSize(
                context,
                constraints,
              );

              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 42),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ComicSourceBadge(
                        label: _sourceLabel(detail.sourceName),
                        prominent: true,
                      ),
                      const SizedBox(height: 12),
                      Hero(
                        tag: 'detail-cover-${detail.title}',
                        child: RepaintBoundary(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  blurRadius: 28,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: ComicCover(
                              imageUrl: detail.coverImageUrl,
                              width: coverSize.width,
                              height: coverSize.height,
                              borderRadius: 12,
                              size: ComicCoverSize.large,
                              fallbackIconSize: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CollapsingToolbarTint extends StatelessWidget {
  const _CollapsingToolbarTint({
    required this.progress,
    required this.color,
    required this.collapsedStatusBarStyle,
  });

  final ValueListenable<double> progress;
  final Color color;
  final SystemUiOverlayStyle collapsedStatusBarStyle;

  @override
  Widget build(BuildContext context) {
    final toolbarHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: toolbarHeight,
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, child) {
            final statusBarStyle = value > 0.56
                ? collapsedStatusBarStyle
                : collapsedStatusBarStyle.copyWith(
                    statusBarIconBrightness: Brightness.light,
                    statusBarBrightness: Brightness.dark,
                  );

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: statusBarStyle,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: value),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08 * value),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.progress,
    this.isLoading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final ValueListenable<double> progress;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, child) {
        // When value = 0 (expanded), bg alpha is 0.34. When value = 1 (collapsed), bg alpha is 0.
        final bgAlpha = 0.34 * (1.0 - value);
        // Fade icon color from White to onSurface for contrast
        final iconColor = Color.lerp(
          Colors.white,
          colorScheme.onSurface,
          value,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: bgAlpha),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: tooltip,
            onPressed: isLoading ? null : onPressed,
            icon: isLoading
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: iconColor,
                    ),
                  )
                : Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: iconColor,
            ),
          ),
        );
      },
    );
  }
}
