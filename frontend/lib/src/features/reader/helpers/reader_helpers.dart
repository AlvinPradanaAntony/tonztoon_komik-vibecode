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
const _readerVerticalPageBleed = 1.0;

double _readerPageAspectRatio(_ReaderPageUi page) {
  final intrinsic = page.intrinsicAspectRatio;
  if (intrinsic != null && intrinsic > 0 && intrinsic.isFinite) {
    return intrinsic;
  }
  return page.aspectRatio > 0 && page.aspectRatio.isFinite
      ? page.aspectRatio
      : _standardWebtoonAspectRatio;
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
