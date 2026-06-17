part of '../reader_screen.dart';

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

class _ReaderPageUi {
  const _ReaderPageUi({
    required this.number,
    required this.pageIndexInChapter,
    required this.totalPagesInChapter,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.aspectRatio,
    this.intrinsicAspectRatio,
    required this.background,
    required this.imageUrl,
  });

  final int number;
  final int pageIndexInChapter;
  final int totalPagesInChapter;
  final double chapterNumber;
  final String chapterTitle;
  final double aspectRatio;
  final double? intrinsicAspectRatio;
  final Color background;
  final String imageUrl;
}
