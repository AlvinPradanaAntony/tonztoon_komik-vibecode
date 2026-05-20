import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../core/app_snackbar.dart';
import '../../core/reader_image_cache.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  ReaderScreen({
    super.key,
    String? comicTitle,
    String? chapterTitle,
    ComicSummary? comic,
    String? sourceName,
    String? slug,
    double? chapterNumber,
    ComicSummary? initialComic,
  }) : comic = initialComic ?? comic,
       sourceName = sourceName ?? comic?.sourceName ?? 'komiku',
       slug = slug ?? comic?.slug ?? '',
       chapterNumber = chapterNumber ?? 1,
       comicTitle =
           comicTitle ?? initialComic?.title ?? comic?.title ?? 'Komik',
       chapterTitle =
           chapterTitle ??
           'Chapter ${chapterNumber == null ? 1 : formatChapterNumber(chapterNumber)}';

  final String sourceName;
  final String slug;
  final double chapterNumber;
  final String comicTitle;
  final String chapterTitle;
  final ComicSummary? comic;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  static const _nearbyChapterWindow = 5.0;
  static const _nearbyStatusPollInterval = Duration(seconds: 4);
  static const _nearbyStatusMaxPolls = 20;
  static const _progressSaveDelay = Duration(milliseconds: 500);
  static const _imagePrefetchCooldown = Duration(seconds: 20);
  static const _imagePrefetchHistoryLifetime = Duration(seconds: 60);

  ScrollController _scrollController = ScrollController();
  PageController _pageController = PageController();
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  final Stopwatch _readingStopwatch = Stopwatch();
  late final ReadingTimeController _readingTimeController;
  List<_ReaderPageUi> _activePages = const [];
  bool _overlayVisible = false;
  bool _pagedMode = false;
  bool _didApplyReaderPreferences = false;
  bool _restored = false;
  bool _isRestoringPosition = false;
  bool _readerScaffoldShown = false;
  bool _nearbyWatcherStarted = false;
  Timer? _imagePrefetchTimer;
  Timer? _initialPreloadTimeoutTimer;
  Timer? _nearbyReadyTimer;
  Timer? _nearbyReadyNoticeTimer;
  Timer? _progressSaveTimer;
  Timer? _autoNextTimer;
  int _nearbyReadyPolls = 0;
  String? _initialPreloadKey;
  Future<void>? _initialPreloadFuture;
  ReadingProgress? _pendingProgress;
  ComicRequest? _pendingProgressRequest;
  ReaderPreferences? _latestReaderPrefs;
  ChapterListItem? _latestNextChapter;
  List<ChapterListItem>? _latestChapterItems;
  String? _activePagesKey;
  double _activeChapterNumber = 0;
  String? _activeChapterTitle;
  bool _autoNextArmed = false;
  bool _autoNextTriggered = false;
  bool _continuousLoadingNext = false;
  String? _nearbyReadyNoticeMessage;
  final Set<double> _continuousLoadedChapterNumbers = <double>{};
  final Set<double> _continuousLoadingChapterNumbers = <double>{};
  final Set<double> _continuousUnavailableChapterNumbers = <double>{};
  final Map<String, DateTime> _recentPrefetchRequests = <String, DateTime>{};
  final Set<double> _announcedNearbyReadyChapters = <double>{};
  final Map<double, int> _knownNearbyPageCounts = <double, int>{};
  final Map<String, GlobalKey> _verticalPageKeys = <String, GlobalKey>{};

  ComicRequest get _comicRequest =>
      ComicRequest(widget.sourceName, widget.slug);

  ComicSummary get _comicSummary =>
      widget.comic ??
      ComicSummary(
        title: widget.comicTitle,
        slug: widget.slug,
        sourceName: widget.sourceName,
        coverImageUrl: widget.comic?.coverImageUrl,
        type: widget.comic?.type,
      );

  @override
  void initState() {
    super.initState();
    _readingTimeController = ref.read(readingTimeProvider.notifier);
    _activeChapterNumber = widget.chapterNumber;
    _activeChapterTitle = widget.chapterTitle;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_syncVerticalProgress);
    _startReadingTimer();
  }

  @override
  void dispose() {
    _flushPendingProgress();
    _flushReadingTime(deferProviderUpdate: true);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController
      ..removeListener(_syncVerticalProgress)
      ..dispose();
    _pageController.dispose();
    _currentPage.dispose();
    _imagePrefetchTimer?.cancel();
    _initialPreloadTimeoutTimer?.cancel();
    _nearbyReadyTimer?.cancel();
    _nearbyReadyNoticeTimer?.cancel();
    _progressSaveTimer?.cancel();
    _autoNextTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _startReadingTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _flushPendingProgress();
        _flushReadingTime(deferProviderUpdate: true);
    }
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceName != widget.sourceName ||
        oldWidget.slug != widget.slug ||
        oldWidget.chapterNumber != widget.chapterNumber) {
      _flushPendingProgress();
      _currentPage.value = 0;
      _pagedMode = false;
      _didApplyReaderPreferences = false;
      _restored = false;
      _isRestoringPosition = false;
      _readerScaffoldShown = false;
      _nearbyWatcherStarted = false;
      _autoNextArmed = false;
      _autoNextTriggered = false;
      _continuousLoadingNext = false;
      _activePagesKey = null;
      _activeChapterNumber = widget.chapterNumber;
      _activeChapterTitle = widget.chapterTitle;
      _nearbyReadyPolls = 0;
      _nearbyReadyNoticeMessage = null;
      _initialPreloadKey = null;
      _initialPreloadFuture = null;
      _continuousLoadedChapterNumbers.clear();
      _continuousLoadingChapterNumbers.clear();
      _continuousUnavailableChapterNumbers.clear();
      _recentPrefetchRequests.clear();
      _announcedNearbyReadyChapters.clear();
      _knownNearbyPageCounts.clear();
      _imagePrefetchTimer?.cancel();
      _initialPreloadTimeoutTimer?.cancel();
      _nearbyReadyTimer?.cancel();
      _nearbyReadyNoticeTimer?.cancel();
      _progressSaveTimer?.cancel();
      _autoNextTimer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  void _syncVerticalProgress() {
    if (!_scrollController.hasClients || _pagedMode || _activePages.isEmpty) {
      return;
    }
    // Suppress progress recording while restoring scroll position to avoid
    // overwriting the saved progress with the intermediate scroll position.
    if (_isRestoringPosition) return;

    final userScrolling =
        _scrollController.position.userScrollDirection != ScrollDirection.idle;
    final visiblePage = _visibleVerticalPagePosition();
    final nextPage =
        visiblePage?.index ??
        _estimatedVerticalPageFromScrollOffset().clamp(
          0,
          _activePages.length - 1,
        );
    final isCompleted = visiblePage == null
        ? null
        : _isCompletedFromVerticalPosition(visiblePage);

    if (_currentPage.value != nextPage) {
      _currentPage.value = nextPage;
      _recordProgressAt(
        nextPage,
        scrollOffset: _scrollController.offset,
        readerPrefs: _latestReaderPrefs,
        isCompletedOverride: isCompleted,
      );
      _scheduleImagePrefetch();
      _ensureContinuousChapterAhead(nextPage, _latestReaderPrefs);
      _maybeAutoNextChapter(
        nextPage,
        readerPrefs: _latestReaderPrefs,
        nextChapter: _latestNextChapter,
        triggeredByUser: true,
      );
    } else {
      _recordProgressAt(
        nextPage,
        scrollOffset: _scrollController.offset,
        trackReadingTime: false,
        readerPrefs: _latestReaderPrefs,
        isCompletedOverride: isCompleted,
      );
    }

    if (_overlayVisible && userScrolling) {
      setState(() => _overlayVisible = false);
    }
  }

  int _estimatedVerticalPageFromScrollOffset() {
    final viewport = MediaQuery.sizeOf(context).height;
    return (_scrollController.offset / (viewport * 0.82)).floor();
  }

  _VerticalPagePosition? _visibleVerticalPagePosition() {
    if (_activePages.isEmpty) return null;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final viewportCenter = viewportHeight / 2;
    _VerticalPagePosition? best;
    var bestVisibleHeight = -1.0;
    var bestCenterDistance = double.infinity;

    for (var index = 0; index < _activePages.length; index++) {
      final key = _verticalPageKeys[_verticalPageKey(_activePages[index])];
      final context = key?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;

      final top = renderObject.localToGlobal(Offset.zero).dy;
      final height = renderObject.size.height;
      if (height <= 0) continue;
      final bottom = top + height;
      final visibleTop = math.max(0.0, top);
      final visibleBottom = math.min(viewportHeight, bottom);
      final visibleHeight = math.max(0.0, visibleBottom - visibleTop);
      if (visibleHeight <= 0) continue;

      final centerDistance = ((visibleTop + visibleBottom) / 2 - viewportCenter)
          .abs();
      if (visibleHeight > bestVisibleHeight ||
          (visibleHeight == bestVisibleHeight &&
              centerDistance < bestCenterDistance)) {
        bestVisibleHeight = visibleHeight;
        bestCenterDistance = centerDistance;
        best = _VerticalPagePosition(
          index: index,
          page: _activePages[index],
          bottom: bottom,
          viewportHeight: viewportHeight,
        );
      }
    }

    return best;
  }

  bool _isCompletedFromVerticalPosition(_VerticalPagePosition position) {
    final page = position.page;
    if (page.pageIndexInChapter < page.totalPagesInChapter - 1) {
      return false;
    }
    const bottomVisibilityTolerance = 24.0;
    return position.bottom <=
        position.viewportHeight + bottomVisibilityTolerance;
  }

  void _scheduleImagePrefetch() {
    _imagePrefetchTimer?.cancel();
    _imagePrefetchTimer = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      unawaited(_preloadFromCurrentPosition());
    });
  }

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
  }

  void _toggleMode() {
    setState(() {
      _pagedMode = !_pagedMode;
      _overlayVisible = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final page = _currentPage.value.clamp(0, _activePages.length - 1);
      if (_pagedMode && _pageController.hasClients) {
        _pageController.jumpToPage(page);
      } else if (!_pagedMode && _scrollController.hasClients) {
        _scrollController.jumpTo(
          page * MediaQuery.sizeOf(context).height * 0.82,
        );
      }
    });
  }

  void _goRelativePage(
    int delta, {
    ReaderPreferences? readerPrefs,
    ChapterListItem? nextChapter,
  }) {
    final current = _currentPage.value;
    final next = (current + delta).clamp(0, _activePages.length - 1);
    _currentPage.value = next;
    _recordProgressAt(next, readerPrefs: readerPrefs);
    _ensureContinuousChapterAhead(next, readerPrefs);
    _maybeAutoNextChapter(
      next,
      readerPrefs: readerPrefs,
      nextChapter: nextChapter,
      triggeredByUser: delta > 0,
    );
    if (_pagedMode && _pageController.hasClients) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (_scrollController.hasClients) {
      unawaited(
        _animateToVerticalPageIndex(
          next,
          duration: const Duration(milliseconds: 260),
        ),
      );
    }
  }

  void _downloadPage(_ReaderPageUi page) {
    final comic =
        widget.comic ??
        ComicSummary(
          title: widget.comicTitle,
          slug: widget.slug,
          sourceName: widget.sourceName,
        );
    if (comic.slug.trim().isEmpty) return;

    unawaited(
      ref
          .read(libraryRepositoryProvider)
          .saveFavoriteScene(
            comic: comic,
            chapterNumber: widget.chapterNumber,
            pageItemIndex: page.number - 1,
            imageUrl: page.imageUrl,
          )
          .then((_) {
            ref.invalidate(favoriteScenesProvider);
            if (!mounted) return;
            showAppSnackBar(
              context,
              message: 'Page ${page.number} tersimpan ke Scene.',
              type: AppSnackBarType.success,
              duration: const Duration(seconds: 2),
            );
          })
          .catchError((Object error) {
            if (!mounted) return;
            showAppSnackBar(
              context,
              message: error.toString(),
              type: AppSnackBarType.failure,
              duration: const Duration(seconds: 2),
            );
          }),
    );
  }

  void _recordProgressAt(
    int pageIndex, {
    double? scrollOffset,
    bool trackReadingTime = true,
    ReaderPreferences? readerPrefs,
    bool? isCompletedOverride,
  }) {
    if (trackReadingTime) {
      _flushReadingTime(restart: true);
    }
    final page = pageIndex >= 0 && pageIndex < _activePages.length
        ? _activePages[pageIndex]
        : null;
    if (page == null) return;
    _updateActiveChapter(page);
    final progress = _buildProgress(
      page,
      scrollOffset: page.chapterNumber == widget.chapterNumber
          ? scrollOffset
          : null,
      readerPrefs: readerPrefs,
      isCompletedOverride: isCompletedOverride,
    );
    if (progress == null) return;
    _pendingProgress = progress;
    _pendingProgressRequest = ComicRequest(widget.sourceName, widget.slug);
    _progressSaveTimer?.cancel();
    if (progress.isCompleted) {
      _flushPendingProgress();
      return;
    }
    _progressSaveTimer = Timer(_progressSaveDelay, _flushPendingProgress);
  }

  ReadingProgress? _buildProgress(
    _ReaderPageUi page, {
    double? scrollOffset,
    ReaderPreferences? readerPrefs,
    bool? isCompletedOverride,
  }) {
    final comic =
        widget.comic ??
        ComicSummary(
          title: widget.comicTitle,
          slug: widget.slug,
          sourceName: widget.sourceName,
          coverImageUrl: widget.comic?.coverImageUrl,
        );
    if (comic.slug.trim().isEmpty) return null;
    return ReadingProgress.fromReader(
      comic: comic,
      chapterNumber: page.chapterNumber,
      readingMode: _pagedMode ? 'paged' : 'vertical',
      scrollOffset: scrollOffset,
      pageIndex: _pagedMode ? page.pageIndexInChapter : null,
      pageItemIndex: page.pageIndexInChapter,
      totalPageItems: page.totalPagesInChapter,
      isCompleted:
          readerPrefs?.markReadOnComplete == true &&
          (isCompletedOverride ??
              page.pageIndexInChapter >= page.totalPagesInChapter - 1),
    );
  }

  void _updateActiveChapter(_ReaderPageUi page) {
    if (_activeChapterNumber == page.chapterNumber &&
        _activeChapterTitle == page.chapterTitle) {
      return;
    }
    setState(() {
      _activeChapterNumber = page.chapterNumber;
      _activeChapterTitle = page.chapterTitle;
    });
  }

  void _maybeAutoNextChapter(
    int pageIndex, {
    required ReaderPreferences? readerPrefs,
    required ChapterListItem? nextChapter,
    required bool triggeredByUser,
  }) {
    if (_activePages.isEmpty || pageIndex < _activePages.length - 1) {
      _autoNextTimer?.cancel();
      _autoNextTriggered = false;
      return;
    }
    if (!_autoNextArmed ||
        !triggeredByUser ||
        _autoNextTriggered ||
        readerPrefs?.defaultBingeMode != true ||
        !_pagedMode ||
        nextChapter == null) {
      return;
    }

    _autoNextTriggered = true;
    _autoNextTimer?.cancel();
    _autoNextTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      _goToChapter(nextChapter);
    });
  }

  void _flushPendingProgress() {
    final progress = _pendingProgress;
    final request = _pendingProgressRequest;
    if (progress == null || request == null) return;
    _pendingProgress = null;
    _pendingProgressRequest = null;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;

    unawaited(
      ref
          .read(progressRepositoryProvider)
          .saveProgress(progress)
          .whenComplete(() => _invalidateProgressState(request))
          .catchError((Object error, StackTrace _) {
            debugPrint('Failed to save reading progress locally: $error');
          }),
    );
  }

  void _invalidateProgressState(ComicRequest request) {
    if (!mounted) return;
    ref.invalidate(progressProvider(request));
    ref.invalidate(continueReadingProvider);
    ref.invalidate(libraryComicStateProvider(_comicSummary));
  }

  void _startReadingTimer() {
    if (!_readingStopwatch.isRunning) {
      _readingStopwatch.start();
    }
  }

  void _flushReadingTime({
    bool restart = false,
    bool deferProviderUpdate = false,
  }) {
    final elapsed = _readingStopwatch.elapsed;
    _readingStopwatch
      ..reset()
      ..stop();
    if (elapsed.inSeconds > 0) {
      if (deferProviderUpdate) {
        unawaited(Future<void>(() => _readingTimeController.add(elapsed)));
      } else {
        unawaited(_readingTimeController.add(elapsed));
      }
    }
    if (restart) {
      _readingStopwatch.start();
    }
  }

  void _restorePosition(ReadingProgress? progress) {
    if (_restored || progress == null || _activePages.isEmpty) return;
    if (progress.chapterNumber != widget.chapterNumber) return;

    _restored = true;
    final pageIndex =
        (progress.pageIndex ?? progress.lastReadPageItemIndex ?? 0).clamp(
          0,
          _activePages.length - 1,
        );
    _currentPage.value = pageIndex;
    _pagedMode = progress.readingMode == 'paged';

    if (_pagedMode) {
      // Paged mode: jump after the PageView attaches.
      _isRestoringPosition = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _isRestoringPosition = false;
          return;
        }
        if (_pageController.hasClients) {
          _pageController.jumpToPage(pageIndex);
        }
        _isRestoringPosition = false;
      });
      return;
    }

    if (!_scrollController.hasClients) {
      // Fast path: the ListView hasn't attached yet (we're inside the
      // FutureBuilder builder that is about to build it for the first time).
      // Recreate the controller with initialScrollOffset so Flutter renders
      // the list starting directly at the saved position — no visible jump.
      _recreateScrollControllerAt(_progressScrollOffset(pageIndex));
      _schedulePreciseScrollRestoration(pageIndex);
      return;
    }

    _restoreAttachedVerticalPosition(pageIndex);
  }

  void _restoreAttachedVerticalPosition(int pageIndex) {
    final targetOffset = _progressScrollOffset(pageIndex);
    _isRestoringPosition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isRestoringPosition = false;
        return;
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
        );
        _schedulePreciseScrollRestoration(pageIndex);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isRestoringPosition = false;
      });
    });
  }

  /// Disposes the current [ScrollController] and creates a fresh one that
  /// starts at [initialOffset]. The progress listener is re-attached so the
  /// rest of the code is unaware of the swap.
  void _recreateScrollControllerAt(double initialOffset) {
    _scrollController.removeListener(_syncVerticalProgress);
    _scrollController.dispose();
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _scrollController.addListener(_syncVerticalProgress);
  }

  void _recreatePageControllerAt(int pageIndex) {
    _pageController.dispose();
    _pageController = PageController(initialPage: pageIndex);
  }

  /// Schedules a multi-frame check to align the target page index perfectly
  /// with the top of the viewport using [Scrollable.ensureVisible] as soon
  /// as its render context is available.
  void _schedulePreciseScrollRestoration(int pageIndex) {
    if (_activePages.isEmpty ||
        pageIndex < 0 ||
        pageIndex >= _activePages.length) {
      return;
    }

    var attempts = 0;
    void checkAndAlign() {
      if (!mounted) return;
      final page = _activePages[pageIndex];
      final pageContext =
          _verticalPageKeys[_verticalPageKey(page)]?.currentContext;

      if (pageContext != null) {
        final renderBox = pageContext.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.attached) {
          // Suppress sync vertical progress to avoid saving intermediate scrolls
          _isRestoringPosition = true;
          Scrollable.ensureVisible(
            pageContext,
            alignment: 0.0,
            duration: Duration.zero, // Snap instantly
          );
          // Wait one frame after alignment to let it settle before unsuppressing
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isRestoringPosition = false;
            }
          });
          return;
        }
      }

      attempts++;
      if (attempts < 15) {
        // Try again in the next frame to allow lazy list items to build and lay out
        WidgetsBinding.instance.addPostFrameCallback((_) => checkAndAlign());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => checkAndAlign());
  }

  @override
  Widget build(BuildContext context) {
    final request = ChapterRequest(
      widget.sourceName,
      widget.slug,
      widget.chapterNumber,
    );
    final chapterAsync = ref.watch(chapterProvider(request));
    final payload = chapterAsync.asData?.value;
    final readerPrefs = ref.watch(readerPreferencesProvider).asData?.value;
    final chapters = ref.watch(chaptersProvider(_comicRequest));
    final chapterItems = chapters.asData?.value;
    _latestReaderPrefs = readerPrefs;
    _latestChapterItems = chapterItems;
    final referenceChapter = _activeChapterNumber <= 0
        ? widget.chapterNumber
        : _activeChapterNumber;
    final previousChapter = _previousChapter(chapterItems, referenceChapter);
    final nextChapter = _nextChapter(chapterItems, referenceChapter);
    _latestNextChapter = nextChapter;
    final progress = ref.watch(progressProvider(_comicRequest));
    final savedProgress = progress.asData?.value;
    final matchingProgress =
        savedProgress?.chapterNumber == widget.chapterNumber
        ? savedProgress
        : null;
    if (!_restored && matchingProgress != null) {
      _pagedMode = matchingProgress.readingMode == 'paged';
      _didApplyReaderPreferences = true;
    } else if (!_didApplyReaderPreferences && readerPrefs != null) {
      _pagedMode = readerPrefs.defaultReadingMode == 'paged';
      _didApplyReaderPreferences = true;
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final readerBackground = isDark
        ? const Color(0xFF050608)
        : colorScheme.surfaceContainerLowest;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
    const preparingOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );

    if (payload == null && chapterAsync.isLoading) {
      return _buildBackAwareRoute(
        _PreparingReaderScaffold(
          overlayStyle: preparingOverlayStyle,
          backgroundColor: readerBackground,
          comicSummary: _comicSummary,
          chapterTitle: widget.chapterTitle,
        ),
      );
    }

    if (payload == null) {
      final error = chapterAsync.whenOrNull(
        error: (error, stackTrace) => error,
      );
      return _buildBackAwareRoute(
        Scaffold(
          backgroundColor: readerBackground,
          body: _ReaderErrorView(
            message: error?.toString() ?? 'Chapter gagal dimuat.',
            onRetry: () => ref.invalidate(chapterProvider(request)),
          ),
        ),
      );
    }
    _ensureActivePages(payload);
    if (_activePages.isEmpty) {
      return _buildBackAwareRoute(
        Scaffold(
          backgroundColor: readerBackground,
          body: _ReaderErrorView(
            message: 'Chapter ini belum memiliki gambar.',
            onRetry: () => ref.invalidate(chapterProvider(request)),
          ),
        ),
      );
    }

    final waitingForInitialProgress =
        !_readerScaffoldShown &&
        !_restored &&
        progress.isLoading &&
        savedProgress == null;
    if (waitingForInitialProgress) {
      return _buildBackAwareRoute(
        _PreparingReaderScaffold(
          overlayStyle: preparingOverlayStyle,
          backgroundColor: readerBackground,
          comicSummary: _comicSummary,
          chapterTitle: widget.chapterTitle,
        ),
      );
    }

    return _buildBackAwareRoute(
      FutureBuilder<void>(
        future: _ensureInitialPreload(_initialChapterPages(), matchingProgress),
        builder: (context, snapshot) {
          // Position restore can happen synchronously before the first reader
          // frame, but keep the loading screen until the target image window has
          // been decoded/cached. Otherwise continue-reading opens on a correct
          // anchor with a blank reserved image area.
          if (snapshot.connectionState != ConnectionState.done &&
              !_readerScaffoldShown) {
            return _PreparingReaderScaffold(
              overlayStyle: preparingOverlayStyle,
              backgroundColor: readerBackground,
              comicSummary: _comicSummary,
              chapterTitle: widget.chapterTitle,
            );
          }

          _readerScaffoldShown = true;
          _restorePosition(matchingProgress);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoNextArmed = true;
            _scheduleImagePrefetch();
            _ensureNearbyReadinessWatcher(chapters.asData?.value);
            _ensureContinuousChapterAhead(_currentPage.value, readerPrefs);
          });

          return _ReadyReaderScaffold(
            overlayStyle: overlayStyle,
            readerBackground: readerBackground,
            pagedMode: _pagedMode,
            pageController: _pageController,
            scrollController: _scrollController,
            activePages: _activePages,
            continuousLoadingNext: _continuousLoadingNext,
            nearbyReadyMessage: _nearbyReadyNoticeMessage,
            readerPrefs: readerPrefs,
            overlayVisible: _overlayVisible,
            currentPage: _currentPage,
            comicTitle: widget.comicTitle,
            chapterTitle: _activeChapterTitle ?? widget.chapterTitle,
            onToggleOverlay: _toggleOverlay,
            onBack: _goBack,
            onOpenComicDetail: _openComicDetail,
            onDownloadPage: _downloadPage,
            onPageChanged: (index) {
              _currentPage.value = index;
              _recordProgressAt(index, readerPrefs: readerPrefs);
              _scheduleImagePrefetch();
              _ensureContinuousChapterAhead(index, readerPrefs);
              _maybeAutoNextChapter(
                index,
                readerPrefs: readerPrefs,
                nextChapter: nextChapter,
                triggeredByUser: true,
              );
              if (_overlayVisible) {
                setState(() => _overlayVisible = false);
              }
            },
            onPrevious: () => _goRelativePage(-1, readerPrefs: readerPrefs),
            onNext: () => _goRelativePage(
              1,
              readerPrefs: readerPrefs,
              nextChapter: nextChapter,
            ),
            onPreviousChapter: previousChapter == null
                ? null
                : () => _goToAdjacentChapter(
                    previousChapter,
                    readerPrefs: readerPrefs,
                  ),
            onNextChapter: nextChapter == null
                ? null
                : () => _goToAdjacentChapter(
                    nextChapter,
                    readerPrefs: readerPrefs,
                  ),
            onToggleMode: _toggleMode,
            verticalPageKeyFor: _verticalPageKeyFor,
          );
        },
      ),
    );
  }

  Widget _buildBackAwareRoute(Widget child) {
    return PopScope(
      canPop: _canPopRoute(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: child,
    );
  }

  void _ensureActivePages(ChapterPayload payload) {
    final key =
        '${widget.sourceName}|${widget.slug}|${widget.chapterNumber}|${payload.images.length}';
    if (_activePagesKey == key) return;

    _activePagesKey = key;
    _activePages = _pagesFromChapter(
      payload,
      chapterTitle: widget.chapterTitle,
      fallbackChapterNumber: widget.chapterNumber,
    );
    _continuousLoadedChapterNumbers
      ..clear()
      ..add(widget.chapterNumber);
    _continuousLoadingChapterNumbers.clear();
    _continuousUnavailableChapterNumbers.clear();
    _continuousLoadingNext = false;
    _activeChapterNumber = widget.chapterNumber;
    _activeChapterTitle = widget.chapterTitle;
    _pruneVerticalPageKeys();
  }

  GlobalKey _verticalPageKeyFor(_ReaderPageUi page) {
    return _verticalPageKeys.putIfAbsent(_verticalPageKey(page), GlobalKey.new);
  }

  void _pruneVerticalPageKeys() {
    final activeKeys = _activePages.map(_verticalPageKey).toSet();
    _verticalPageKeys.removeWhere((key, value) => !activeKeys.contains(key));
  }

  List<_ReaderPageUi> _initialChapterPages() {
    return _activePages
        .where((page) => page.chapterNumber == widget.chapterNumber)
        .toList();
  }

  ChapterListItem? _previousChapter(
    List<ChapterListItem>? chapters,
    double chapterNumber,
  ) {
    return _relativeChapter(
      chapters,
      chapterNumber,
      (number) => number < chapterNumber,
    );
  }

  ChapterListItem? _nextChapter(
    List<ChapterListItem>? chapters,
    double chapterNumber,
  ) {
    return _relativeChapter(
      chapters,
      chapterNumber,
      (number) => number > chapterNumber,
    );
  }

  ChapterListItem? _relativeChapter(
    List<ChapterListItem>? chapters,
    double referenceChapterNumber,
    bool Function(double chapterNumber) keep,
  ) {
    if (chapters == null || chapters.isEmpty) return null;
    final candidates =
        chapters.where((chapter) => keep(chapter.chapterNumber)).toList()..sort(
          (a, b) => (a.chapterNumber - referenceChapterNumber).abs().compareTo(
            (b.chapterNumber - referenceChapterNumber).abs(),
          ),
        );
    return candidates.firstOrNull;
  }

  bool _continuousVerticalEnabled(ReaderPreferences? readerPrefs) {
    return !_pagedMode && readerPrefs?.defaultBingeMode == true;
  }

  void _ensureContinuousChapterAhead(
    int pageIndex,
    ReaderPreferences? readerPrefs,
  ) {
    if (!_continuousVerticalEnabled(readerPrefs) || _activePages.isEmpty) {
      return;
    }
    final page = _activePages[pageIndex.clamp(0, _activePages.length - 1)];
    final nextChapter = _nextChapter(_latestChapterItems, page.chapterNumber);
    if (nextChapter == null) return;
    unawaited(_ensureContinuousChapterLoaded(nextChapter));
  }

  Future<void> _ensureContinuousChapterLoaded(ChapterListItem chapter) async {
    final chapterNumber = chapter.chapterNumber;
    if (_continuousLoadedChapterNumbers.contains(chapterNumber) ||
        _continuousLoadingChapterNumbers.contains(chapterNumber) ||
        _continuousUnavailableChapterNumbers.contains(chapterNumber)) {
      return;
    }

    _continuousLoadingChapterNumbers.add(chapterNumber);
    if (mounted) {
      setState(() => _continuousLoadingNext = true);
    }

    try {
      final payload = await ref.read(
        chapterProvider(
          ChapterRequest(widget.sourceName, widget.slug, chapterNumber),
        ).future,
      );
      final pages = _pagesFromChapter(
        payload,
        chapterTitle: _chapterTitleFor(chapter),
        fallbackChapterNumber: chapterNumber,
      );
      if (!mounted) return;
      if (pages.isEmpty) {
        _continuousUnavailableChapterNumbers.add(chapterNumber);
        return;
      }

      final startIndex = _activePages.length;
      setState(() {
        _activePages = [..._activePages, ...pages];
        _continuousLoadedChapterNumbers.add(chapterNumber);
        _pruneVerticalPageKeys();
      });
      unawaited(
        _preloadIndexes(
          Iterable<int>.generate(
            math.min(3, pages.length),
            (index) => startIndex + index,
          ),
        ),
      );
    } catch (_) {
      _continuousUnavailableChapterNumbers.add(chapterNumber);
    } finally {
      _continuousLoadingChapterNumbers.remove(chapterNumber);
      if (mounted) {
        setState(() => _continuousLoadingNext = false);
      }
    }
  }

  void _goToAdjacentChapter(
    ChapterListItem chapter, {
    required ReaderPreferences? readerPrefs,
  }) {
    if (!_continuousVerticalEnabled(readerPrefs)) {
      _goToChapter(chapter);
      return;
    }
    unawaited(_scrollToContinuousChapter(chapter));
  }

  Future<void> _scrollToContinuousChapter(ChapterListItem chapter) async {
    var targetIndex = _activePages.indexWhere(
      (page) => page.chapterNumber == chapter.chapterNumber,
    );
    if (targetIndex < 0 && chapter.chapterNumber > _activeChapterNumber) {
      await _ensureContinuousChapterLoaded(chapter);
      if (!mounted) return;
      targetIndex = _activePages.indexWhere(
        (page) => page.chapterNumber == chapter.chapterNumber,
      );
    }
    if (targetIndex < 0) {
      _goToChapter(chapter);
      return;
    }
    _currentPage.value = targetIndex;
    _updateActiveChapter(_activePages[targetIndex]);
    if (!_scrollController.hasClients) return;
    await _animateToVerticalPageIndex(
      targetIndex,
      duration: const Duration(milliseconds: 320),
    );
  }

  Future<void> _animateToVerticalPageIndex(
    int pageIndex, {
    required Duration duration,
  }) async {
    if (!_scrollController.hasClients || _activePages.isEmpty) return;
    final targetIndex = pageIndex.clamp(0, _activePages.length - 1);
    final page = _activePages[targetIndex];
    final pageContext =
        _verticalPageKeys[_verticalPageKey(page)]?.currentContext;

    if (pageContext != null) {
      await Scrollable.ensureVisible(
        pageContext,
        alignment: 0,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final fallbackOffset =
        targetIndex * MediaQuery.sizeOf(context).height * 0.82;
    await _scrollController.animateTo(
      fallbackOffset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  void _goToChapter(ChapterListItem chapter) {
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    _autoNextArmed = false;
    _flushPendingProgress();
    final comic =
        widget.comic ??
        ComicSummary(
          title: widget.comicTitle,
          slug: widget.slug,
          sourceName: widget.sourceName,
        );
    final location =
        '/reader/${Uri.encodeComponent(widget.sourceName)}/${Uri.encodeComponent(widget.slug)}/${formatChapterNumber(chapter.chapterNumber)}';
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.canPop()) {
      router.pushReplacement(location, extra: comic);
    } else {
      router.go(location, extra: comic);
    }
  }

  void _goBack() {
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    _flushPendingProgress();
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() ?? Navigator.of(context).canPop()) {
      if (router != null) {
        router.pop();
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    if (router == null) return;
    final comic = _comicSummary;
    final source = comicRouteSource(comic);
    final slug = comicRouteSlug(comic);
    if (source.trim().isEmpty || slug.trim().isEmpty) {
      router.go('/');
      return;
    }
    router.go(
      '/comic/${Uri.encodeComponent(source)}/${Uri.encodeComponent(slug)}',
      extra: comic,
    );
  }

  bool _canPopRoute() {
    final router = GoRouter.maybeOf(context);
    return router?.canPop() ?? Navigator.of(context).canPop();
  }

  void _openComicDetail() {
    final comic =
        widget.comic ??
        ComicSummary(
          title: widget.comicTitle,
          slug: widget.slug,
          sourceName: widget.sourceName,
        );
    context.push(
      '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
      extra: comic,
    );
  }

  Future<void> _ensureInitialPreload(
    List<_ReaderPageUi> pages,
    ReadingProgress? matchingProgress,
  ) {
    final restoreIndex = matchingProgress == null
        ? null
        : (matchingProgress.pageIndex ??
                      matchingProgress.lastReadPageItemIndex ??
                      0)
                  .clamp(0, math.max(0, pages.length - 1))
              as int;

    // Run the synchronous restoration IMMEDIATELY!
    // This sets up the controller and flags synchronously, allowing the first
    // frame to layout exactly at the saved position and bypass the loading gate.
    if (restoreIndex != null && !_restored) {
      _currentPage.value = restoreIndex;
      if (_pagedMode) {
        _recreatePageControllerAt(restoreIndex);
        _restored = true;
      } else if (!_scrollController.hasClients) {
        _recreateScrollControllerAt(_progressScrollOffset(restoreIndex));
        _schedulePreciseScrollRestoration(restoreIndex);
        _restored = true;
      } else {
        _restoreAttachedVerticalPosition(restoreIndex);
        _restored = true;
      }
    }

    final key =
        '${widget.sourceName}|${widget.slug}|${widget.chapterNumber}|${pages.length}|${restoreIndex ?? 'none'}';
    if (_initialPreloadKey == key && _initialPreloadFuture != null) {
      return _initialPreloadFuture!;
    }
    _initialPreloadKey = key;
    _initialPreloadFuture = _prepareInitialReaderAfterFirstFrame(
      pages,
      restoreIndex,
    );
    return _initialPreloadFuture!;
  }

  Future<void> _prepareInitialReaderAfterFirstFrame(
    List<_ReaderPageUi> pages,
    int? restoreIndex,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _prepareInitialReader(pages, restoreIndex);
  }

  /// Synchronously prepares the scroll controller for the restore position,
  /// then preloads images centred around [restoreIndex] (or from the start).
  Future<void> _prepareInitialReader(
    List<_ReaderPageUi> pages,
    int? restoreIndex,
  ) async {
    // ── Synchronous part (runs before the first await) ──────────────────────
    if (restoreIndex != null &&
        !_restored &&
        !_pagedMode &&
        !_scrollController.hasClients) {
      _currentPage.value = restoreIndex;
      _recreateScrollControllerAt(_progressScrollOffset(restoreIndex));
      _schedulePreciseScrollRestoration(restoreIndex);
      _restored = true; // _restorePosition will be a no-op
    }

    // ── Async part: preload images around the restore (or start) ─────────────
    final center = restoreIndex ?? 0;
    final start = math.max(0, center - 2);
    final end = math.min(pages.length - 1, center + 3);
    await _preloadIndexes(
      Iterable<int>.generate(end - start + 1, (i) => start + i),
      timeout: const Duration(seconds: 6),
      ignoreRecentRequests: true,
    );
  }

  /// Estimates the scroll offset for a given page index using the known
  /// aspect ratios of already-loaded images, falling back to a viewport ratio.
  double _progressScrollOffset(int pageIndex) {
    if (_activePages.isEmpty) return 0;
    var offset = 0.0;
    final width = MediaQuery.sizeOf(context).width;
    for (var i = 0; i < pageIndex && i < _activePages.length; i++) {
      final ar = _readerPageAspectRatio(_activePages[i]);
      offset += ar > 0 ? width / ar : MediaQuery.sizeOf(context).height * 0.82;
    }
    return offset;
  }

  Future<void> _preloadFromCurrentPosition() {
    if (_activePages.isEmpty) return Future<void>.value();
    final current = _currentPage.value.clamp(0, _activePages.length - 1);
    final indexes = <int>[current];
    for (var distance = 1; distance <= 3; distance++) {
      final next = current + distance;
      final previous = current - distance;
      if (next < _activePages.length) indexes.add(next);
      if (previous >= 0) indexes.add(previous);
    }
    return _preloadIndexes(indexes);
  }

  Future<void> _preloadIndexes(
    Iterable<int> indexes, {
    Duration? timeout,
    bool ignoreRecentRequests = false,
  }) async {
    if (!mounted) return;
    final now = DateTime.now();
    _recentPrefetchRequests.removeWhere(
      (_, requestedAt) =>
          now.difference(requestedAt) > _imagePrefetchHistoryLifetime,
    );
    final futures = <Future<void>>[];
    for (final index in indexes) {
      if (index < 0 || index >= _activePages.length) continue;
      final imageUrl = _activePages[index].imageUrl;
      final lastRequested = _recentPrefetchRequests[imageUrl];
      if (!ignoreRecentRequests &&
          lastRequested != null &&
          now.difference(lastRequested) < _imagePrefetchCooldown) {
        continue;
      }
      _recentPrefetchRequests[imageUrl] = now;
      final filePath = _localFilePath(imageUrl);
      final ImageProvider provider = filePath == null
          ? CachedNetworkImageProvider(
              imageUrl,
              cacheManager: ReaderImageCacheManager.instance,
            )
          : FileImage(File(filePath));
      futures.add(_precacheReaderImageProvider(provider, imageUrl));
    }
    if (futures.isEmpty) return;

    final future = Future.wait(futures);
    if (timeout == null) {
      await future;
      return;
    }
    final timeoutCompleter = Completer<void>();
    _initialPreloadTimeoutTimer?.cancel();
    _initialPreloadTimeoutTimer = Timer(timeout, () {
      if (!timeoutCompleter.isCompleted) {
        timeoutCompleter.complete();
      }
    });
    await Future.any<void>([future.then((_) {}), timeoutCompleter.future]);
    _initialPreloadTimeoutTimer?.cancel();
    _initialPreloadTimeoutTimer = null;
  }

  Future<void> _precacheReaderImageProvider(
    ImageProvider provider,
    String imageUrl,
  ) async {
    if (!mounted) return;

    final imageConfig = createLocalImageConfiguration(context);
    final stream = provider.resolve(imageConfig);
    final ratioCompleter = Completer<void>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        _rememberReaderImageAspectRatio(imageUrl, info);
        if (!ratioCompleter.isCompleted) {
          ratioCompleter.complete();
        }
      },
      onError: (_, _) {
        if (!ratioCompleter.isCompleted) {
          ratioCompleter.complete();
        }
      },
    );
    stream.addListener(listener);

    try {
      await Future.wait<void>([
        precacheImage(
          provider,
          context,
        ).timeout(const Duration(seconds: 10)).catchError((_) {}),
        ratioCompleter.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        ),
      ]);
    } finally {
      stream.removeListener(listener);
    }
  }

  void _ensureNearbyReadinessWatcher(List<ChapterListItem>? chapters) {
    if (!mounted || _nearbyWatcherStarted || chapters == null) return;

    final nearby = _nearbyChapters(chapters).toList();
    if (nearby.isEmpty || nearby.every((chapter) => chapter.totalImages > 0)) {
      return;
    }

    _nearbyWatcherStarted = true;
    _syncNearbyBaseline(nearby);

    _nearbyReadyTimer?.cancel();
    _nearbyReadyTimer = Timer.periodic(_nearbyStatusPollInterval, (timer) {
      _nearbyReadyPolls += 1;
      if (_nearbyReadyPolls > _nearbyStatusMaxPolls || !mounted) {
        timer.cancel();
        return;
      }
      unawaited(_pollNearbyReadiness());
    });
  }

  void _syncNearbyBaseline(List<ChapterListItem> chapters) {
    for (final chapter in chapters) {
      _knownNearbyPageCounts[chapter.chapterNumber] = chapter.totalImages;
    }
  }

  Future<void> _pollNearbyReadiness() async {
    try {
      final chapters = await ref
          .read(catalogRepositoryProvider)
          .getChapters(widget.sourceName, widget.slug);
      final newlyReady = <ChapterListItem>[];

      for (final chapter in _nearbyChapters(chapters)) {
        final oldCount = _knownNearbyPageCounts[chapter.chapterNumber];
        _knownNearbyPageCounts[chapter.chapterNumber] = chapter.totalImages;
        if (oldCount != null &&
            oldCount <= 0 &&
            chapter.totalImages > 0 &&
            _announcedNearbyReadyChapters.add(chapter.chapterNumber)) {
          newlyReady.add(chapter);
        }
      }

      if (newlyReady.isNotEmpty && mounted) {
        ref.invalidate(chaptersProvider(_comicRequest));
        _showNearbyReadyNotice(newlyReady);
      }

      final stillPending = _nearbyChapters(
        chapters,
      ).any((chapter) => chapter.totalImages <= 0);
      if (!stillPending) {
        _nearbyReadyTimer?.cancel();
      }
    } catch (_) {
      // Keep this watcher quiet; reader UX should not be interrupted by polling.
    }
  }

  Iterable<ChapterListItem> _nearbyChapters(List<ChapterListItem> chapters) {
    final lower = widget.chapterNumber - _nearbyChapterWindow;
    final upper = widget.chapterNumber + _nearbyChapterWindow;
    return chapters.where((chapter) {
      return chapter.chapterNumber >= lower &&
          chapter.chapterNumber <= upper &&
          chapter.chapterNumber != widget.chapterNumber;
    });
  }

  void _showNearbyReadyNotice(List<ChapterListItem> chapters) {
    final sorted = [...chapters]
      ..sort(
        (a, b) => (a.chapterNumber - widget.chapterNumber).abs().compareTo(
          (b.chapterNumber - widget.chapterNumber).abs(),
        ),
      );
    final shown = sorted
        .take(3)
        .map((chapter) => 'Ch ${formatChapterNumber(chapter.chapterNumber)}');
    final extra = sorted.length - shown.length;
    final message = extra > 0
        ? '${shown.join(', ')} +$extra siap dibaca'
        : '${shown.join(', ')} siap dibaca';

    _nearbyReadyNoticeTimer?.cancel();
    setState(() => _nearbyReadyNoticeMessage = message);
    _nearbyReadyNoticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _nearbyReadyNoticeMessage == message) {
        setState(() => _nearbyReadyNoticeMessage = null);
      }
    });
  }
}

