part of '../reader_screen.dart';

class _NearbyReadyIndicator extends StatelessWidget {
  const _NearbyReadyIndicator({
    required this.message,
    required this.controlsVisible,
  });

  final String? message;
  final bool controlsVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      right: 12,
      left: 12,
      bottom: safeBottom + (controlsVisible ? 238 : 18),
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomRight,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            reverseDuration: const Duration(milliseconds: 140),
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                  child: child,
                ),
              );
            },
            child: message == null
                ? const SizedBox.shrink(key: ValueKey('nearby-ready-empty'))
                : Semantics(
                    key: ValueKey(message),
                    liveRegion: true,
                    label: message,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(
                          MediaQuery.sizeOf(context).width - 24,
                          320,
                        ),
                      ),
                      child: Material(
                        color: colorScheme.inverseSurface.withValues(
                          alpha: 0.88,
                        ),
                        borderRadius: BorderRadius.circular(99),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                TonztoonIcons.check,
                                size: 15,
                                color: colorScheme.onInverseSurface,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  message!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onInverseSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _VerticalReader extends StatelessWidget {
  const _VerticalReader({
    required this.controller,
    required this.pages,
    required this.loadingNextChapter,
    required this.onDownloadPage,
    required this.actionsVisible,
    required this.pageKeyFor,
  });

  final ScrollController controller;
  final List<_ReaderPageUi> pages;
  final bool loadingNextChapter;
  final ValueChanged<_ReaderPageUi> onDownloadPage;
  final bool actionsVisible;
  final GlobalKey Function(_ReaderPageUi page) pageKeyFor;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      cacheExtent: _dynamicReaderCacheExtent(context),
      itemBuilder: (context, index) {
        if (index >= pages.length) {
          return const _InlineChapterLoading();
        }
        final page = pages[index];
        return Column(
          key: pageKeyFor(page),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index > 0 && page.pageIndexInChapter == 0)
              _ChapterBoundaryLabel(title: page.chapterTitle),
            _ReaderPage(
              page: page,
              actionsVisible: actionsVisible,
              onDownload: () => onDownloadPage(page),
            ),
          ],
        );
      },
      itemCount: pages.length + (loadingNextChapter ? 1 : 0),
    );
  }
}

class _ChapterBoundaryLabel extends StatelessWidget {
  const _ChapterBoundaryLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Row(
            children: [
              Expanded(
                child: Divider(
                  color: colorScheme.outlineVariant,
                  endIndent: 12,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: colorScheme.outlineVariant, indent: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineChapterLoading extends StatelessWidget {
  const _InlineChapterLoading();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        32,
        24,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                minHeight: 4,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 12),
              Text(
                'Menyiapkan chapter berikutnya...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
