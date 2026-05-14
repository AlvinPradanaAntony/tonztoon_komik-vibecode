import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
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
  static const _progressSaveDelay = Duration(milliseconds: 900);

  final _scrollController = ScrollController();
  final _pageController = PageController();
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  final Stopwatch _readingStopwatch = Stopwatch();
  late final ReadingTimeController _readingTimeController;
  List<_ReaderPageUi> _activePages = const [];
  bool _overlayVisible = false;
  bool _pagedMode = false;
  bool _didApplyReaderPreferences = false;
  bool _restored = false;
  bool _nearbyWatcherStarted = false;
  Timer? _imagePrefetchTimer;
  Timer? _initialPreloadTimeoutTimer;
  Timer? _nearbyReadyTimer;
  Timer? _progressSaveTimer;
  int _nearbyReadyPolls = 0;
  String? _initialPreloadKey;
  Future<void>? _initialPreloadFuture;
  ReadingProgress? _pendingProgress;
  ComicRequest? _pendingProgressRequest;
  final Set<int> _requestedPrefetchIndexes = <int>{};
  final Set<double> _announcedNearbyReadyChapters = <double>{};
  final Map<double, int> _knownNearbyPageCounts = <double, int>{};

  ComicRequest get _comicRequest =>
      ComicRequest(widget.sourceName, widget.slug);

  @override
  void initState() {
    super.initState();
    _readingTimeController = ref.read(readingTimeProvider.notifier);
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
    _progressSaveTimer?.cancel();
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
      _nearbyWatcherStarted = false;
      _nearbyReadyPolls = 0;
      _initialPreloadKey = null;
      _initialPreloadFuture = null;
      _requestedPrefetchIndexes.clear();
      _announcedNearbyReadyChapters.clear();
      _knownNearbyPageCounts.clear();
      _imagePrefetchTimer?.cancel();
      _initialPreloadTimeoutTimer?.cancel();
      _nearbyReadyTimer?.cancel();
      _progressSaveTimer?.cancel();
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
    final viewport = MediaQuery.sizeOf(context).height;
    final nextPage = (_scrollController.offset / (viewport * 0.82))
        .floor()
        .clamp(0, _activePages.length - 1);

    if (_currentPage.value != nextPage) {
      _currentPage.value = nextPage;
      _recordProgress(nextPage, scrollOffset: _scrollController.offset);
      _scheduleImagePrefetch();
    } else {
      _recordProgress(
        nextPage,
        scrollOffset: _scrollController.offset,
        trackReadingTime: false,
      );
    }

    if (_overlayVisible &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      setState(() => _overlayVisible = false);
    }
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

  void _goRelativePage(int delta) {
    final next = (_currentPage.value + delta).clamp(0, _activePages.length - 1);
    _currentPage.value = next;
    _recordProgress(next);
    if (_pagedMode && _pageController.hasClients) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        next * MediaQuery.sizeOf(context).height * 0.82,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
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
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text('Page ${page.number} tersimpan ke Scene.'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
          })
          .catchError((Object error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(error.toString()),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
          }),
    );
  }

  void _recordProgress(
    int pageIndex, {
    double? scrollOffset,
    bool trackReadingTime = true,
  }) {
    if (trackReadingTime) {
      _flushReadingTime(restart: true);
    }
    final progress = _buildProgress(pageIndex, scrollOffset: scrollOffset);
    if (progress == null) return;
    _pendingProgress = progress;
    _pendingProgressRequest = ComicRequest(widget.sourceName, widget.slug);
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(_progressSaveDelay, _flushPendingProgress);
  }

  ReadingProgress? _buildProgress(int pageIndex, {double? scrollOffset}) {
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
      chapterNumber: widget.chapterNumber,
      readingMode: _pagedMode ? 'paged' : 'vertical',
      scrollOffset: scrollOffset,
      pageIndex: _pagedMode ? pageIndex : null,
      pageItemIndex: pageIndex,
      totalPageItems: _activePages.length,
      isCompleted: pageIndex >= _activePages.length - 1,
    );
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
          .then((_) {
            if (!mounted) return;
            ref.invalidate(progressProvider(request));
            ref.invalidate(continueReadingProvider);
          })
          .catchError((_) {}),
    );
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pagedMode) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(pageIndex);
        }
        return;
      }
      if (!_scrollController.hasClients) return;
      final targetOffset =
          progress.scrollOffset ??
          pageIndex * MediaQuery.sizeOf(context).height * 0.82;
      _scrollController.jumpTo(
        targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
      );
    });
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
    final previousChapter = _previousChapter(chapterItems);
    final nextChapter = _nextChapter(chapterItems);
    final progress = ref.watch(progressProvider(_comicRequest));
    final savedProgress = progress.asData?.value;
    final matchingProgress =
        savedProgress?.chapterNumber == widget.chapterNumber
        ? savedProgress
        : null;
    if (!_didApplyReaderPreferences &&
        (readerPrefs != null || matchingProgress != null)) {
      _pagedMode =
          matchingProgress?.readingMode == 'paged' ||
          (matchingProgress == null &&
              readerPrefs?.defaultReadingMode == 'paged');
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
      systemNavigationBarColor: readerBackground,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    if (payload == null && chapterAsync.isLoading) {
      return Scaffold(
        backgroundColor: readerBackground,
        body: const _PreparingChapterView(),
      );
    }

    if (payload == null) {
      final error = chapterAsync.whenOrNull(
        error: (error, stackTrace) => error,
      );
      return Scaffold(
        backgroundColor: readerBackground,
        body: _ReaderErrorView(
          message: error?.toString() ?? 'Chapter gagal dimuat.',
          onRetry: () => ref.invalidate(chapterProvider(request)),
        ),
      );
    }
    _activePages = _pagesFromChapter(payload);
    if (_activePages.isEmpty) {
      return Scaffold(
        backgroundColor: readerBackground,
        body: _ReaderErrorView(
          message: 'Chapter ini belum memiliki gambar.',
          onRetry: () => ref.invalidate(chapterProvider(request)),
        ),
      );
    }

    return FutureBuilder<void>(
      future: _ensureInitialPreload(_activePages),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: readerBackground,
            body: const _PreparingChapterView(),
          );
        }

        _restorePosition(matchingProgress);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleImagePrefetch();
          _ensureNearbyReadinessWatcher(chapters.asData?.value);
        });

        return _ReadyReaderScaffold(
          overlayStyle: overlayStyle,
          readerBackground: readerBackground,
          pagedMode: _pagedMode,
          pageController: _pageController,
          scrollController: _scrollController,
          activePages: _activePages,
          readerPrefs: readerPrefs,
          overlayVisible: _overlayVisible,
          currentPage: _currentPage,
          comicTitle: widget.comicTitle,
          chapterTitle: widget.chapterTitle,
          onToggleOverlay: _toggleOverlay,
          onBack: () => context.pop(),
          onOpenComicDetail: _openComicDetail,
          onDownloadPage: _downloadPage,
          onPageChanged: (index) {
            _currentPage.value = index;
            _recordProgress(index);
            _scheduleImagePrefetch();
            if (_overlayVisible) {
              setState(() => _overlayVisible = false);
            }
          },
          onPrevious: () => _goRelativePage(-1),
          onNext: () => _goRelativePage(1),
          onPreviousChapter: previousChapter == null
              ? null
              : () => _goToChapter(previousChapter),
          onNextChapter: nextChapter == null
              ? null
              : () => _goToChapter(nextChapter),
          onToggleMode: _toggleMode,
        );
      },
    );
  }

  ChapterListItem? _previousChapter(List<ChapterListItem>? chapters) {
    return _relativeChapter(
      chapters,
      (number) => number < widget.chapterNumber,
    );
  }

  ChapterListItem? _nextChapter(List<ChapterListItem>? chapters) {
    return _relativeChapter(
      chapters,
      (number) => number > widget.chapterNumber,
    );
  }

  ChapterListItem? _relativeChapter(
    List<ChapterListItem>? chapters,
    bool Function(double chapterNumber) keep,
  ) {
    if (chapters == null || chapters.isEmpty) return null;
    final candidates =
        chapters.where((chapter) => keep(chapter.chapterNumber)).toList()..sort(
          (a, b) => (a.chapterNumber - widget.chapterNumber).abs().compareTo(
            (b.chapterNumber - widget.chapterNumber).abs(),
          ),
        );
    return candidates.firstOrNull;
  }

  void _goToChapter(ChapterListItem chapter) {
    _flushPendingProgress();
    final comic =
        widget.comic ??
        ComicSummary(
          title: widget.comicTitle,
          slug: widget.slug,
          sourceName: widget.sourceName,
        );
    context.go(
      '/reader/${Uri.encodeComponent(widget.sourceName)}/${Uri.encodeComponent(widget.slug)}/${formatChapterNumber(chapter.chapterNumber)}',
      extra: comic,
    );
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

  Future<void> _ensureInitialPreload(List<_ReaderPageUi> pages) {
    final key =
        '${widget.sourceName}|${widget.slug}|${widget.chapterNumber}|${pages.length}';
    if (_initialPreloadKey == key && _initialPreloadFuture != null) {
      return _initialPreloadFuture!;
    }
    _initialPreloadKey = key;
    _initialPreloadFuture = _preloadIndexes(
      Iterable<int>.generate(math.min(3, pages.length)),
      timeout: const Duration(seconds: 6),
    );
    return _initialPreloadFuture!;
  }

  Future<void> _preloadFromCurrentPosition() {
    if (_activePages.isEmpty) return Future<void>.value();
    final current = _currentPage.value.clamp(0, _activePages.length - 1);
    final indexes = <int>[];
    for (var index = current + 1; index <= current + 3; index++) {
      if (index < _activePages.length) {
        indexes.add(index);
      }
    }
    return _preloadIndexes(indexes);
  }

  Future<void> _preloadIndexes(
    Iterable<int> indexes, {
    Duration? timeout,
  }) async {
    if (!mounted) return;
    final providers = <ImageProvider>[];
    for (final index in indexes) {
      if (index < 0 || index >= _activePages.length) continue;
      if (!_requestedPrefetchIndexes.add(index)) continue;
      final imageUrl = _activePages[index].imageUrl;
      final filePath = _localFilePath(imageUrl);
      providers.add(
        filePath == null
            ? CachedNetworkImageProvider(
                imageUrl,
                cacheManager: ReaderImageCacheManager.instance,
              )
            : FileImage(File(filePath)),
      );
    }
    if (providers.isEmpty) return;

    final future = Future.wait(
      providers.map(
        (provider) => precacheImage(provider, context).catchError((_) {}),
      ),
    );
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
        _showNearbyReadyToast(newlyReady);
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

  void _showNearbyReadyToast(List<ChapterListItem> chapters) {
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

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

class _ReadyReaderScaffold extends StatelessWidget {
  const _ReadyReaderScaffold({
    required this.overlayStyle,
    required this.readerBackground,
    required this.pagedMode,
    required this.pageController,
    required this.scrollController,
    required this.activePages,
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
  });

  final SystemUiOverlayStyle overlayStyle;
  final Color readerBackground;
  final bool pagedMode;
  final PageController pageController;
  final ScrollController scrollController;
  final List<_ReaderPageUi> activePages;
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

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
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
                        onDownloadPage: onDownloadPage,
                        actionsVisible: overlayVisible,
                      ),
              ),
              _ReaderTopBar(
                visible: overlayVisible,
                comicTitle: comicTitle,
                chapterTitle: chapterTitle,
                onBack: onBack,
                onOpenComicDetail: onOpenComicDetail,
              ),
              _ReaderBottomBar(
                visible: overlayVisible,
                pagedMode: pagedMode,
                currentPage: currentPage,
                totalPages: activePages.length,
                onPrevious: onPrevious,
                onNext: onNext,
                onPreviousChapter: onPreviousChapter,
                onNextChapter: onNextChapter,
                onToggleMode: onToggleMode,
              ),
            ],
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
    required this.onDownloadPage,
    required this.actionsVisible,
  });

  final ScrollController controller;
  final List<_ReaderPageUi> pages;
  final ValueChanged<_ReaderPageUi> onDownloadPage;
  final bool actionsVisible;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      cacheExtent: _dynamicReaderCacheExtent(context),
      itemBuilder: (context, index) {
        final page = pages[index];
        return _ReaderPage(
          page: page,
          actionsVisible: actionsVisible,
          onDownload: () => onDownloadPage(page),
        );
      },
      itemCount: pages.length,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageUrl = widget.page.imageUrl;
    final filePath = _localFilePath(imageUrl);
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
            placeholder: (context, url) =>
                _ImageSkeleton(height: widget.paged ? double.infinity : 360),
            errorWidget: (context, url, error) => _ReaderPageError(
              pageNumber: widget.page.number,
              paged: widget.paged,
              retrying: _retrying,
              onRetry: () => _retryImage(url),
            ),
          )
        : Image.file(
            File(filePath),
            key: ValueKey('$filePath|$_retrySerial'),
            width: double.infinity,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => _ReaderPageError(
              pageNumber: widget.page.number,
              paged: widget.paged,
              retrying: _retrying,
              onRetry: () => _retryImage(imageUrl),
            ),
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
}

