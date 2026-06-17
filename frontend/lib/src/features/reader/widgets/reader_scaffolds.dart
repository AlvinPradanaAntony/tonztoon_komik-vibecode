part of '../reader_screen.dart';

class _ReadyReaderScaffold extends StatelessWidget {
  const _ReadyReaderScaffold({
    required this.overlayStyle,
    required this.readerBackground,
    required this.pagedMode,
    required this.pageController,
    required this.scrollController,
    required this.activePages,
    required this.continuousLoadingNext,
    required this.nearbyReadyMessage,
    required this.readerPrefs,
    required this.overlayVisible,
    required this.autoScrollAvailable,
    required this.autoScrollRunning,
    required this.currentPage,
    required this.comicTitle,
    required this.chapterTitle,
    required this.onToggleOverlay,
    required this.onBack,
    required this.onOpenComicDetail,
    required this.onDownloadPage,
    required this.onPageChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onToggleMode,
    required this.onPlayAutoScroll,
    required this.onPauseAutoScroll,
    required this.onOpenAutoScrollSettings,
    required this.verticalPageKeyFor,
  });

  final SystemUiOverlayStyle overlayStyle;
  final Color readerBackground;
  final bool pagedMode;
  final PageController pageController;
  final ScrollController scrollController;
  final List<_ReaderPageUi> activePages;
  final bool continuousLoadingNext;
  final String? nearbyReadyMessage;
  final ReaderPreferences? readerPrefs;
  final bool overlayVisible;
  final bool autoScrollAvailable;
  final bool autoScrollRunning;
  final ValueListenable<int> currentPage;
  final String comicTitle;
  final String chapterTitle;
  final VoidCallback onToggleOverlay;
  final VoidCallback onBack;
  final VoidCallback onOpenComicDetail;
  final ValueChanged<_ReaderPageUi> onDownloadPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onToggleMode;
  final VoidCallback onPlayAutoScroll;
  final VoidCallback onPauseAutoScroll;
  final VoidCallback onOpenAutoScrollSettings;
  final GlobalKey Function(_ReaderPageUi page) verticalPageKeyFor;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        extendBody: true,
        backgroundColor: readerBackground,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleOverlay,
          child: Stack(
            children: [
              Positioned.fill(
                child: pagedMode
                    ? _PagedReader(
                        controller: pageController,
                        pages: activePages,
                        reverse: readerPrefs?.readingDirection == 'rtl',
                        onDownloadPage: onDownloadPage,
                        actionsVisible: overlayVisible,
                        onPageChanged: onPageChanged,
                      )
                    : _VerticalReader(
                        controller: scrollController,
                        pages: activePages,
                        loadingNextChapter: continuousLoadingNext,
                        onDownloadPage: onDownloadPage,
                        actionsVisible: overlayVisible,
                        pageKeyFor: verticalPageKeyFor,
                      ),
              ),
              const _ReaderTopViewportFade(),
              const _ReaderBottomViewportFade(),
              _ReaderTopBar(
                visible: overlayVisible,
                pagedMode: pagedMode,
                comicTitle: comicTitle,
                chapterTitle: chapterTitle,
                onBack: onBack,
                onOpenComicDetail: onOpenComicDetail,
                onToggleMode: onToggleMode,
              ),
              _NearbyReadyIndicator(
                message: nearbyReadyMessage,
                controlsVisible: overlayVisible,
              ),
              _ReaderBottomBar(
                visible: overlayVisible,
                bingeModeActive: readerPrefs?.defaultBingeMode == true,
                currentPage: currentPage,
                totalPages: activePages.length,
                onPrevious: onPrevious,
                onNext: onNext,
                onPreviousChapter: onPreviousChapter,
                onNextChapter: onNextChapter,
              ),
              _AutoScrollFloatingControls(
                visible: autoScrollAvailable,
                running: autoScrollRunning,
                controlsVisible: overlayVisible,
                onPlay: onPlayAutoScroll,
                onPause: onPauseAutoScroll,
                onOpenSettings: onOpenAutoScrollSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreparingReaderScaffold extends StatelessWidget {
  const _PreparingReaderScaffold({
    required this.overlayStyle,
    required this.backgroundColor,
    required this.comicSummary,
    required this.chapterTitle,
  });

  final SystemUiOverlayStyle overlayStyle;
  final Color backgroundColor;
  final ComicSummary comicSummary;
  final String chapterTitle;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: _PreparingChapterView(
          comicSummary: comicSummary,
          chapterTitle: chapterTitle,
        ),
      ),
    );
  }
}
