class Genre {
  const Genre({required this.id, required this.name, required this.slug});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String slug;
}

class ComicSummary {
  const ComicSummary({
    required this.title,
    required this.slug,
    required this.sourceName,
    this.coverImageUrl,
    this.status,
    this.type,
    this.rating,
    this.totalView,
    this.latestChapterNumber,
  });

  factory ComicSummary.fromJson(Map<String, dynamic> json) {
    return ComicSummary(
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      coverImageUrl: json['cover_image_url'] as String?,
      status: json['status'] as String?,
      type: json['type'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalView: json['total_view'] as int?,
      latestChapterNumber: (json['latest_chapter_number'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'slug': slug,
    'source_name': sourceName,
    'cover_image_url': coverImageUrl,
    'status': status,
    'type': type,
    'rating': rating,
    'total_view': totalView,
    'latest_chapter_number': latestChapterNumber,
  };

  final String title;
  final String slug;
  final String sourceName;
  final String? coverImageUrl;
  final String? status;
  final String? type;
  final double? rating;
  final int? totalView;
  final double? latestChapterNumber;
}

class ComicDetail {
  const ComicDetail({
    required this.id,
    required this.title,
    required this.slug,
    required this.sourceName,
    required this.sourceUrl,
    required this.genres,
    required this.totalChapters,
    this.alternativeTitles,
    this.coverImageUrl,
    this.author,
    this.artist,
    this.status,
    this.type,
    this.synopsis,
    this.rating,
    this.totalView,
  });

  factory ComicDetail.fromJson(Map<String, dynamic> json) {
    return ComicDetail(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
      alternativeTitles: json['alternative_titles'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      author: json['author'] as String?,
      artist: json['artist'] as String?,
      status: json['status'] as String?,
      type: json['type'] as String?,
      synopsis: json['synopsis'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalView: json['total_view'] as int?,
      genres: ((json['genres'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Genre.fromJson)
          .toList(),
      totalChapters: json['total_chapters'] as int? ?? 0,
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

  final int id;
  final String title;
  final String slug;
  final String sourceName;
  final String sourceUrl;
  final String? alternativeTitles;
  final String? coverImageUrl;
  final String? author;
  final String? artist;
  final String? status;
  final String? type;
  final String? synopsis;
  final double? rating;
  final int? totalView;
  final List<Genre> genres;
  final int totalChapters;
}

class ChapterListItem {
  const ChapterListItem({
    required this.chapterNumber,
    required this.createdAt,
    required this.totalImages,
    required this.detailUrl,
    this.title,
    this.releaseDate,
  });

  factory ChapterListItem.fromJson(Map<String, dynamic> json) {
    return ChapterListItem(
      chapterNumber: (json['chapter_number'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String?,
      detailUrl: json['detail_url'] as String? ?? '',
      releaseDate: DateTime.tryParse(json['release_date'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      totalImages: json['total_images'] as int? ?? 0,
    );
  }

  final double chapterNumber;
  final String? title;
  final String detailUrl;
  final DateTime? releaseDate;
  final DateTime createdAt;
  final int totalImages;
}

class ChapterImageItem {
  const ChapterImageItem({required this.page, required this.url});

  factory ChapterImageItem.fromJson(Map<String, dynamic> json) {
    return ChapterImageItem(
      page: json['page'] as int? ?? 0,
      url: json['url'] as String? ?? '',
    );
  }

  final int page;
  final String url;
}

class ChapterPayload {
  const ChapterPayload({
    required this.sourceName,
    required this.chapterNumber,
    required this.images,
    required this.total,
  });

  factory ChapterPayload.fromJson(Map<String, dynamic> json) {
    return ChapterPayload(
      sourceName: json['source_name'] as String? ?? '',
      chapterNumber: (json['chapter_number'] as num?)?.toDouble() ?? 0,
      images: ((json['images'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChapterImageItem.fromJson)
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }

  final String sourceName;
  final double chapterNumber;
  final List<ChapterImageItem> images;
  final int total;
}

String formatChapterNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}