class _VerticalPagePosition {
  const _VerticalPagePosition({
    required this.index,
    required this.page,
    required this.bottom,
    required this.viewportHeight,
  });

  final int index;
  final _ReaderPageUi page;
  final double bottom;
  final double viewportHeight;
}

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

class _ReaderBottomViewportFade extends StatelessWidget {
  const _ReaderBottomViewportFade();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 220,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: List.generate(9, (index) {
                final p = index / 8;
                return Colors.black.withValues(
                  alpha: math.pow(p, 1.5).toDouble(),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

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

double _dynamicReaderCacheExtent(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  final multiplier = height < 700
      ? 4.0
      : height < 1000
      ? 3.25
      : 2.75;
  return height * multiplier;
}

class _PagedReader extends StatelessWidget {
  const _PagedReader({
    required this.controller,
    required this.pages,
    required this.reverse,
    required this.onPageChanged,
    required this.onDownloadPage,
    required this.actionsVisible,
  });

  final PageController controller;
  final List<_ReaderPageUi> pages;
  final bool reverse;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_ReaderPageUi> onDownloadPage;
  final bool actionsVisible;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      reverse: reverse,
      onPageChanged: onPageChanged,
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        return Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              MediaQuery.paddingOf(context).top + 74,
              0,
              MediaQuery.paddingOf(context).bottom + 104,
            ),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 3.5,
              child: _ReaderPage(
                page: page,
                paged: true,
                actionsVisible: actionsVisible,
                onDownload: () => onDownloadPage(page),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _standardWebtoonAspectRatio = 0.68;
const _minReliableReaderImageAspectRatio = 0.25;
const _maxReliableReaderImageAspectRatio = 2.5;
const _minFallbackWebtoonAspectRatio = 0.45;
const _maxFallbackWebtoonAspectRatio = 0.9;

final Map<String, double> _knownReaderImageAspectRatios = <String, double>{};

void _rememberReaderImageAspectRatio(String url, ImageInfo info) {
  final width = info.image.width.toDouble();
  final height = info.image.height.toDouble();
  if (width <= 0 || height <= 0) return;
  final aspectRatio = width / height;
  if (!aspectRatio.isFinite ||
      aspectRatio < _minReliableReaderImageAspectRatio ||
      aspectRatio > _maxReliableReaderImageAspectRatio) {
    return;
  }
  _knownReaderImageAspectRatios[url] = aspectRatio;
}

double _readerPageAspectRatio(_ReaderPageUi page) {
  final known = _knownReaderImageAspectRatios[page.imageUrl];
  if (known != null && known > 0) return known;
  return _dynamicReaderFallbackAspectRatio(page.aspectRatio);
}

double _dynamicReaderFallbackAspectRatio(double seedAspectRatio) {
  final knownRatios =
      _knownReaderImageAspectRatios.values
          .where(
            (ratio) =>
                ratio.isFinite &&
                ratio >= _minReliableReaderImageAspectRatio &&
                ratio <= _maxReliableReaderImageAspectRatio,
          )
          .toList()
        ..sort();
  if (knownRatios.isEmpty) {
    final seed = seedAspectRatio > 0
        ? seedAspectRatio
        : _standardWebtoonAspectRatio;
    return seed.clamp(
      _minFallbackWebtoonAspectRatio,
      _maxFallbackWebtoonAspectRatio,
    );
  }

  final middle = knownRatios.length ~/ 2;
  final median = knownRatios.length.isOdd
      ? knownRatios[middle]
      : (knownRatios[middle - 1] + knownRatios[middle]) / 2;
  return median.clamp(
    _minFallbackWebtoonAspectRatio,
    _maxFallbackWebtoonAspectRatio,
  );
}

double _readerPageHeightForWidth(BuildContext context, double aspectRatio) {
  final width = MediaQuery.sizeOf(context).width;
  final ratio = aspectRatio > 0 && aspectRatio.isFinite
      ? aspectRatio
      : _standardWebtoonAspectRatio;
  return width / ratio;
}

class _ReaderPage extends StatefulWidget {
  const _ReaderPage({
    required this.page,
    required this.onDownload,
    required this.actionsVisible,
    this.paged = false,
  });

  final _ReaderPageUi page;
  final VoidCallback onDownload;
  final bool actionsVisible;
  final bool paged;

  @override
  State<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<_ReaderPage> {
  var _retrySerial = 0;
  bool _retrying = false;
  String? _aspectRatioResolveUrl;
  ImageStream? _aspectRatioStream;
  ImageStreamListener? _aspectRatioListener;

  @override
  void dispose() {
    _removeAspectRatioListener();
    super.dispose();
  }

  Future<void> _retryImage(String url) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      if (_localFilePath(url) == null) {
        await ReaderImageCacheManager.instance.removeFile(url);
      }
    } finally {
      if (mounted) {
        setState(() {
          _retrySerial += 1;
          _retrying = false;
        });
      }
    }
  }

  void _rememberImageAspectRatio(ImageProvider provider, String url) {
    if (_knownReaderImageAspectRatios.containsKey(url) ||
        _aspectRatioResolveUrl == url) {
      return;
    }

    _removeAspectRatioListener();
    _aspectRatioResolveUrl = url;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      _rememberReaderImageAspectRatio(url, info);
      if (mounted && widget.page.imageUrl == url) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      _removeAspectRatioListener();
    }, onError: (_, _) => _removeAspectRatioListener());
    _aspectRatioStream = stream;
    _aspectRatioListener = listener;
    stream.addListener(listener);
  }

  void _removeAspectRatioListener() {
    final stream = _aspectRatioStream;
    final listener = _aspectRatioListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _aspectRatioStream = null;
    _aspectRatioListener = null;
    _aspectRatioResolveUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageUrl = widget.page.imageUrl;
    final filePath = _localFilePath(imageUrl);
    final aspectRatio = _readerPageAspectRatio(widget.page);
    final reservedHeight = widget.paged
        ? double.infinity
        : _readerPageHeightForWidth(context, aspectRatio);
    final decoration = widget.paged
        ? BoxDecoration(
            color: widget.page.background,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: isDark ? 18 : 12,
                offset: Offset(0, isDark ? 10 : 6),
              ),
            ],
          )
        : BoxDecoration(color: widget.page.background);
    final fit = widget.paged ? BoxFit.contain : BoxFit.fitWidth;
    final image = filePath == null
        ? CachedNetworkImage(
            key: ValueKey('$imageUrl|$_retrySerial'),
            imageUrl: imageUrl,
            cacheManager: ReaderImageCacheManager.instance,
            width: double.infinity,
            fit: fit,
            imageBuilder: (context, imageProvider) {
              _rememberImageAspectRatio(imageProvider, imageUrl);
              return Image(
                image: imageProvider,
                width: double.infinity,
                fit: fit,
              );
            },
            placeholder: (context, url) =>
                _ReaderPageReservedSpace(height: reservedHeight),
            errorWidget: (context, url, error) => _ReaderPageError(
              pageNumber: widget.page.number,
              paged: widget.paged,
              reservedHeight: reservedHeight,
              retrying: _retrying,
              onRetry: () => _retryImage(url),
            ),
          )
        : _localReaderImage(
            filePath: filePath,
            imageUrl: imageUrl,
            fit: fit,
            reservedHeight: reservedHeight,
          );

    if (widget.paged) {
      return DecoratedBox(
        decoration: decoration,
        child: AspectRatio(
          aspectRatio: widget.page.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _ReaderPageStack(
              image: image,
              actionsVisible: widget.actionsVisible,
              onDownload: widget.onDownload,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: _ReaderPageStack(
        image: image,
        actionsVisible: widget.actionsVisible,
        onDownload: widget.onDownload,
      ),
    );
  }

  Widget _localReaderImage({
    required String filePath,
    required String imageUrl,
    required BoxFit fit,
    required double reservedHeight,
  }) {
    final provider = FileImage(File(filePath));
    _rememberImageAspectRatio(provider, imageUrl);
    return Image(
      image: provider,
      key: ValueKey('$filePath|$_retrySerial'),
      width: double.infinity,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _ReaderPageError(
        pageNumber: widget.page.number,
        paged: widget.paged,
        reservedHeight: reservedHeight,
        retrying: _retrying,
        onRetry: () => _retryImage(imageUrl),
      ),
    );
  }
}

class _ReaderPageError extends StatelessWidget {
  const _ReaderPageError({
    required this.pageNumber,
    required this.paged,
    required this.reservedHeight,
    required this.retrying,
    required this.onRetry,
  });

  final int pageNumber;
  final bool paged;
  final double reservedHeight;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: paged ? double.infinity : reservedHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: retrying ? null : onRetry,
              icon: retrying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text('Retry page $pageNumber'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderPageStack extends StatelessWidget {
  const _ReaderPageStack({
    required this.image,
    required this.actionsVisible,
    required this.onDownload,
  });

  final Widget image;
  final bool actionsVisible;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        image,
        Positioned(
          top: 12,
          right: 12,
          child: _PageDownloadButton(
            visible: actionsVisible,
            onPressed: onDownload,
          ),
        ),
      ],
    );
  }
}

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
    final hasCover = coverUrl != null && coverUrl.isNotEmpty;

    return Stack(
      children: [
        // Blurred Cover Background
        Positioned.fill(
          child: hasCover
              ? ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        const SizedBox.shrink(),
                  ),
                )
              : Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F172A), Color(0xFF020617)],
                    ),
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
                    if (hasCover)
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.white.withValues(alpha: 0.05),
                              child: const Center(
                                child: Icon(
                                  Icons.book_outlined,
                                  color: Colors.white54,
                                  size: 32,
                                ),
                              ),
                            ),
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

