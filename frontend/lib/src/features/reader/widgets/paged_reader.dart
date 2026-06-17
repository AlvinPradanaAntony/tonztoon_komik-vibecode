part of '../reader_screen.dart';

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

  void _rememberImageAspectRatio(ImageProvider<Object> provider, String url) {
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
    final fit = widget.paged ? BoxFit.contain : BoxFit.cover;
    final image = filePath == null
        ? CachedNetworkImage(
            key: ValueKey('$imageUrl|$_retrySerial'),
            imageUrl: imageUrl,
            cacheManager: ReaderImageCacheManager.instance,
            width: double.infinity,
            height: double.infinity,
            fit: fit,
            memCacheHeight: _maxReaderDecodedImageHeight,
            imageBuilder: (context, imageProvider) {
              final decodedProvider = _readerDecodedImageProvider(
                imageProvider,
              );
              _rememberImageAspectRatio(decodedProvider, imageUrl);
              return Image(
                image: decodedProvider,
                width: double.infinity,
                height: double.infinity,
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
              imageBleed: 0,
              actionsVisible: widget.actionsVisible,
              onDownload: widget.onDownload,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _ReaderPageStack(
          image: image,
          imageBleed: _readerVerticalPageBleed,
          actionsVisible: widget.actionsVisible,
          onDownload: widget.onDownload,
        ),
      ),
    );
  }

  Widget _localReaderImage({
    required String filePath,
    required String imageUrl,
    required BoxFit fit,
    required double reservedHeight,
  }) {
    final provider = _readerDecodedImageProvider(FileImage(File(filePath)));
    _rememberImageAspectRatio(provider, imageUrl);
    return Image(
      image: provider,
      key: ValueKey('$filePath|$_retrySerial'),
      width: double.infinity,
      height: double.infinity,
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
    required this.imageBleed,
    required this.actionsVisible,
    required this.onDownload,
  });

  final Widget image;
  final double imageBleed;
  final bool actionsVisible;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned(
          top: -imageBleed,
          right: 0,
          bottom: -imageBleed,
          left: 0,
          child: image,
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
