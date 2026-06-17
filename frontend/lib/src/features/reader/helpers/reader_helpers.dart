part of '../reader_screen.dart';

double _dynamicReaderCacheExtent(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  final multiplier = height < 700
      ? 4.0
      : height < 1000
      ? 3.25
      : 2.75;
  return height * multiplier;
}

const _standardWebtoonAspectRatio = 0.68;
const _maxReaderDecodedImageHeight = 4096;
const _readerVerticalPageBleed = 1.0;
const _minFallbackSampleAspectRatio = 0.25;
const _maxFallbackSampleAspectRatio = 2.5;
const _minFallbackWebtoonAspectRatio = 0.45;
const _maxFallbackWebtoonAspectRatio = 0.9;

final Map<String, double> _knownReaderImageAspectRatios = <String, double>{};

ImageProvider<Object> _readerDecodedImageProvider(
  ImageProvider<Object> provider,
) {
  // Some sources publish a full webtoon page as a very tall strip. Keeping the
  // decoded texture below older Android GPU limits avoids distorted rendering.
  return ResizeImage(provider, height: _maxReaderDecodedImageHeight);
}

void _rememberReaderImageAspectRatio(String url, ImageInfo info) {
  final width = info.image.width.toDouble();
  final height = info.image.height.toDouble();
  if (width <= 0 || height <= 0) return;
  final aspectRatio = width / height;
  if (!aspectRatio.isFinite || aspectRatio <= 0) return;
  _knownReaderImageAspectRatios[url] = aspectRatio;
}

double _readerPageAspectRatio(_ReaderPageUi page) {
  final known = _knownReaderImageAspectRatios[page.imageUrl];
  if (known != null && known > 0) return known;
  final intrinsic = page.intrinsicAspectRatio;
  if (intrinsic != null && intrinsic > 0 && intrinsic.isFinite) {
    return intrinsic;
  }
  return _dynamicReaderFallbackAspectRatio(page.aspectRatio);
}

double _dynamicReaderFallbackAspectRatio(double seedAspectRatio) {
  final knownRatios =
      _knownReaderImageAspectRatios.values
          .where(
            (ratio) =>
                ratio.isFinite &&
                ratio >= _minFallbackSampleAspectRatio &&
                ratio <= _maxFallbackSampleAspectRatio,
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
          intrinsicAspectRatio: entry.value.aspectRatio,
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
