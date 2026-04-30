import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/reader_image_cache.dart';
import '../../models/comic.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.sourceName,
    required this.slug,
    required this.chapterNumber,
  });

  final String sourceName;
  final String slug;
  final double chapterNumber;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  static const _nearbyChapterWindow = 5.0;
  static const _nearbyStatusPollInterval = Duration(seconds: 4);
  static const _nearbyStatusMaxPolls = 8;

  final _scrollController = ScrollController();
  final _pageController = PageController();
  Timer? _saveTimer;
  Timer? _overlayTimer;
  Timer? _prefetchTimer;
  Timer? _nearbyReadyTimer;
  bool _overlayVisible = true;
  bool _restored = false;
  bool _nearbyWatcherStarted = false;
  double _lastOffset = 0;
  int _pagedIndex = 0;
  String? _readingMode;
  int _nearbyReadyPolls = 0;
  String? _initialPreloadKey;
  Future<void>? _initialPreloadFuture;
  final Set<int> _requestedPrefetchIndexes = <int>{};
  final Set<double> _announcedNearbyReadyChapters = <double>{};
  final Map<double, int> _knownNearbyPageCounts = <double, int>{};
  late ProviderContainer _container;

  ComicRequest get _comicRequest =>
      ComicRequest(widget.sourceName, widget.slug);

  ChapterRequest get _chapterRequest =>
      ChapterRequest(widget.sourceName, widget.slug, widget.chapterNumber);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _scheduleOverlayHide();
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterNumber != widget.chapterNumber ||
        oldWidget.sourceName != widget.sourceName ||
        oldWidget.slug != widget.slug) {
      _restored = false;
      _lastOffset = 0;
      _pagedIndex = 0;
      _readingMode = null;
      _initialPreloadKey = null;
      _initialPreloadFuture = null;
      _requestedPrefetchIndexes.clear();
      _nearbyWatcherStarted = false;
      _nearbyReadyPolls = 0;
      _announcedNearbyReadyChapters.clear();
      _knownNearbyPageCounts.clear();
      _nearbyReadyTimer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _overlayTimer?.cancel();
    _prefetchTimer?.cancel();
    _nearbyReadyTimer?.cancel();
    _saveProgress();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = ref.watch(chapterProvider(_chapterRequest));
    final detail = ref.watch(comicDetailProvider(_comicRequest));
    final chapters = ref.watch(chaptersProvider(_comicRequest));
    final progress = ref.watch(progressProvider(_comicRequest));
    final preferences = ref.watch(readerPreferencesProvider).asData?.value;
    _readingMode ??= preferences?.defaultReadingMode ?? 'vertical';

    _restorePosition(progress.asData?.value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNearbyReadinessWatcher(chapters.asData?.value);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: chapter.when(
        loading: () => const _PreparingChapterView(),
        error: (error, stackTrace) => _ReaderErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(chapterProvider(_chapterRequest)),
        ),
        data: (payload) => FutureBuilder<void>(
          future: _ensureInitialPreload(payload),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _PreparingChapterView();
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _prefetchFromCurrentPosition(payload);
            });
            final chapterList = chapters.asData?.value;
            final previousChapter = _relativeChapterTarget(chapterList, 1);
            final nextChapter = _relativeChapterTarget(chapterList, -1);
            final isPaged = _readingMode == 'paged';
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleOverlay,
              child: Stack(
                children: [
                  isPaged
                      ? _PagedReader(
                          controller: _pageController,
                          reverse: preferences?.readingDirection == 'rtl',
                          payload: payload,
                          onPageChanged: (index) {
                            _pagedIndex = index;
                            if (_overlayVisible) {
                              setState(() => _overlayVisible = false);
                            }
                            _saveTimer?.cancel();
                            _saveTimer = Timer(
                              const Duration(milliseconds: 500),
                              _saveProgress,
                            );
                            _prefetchFromCurrentPosition(payload);
                          },
                          onFavorite: _saveFavoriteScene,
                        )
                      : NotificationListener<UserScrollNotification>(
                          onNotification: (_) {
                            if (_overlayVisible) {
                              setState(() => _overlayVisible = false);
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.zero,
                            cacheExtent: MediaQuery.sizeOf(context).height * 3,
                            itemCount: payload.images.length,
                            itemBuilder: (context, index) {
                              final image = payload.images[index];
                              return _ReaderImage(
                                imageUrl: image.url,
                                pageNumber: index + 1,
                                onLongPress: () =>
                                    _saveFavoriteScene(index, image.url),
                              );
                            },
                          ),
                        ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    top: _overlayVisible ? 0 : -96,
                    left: 0,
                    right: 0,
                    child: _ReaderTopBar(
                      title: detail.asData?.value.title ?? 'Chapter',
                      chapterNumber: widget.chapterNumber,
                      onBack: _handleBack,
                      onOpenDetail: _openComicDetail,
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    bottom: _overlayVisible ? 0 : -120,
                    left: 0,
                    right: 0,
                    child: _ReaderBottomBar(
                      currentIndex: _pageIndex(payload.total),
                      total: payload.total,
                      readingMode: _readingMode ?? 'vertical',
                      onToggleMode: _toggleReadingMode,
                      onPrevious: previousChapter == null
                          ? null
                          : () => _goRelativeChapter(chapterList, 1),
                      onNext: nextChapter == null
                          ? null
                          : () => _goRelativeChapter(chapterList, -1),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _onScroll() {
    _lastOffset = _scrollController.offset;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveProgress);
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 160), () {
      final payload = _container
          .read(chapterProvider(_chapterRequest))
          .asData
          ?.value;
      if (payload != null) {
        _prefetchFromCurrentPosition(payload);
      }
    });
  }

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _restorePosition(ReadingProgress? progress) {
    if (_restored || progress == null) return;
    if (progress.chapterNumber != widget.chapterNumber) return;
    final offset = progress.scrollOffset;
    if (progress.readingMode == 'paged') {
      _restored = true;
      final pageIndex =
          progress.pageIndex ?? progress.lastReadPageItemIndex ?? 0;
      _pagedIndex = pageIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(pageIndex);
        }
      });
      return;
    }
    if (offset == null || offset <= 0) {
      _restored = true;
      return;
    }
    _restored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  int _pageIndex(int total) {
    if (total <= 0) return 0;
    if (_readingMode == 'paged') return math.min(total - 1, _pagedIndex);
    return math.min(total - 1, (_lastOffset / 800).floor());
  }

  Future<void> _ensureInitialPreload(ChapterPayload payload) {
    final key =
        '${payload.sourceName}|${payload.chapterNumber}|${payload.images.length}';
    if (_initialPreloadKey == key && _initialPreloadFuture != null) {
      return _initialPreloadFuture!;
    }
    _initialPreloadKey = key;
    _initialPreloadFuture = _preloadIndexes(
      payload,
      Iterable<int>.generate(math.min(3, payload.images.length)),
    );
    return _initialPreloadFuture!;
  }

  void _prefetchFromCurrentPosition(ChapterPayload payload) {
    if (!mounted || payload.images.isEmpty) return;
    final current = _pageIndex(payload.images.length);
    final indexes = <int>[];
    for (var index = current + 1; index <= current + 5; index++) {
      if (index < payload.images.length) {
        indexes.add(index);
      }
    }
    unawaited(_preloadIndexes(payload, indexes));
  }

  Future<void> _preloadIndexes(
    ChapterPayload payload,
    Iterable<int> indexes,
  ) async {
    final providers = <ImageProvider>[];
    for (final index in indexes) {
      if (index < 0 || index >= payload.images.length) continue;
      if (!_requestedPrefetchIndexes.add(index)) continue;
      providers.add(
        CachedNetworkImageProvider(
          payload.images[index].url,
          cacheManager: ReaderImageCacheManager.instance,
        ),
      );
    }
    await Future.wait(
      providers.map(
        (provider) => precacheImage(provider, context).catchError((_) {}),
      ),
    );
  }

  void _ensureNearbyReadinessWatcher(List<ChapterListItem>? chapters) {
    if (!mounted || _nearbyWatcherStarted || chapters == null) return;
    _nearbyWatcherStarted = true;
    _syncNearbyBaseline(chapters);

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
    for (final chapter in _nearbyChapters(chapters)) {
      _knownNearbyPageCounts[chapter.chapterNumber] = chapter.totalImages;
    }
  }

  Future<void> _pollNearbyReadiness() async {
    try {
      final chapters = await _container
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
        _container.invalidate(chaptersProvider(_comicRequest));
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

  Future<void> _saveProgress() async {
    final detail = _container
        .read(comicDetailProvider(_comicRequest))
        .asData
        ?.value;
    final chapter = _container
        .read(chapterProvider(_chapterRequest))
        .asData
        ?.value;
    if (detail == null || chapter == null) return;

    final total = chapter.total == 0 ? chapter.images.length : chapter.total;
    final progress = ReadingProgress.fromReader(
      comic: detail.toSummary(),
      chapterNumber: widget.chapterNumber,
      readingMode: _readingMode ?? 'vertical',
      scrollOffset: _readingMode == 'paged' ? null : _lastOffset,
      pageIndex: _readingMode == 'paged' ? _pagedIndex : null,
      pageItemIndex: _pageIndex(total),
      totalPageItems: total,
      isCompleted: total > 0 && _pageIndex(total) >= total - 1,
    );

    try {
      await _container.read(progressRepositoryProvider).saveProgress(progress);
      _container.invalidate(progressProvider(_comicRequest));
      _container.invalidate(continueReadingProvider);
      _container.invalidate(homeDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _goRelativeChapter(List<ChapterListItem>? chapters, int delta) {
    final target = _relativeChapterTarget(chapters, delta);
    if (target == null) return;
    _saveProgress();
    context.pushReplacement(
      '/reader/${widget.sourceName}/${widget.slug}/${formatChapterNumber(target.chapterNumber)}',
    );
  }

  ChapterListItem? _relativeChapterTarget(
    List<ChapterListItem>? chapters,
    int delta,
  ) {
    if (chapters == null || chapters.isEmpty) return null;
    final currentIndex = chapters.indexWhere(
      (chapter) => chapter.chapterNumber == widget.chapterNumber,
    );
    if (currentIndex < 0) return null;
    final targetIndex = currentIndex + delta;
    if (targetIndex < 0 || targetIndex >= chapters.length) return null;
    return chapters[targetIndex];
  }

  void _handleBack() {
    _saveProgress();
    if (context.canPop()) {
      context.pop();
      return;
    }
    _goToComicDetailFallback();
  }

  void _openComicDetail() {
    _saveProgress();
    context.push('/comic/${widget.sourceName}/${widget.slug}');
  }

  void _goToComicDetailFallback() {
    _saveProgress();
    context.go('/comic/${widget.sourceName}/${widget.slug}');
  }

  void _toggleReadingMode() {
    setState(() {
      _readingMode = _readingMode == 'paged' ? 'vertical' : 'paged';
      _overlayVisible = true;
    });
    _scheduleOverlayHide();
    _saveProgress();
  }

  Future<void> _saveFavoriteScene(int index, String imageUrl) async {
    final detail = _container
        .read(comicDetailProvider(_comicRequest))
        .asData
        ?.value;
    if (detail == null) return;
    try {
      await _container
          .read(libraryRepositoryProvider)
          .saveFavoriteScene(
            comic: detail.toSummary(),
            chapterNumber: widget.chapterNumber,
            pageItemIndex: index,
            imageUrl: imageUrl,
          );
      _container.invalidate(favoriteScenesProvider);
      _container.invalidate(libraryComicStateProvider(detail.toSummary()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Page ${index + 1} saved to favorite scenes.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _PagedReader extends StatelessWidget {
  const _PagedReader({
    required this.controller,
    required this.reverse,
    required this.payload,
    required this.onPageChanged,
    required this.onFavorite,
  });

  final PageController controller;
  final bool reverse;
  final ChapterPayload payload;
  final ValueChanged<int> onPageChanged;
  final void Function(int index, String imageUrl) onFavorite;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      reverse: reverse,
      itemCount: payload.images.length,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final image = payload.images[index];
        return Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: GestureDetector(
              onLongPress: () => onFavorite(index, image.url),
              child: image.url.startsWith('file:')
                  ? Image.file(
                      File.fromUri(Uri.parse(image.url)),
                      fit: BoxFit.contain,
                    )
                  : CachedNetworkImage(
                      imageUrl: image.url,
                      cacheManager: ReaderImageCacheManager.instance,
                      fit: BoxFit.contain,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (context, url) => const _ImageSkeleton(),
                      errorWidget: (context, url, error) => Center(
                        child: FilledButton.icon(
                          onPressed: () {
                            CachedNetworkImage.evictFromCache(
                              image.url,
                              cacheManager: ReaderImageCacheManager.instance,
                            );
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text('Retry page ${index + 1}'),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _ReaderImage extends StatefulWidget {
  const _ReaderImage({
    required this.imageUrl,
    required this.pageNumber,
    required this.onLongPress,
  });

  final String imageUrl;
  final int pageNumber;
  final VoidCallback onLongPress;

  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage> {
  int _retry = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.startsWith('file:')) {
      return GestureDetector(
        onLongPress: widget.onLongPress,
        child: Image.file(
          File.fromUri(Uri.parse(widget.imageUrl)),
          fit: BoxFit.fitWidth,
          width: double.infinity,
        ),
      );
    }

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: CachedNetworkImage(
        key: ValueKey('${widget.imageUrl}#$_retry'),
        imageUrl: widget.imageUrl,
        cacheManager: ReaderImageCacheManager.instance,
        fit: BoxFit.fitWidth,
        width: double.infinity,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => const _ImageSkeleton(),
        errorWidget: (context, url, error) => SizedBox(
          height: 260,
          child: Center(
            child: FilledButton.icon(
              onPressed: () => setState(() => _retry++),
              icon: const Icon(Icons.refresh),
              label: Text('Retry page ${widget.pageNumber}'),
            ),
          ),
        ),
      ),
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderErrorView extends StatelessWidget {
  const _ReaderErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 40),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
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
  const _ImageSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(height: 360, color: const Color(0xFF090A0D));
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.chapterNumber,
    required this.onBack,
    required this.onOpenDetail,
  });

  final String title;
  final double chapterNumber;
  final VoidCallback onBack;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        bottom: false,
        child: ListTile(
          leading: IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onOpenDetail,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          subtitle: Text('Chapter ${formatChapterNumber(chapterNumber)}'),
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.currentIndex,
    required this.total,
    required this.readingMode,
    required this.onToggleMode,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentIndex;
  final int total;
  final String readingMode;
  final VoidCallback onToggleMode;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              if (onPrevious != null)
                IconButton.filledTonal(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous chapter',
                )
              else
                const SizedBox(width: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: total == 0 ? null : (currentIndex + 1) / total,
                    ),
                    const SizedBox(height: 6),
                    Text(total == 0 ? 'Loading' : '${currentIndex + 1}/$total'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: onToggleMode,
                icon: Icon(
                  readingMode == 'paged'
                      ? Icons.view_agenda_outlined
                      : Icons.auto_stories_outlined,
                ),
                tooltip: readingMode == 'paged'
                    ? 'Switch to vertical'
                    : 'Switch to paged',
              ),
              const SizedBox(width: 12),
              if (onNext != null)
                IconButton.filledTonal(
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next chapter',
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}
