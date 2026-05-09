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
    this.slug = '',
    this.sourceName = 'komiku',
    this.coverImageUrl,
    this.status,
    this.type,
    this.rating,
    this.totalView,
    this.latestChapterNumber,
    this.genres = const [],
  });

  factory ComicSummary.fromJson(Map<String, dynamic> json) {
    return ComicSummary(
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      coverImageUrl: json['cover_image_url'] as String?,
      status: json['status'] as String?,
      type: json['type'] as String?,
      rating: _readRating(json),
      totalView: json['total_view'] as int?,
      latestChapterNumber: (json['latest_chapter_number'] as num?)?.toDouble(),
      genres: ((json['genres'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Genre.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
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
    'genres': genres
        .map(
          (genre) => {'id': genre.id, 'name': genre.name, 'slug': genre.slug},
        )
        .toList(),
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
  final List<Genre> genres;

  @override
  bool operator ==(Object other) {
    return other is ComicSummary &&
        other.sourceName == sourceName &&
        other.slug == slug;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug);
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
      rating: _readRating(json),
      totalView: json['total_view'] as int?,
      genres: ((json['genres'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Genre.fromJson(Map<String, dynamic>.from(item)))
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
          .whereType<Map>()
          .map(
            (item) =>
                ChapterImageItem.fromJson(Map<String, dynamic>.from(item)),
          )
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

String comicRouteSource(ComicSummary comic) {
  return comic.sourceName.trim().isEmpty ? 'komiku' : comic.sourceName.trim();
}

String comicRouteSlug(ComicSummary comic) {
  final slug = comic.slug.trim();
  if (slug.isNotEmpty) return slug;
  return comic.title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

double? _readRating(Map<String, dynamic> json) {
  for (final key in const ['rating', 'rating_score', 'score', 'user_rate']) {
    final value = _readDouble(json[key]);
    if (value == null || value < 0) continue;
    if (value <= 10) return value;
    if (value <= 100) return value / 10;
  }
  return null;
}

double? _readDouble(Object? value) {
  return switch (value) {
    num value => value.toDouble(),
    String value => double.tryParse(value.trim().replaceAll(',', '.')),
    _ => null,
  };
}
