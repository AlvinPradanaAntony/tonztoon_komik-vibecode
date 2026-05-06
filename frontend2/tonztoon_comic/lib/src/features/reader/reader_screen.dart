import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../library/downloaded_scene_store.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.comicTitle,
    required this.chapterTitle,
    this.comic,
  });

  final String comicTitle;
  final String chapterTitle;
  final ComicSummary? comic;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _scrollController = ScrollController();
  final _pageController = PageController();
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  bool _overlayVisible = false;
  bool _pagedMode = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncVerticalProgress);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncVerticalProgress)
      ..dispose();
    _pageController.dispose();
    _currentPage.dispose();
    super.dispose();
  }

  void _syncVerticalProgress() {
    if (!_scrollController.hasClients || _pagedMode) return;
    final viewport = MediaQuery.sizeOf(context).height;
    final nextPage = (_scrollController.offset / (viewport * 0.82))
        .floor()
        .clamp(0, _readerPages.length - 1);

    if (_currentPage.value != nextPage) {
      _currentPage.value = nextPage;
    }

    if (_overlayVisible &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      setState(() => _overlayVisible = false);
    }
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
      final page = _currentPage.value.clamp(0, _readerPages.length - 1);
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
    final next = (_currentPage.value + delta).clamp(0, _readerPages.length - 1);
    _currentPage.value = next;
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
          coverImageUrl: _coverForTitle(widget.comicTitle),
        );

    saveDownloadedScene(
      DownloadedSceneItem(
        comic: comic,
        chapterTitle: widget.chapterTitle,
        pageNumber: page.number,
        label: '${widget.chapterTitle} - Page ${page.number}',
        imageUrl: comic.coverImageUrl,
        downloadedAt: DateTime.now(),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Page ${page.number} tersimpan ke Scene.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: readerBackground,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          child: Stack(
            children: [
              Positioned.fill(
                child: _pagedMode
                    ? _PagedReader(
                        controller: _pageController,
                        onDownloadPage: _downloadPage,
                        actionsVisible: _overlayVisible,
                        onPageChanged: (index) {
                          _currentPage.value = index;
                          if (_overlayVisible) {
                            setState(() => _overlayVisible = false);
                          }
                        },
                      )
                    : _VerticalReader(
                        controller: _scrollController,
                        onDownloadPage: _downloadPage,
                        actionsVisible: _overlayVisible,
                      ),
              ),
              _ReaderTopBar(
                visible: _overlayVisible,
                comicTitle: widget.comicTitle,
                chapterTitle: widget.chapterTitle,
                onBack: () => Navigator.of(context).pop(),
              ),
              _ReaderBottomBar(
                visible: _overlayVisible,
                pagedMode: _pagedMode,
                currentPage: _currentPage,
                totalPages: _readerPages.length,
                onPrevious: () => _goRelativePage(-1),
                onNext: () => _goRelativePage(1),
                onToggleMode: _toggleMode,
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
    required this.onDownloadPage,
    required this.actionsVisible,
  });

  final ScrollController controller;
  final ValueChanged<_ReaderPageUi> onDownloadPage;
  final bool actionsVisible;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final page = _readerPages[index];
        return _ReaderPage(
          page: page,
          actionsVisible: actionsVisible,
          onDownload: () => onDownloadPage(page),
        );
      },
      itemCount: _readerPages.length,
    );
  }
}

class _PagedReader extends StatelessWidget {
  const _PagedReader({
    required this.controller,
    required this.onPageChanged,
    required this.onDownloadPage,
    required this.actionsVisible,
  });

  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_ReaderPageUi> onDownloadPage;
  final bool actionsVisible;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      onPageChanged: onPageChanged,
      itemCount: _readerPages.length,
      itemBuilder: (context, index) {
        final page = _readerPages[index];
        return Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              MediaQuery.paddingOf(context).top + 74,
              14,
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

class _ReaderPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final decoration = paged
        ? BoxDecoration(
            color: page.background,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: isDark ? 18 : 12,
                offset: Offset(0, isDark ? 10 : 6),
              ),
            ],
          )
        : BoxDecoration(color: page.background);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: paged ? width : 720),
        child: AspectRatio(
          aspectRatio: page.aspectRatio,
          child: DecoratedBox(
            decoration: decoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(paged ? 8 : 0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final panel in page.panels) _ComicPanel(panel: panel),
                  Positioned(
                    right: 14,
                    bottom: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Text(
                          '${page.number}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _PageDownloadButton(
                      visible: actionsVisible,
                      onPressed: onDownload,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

class _ComicPanel extends StatelessWidget {
  const _ComicPanel({required this.panel});

  final _PanelUi panel;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: panel.alignment,
      widthFactor: panel.widthFactor,
      heightFactor: panel.heightFactor,
      child: Padding(
        padding: panel.padding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: panel.colors,
            ),
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SpeedLinePainter(panel.accent)),
              ),
              Align(
                alignment: panel.bubbleAlignment,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        panel.caption,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
  });

  final bool visible;
  final String comicTitle;
  final String chapterTitle;
  final VoidCallback onBack;

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
    required this.onToggleMode,
  });

  final bool visible;
  final bool pagedMode;
  final ValueListenable<int> currentPage;
  final int totalPages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
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
      bottom: visible ? 0 : -132,
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

