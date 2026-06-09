import 'comic.dart';
import 'progress.dart';

class LibraryComicRef {
  const LibraryComicRef({
    required this.sourceName,
    required this.slug,
    required this.title,
    this.comicId,
    this.coverImageUrl,
    this.author,
    this.status,
    this.type,
    this.rating,
    this.totalView,
    this.linkedComics = const [],
  });

  factory LibraryComicRef.fromJson(Map<String, dynamic> json) {
    return LibraryComicRef(
      comicId: json['comic_id'] as int?,
      sourceName: json['source_name'] as String? ?? '',
      slug: json['slug'] as String? ?? json['comic_slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      coverImageUrl: json['cover_image_url'] as String?,
      author: json['author'] as String?,
      status: json['status'] as String?,
      type: json['type'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalView: json['total_view'] as int?,
      linkedComics: ((json['linked_comics'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => LibraryComicRef.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  factory LibraryComicRef.fromSummary(ComicSummary comic) {
    return LibraryComicRef(
      sourceName: comic.sourceName,
      slug: comic.slug,
      title: comic.title,
      coverImageUrl: comic.coverImageUrl,
      status: comic.status,
      type: comic.type,
      rating: comic.rating,
      totalView: comic.totalView,
    );
  }

  ComicSummary toSummary() {
    return ComicSummary(
      title: title,
      slug: slug,
      sourceName: sourceName,
      coverImageUrl: coverImageUrl,
      status: status,
      type: type,
      rating: rating,
      totalView: totalView,
    );
  }

  Map<String, dynamic> toJson() => {
    'comic_id': comicId,
    'source_name': sourceName,
    'slug': slug,
    'title': title,
    'cover_image_url': coverImageUrl,
    'author': author,
    'status': status,
    'type': type,
    'rating': rating,
    'total_view': totalView,
    'linked_comics': linkedComics.map((item) => item.toJson()).toList(),
  };

  String get key => '$sourceName|$slug';

  final int? comicId;
  final String sourceName;
  final String slug;
  final String title;
  final String? coverImageUrl;
  final String? author;
  final String? status;
  final String? type;
  final double? rating;
  final int? totalView;
  final List<LibraryComicRef> linkedComics;
}

class BookmarkLinkCandidate {
  const BookmarkLinkCandidate({
    required this.bookmark,
    required this.comic,
    required this.confidence,
  });

  factory BookmarkLinkCandidate.fromJson(
    LibraryComicRef bookmark,
    Map<String, dynamic> json,
  ) {
    return BookmarkLinkCandidate(
      bookmark: bookmark,
      comic: LibraryComicRef.fromJson(
        Map<String, dynamic>.from(json['comic'] as Map? ?? const {}),
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  String get key => '${bookmark.key}->${comic.key}';

  final LibraryComicRef bookmark;
  final LibraryComicRef comic;
  final double confidence;
}

enum BookmarkRelation { none, direct, linked }

class BookmarkLinkSaveResult {
  const BookmarkLinkSaveResult({
    this.linkedTotal = 0,
    required this.completedPropagated,
    this.completionSyncBookmarkIds = const [],
  });

  factory BookmarkLinkSaveResult.fromJson(Map<String, dynamic> json) {
    return BookmarkLinkSaveResult(
      linkedTotal: json['linked_total'] as int? ?? 0,
      completedPropagated: json['completed_propagated'] as int? ?? 0,
      completionSyncBookmarkIds:
          (json['completion_sync_bookmark_ids'] as List?)
              ?.whereType<num>()
              .map((item) => item.toInt())
              .toList() ??
          const [],
    );
  }

  final int linkedTotal;
  final int completedPropagated;
  final List<int> completionSyncBookmarkIds;
}

class ReadStatusSyncResult {
  const ReadStatusSyncResult({
    required this.completedSynced,
    required this.completedPropagated,
  });

  final int completedSynced;
  final int completedPropagated;
}

enum BookmarkLinkSaveStage { linking, syncingCompleted }

class BookmarkLinkSaveProgress {
  const BookmarkLinkSaveProgress({
    required this.stage,
    required this.completed,
    required this.total,
  });

  final BookmarkLinkSaveStage stage;
  final int completed;
  final int total;
}

class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.name,
    required this.totalItems,
  });

  factory CollectionSummary.fromJson(Map<String, dynamic> json) {
    return CollectionSummary(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      totalItems: json['total_items'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'total_items': totalItems,
  };

  final int id;
  final String name;
  final int totalItems;
}

class CollectionDetail extends CollectionSummary {
  const CollectionDetail({
    required super.id,
    required super.name,
    required super.totalItems,
    required this.items,
  });

  factory CollectionDetail.fromJson(Map<String, dynamic> json) {
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) => LibraryComicRef.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    return CollectionDetail(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      totalItems: json['total_items'] as int? ?? items.length,
      items: items,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'items': items.map((item) => item.toJson()).toList(),
  };

  final List<LibraryComicRef> items;
}

class FavoriteScene {
  const FavoriteScene({
    required this.id,
    required this.comic,
    required this.chapterNumber,
    required this.pageItemIndex,
    this.imageUrl,
    this.note,
  });

  factory FavoriteScene.fromJson(Map<String, dynamic> json) {
    final chapterRaw = json['chapter'];
    final chapter = chapterRaw is Map
        ? Map<String, dynamic>.from(chapterRaw)
        : const <String, dynamic>{};
    final comicRaw = json['comic'];
    final comic = comicRaw is Map
        ? Map<String, dynamic>.from(comicRaw)
        : const <String, dynamic>{};
    return FavoriteScene(
      id: json['id'] as int? ?? 0,
      comic: LibraryComicRef.fromJson(comic),
      chapterNumber: (chapter['chapter_number'] as num?)?.toDouble() ?? 0,
      pageItemIndex: json['page_item_index'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'comic': comic.toJson(),
    'chapter': {'chapter_number': chapterNumber},
    'page_item_index': pageItemIndex,
    'image_url': imageUrl,
    'note': note,
  };

  final int id;
  final LibraryComicRef comic;
  final double chapterNumber;
  final int pageItemIndex;
  final String? imageUrl;
  final String? note;
}

class DownloadEntry {
  const DownloadEntry({
    required this.id,
    required this.comic,
    required this.chapterNumber,
    required this.status,
    this.lastError,
  });

  factory DownloadEntry.fromJson(Map<String, dynamic> json) {
    final chapterRaw = json['chapter'];
    final chapter = chapterRaw is Map
        ? Map<String, dynamic>.from(chapterRaw)
        : const <String, dynamic>{};
    final comicRaw = json['comic'];
    final comic = comicRaw is Map
        ? Map<String, dynamic>.from(comicRaw)
        : const <String, dynamic>{};
    return DownloadEntry(
      id: json['id'] as int? ?? 0,
      comic: LibraryComicRef.fromJson(comic),
      chapterNumber: (chapter['chapter_number'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      lastError: json['last_error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'comic': comic.toJson(),
    'chapter': {'chapter_number': chapterNumber},
    'status': status,
    'last_error': lastError,
  };

  final int id;
  final LibraryComicRef comic;
  final double chapterNumber;
  final String status;
  final String? lastError;
}

class OfflineChapter {
  const OfflineChapter({
    required this.comic,
    required this.chapterNumber,
    required this.status,
    required this.localPaths,
    required this.updatedAt,
    this.lastError,
  });

  factory OfflineChapter.fromJson(Map<dynamic, dynamic> json) {
    return OfflineChapter(
      comic: LibraryComicRef.fromJson(
        Map<String, dynamic>.from(json['comic'] as Map? ?? const {}),
      ),
      chapterNumber: (json['chapter_number'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      localPaths: ((json['local_paths'] as List?) ?? const [])
          .map((path) => path.toString())
          .toList(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      lastError: json['last_error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'comic': comic.toJson(),
    'chapter_number': chapterNumber,
    'status': status,
    'local_paths': localPaths,
    'updated_at': updatedAt.toIso8601String(),
    'last_error': lastError,
  };

  String get key => '${comic.sourceName}|${comic.slug}|$chapterNumber';
  bool get isCompleted => status == 'completed' && localPaths.isNotEmpty;

  final LibraryComicRef comic;
  final double chapterNumber;
  final String status;
  final List<String> localPaths;
  final DateTime updatedAt;
  final String? lastError;
}

class OfflineDownloadBatch {
  const OfflineDownloadBatch({
    required this.id,
    required this.comic,
    required this.chapterNumbers,
    required this.status,
    required this.completedChapters,
    required this.totalChapters,
    required this.completedImages,
    required this.totalImages,
    required this.createdAt,
    required this.updatedAt,
    this.progressValue,
    this.currentChapterNumber,
    this.lastError,
  });

  factory OfflineDownloadBatch.create({
    required String id,
    required ComicSummary comic,
    required List<double> chapterNumbers,
  }) {
    final now = DateTime.now();
    return OfflineDownloadBatch(
      id: id,
      comic: LibraryComicRef.fromSummary(comic),
      chapterNumbers: chapterNumbers,
      status: 'pending',
      completedChapters: 0,
      totalChapters: chapterNumbers.length,
      completedImages: 0,
      totalImages: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory OfflineDownloadBatch.fromJson(Map<dynamic, dynamic> json) {
    return OfflineDownloadBatch(
      id: json['id'] as String? ?? '',
      comic: LibraryComicRef.fromJson(
        Map<String, dynamic>.from(json['comic'] as Map? ?? const {}),
      ),
      chapterNumbers: ((json['chapter_numbers'] as List?) ?? const [])
          .map((value) => (value as num).toDouble())
          .toList(),
      status: json['status'] as String? ?? 'pending',
      completedChapters: json['completed_chapters'] as int? ?? 0,
      totalChapters: json['total_chapters'] as int? ?? 0,
      completedImages: json['completed_images'] as int? ?? 0,
      totalImages: json['total_images'] as int? ?? 0,
      currentChapterNumber: (json['current_chapter_number'] as num?)
          ?.toDouble(),
      progressValue: (json['progress_value'] as num?)?.toDouble(),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      lastError: json['last_error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'comic': comic.toJson(),
    'chapter_numbers': chapterNumbers,
    'status': status,
    'completed_chapters': completedChapters,
    'total_chapters': totalChapters,
    'completed_images': completedImages,
    'total_images': totalImages,
    'progress_value': progressValue,
    'current_chapter_number': currentChapterNumber,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'last_error': lastError,
  };

  OfflineDownloadBatch copyWith({
    String? status,
    int? completedChapters,
    int? totalChapters,
    int? completedImages,
    int? totalImages,
    double? currentChapterNumber,
    double? progressValue,
    bool clearCurrentChapterNumber = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return OfflineDownloadBatch(
      id: id,
      comic: comic,
      chapterNumbers: chapterNumbers,
      status: status ?? this.status,
      completedChapters: completedChapters ?? this.completedChapters,
      totalChapters: totalChapters ?? this.totalChapters,
      completedImages: completedImages ?? this.completedImages,
      totalImages: totalImages ?? this.totalImages,
      currentChapterNumber: clearCurrentChapterNumber
          ? null
          : currentChapterNumber ?? this.currentChapterNumber,
      progressValue: progressValue ?? this.progressValue,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  double get progress {
    if (progressValue != null) {
      return progressValue!.clamp(0, 1).toDouble();
    }
    if (totalImages > 0) {
      return (completedImages / totalImages).clamp(0, 1).toDouble();
    }
    if (totalChapters > 0) {
      return (completedChapters / totalChapters).clamp(0, 1).toDouble();
    }
    return 0;
  }

  bool get canCancel => status == 'pending' || status == 'downloading';
  bool get canResume =>
      status == 'pending' || status == 'paused' || status == 'failed';
  bool get canAutoResume => status == 'pending' || status == 'paused';

  final String id;
  final LibraryComicRef comic;
  final List<double> chapterNumbers;
  final String status;
  final int completedChapters;
  final int totalChapters;
  final int completedImages;
  final int totalImages;
  final double? progressValue;
  final double? currentChapterNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;
}

class ReaderPreferences {
  const ReaderPreferences({
    this.defaultReadingMode = 'vertical',
    this.readingDirection = 'ltr',
    this.markReadOnComplete = false,
    this.defaultBingeMode = false,
  });

  factory ReaderPreferences.fromJson(Map<dynamic, dynamic> json) {
    final defaultBingeMode = json['default_binge_mode'];
    return ReaderPreferences(
      defaultReadingMode: json['default_reading_mode'] as String? ?? 'vertical',
      readingDirection: json['reading_direction'] as String? ?? 'ltr',
      markReadOnComplete: json['mark_read_on_complete'] as bool? ?? false,
      defaultBingeMode: defaultBingeMode is bool ? defaultBingeMode : false,
    );
  }

  Map<String, dynamic> toJson() => {
    'default_reading_mode': defaultReadingMode,
    'reading_direction': readingDirection,
    'mark_read_on_complete': markReadOnComplete,
    'default_binge_mode': defaultBingeMode,
  };

  ReaderPreferences copyWith({
    String? defaultReadingMode,
    String? readingDirection,
    bool? markReadOnComplete,
    bool? defaultBingeMode,
  }) {
    return ReaderPreferences(
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
      readingDirection: readingDirection ?? this.readingDirection,
      markReadOnComplete: markReadOnComplete ?? this.markReadOnComplete,
      defaultBingeMode: defaultBingeMode ?? this.defaultBingeMode,
    );
  }

  final String defaultReadingMode;
  final String readingDirection;
  final bool markReadOnComplete;
  final bool defaultBingeMode;
}

class LibraryComicState {
  const LibraryComicState({
    required this.comic,
    required this.bookmarked,
    required this.collections,
    this.bookmarkRelation = BookmarkRelation.none,
    this.bookmarkOrigin,
    this.linkedComics = const [],
    this.progress,
    this.completedChapterNumbers = const [],
    this.favoriteSceneCount = 0,
    this.downloadStatusCounts = const {},
    this.downloadEntries = const [],
  });

  factory LibraryComicState.fromJson(Map<String, dynamic> json) {
    final comicRaw = json['comic'];
    final comic = comicRaw is Map
        ? Map<String, dynamic>.from(comicRaw)
        : const <String, dynamic>{};
    final progressRaw = json['progress'];
    final progressMap = progressRaw is Map
        ? Map<String, dynamic>.from(progressRaw)
        : null;
    return LibraryComicState(
      comic: LibraryComicRef.fromJson(comic),
      bookmarked: json['bookmarked'] as bool? ?? false,
      bookmarkRelation: switch (json['bookmark_relation']) {
        'direct' => BookmarkRelation.direct,
        'linked' => BookmarkRelation.linked,
        _ => BookmarkRelation.none,
      },
      bookmarkOrigin: json['bookmark_origin'] is Map
          ? LibraryComicRef.fromJson(
              Map<String, dynamic>.from(json['bookmark_origin'] as Map),
            )
          : null,
      linkedComics: ((json['linked_comics'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => LibraryComicRef.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      collections: ((json['collections'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CollectionSummary.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      progress: progressMap != null
          ? ReadingProgress.fromLibraryJson(progressMap)
          : null,
      completedChapterNumbers:
          ((json['completed_chapter_numbers'] as List?) ?? const [])
              .whereType<num>()
              .map((value) => value.toDouble())
              .toList(),
      favoriteSceneCount: json['favorite_scene_count'] as int? ?? 0,
      downloadStatusCounts: Map<String, int>.from(
        json['download_status_counts'] as Map? ?? {},
      ),
      downloadEntries: ((json['download_entries'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => DownloadEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  final LibraryComicRef comic;
  final bool bookmarked;
  final BookmarkRelation bookmarkRelation;
  final LibraryComicRef? bookmarkOrigin;
  final List<LibraryComicRef> linkedComics;
  final List<CollectionSummary> collections;
  final ReadingProgress? progress;
  final List<double> completedChapterNumbers;
  final int favoriteSceneCount;
  final Map<String, int> downloadStatusCounts;
  final List<DownloadEntry> downloadEntries;
}

class LibrarySummaryCounts {
  const LibrarySummaryCounts({
    required this.bookmarks,
    required this.collections,
    required this.favoriteScenes,
    required this.history,
    required this.downloads,
    required this.continueReading,
  });

  factory LibrarySummaryCounts.fromJson(Map<String, dynamic> json) {
    return LibrarySummaryCounts(
      bookmarks: json['bookmarks'] as int? ?? 0,
      collections: json['collections'] as int? ?? 0,
      favoriteScenes: json['favorite_scenes'] as int? ?? 0,
      history: json['history'] as int? ?? 0,
      downloads: json['downloads'] as int? ?? 0,
      continueReading: json['continue_reading'] as int? ?? 0,
    );
  }

  final int bookmarks;
  final int collections;
  final int favoriteScenes;
  final int history;
  final int downloads;
  final int continueReading;
}

class LibrarySummary {
  const LibrarySummary({
    required this.counts,
    required this.readingTimeSeconds,
  });

  factory LibrarySummary.fromJson(Map<String, dynamic> json) {
    final countsRaw = json['counts'];
    return LibrarySummary(
      counts: LibrarySummaryCounts.fromJson(
        countsRaw is Map ? Map<String, dynamic>.from(countsRaw) : const {},
      ),
      readingTimeSeconds: json['reading_time_seconds'] as int? ?? 0,
    );
  }

  final LibrarySummaryCounts counts;
  final int readingTimeSeconds;
}

class GuestMigrationSummary {
  const GuestMigrationSummary({
    required this.bookmarks,
    required this.collections,
    required this.progress,
    required this.favoriteScenes,
    required this.downloads,
    required this.hasReaderPreferences,
    required this.readingTimeSeconds,
  });

  final int bookmarks;
  final int collections;
  final int progress;
  final int favoriteScenes;
  final int downloads;
  final bool hasReaderPreferences;
  final int readingTimeSeconds;

  bool get isEmpty =>
      bookmarks == 0 &&
      collections == 0 &&
      progress == 0 &&
      favoriteScenes == 0 &&
      downloads == 0 &&
      !hasReaderPreferences &&
      readingTimeSeconds <= 0;
}
