import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/comic.dart';
import '../models/source_info.dart';

class CatalogRepository {
  CatalogRepository(this._api, this._store);

  final TonztoonApi _api;
  final LocalStore _store;
  static const _genresCacheKey = 'genres';
  final Map<String, List<ComicSummary>> _comicSectionCache = {};

  Future<List<SourceInfo>> getSources() async {
    const cacheKey = 'sources';
    try {
      final response = await _api.get<List<dynamic>>('/sources');
      final items = (response.data ?? const [])
          .whereType<Map>()
          .map((item) => SourceInfo.fromJson(Map<String, dynamic>.from(item)))
          .where((source) => source.enabled)
          .toList();
      await _store.cache.put(
        cacheKey,
        items
            .map(
              (source) => {
                'id': source.id,
                'label': source.label,
                'base_url': source.baseUrl,
                'enabled': source.enabled,
                'db_comic_count': source.dbComicCount,
              },
            )
            .toList(),
      );
      return items;
    } catch (_) {
      final cached = _store.cache.get(cacheKey);
      if (cached is List) {
        return cached
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => SourceInfo.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      rethrow;
    }
  }

  Future<List<Genre>> getGenres() async {
    final cached = getCachedGenres();
    if (cached.isNotEmpty) return cached;

    return refreshGenres();
  }

  List<Genre> getCachedGenres() {
    final cached = _store.cache.get(_genresCacheKey);
    if (cached is! List) return const [];
    return cached
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => Genre.fromJson(Map<String, dynamic>.from(item)))
        .where((genre) => genre.name.trim().isNotEmpty)
        .toList();
  }

  Future<List<Genre>> refreshGenres() async {
    try {
      final response = await _api.get<List<dynamic>>('/genres');
      final items = (response.data ?? const [])
          .whereType<Map>()
          .map((item) => Genre.fromJson(Map<String, dynamic>.from(item)))
          .where((genre) => genre.name.trim().isNotEmpty)
          .toList();
      await _store.cache.put(_genresCacheKey, _encodeGenres(items));
      return items;
    } catch (_) {
      return getCachedGenres();
    }
  }

  List<Map<String, dynamic>> _encodeGenres(List<Genre> genres) {
    return genres
        .map(
          (genre) => {'id': genre.id, 'name': genre.name, 'slug': genre.slug},
        )
        .toList();
  }