class _SpeedLinePainter extends CustomPainter {
  const _SpeedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1.4;

    for (var i = 0; i < 12; i++) {
      final y = size.height * (i / 12);
      canvas.drawLine(
        Offset(size.width * 0.08, y),
        Offset(size.width * 0.92, y + size.height * 0.12),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ReaderPageUi {
  const _ReaderPageUi({
    required this.number,
    required this.aspectRatio,
    required this.background,
    required this.panels,
  });

  final int number;
  final double aspectRatio;
  final Color background;
  final List<_PanelUi> panels;
}

class _PanelUi {
  const _PanelUi({
    required this.alignment,
    required this.widthFactor,
    required this.heightFactor,
    required this.padding,
    required this.colors,
    required this.accent,
    required this.caption,
    required this.bubbleAlignment,
  });

  final Alignment alignment;
  final double widthFactor;
  final double heightFactor;
  final EdgeInsets padding;
  final List<Color> colors;
  final Color accent;
  final String caption;
  final Alignment bubbleAlignment;
}

String? _coverForTitle(String title) {
  for (final comic in dummyComics) {
    if (comic.title == title) return comic.coverImageUrl;
  }
  return null;
}

const _readerPages = [
  _ReaderPageUi(
    number: 1,
    aspectRatio: 0.68,
    background: Color(0xFFF5F1E8),
    panels: [
      _PanelUi(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 0.46,
        padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
        colors: [Color(0xFF1D2A3A), Color(0xFF55708A)],
        accent: Color(0xFFFFFFFF),
        caption: 'Gerbang dungeon terbuka.',
        bubbleAlignment: Alignment.topLeft,
      ),
      _PanelUi(
        alignment: Alignment.bottomLeft,
        widthFactor: 0.54,
        heightFactor: 0.54,
        padding: EdgeInsets.fromLTRB(14, 6, 5, 14),
        colors: [Color(0xFFB9472C), Color(0xFFF5A34A)],
        accent: Color(0xFFFFFFFF),
        caption: 'Cepat!',
        bubbleAlignment: Alignment.bottomLeft,
      ),
      _PanelUi(
        alignment: Alignment.bottomRight,
        widthFactor: 0.46,
        heightFactor: 0.54,
        padding: EdgeInsets.fromLTRB(5, 6, 14, 14),
        colors: [Color(0xFF192230), Color(0xFF8557D9)],
        accent: Color(0xFFFFFFFF),
        caption: 'Ada sesuatu.',
        bubbleAlignment: Alignment.topRight,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 2,
    aspectRatio: 0.66,
    background: Color(0xFFEDE7DA),
    panels: [
      _PanelUi(
        alignment: Alignment.topLeft,
        widthFactor: 0.58,
        heightFactor: 0.52,
        padding: EdgeInsets.fromLTRB(14, 14, 5, 6),
        colors: [Color(0xFF111827), Color(0xFF374151)],
        accent: Color(0xFFFDE68A),
        caption: 'Aku bisa melihat polanya.',
        bubbleAlignment: Alignment.topLeft,
      ),
      _PanelUi(
        alignment: Alignment.topRight,
        widthFactor: 0.42,
        heightFactor: 0.52,
        padding: EdgeInsets.fromLTRB(5, 14, 14, 6),
        colors: [Color(0xFF0F766E), Color(0xFF5EEAD4)],
        accent: Color(0xFFFFFFFF),
        caption: 'Tunggu.',
        bubbleAlignment: Alignment.center,
      ),
      _PanelUi(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 0.48,
        padding: EdgeInsets.fromLTRB(14, 6, 14, 14),
        colors: [Color(0xFF312E81), Color(0xFF818CF8)],
        accent: Color(0xFFFFFFFF),
        caption: 'Bayangan itu bergerak.',
        bubbleAlignment: Alignment.bottomRight,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 3,
    aspectRatio: 0.7,
    background: Color(0xFFF7F2E7),
    panels: [
      _PanelUi(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 0.34,
        padding: EdgeInsets.fromLTRB(14, 14, 14, 5),
        colors: [Color(0xFF7C2D12), Color(0xFFF97316)],
        accent: Color(0xFFFFFFFF),
        caption: 'Serangan datang dari atas!',
        bubbleAlignment: Alignment.topCenter,
      ),
      _PanelUi(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 0.34,
        padding: EdgeInsets.fromLTRB(14, 5, 14, 5),
        colors: [Color(0xFF020617), Color(0xFF334155)],
        accent: Color(0xFF93C5FD),
        caption: 'Aku tidak boleh mundur.',
        bubbleAlignment: Alignment.centerLeft,
      ),
      _PanelUi(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 0.32,
        padding: EdgeInsets.fromLTRB(14, 5, 14, 14),
        colors: [Color(0xFF14532D), Color(0xFF86EFAC)],
        accent: Color(0xFFFFFFFF),
        caption: 'Skill baru terbuka.',
        bubbleAlignment: Alignment.bottomRight,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 4,
    aspectRatio: 0.64,
    background: Color(0xFFEFE7DC),
    panels: [
      _PanelUi(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 0.58,
        padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
        colors: [Color(0xFF581C87), Color(0xFFE879F9)],
        accent: Color(0xFFFFFFFF),
        caption: 'Kekuatan ini...',
        bubbleAlignment: Alignment.topLeft,
      ),
      _PanelUi(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 0.42,
        padding: EdgeInsets.fromLTRB(14, 6, 14, 14),
        colors: [Color(0xFF0C4A6E), Color(0xFF38BDF8)],
        accent: Color(0xFFFFFFFF),
        caption: '...bukan kebetulan.',
        bubbleAlignment: Alignment.bottomRight,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 5,
    aspectRatio: 0.68,
    background: Color(0xFFF2EDE2),
    panels: [
      _PanelUi(
        alignment: Alignment.topLeft,
        widthFactor: 0.5,
        heightFactor: 0.5,
        padding: EdgeInsets.fromLTRB(14, 14, 5, 5),
        colors: [Color(0xFF111827), Color(0xFF6B7280)],
        accent: Color(0xFFFFFFFF),
        caption: 'Hening.',
        bubbleAlignment: Alignment.topLeft,
      ),
      _PanelUi(
        alignment: Alignment.topRight,
        widthFactor: 0.5,
        heightFactor: 0.5,
        padding: EdgeInsets.fromLTRB(5, 14, 14, 5),
        colors: [Color(0xFF92400E), Color(0xFFFBBF24)],
        accent: Color(0xFFFFFFFF),
        caption: 'Terlalu hening.',
        bubbleAlignment: Alignment.bottomRight,
      ),
      _PanelUi(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 0.5,
        padding: EdgeInsets.fromLTRB(14, 5, 14, 14),
        colors: [Color(0xFF172554), Color(0xFF60A5FA)],
        accent: Color(0xFFFFFFFF),
        caption: 'Boss muncul.',
        bubbleAlignment: Alignment.center,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 6,
    aspectRatio: 0.67,
    background: Color(0xFFF8F1E5),
    panels: [
      _PanelUi(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 0.45,
        padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
        colors: [Color(0xFF450A0A), Color(0xFFEF4444)],
        accent: Color(0xFFFFFFFF),
        caption: 'Satu pukulan.',
        bubbleAlignment: Alignment.topRight,
      ),
      _PanelUi(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 0.55,
        padding: EdgeInsets.fromLTRB(14, 6, 14, 14),
        colors: [Color(0xFF052E16), Color(0xFF22C55E)],
        accent: Color(0xFFFFFFFF),
        caption: 'Masih belum cukup.',
        bubbleAlignment: Alignment.bottomLeft,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 7,
    aspectRatio: 0.69,
    background: Color(0xFFF3ECDF),
    panels: [
      _PanelUi(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 0.38,
        padding: EdgeInsets.fromLTRB(14, 14, 14, 5),
        colors: [Color(0xFF0F172A), Color(0xFF475569)],
        accent: Color(0xFFFFFFFF),
        caption: 'Aku mengerti sekarang.',
        bubbleAlignment: Alignment.topLeft,
      ),
      _PanelUi(
        alignment: Alignment.bottomLeft,
        widthFactor: 0.48,
        heightFactor: 0.62,
        padding: EdgeInsets.fromLTRB(14, 5, 5, 14),
        colors: [Color(0xFF1E3A8A), Color(0xFF93C5FD)],
        accent: Color(0xFFFFFFFF),
        caption: 'Formasi kiri.',
        bubbleAlignment: Alignment.center,
      ),
      _PanelUi(
        alignment: Alignment.bottomRight,
        widthFactor: 0.52,
        heightFactor: 0.62,
        padding: EdgeInsets.fromLTRB(5, 5, 14, 14),
        colors: [Color(0xFF713F12), Color(0xFFFACC15)],
        accent: Color(0xFFFFFFFF),
        caption: 'Tutup jalannya.',
        bubbleAlignment: Alignment.bottomRight,
      ),
    ],
  ),
  _ReaderPageUi(
    number: 8,
    aspectRatio: 0.65,
    background: Color(0xFFF7EFE4),
    panels: [
      _PanelUi(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 0.5,
        padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
        colors: [Color(0xFF4C1D95), Color(0xFFA78BFA)],
        accent: Color(0xFFFFFFFF),
        caption: 'Sistem merespons.',
        bubbleAlignment: Alignment.topCenter,
      ),
      _PanelUi(
        alignment: Alignment.bottomCenter,
        widthFactor: 1,
        heightFactor: 0.5,
        padding: EdgeInsets.fromLTRB(14, 6, 14, 14),
        colors: [Color(0xFF7F1D1D), Color(0xFFFCA5A5)],
        accent: Color(0xFFFFFFFF),
        caption: 'Misi dimulai.',
        bubbleAlignment: Alignment.bottomRight,
      ),
    ],
  ),
];