class _ReaderPageReservedSpace extends StatelessWidget {
  const _ReaderPageReservedSpace({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity, height: height);
  }
}

class _PageDownloadButton extends StatelessWidget {
  const _PageDownloadButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.86,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.black.withValues(alpha: 0.62),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Unduh page ke Scene',
              onPressed: onPressed,
              icon: const Icon(TonztoonIcons.download),
              color: Colors.white,
              iconSize: 18,
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayColor = colorScheme.surface.withValues(
      alpha: isDark ? 0.88 : 0.94,
    );
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayColor = colorScheme.surface.withValues(
      alpha: isDark ? 0.9 : 0.96,
    );
    final foreground = colorScheme.onSurface;
    final outline = colorScheme.outlineVariant;

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
                        IconButton.filledTonal(
                          tooltip: 'Halaman sebelumnya',
                          onPressed: onPrevious,
                          icon: const Icon(TonztoonIcons.chevronLeft),
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
                        IconButton.filledTonal(
                          tooltip: 'Halaman berikutnya',
                          onPressed: onNext,
                          icon: const Icon(TonztoonIcons.chevronRight),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onPreviousChapter,
                            icon: const Icon(TonztoonIcons.skipBack),
                            label: const Text(
                              'Ch sebelumnya',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: foreground,
                              side: BorderSide(color: outline),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onNextChapter,
                            icon: const Icon(TonztoonIcons.skipForward),
                            label: const Text(
                              'Ch berikutnya',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: foreground,
                              side: BorderSide(color: outline),
                            ),
                          ),
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

class _BingeModeIndicator extends StatelessWidget {
  const _BingeModeIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.82),
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

class _ReaderPageUi {
  const _ReaderPageUi({
    required this.number,
    required this.pageIndexInChapter,
    required this.totalPagesInChapter,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.aspectRatio,
    required this.background,
    required this.imageUrl,
  });

  final int number;
  final int pageIndexInChapter;
  final int totalPagesInChapter;
  final double chapterNumber;
  final String chapterTitle;
  final double aspectRatio;
  final Color background;
  final String imageUrl;
}

String _verticalPageKey(_ReaderPageUi page) {
  return '${page.chapterNumber}|${page.pageIndexInChapter}|${page.imageUrl}';
}

List<_ReaderPageUi> _pagesFromChapter(
  ChapterPayload payload, {
  required String chapterTitle,
  required double fallbackChapterNumber,
}) {
  final images = payload.images.where((image) => image.url.isNotEmpty).toList();
  if (images.isEmpty) return const [];
  return images
      .asMap()
      .entries
      .map(
        (entry) => _ReaderPageUi(
          number: entry.value.page <= 0 ? entry.key + 1 : entry.value.page,
          pageIndexInChapter: entry.key,
          totalPagesInChapter: images.length,
          chapterNumber: payload.chapterNumber > 0
              ? payload.chapterNumber
              : fallbackChapterNumber,
          chapterTitle: chapterTitle,
          aspectRatio: 0.68,
          background: Colors.black,
          imageUrl: entry.value.url,
        ),
      )
      .toList();
}

String _chapterTitleFor(ChapterListItem chapter) {
  final title = chapter.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return 'Chapter ${formatChapterNumber(chapter.chapterNumber)}';
}

String? _localFilePath(String imageUrl) {
  final uri = Uri.tryParse(imageUrl);
  if (uri == null || uri.scheme != 'file') return null;
  return uri.toFilePath();
}

class _ReaderErrorView extends StatelessWidget {
  const _ReaderErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 42, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
