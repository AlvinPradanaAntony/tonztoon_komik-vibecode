part of '../reader_screen.dart';

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.visible,
    required this.pagedMode,
    required this.comicTitle,
    required this.chapterTitle,
    required this.onBack,
    required this.onOpenComicDetail,
    required this.onToggleMode,
  });

  final bool visible;
  final bool pagedMode;
  final String comicTitle;
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onOpenComicDetail;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final overlayColor =
        (isDark ? colorScheme.surfaceContainerLowest : colorScheme.surface)
            .withValues(alpha: isDark ? 0.92 : 0.94);
    final foreground = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      top: visible ? 0 : -104,
      left: 0,
      right: 0,
      child: Material(
        color: overlayColor,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Kembali',
                  onPressed: onBack,
                  icon: const Icon(TonztoonIcons.arrowBack),
                  color: foreground,
                ),
                Expanded(
                  child: Tooltip(
                    message: 'Buka detail komik',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onOpenComicDetail,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              comicTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: pagedMode ? 'Mode vertical' : 'Mode paged',
                  onPressed: onToggleMode,
                  icon: Icon(
                    pagedMode ? TonztoonIcons.rows : TonztoonIcons.columns,
                  ),
                  color: foreground,
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.visible,
    required this.bingeModeActive,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
    required this.onPreviousChapter,
    required this.onNextChapter,
  });

  final bool visible;
  final bool bingeModeActive;
  final ValueListenable<int> currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final overlayColor =
        (isDark ? colorScheme.surfaceContainerLowest : colorScheme.surface)
            .withValues(alpha: isDark ? 0.94 : 0.96);
    final foreground = colorScheme.onSurface;
    final outline = colorScheme.outlineVariant;
    final pageControlBackground = isDark
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final pageControlForeground = isDark
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      bottom: visible ? 0 : -226,
      left: 0,
      right: 0,
      child: Material(
        color: overlayColor,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: ValueListenableBuilder<int>(
              valueListenable: currentPage,
              builder: (context, page, child) {
                final progress = totalPages == 0
                    ? 0.0
                    : ((page + 1) / totalPages).clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bingeModeActive) ...[
                      const _BingeModeIndicator(),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        _ReaderIconControl(
                          tooltip: 'Chapter sebelumnya',
                          onPressed: onPreviousChapter,
                          icon: TonztoonIcons.skipBack,
                          outlined: true,
                          foreground: foreground,
                          outline: outline,
                        ),
                        const SizedBox(width: 8),
                        _ReaderIconControl(
                          tooltip: 'Halaman sebelumnya',
                          onPressed: onPrevious,
                          icon: TonztoonIcons.chevronLeft,
                          foreground: pageControlForeground,
                          filledBackground: pageControlBackground,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 5,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Halaman ${page + 1} dari $totalPages',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: foreground),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _ReaderIconControl(
                          tooltip: 'Halaman berikutnya',
                          onPressed: onNext,
                          icon: TonztoonIcons.chevronRight,
                          foreground: pageControlForeground,
                          filledBackground: pageControlBackground,
                        ),
                        const SizedBox(width: 8),
                        _ReaderIconControl(
                          tooltip: 'Chapter berikutnya',
                          onPressed: onNextChapter,
                          icon: TonztoonIcons.skipForward,
                          outlined: true,
                          foreground: foreground,
                          outline: outline,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderIconControl extends StatelessWidget {
  const _ReaderIconControl({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.outlined = false,
    this.foreground,
    this.filledBackground,
    this.outline,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool outlined;
  final Color? foreground;
  final Color? filledBackground;
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final style = outlined
        ? IconButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: outline ?? Theme.of(context).dividerColor),
            fixedSize: const Size.square(48),
          )
        : IconButton.styleFrom(
            backgroundColor: filledBackground,
            foregroundColor: foreground,
            fixedSize: const Size.square(48),
          );
    final button = outlined
        ? IconButton.outlined(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
            style: style,
          )
        : IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
            style: style,
          );
    return SizedBox.square(dimension: 48, child: button);
  }
}

class _AutoScrollFloatingControls extends StatelessWidget {
  const _AutoScrollFloatingControls({
    required this.visible,
    required this.running,
    required this.controlsVisible,
    required this.onPlay,
    required this.onPause,
    required this.onOpenSettings,
  });

  final bool visible;
  final bool running;
  final bool controlsVisible;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final playBackground = isDark ? colorScheme.secondary : colorScheme.primary;
    final playForeground = isDark ? Colors.white : colorScheme.onPrimary;
    final settingsBackground = isDark
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainerHighest;
    final settingsForeground = colorScheme.onSurface;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final targetOpacity = visible ? (running ? 0.15 : 1.0) : 0.0;
    final bottomOffset = controlsVisible ? 115 : 18;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      right: 16,
      bottom: safeBottom + bottomOffset,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          opacity: targetOpacity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'reader-autoscroll-toggle',
                  tooltip: running ? 'Pause AutoScroll' : 'Play AutoScroll',
                  onPressed: running ? onPause : onPlay,
                  backgroundColor: playBackground,
                  foregroundColor: playForeground,
                  child: Icon(
                    running ? TonztoonIcons.pause : TonztoonIcons.play,
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'reader-autoscroll-settings',
                  tooltip: 'Pengaturan AutoScroll',
                  onPressed: onOpenSettings,
                  backgroundColor: settingsBackground,
                  foregroundColor: settingsForeground,
                  child: const Icon(TonztoonIcons.settings2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BingeModeIndicator extends StatelessWidget {
  const _BingeModeIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: colorScheme.tertiary.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TonztoonIcons.localFireDepartment,
                size: 14,
                color: colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Binge Mode aktif',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
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
