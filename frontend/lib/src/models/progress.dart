import 'comic.dart';

class ReadingProgress {
  const ReadingProgress({
    required this.sourceName,
    required this.comicSlug,
    required this.comicTitle,
    required this.chapterNumber,
    required this.lastReadAt,
    this.coverImageUrl,
    this.readingMode = 'vertical',
    this.scrollOffset,
    this.pageIndex,
    this.lastReadPageItemIndex,
    this.totalPageItems,
    this.isCompleted = false,
  });

  factory ReadingProgress.fromLibraryJson(Map<String, dynamic> json) {
    final comic = json['comic'] as Map<String, dynamic>? ?? const {};
    final chapter = json['chapter'] as Map<String, dynamic>? ?? const {};
    return ReadingProgress(
      sourceName: comic['source_name'] as String? ?? '',
      comicSlug: comic['slug'] as String? ?? '',
      comicTitle: comic['title'] as String? ?? '',
      coverImageUrl: comic['cover_image_url'] as String?,
      chapterNumber: (chapter['chapter_number'] as num?)?.toDouble() ?? 0,
      readingMode: json['reading_mode'] as String? ?? 'vertical',
      scrollOffset: (json['scroll_offset'] as num?)?.toDouble(),
      pageIndex: json['page_index'] as int?,
      lastReadPageItemIndex: json['last_read_page_item_index'] as int?,
      totalPageItems: json['total_page_items'] as int?,
      isCompleted: json['is_completed'] as bool? ?? false,
      lastReadAt:
          DateTime.tryParse(json['last_read_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  factory ReadingProgress.fromLocalJson(Map<dynamic, dynamic> json) {
    return ReadingProgress(
      sourceName: json['source_name'] as String? ?? '',
      comicSlug: json['comic_slug'] as String? ?? '',
      comicTitle: json['comic_title'] as String? ?? '',
      coverImageUrl: json['cover_image_url'] as String?,
      chapterNumber: (json['chapter_number'] as num?)?.toDouble() ?? 0,
      readingMode: json['reading_mode'] as String? ?? 'vertical',
      scrollOffset: (json['scroll_offset'] as num?)?.toDouble(),
      pageIndex: json['page_index'] as int?,
      lastReadPageItemIndex: json['last_read_page_item_index'] as int?,
      totalPageItems: json['total_page_items'] as int?,
      isCompleted: json['is_completed'] as bool? ?? false,
      lastReadAt:
          DateTime.tryParse(json['last_read_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  factory ReadingProgress.fromReader({
    required ComicSummary comic,
    required double chapterNumber,
    required double scrollOffset,
    required int pageItemIndex,
    required int totalPageItems,
    bool isCompleted = false,
  }) {
    return ReadingProgress(
      sourceName: comic.sourceName,
      comicSlug: comic.slug,
      comicTitle: comic.title,
      coverImageUrl: comic.coverImageUrl,
      chapterNumber: chapterNumber,
      scrollOffset: scrollOffset,
      lastReadPageItemIndex: pageItemIndex,
      totalPageItems: totalPageItems,
      isCompleted: isCompleted,
      lastReadAt: DateTime.now(),
    );
  }

  static String key(String sourceName, String comicSlug) {
    return '$sourceName|$comicSlug';
  }

  String get storageKey => key(sourceName, comicSlug);

  Map<String, dynamic> toLocalJson() => {
    'source_name': sourceName,
    'comic_slug': comicSlug,
    'comic_title': comicTitle,
    'cover_image_url': coverImageUrl,
    'chapter_number': chapterNumber,
    'reading_mode': readingMode,
    'scroll_offset': scrollOffset,
    'page_index': pageIndex,
    'last_read_page_item_index': lastReadPageItemIndex,
    'total_page_items': totalPageItems,
    'is_completed': isCompleted,
    'last_read_at': lastReadAt.toIso8601String(),
  };

  Map<String, dynamic> toProgressPayload() => {
    'source_name': sourceName,
    'comic_slug': comicSlug,
    'chapter_number': chapterNumber,
    'reading_mode': readingMode,
    'scroll_offset': scrollOffset,
    'page_index': pageIndex,
    'last_read_page_item_index': lastReadPageItemIndex,
    'total_page_items': totalPageItems,
    'is_completed': isCompleted,
  };

  final String sourceName;
  final String comicSlug;
  final String comicTitle;
  final String? coverImageUrl;
  final double chapterNumber;
  final String readingMode;
  final double? scrollOffset;
  final int? pageIndex;
  final int? lastReadPageItemIndex;
  final int? totalPageItems;
  final bool isCompleted;
  final DateTime lastReadAt;
}