class _ReaderPageError extends StatelessWidget {
  const _ReaderPageError({
    required this.pageNumber,
    required this.paged,
    required this.retrying,
    required this.onRetry,
  });

  final int pageNumber;
  final bool paged;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: paged ? double.infinity : 260,
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
  const _PreparingChapterView();

  @override
  State<_PreparingChapterView> createState() => _PreparingChapterViewState();
}

class _PreparingChapterViewState extends State<_PreparingChapterView> {
  bool _showMessage = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _showMessage = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: AnimatedOpacity(
            opacity: _showMessage ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
                const SizedBox(height: 16),
                Text(
                  'Preparing chapter...',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF090A0D)),
      child: SizedBox(width: double.infinity, height: height),
    );
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
    required this.comicTitle,
    required this.chapterTitle,
    required this.onBack,
    required this.onOpenComicDetail,
  });

  final bool visible;
  final String comicTitle;
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onOpenComicDetail;

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
                const SizedBox(width: 54),
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
    required this.pagedMode,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onToggleMode,
  });

  final bool visible;
  final bool pagedMode;
  final ValueListenable<int> currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onToggleMode;

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
      bottom: visible ? 0 : -186,
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onToggleMode,
                            icon: Icon(
                              pagedMode
                                  ? TonztoonIcons.rows
                                  : TonztoonIcons.columns,
                            ),
                            label: Text(
                              pagedMode ? 'Vertical' : 'Paged',
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

class _ReaderPageUi {
  const _ReaderPageUi({
    required this.number,
    required this.aspectRatio,
    required this.background,
    required this.imageUrl,
  });

  final int number;
  final double aspectRatio;
  final Color background;
  final String imageUrl;
}

List<_ReaderPageUi> _pagesFromChapter(ChapterPayload payload) {
  final images = payload.images.where((image) => image.url.isNotEmpty).toList();
  if (images.isEmpty) return const [];
  return images
      .map(
        (image) => _ReaderPageUi(
          number: image.page <= 0 ? images.indexOf(image) + 1 : image.page,
          aspectRatio: 0.68,
          background: Colors.black,
          imageUrl: image.url,
        ),
      )
      .toList();
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
