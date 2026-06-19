part of '../reader_screen.dart';

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  static const _nearbyChapterWindow = 5.0;
  static const _komikuAsiaNearbyChapterWindow = 2.0;
  static const _nearbyStatusPollInterval = Duration(seconds: 4);
  static const _komikuAsiaNearbyStatusPollInterval = Duration(seconds: 8);
  static const _nearbyStatusMaxPolls = 20;
  static const _komikuAsiaNearbyStatusMaxPolls = 8;
  static const _progressSaveDelay = Duration(milliseconds: 500);
  static const _imagePrefetchCooldown = Duration(seconds: 20);
  static const _imagePrefetchHistoryLifetime = Duration(seconds: 60);
  static const _chapterReadyRetryInterval = Duration(seconds: 5);
  static const _komikuAsiaChapterReadyRetryBaseInterval = Duration(seconds: 8);
  static const _komikuAsiaChapterReadyRetryMaxInterval = Duration(seconds: 30);

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
  Timer? _autoScrollTimer;
  Timer? _chapterReadyRetryTimer;
  DateTime? _lastAutoScrollTick;
  int _nearbyReadyPolls = 0;
  int _chapterReadyRetryAttempts = 0;
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
  bool _autoScrollRunning = false;
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
    _autoScrollTimer?.cancel();
    _chapterReadyRetryTimer?.cancel();
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
      _chapterReadyRetryAttempts = 0;
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
      _stopAutoScroll();
      _chapterReadyRetryTimer?.cancel();
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
    if (userScrolling && _autoScrollRunning) {
      _stopAutoScroll();
    }
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
      _completeChapterWhenCrossingBoundary(
        fromPageIndex: _currentPage.value,
        toPageIndex: nextPage,
        readerPrefs: _latestReaderPrefs,
      );
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
    final nextPagedMode = !_pagedMode;
    if (nextPagedMode) {
      _stopAutoScroll();
    }
    setState(() {
      _pagedMode = nextPagedMode;
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

  void _playAutoScroll(ReaderPreferences? readerPrefs) {
    if (_pagedMode || readerPrefs?.autoScrollEnabled != true) return;
    _startAutoScroll();
  }

  void _pauseAutoScroll() {
    _stopAutoScroll();
  }

  void _startAutoScroll() {
    if (!_scrollController.hasClients || _activePages.isEmpty) return;
    _autoScrollTimer?.cancel();
    _lastAutoScrollTick = DateTime.now();
    setState(() => _autoScrollRunning = true);
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _pagedMode ||
          _latestReaderPrefs?.autoScrollEnabled != true) {
        _stopAutoScroll();
        return;
      }

      final now = DateTime.now();
      final previous = _lastAutoScrollTick ?? now;
      _lastAutoScrollTick = now;
      final elapsedSeconds = now.difference(previous).inMicroseconds / 1000000;
      if (elapsedSeconds <= 0) return;

      const basePixelsPerSecond = 82.0;
      final speed = _autoScrollSpeed(_latestReaderPrefs);
      final position = _scrollController.position;
      final nextOffset = math.min(
        position.maxScrollExtent,
        _scrollController.offset +
            (basePixelsPerSecond * speed * elapsedSeconds),
      );
      if ((nextOffset - _scrollController.offset).abs() < 0.1 ||
          nextOffset >= position.maxScrollExtent) {
        if (_shouldWaitForContinuousAutoScrollChapter()) {
          _ensureContinuousChapterAhead(_currentPage.value, _latestReaderPrefs);
          return;
        }
        _scrollController.jumpTo(position.maxScrollExtent);
        _stopAutoScroll();
        return;
      }
      _scrollController.jumpTo(nextOffset);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _lastAutoScrollTick = null;
    if (_autoScrollRunning && mounted) {
      setState(() => _autoScrollRunning = false);
    } else {
      _autoScrollRunning = false;
    }
  }

  double _autoScrollSpeed(ReaderPreferences? prefs) {
    return (prefs?.autoScrollSpeed ?? 1.0).clamp(0.5, 1.5).toDouble();
  }

  bool _shouldWaitForContinuousAutoScrollChapter() {
    if (!_continuousVerticalEnabled(_latestReaderPrefs) ||
        _activePages.isEmpty) {
      return false;
    }
    final currentIndex = _currentPage.value.clamp(0, _activePages.length - 1);
    final currentChapterNumber = _activePages[currentIndex].chapterNumber;
    final nextChapter = _nextChapter(_latestChapterItems, currentChapterNumber);
    if (nextChapter == null ||
        _continuousUnavailableChapterNumbers.contains(
          nextChapter.chapterNumber,
        )) {
      return false;
    }
    return true;
  }

  Future<void> _showAutoScrollSettings(ReaderPreferences? readerPrefs) async {
    if (readerPrefs == null) return;
    var selectedSpeed = _autoScrollSpeed(readerPrefs);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final savedSpeed = await showModalBottomSheet<double>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor:
          isDark ? Theme.of(context).colorScheme.surfaceContainerLowest : null,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final bottomSafePadding = math.max(
          24.0,
          MediaQuery.viewPaddingOf(context).bottom + 16,
        );
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, bottomSafePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Autoscroll Speed',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Slider(
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
                    value: selectedSpeed,
                    label: selectedSpeed.toStringAsFixed(2),
                    onChanged: (value) {
                      setSheetState(() => selectedSpeed = value);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('0.5'),
                      Text('0.75'),
                      Text('1.0'),
                      Text('1.25'),
                      Text('1.5'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(selectedSpeed),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurface,
                            minimumSize: const Size(48, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text('Later'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (!mounted || savedSpeed == null) return;

    try {
      await ref
          .read(readerPreferencesProvider.notifier)
          .save(readerPrefs.copyWith(autoScrollSpeed: savedSpeed));
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Save autoscroll speed failed',
        fallbackMessage: 'Kecepatan AutoScroll belum dapat disimpan.',
      );
    }
  }

  void _goRelativePage(
    int delta, {
    ReaderPreferences? readerPrefs,
    ChapterListItem? nextChapter,
  }) {
    _stopAutoScroll();
    final current = _currentPage.value;
    final next = (current + delta).clamp(0, _activePages.length - 1);
    _completeChapterWhenCrossingBoundary(
      fromPageIndex: current,
      toPageIndex: next,
      readerPrefs: readerPrefs,
    );
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
          .catchError((Object error, StackTrace stackTrace) {
            if (!mounted) return;
            showAppErrorSnackBar(
              context,
              error: error,
              stackTrace: stackTrace,
              logContext: 'Save favorite scene failed',
              fallbackMessage: 'Scene belum dapat disimpan. Silakan coba lagi.',
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

  void _completeChapterWhenCrossingBoundary({
    required int fromPageIndex,
    required int toPageIndex,
    required ReaderPreferences? readerPrefs,
  }) {
    if (readerPrefs?.markReadOnComplete != true ||
        fromPageIndex < 0 ||
        toPageIndex < 0 ||
        fromPageIndex >= _activePages.length ||
        toPageIndex >= _activePages.length ||
        toPageIndex <= fromPageIndex) {
      return;
    }

    final fromPage = _activePages[fromPageIndex];
    final toPage = _activePages[toPageIndex];
    if (fromPage.chapterNumber == toPage.chapterNumber) return;

    _ReaderPageUi? completionPage;
    for (final page in _activePages) {
      if (page.chapterNumber == fromPage.chapterNumber) {
        completionPage = page;
      }
    }
    if (completionPage == null) return;

    final progress = _buildProgress(
      completionPage,
      readerPrefs: readerPrefs,
      isCompletedOverride: true,
    );
    if (progress == null) return;

    _saveProgressNow(progress, ComicRequest(widget.sourceName, widget.slug));
  }

  void _saveProgressNow(ReadingProgress progress, ComicRequest request) {
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
    final autoScrollAvailable =
        !_pagedMode && readerPrefs?.autoScrollEnabled == true;
    if (_autoScrollRunning && !autoScrollAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stopAutoScroll();
      });
    }
    final statusBarIconBrightness = _overlayVisible
        ? (isDark ? Brightness.light : Brightness.dark)
        : Brightness.light;
    final statusBarBrightness = _overlayVisible
        ? (isDark ? Brightness.dark : Brightness.light)
        : Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: statusBarIconBrightness,
      statusBarBrightness: statusBarBrightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
    final preparingOverlayStyle = SystemUiOverlayStyle(
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
      if (error is ApiException && error.statusCode == 202) {
        _scheduleChapterReadyRetry(request);
        return _buildBackAwareRoute(
          _PreparingReaderScaffold(
            overlayStyle: preparingOverlayStyle,
            backgroundColor: readerBackground,
            comicSummary: _comicSummary,
            chapterTitle: 'Menyiapkan ${widget.chapterTitle}...',
          ),
        );
      }
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
    _chapterReadyRetryTimer?.cancel();
    _chapterReadyRetryAttempts = 0;
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
            autoScrollAvailable: autoScrollAvailable,
            autoScrollRunning: _autoScrollRunning,
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
            onPlayAutoScroll: () => _playAutoScroll(readerPrefs),
            onPauseAutoScroll: _pauseAutoScroll,
            onOpenAutoScrollSettings: () =>
                _showAutoScrollSettings(readerPrefs),
            verticalPageKeyFor: _verticalPageKeyFor,
          );
        },
      ),
    );
  }

  void _scheduleChapterReadyRetry(ChapterRequest request) {
    if (_chapterReadyRetryTimer?.isActive == true) return;
    _chapterReadyRetryAttempts += 1;
    _chapterReadyRetryTimer = Timer(_chapterReadyRetryDelay(), () {
      if (!mounted) return;
      ref.invalidate(chapterProvider(request));
    });
  }

  Duration _chapterReadyRetryDelay() {
    if (!_isKomikuAsiaSource) return _chapterReadyRetryInterval;

    final multiplier = math.min(_chapterReadyRetryAttempts, 4);
    final seconds =
        _komikuAsiaChapterReadyRetryBaseInterval.inSeconds * multiplier;
    return Duration(
      seconds: math.min(
        seconds,
        _komikuAsiaChapterReadyRetryMaxInterval.inSeconds,
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
    _stopAutoScroll();
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
    _stopAutoScroll();
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
    openComicDetail(context, comic);
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
      final ImageProvider<Object> provider = _readerDecodedImageProvider(
        filePath == null
            ? CachedNetworkImageProvider(
                imageUrl,
                cacheManager: ReaderImageCacheManager.instance,
              )
            : FileImage(File(filePath)),
      );
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
    _nearbyReadyTimer = Timer.periodic(_nearbyReadinessPollInterval, (timer) {
      _nearbyReadyPolls += 1;
      if (_nearbyReadyPolls > _nearbyReadinessMaxPolls || !mounted) {
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
    final lower = widget.chapterNumber - _nearbyReadinessWindow;
    final upper = widget.chapterNumber + _nearbyReadinessWindow;
    return chapters.where((chapter) {
      return chapter.chapterNumber >= lower &&
          chapter.chapterNumber <= upper &&
          chapter.chapterNumber != widget.chapterNumber;
    });
  }

  bool get _isKomikuAsiaSource => widget.sourceName == 'komiku_asia';

  double get _nearbyReadinessWindow => _isKomikuAsiaSource
      ? _komikuAsiaNearbyChapterWindow
      : _nearbyChapterWindow;

  Duration get _nearbyReadinessPollInterval => _isKomikuAsiaSource
      ? _komikuAsiaNearbyStatusPollInterval
      : _nearbyStatusPollInterval;

  int get _nearbyReadinessMaxPolls => _isKomikuAsiaSource
      ? _komikuAsiaNearbyStatusMaxPolls
      : _nearbyStatusMaxPolls;

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
