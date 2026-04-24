import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comic.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';

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
  final _scrollController = ScrollController();
  Timer? _saveTimer;
  Timer? _overlayTimer;
  bool _overlayVisible = true;
  bool _restored = false;
  double _lastOffset = 0;

  ComicRequest get _comicRequest =>
      ComicRequest(widget.sourceName, widget.slug);

  ChapterRequest get _chapterRequest =>
      ChapterRequest(widget.sourceName, widget.slug, widget.chapterNumber);

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
    _saveProgress();
    _scrollController.dispose();
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

    _restorePosition(progress.asData?.value);

    return Scaffold(
      backgroundColor: Colors.black,
      body: AppAsyncView(
        value: chapter,
        onRetry: () => ref.invalidate(chapterProvider(_chapterRequest)),
        builder: (payload) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          child: Stack(
            children: [
              NotificationListener<UserScrollNotification>(
                onNotification: (_) {
                  if (_overlayVisible) {
                    setState(() => _overlayVisible = false);
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: payload.images.length,
                  itemBuilder: (context, index) {
                    final image = payload.images[index];
                    return _ReaderImage(
                      imageUrl: image.url,
                      pageNumber: index + 1,
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
                  onBack: () => context.pop(),
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
                  onPrevious: () =>
                      _goRelativeChapter(chapters.asData?.value, 1),
                  onNext: () => _goRelativeChapter(chapters.asData?.value, -1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onScroll() {
    _lastOffset = _scrollController.offset;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveProgress);
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
    return math.min(total - 1, (_lastOffset / 800).floor());
  }

  Future<void> _saveProgress() async {
    final detail = ref.read(comicDetailProvider(_comicRequest)).asData?.value;
    final chapter = ref.read(chapterProvider(_chapterRequest)).asData?.value;
    if (detail == null || chapter == null) return;

    final total = chapter.total == 0 ? chapter.images.length : chapter.total;
    final progress = ReadingProgress.fromReader(
      comic: detail.toSummary(),
      chapterNumber: widget.chapterNumber,
      scrollOffset: _lastOffset,
      pageItemIndex: _pageIndex(total),
      totalPageItems: total,
      isCompleted: total > 0 && _pageIndex(total) >= total - 1,
    );

    try {
      await ref.read(progressRepositoryProvider).saveProgress(progress);
      ref.invalidate(progressProvider(_comicRequest));
      ref.invalidate(continueReadingProvider);
      ref.invalidate(homeDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _goRelativeChapter(List<ChapterListItem>? chapters, int delta) {
    if (chapters == null || chapters.isEmpty) return;
    final currentIndex = chapters.indexWhere(
      (chapter) => chapter.chapterNumber == widget.chapterNumber,
    );
    if (currentIndex < 0) return;
    final targetIndex = currentIndex + delta;
    if (targetIndex < 0 || targetIndex >= chapters.length) return;
    _saveProgress();
    final target = chapters[targetIndex];
    context.go(
      '/reader/${widget.sourceName}/${widget.slug}/${formatChapterNumber(target.chapterNumber)}',
    );
  }
}

class _ReaderImage extends StatefulWidget {
  const _ReaderImage({required this.imageUrl, required this.pageNumber});

  final String imageUrl;
  final int pageNumber;

  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage> {
  int _retry = 0;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey('${widget.imageUrl}#$_retry'),
      imageUrl: widget.imageUrl,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      placeholder: (context, url) => const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      ),
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
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.chapterNumber,
    required this.onBack,
  });

  final String title;
  final double chapterNumber;
  final VoidCallback onBack;

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
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    required this.onPrevious,
    required this.onNext,
  });

  final int currentIndex;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

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
              IconButton.filledTonal(
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Previous chapter',
              ),
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
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
                tooltip: 'Next chapter',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