  Future<List<ComicSummary>> getLatest(
    String sourceName, {
    int page = 1,
    int pageSize = 20,
    String? type,
    String? genre,
    String? sort,
  }) {
    return _getComicList(
      '/sources/$sourceName/comics/latest',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (type != null && type.trim().isNotEmpty)
          'type': type.trim().toLowerCase(),
        if (genre != null && genre.trim().isNotEmpty)
          'genre': genre.trim().toLowerCase(),
        if (sort != null && sort.trim().isNotEmpty)
          'sort': sort.trim().toLowerCase(),
      },
    );
  }

  Future<List<ComicSummary>> getPopular(
    String sourceName, {
    int page = 1,
    int pageSize = 20,
    String? type,
    String? status,
    String? genre,
    String? sort,
  }) {
    return _getComicList(
      '/sources/$sourceName/comics/popular',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (type != null && type.trim().isNotEmpty)
          'type': type.trim().toLowerCase(),
        if (status != null && status.trim().isNotEmpty)
          'status': status.trim().toLowerCase(),
        if (genre != null && genre.trim().isNotEmpty)
          'genre': genre.trim().toLowerCase(),
        if (sort != null && sort.trim().isNotEmpty)
          'sort': sort.trim().toLowerCase(),
      },
    );
  }

  Future<List<ComicSummary>> getRecommendations(
    String sourceName, {
    int limit = 4,
  }) {
    return _getComicList(
      '/sources/$sourceName/comics/recommendations',
      queryParameters: {'limit': limit},
    );
  }

  Future<List<ComicSummary>> getTopRanking(
    String sourceName, {
    int limit = 10,
    String? type,
  }) {
    return _getComicList(
      '/sources/$sourceName/comics/top-ranking',
      queryParameters: {
        'limit': limit,
        if (type != null && type.trim().isNotEmpty)
          'type': type.trim().toLowerCase(),
      },
    );
  }

  List<ComicSummary> getCachedComicSection(
    String sourceName, {
    required bool popular,
  }) {
    return List.unmodifiable(
      _comicSectionCache[_comicSectionCacheKey(sourceName, popular)] ??
          const [],
    );
  }

  bool hasCachedComicSection(String sourceName, {required bool popular}) {
    return _comicSectionCache.containsKey(
      _comicSectionCacheKey(sourceName, popular),
    );
  }

  void cacheComicSection(
    String sourceName, {
    required bool popular,
    required List<ComicSummary> comics,
  }) {
    _comicSectionCache[_comicSectionCacheKey(sourceName, popular)] = [
      ...comics,
    ];
  }

  String _comicSectionCacheKey(String sourceName, bool popular) {
    return '${popular ? 'popular' : 'latest'}|${sourceName.trim()}';
  }

  Future<LatestComicStats> getLatestStats(String sourceName) async {
    final path = '/sources/$sourceName/comics/latest/stats';
    const queryParameters = {'period_days': 7};
    final cacheKey = _latestStatsCacheKey(path, queryParameters);
    try {
      final response = await _api.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data ?? const {};
      await _store.cache.put(cacheKey, {
        'data': data,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      });
      return LatestComicStats.fromJson(data);
    } catch (_) {
      final cached = getCachedLatestStats(sourceName);
      if (cached != null) return cached;
      rethrow;
    }
  }

  LatestComicStats? getCachedLatestStats(String sourceName) {
    final path = '/sources/$sourceName/comics/latest/stats';
    const queryParameters = {'period_days': 7};
    final cached = _store.cache.get(
      _latestStatsCacheKey(path, queryParameters),
    );
    if (cached is! Map) return null;
    final data = cached['data'];
    if (data is Map) {
      return LatestComicStats.fromJson(Map<String, dynamic>.from(data));
    }
    // Kompatibel dengan cache yang ditulis versi aplikasi sebelumnya.
    return LatestComicStats.fromJson(Map<String, dynamic>.from(cached));
  }

  bool shouldRefreshLatestStats(
    String sourceName, {
    Duration maxAge = const Duration(hours: 1),
  }) {
    final path = '/sources/$sourceName/comics/latest/stats';
    const queryParameters = {'period_days': 7};
    final cached = _store.cache.get(
      _latestStatsCacheKey(path, queryParameters),
    );
    if (cached is! Map || cached['data'] is! Map) return true;
    final cachedAt = DateTime.tryParse(cached['cached_at'] as String? ?? '');
    if (cachedAt == null) return true;
    return DateTime.now().toUtc().difference(cachedAt.toUtc()) >= maxAge;
  }

  String _latestStatsCacheKey(String path, Map<String, dynamic> parameters) {
    return 'latest-comic-stats|$path|$parameters';
  }

  Future<SourceComicPage> getSourceComics({
    required String? sourceName,
    required int page,
    int pageSize = 40,
    String? type,
    String? status,
    String? genre,
    String? sort,
  }) async {
    final queryParameters = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      if (type != null && type.trim().isNotEmpty)
        'type': type.trim().toLowerCase(),
      if (status != null && status.trim().isNotEmpty)
        'status': status.trim().toLowerCase(),
      if (genre != null && genre.trim().isNotEmpty)
        'genre': genre.trim().toLowerCase(),
      if (sort != null && sort.trim().isNotEmpty)
        'sort': sort.trim().toLowerCase(),
    };
    final source = sourceName?.trim();
    final path = source == null || source.isEmpty
        ? '/comics'
        : '/sources/$source/comics';
    final cacheKey = 'source-comics|$path|$queryParameters';
    try {
      final response = await _api.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data ?? const {};
      await _store.cache.put(cacheKey, data);
      return SourceComicPage.fromJson(data);
    } catch (_) {
      final cached = _store.cache.get(cacheKey);
      if (cached is Map) {
        return SourceComicPage.fromJson(Map<String, dynamic>.from(cached));
      }
      rethrow;
    }
  }

  Future<SourceComicPage> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const SourceComicPage(
        items: [],
        total: 0,
        page: 0,
        pageSize: 0,
        totalPages: 0,
      );
    }

    final queryParameters = {
      'q': trimmedQuery,
      'page': page,
      'page_size': pageSize,
    };
    final cacheKey = 'comic-search|/search|$queryParameters';
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/search',
        queryParameters: queryParameters,
      );
      final data = response.data ?? const {};
      await _store.cache.put(cacheKey, data);
      return SourceComicPage.fromJson(data);
    } catch (_) {
      final cached = _store.cache.get(cacheKey);
      if (cached is Map) {
        return SourceComicPage.fromJson(Map<String, dynamic>.from(cached));
      }
      rethrow;
    }
  }

  Future<List<ComicSummary>> _getComicList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final cacheKey = 'comic-list|$path|${queryParameters ?? const {}}';
    try {
      final response = await _api.get<List<dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data ?? const [];
      await _store.cache.put(cacheKey, data);
      return data
          .whereType<Map>()
          .map((item) => ComicSummary.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      final cached = _store.cache.get(cacheKey);
      if (cached is List) {
        return cached
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (item) => ComicSummary.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
      rethrow;
    }
  }

  Future<ComicDetail> getComicDetail(String sourceName, String slug) async {
    final cacheKey = 'comic|$sourceName|$slug';
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/sources/$sourceName/comics/$slug',
      );
      final data = response.data ?? const {};
      await _store.cache.put(cacheKey, data);
      return ComicDetail.fromJson(data);
    } catch (_) {
      final cached = _store.cache.get(cacheKey);
      if (cached is Map) {
        return ComicDetail.fromJson(Map<String, dynamic>.from(cached));
      }
      rethrow;
    }
  }

  Future<List<ChapterListItem>> getChapters(
    String sourceName,
    String slug,
  ) async {
    final cacheKey = 'chapters|$sourceName|$slug';
    try {
      final response = await _api.get<List<dynamic>>(
        '/sources/$sourceName/comics/$slug/chapters',
      );
      final data = response.data ?? const [];
      await _store.cache.put(cacheKey, data);
      return data
          .whereType<Map>()
          .map(
            (item) => ChapterListItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      final cached = _store.cache.get(cacheKey);
      if (cached is List) {
        return cached
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (item) =>
                  ChapterListItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
      rethrow;
    }
  }

  Future<ChapterPayload> getChapter(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/sources/$sourceName/comics/$slug/chapters/${formatChapterNumber(chapterNumber)}',
    );
    if (response.statusCode == 202) {
      final data = response.data ?? const {};
      final detail = data['detail'];
      final detailData = detail is Map
          ? Map<String, dynamic>.from(detail)
          : const <String, dynamic>{};
      throw ApiException(
        detailData['message'] as String? ??
            data['message'] as String? ??
            'Chapter sedang disiapkan. Silakan tunggu beberapa saat.',
        statusCode: 202,
      );
    }
    return ChapterPayload.fromJson(response.data ?? const {});
  }
}

class SourceComicPage {
  const SourceComicPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory SourceComicPage.fromJson(Map<String, dynamic> json) {
    return SourceComicPage(
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => ComicSummary.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 0,
      totalPages: json['total_pages'] as int? ?? 1,
    );
  }

  final List<ComicSummary> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  bool get hasNextPage => page < totalPages;
}
