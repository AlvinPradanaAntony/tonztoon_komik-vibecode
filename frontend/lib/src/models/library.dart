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
        .whereType<Map<String, dynamic>>()
        .map(LibraryComicRef.fromJson)
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
    final chapter = json['chapter'] as Map<String, dynamic>? ?? const {};
    return FavoriteScene(
      id: json['id'] as int? ?? 0,
      comic: LibraryComicRef.fromJson(
        json['comic'] as Map<String, dynamic>? ?? const {},
      ),
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
    final chapter = json['chapter'] as Map<String, dynamic>? ?? const {};
    return DownloadEntry(
      id: json['id'] as int? ?? 0,
      comic: LibraryComicRef.fromJson(
        json['comic'] as Map<String, dynamic>? ?? const {},
      ),
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

class ReaderPreferences {
  const ReaderPreferences({
    this.defaultReadingMode = 'vertical',
    this.readingDirection = 'ltr',
    this.autoNext = true,
    this.markReadOnComplete = true,
    this.defaultBingeMode = false,
  });

  factory ReaderPreferences.fromJson(Map<dynamic, dynamic> json) {
    return ReaderPreferences(
      defaultReadingMode: json['default_reading_mode'] as String? ?? 'vertical',
      readingDirection: json['reading_direction'] as String? ?? 'ltr',
      autoNext: json['auto_next'] as bool? ?? true,
      markReadOnComplete: json['mark_read_on_complete'] as bool? ?? true,
      defaultBingeMode: json['default_binge_mode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'default_reading_mode': defaultReadingMode,
    'reading_direction': readingDirection,
    'auto_next': autoNext,
    'mark_read_on_complete': markReadOnComplete,
    'default_binge_mode': defaultBingeMode,
  };

  ReaderPreferences copyWith({
    String? defaultReadingMode,
    String? readingDirection,
    bool? autoNext,
    bool? markReadOnComplete,
    bool? defaultBingeMode,
  }) {
    return ReaderPreferences(
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
      readingDirection: readingDirection ?? this.readingDirection,
      autoNext: autoNext ?? this.autoNext,
      markReadOnComplete: markReadOnComplete ?? this.markReadOnComplete,
      defaultBingeMode: defaultBingeMode ?? this.defaultBingeMode,
    );
  }

  final String defaultReadingMode;
  final String readingDirection;
  final bool autoNext;
  final bool markReadOnComplete;
  final bool defaultBingeMode;
}

class LibraryComicState {
  const LibraryComicState({
    required this.comic,
    required this.bookmarked,
    required this.collections,
    this.progress,
    this.favoriteSceneCount = 0,
    this.downloadStatusCounts = const {},
    this.downloadEntries = const [],
  });

  factory LibraryComicState.fromJson(Map<String, dynamic> json) {
    return LibraryComicState(
      comic: LibraryComicRef.fromJson(
        json['comic'] as Map<String, dynamic>? ?? const {},
      ),
      bookmarked: json['bookmarked'] as bool? ?? false,
      collections: ((json['collections'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CollectionSummary.fromJson)
          .toList(),
      progress: json['progress'] is Map<String, dynamic>
          ? ReadingProgress.fromLibraryJson(
              json['progress'] as Map<String, dynamic>,
            )
          : null,
      favoriteSceneCount: json['favorite_scene_count'] as int? ?? 0,
      downloadStatusCounts: Map<String, int>.from(
        json['download_status_counts'] as Map? ?? {},
      ),
      downloadEntries: ((json['download_entries'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DownloadEntry.fromJson)
          .toList(),
    );
  }

  final LibraryComicRef comic;
  final bool bookmarked;
  final List<CollectionSummary> collections;
  final ReadingProgress? progress;
  final int favoriteSceneCount;
  final Map<String, int> downloadStatusCounts;
  final List<DownloadEntry> downloadEntries;
}
