import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/comic.dart';
import '../models/source_info.dart';

class CatalogRepository {
  CatalogRepository(this._api, this._store);

  final TonztoonApi _api;
  final LocalStore _store;

  Future<List<SourceInfo>> getSources() async {
    const cacheKey = 'sources';
    try {
      final response = await _api.get<List<dynamic>>('/sources');
      final items = (response.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SourceInfo.fromJson)
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

  Future<List<ComicSummary>> getLatest(String sourceName) {
    return _getComicList('/sources/$sourceName/comics/latest');
  }

  Future<List<ComicSummary>> getPopular(String sourceName) {
    return _getComicList('/sources/$sourceName/comics/popular');
  }

  Future<List<ComicSummary>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    return _getComicList('/search', queryParameters: {'q': query.trim()});
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
          .whereType<Map<String, dynamic>>()
          .map(ComicSummary.fromJson)
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
          .whereType<Map<String, dynamic>>()
          .map(ChapterListItem.fromJson)
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
    return ChapterPayload.fromJson(response.data ?? const {});
  }
}
