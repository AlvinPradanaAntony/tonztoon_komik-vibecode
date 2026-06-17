part of '../library_repository.dart';

/// Favorite scenes, download entries, reader preferences, and reading-time
/// accounting — the remaining per-feature library data access.
extension LibrarySceneDownloads on LibraryRepository {
  Future<List<FavoriteScene>> getFavoriteScenes() async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>(
        '/library/favorite-scenes',
      );
      return (response.data ?? const [])
          .whereType<Map>()
          .map(
            (item) => FavoriteScene.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    }
    return _localFavoriteScenes();
  }

  Future<void> saveFavoriteScene({
    required ComicSummary comic,
    required double chapterNumber,
    required int pageItemIndex,
    required String imageUrl,
  }) async {
    if (await _isLoggedIn) {
      await _api.post<Map<String, dynamic>>(
        '/library/favorite-scenes',
        data: {
          'source_name': comic.sourceName,
          'comic_slug': comic.slug,
          'chapter_number': chapterNumber,
          'page_item_index': pageItemIndex,
          'image_url': imageUrl,
        },
      );
      return;
    }

    final scenes = _localFavoriteScenes();
    scenes.removeWhere(
      (scene) =>
          scene.comic.key == comic.key &&
          scene.chapterNumber == chapterNumber &&
          scene.pageItemIndex == pageItemIndex,
    );
    final nextId = scenes.isEmpty
        ? 1
        : scenes.map((item) => item.id).reduce((a, b) => a > b ? a : b) + 1;
    scenes.add(
      FavoriteScene(
        id: nextId,
        comic: LibraryComicRef.fromSummary(comic),
        chapterNumber: chapterNumber,
        pageItemIndex: pageItemIndex,
        imageUrl: imageUrl,
      ),
    );
    await _store.library.put(
      'favorite_scenes',
      scenes.map((scene) => scene.toJson()).toList(),
    );
  }

  Future<void> deleteFavoriteScene(int sceneId) async {
    if (await _isLoggedIn) {
      await _api.delete<Map<String, dynamic>>(
        '/library/favorite-scenes/$sceneId',
      );
      return;
    }

    final scenes = _localFavoriteScenes()
        .where((scene) => scene.id != sceneId)
        .toList();
    await _store.library.put(
      'favorite_scenes',
      scenes.map((scene) => scene.toJson()).toList(),
    );
  }

  Future<List<ReadingProgress>> getHistory() async {
    return getHistoryPage(page: 1, pageSize: 20);
  }

  Future<List<ReadingProgress>> getHistoryPage({
    required int page,
    required int pageSize,
  }) async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>(
        '/library/history',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return (response.data ?? const [])
          .whereType<Map>()
          .map(
            (item) => ReadingProgress.fromLibraryJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }
    final start = (page - 1) * pageSize;
    final history = _localHistory();
    return history.skip(start).take(pageSize).toList();
  }

  Future<List<DownloadEntry>> getDownloads() async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>('/library/downloads');
      return (response.data ?? const [])
          .whereType<Map>()
          .map(
            (item) => DownloadEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    }
    return _localDownloads();
  }

  Future<void> enqueueDownloadBatch(
    ComicSummary comic,
    List<double>? chapterNumbers,
  ) async {
    if (await _isLoggedIn) {
      await _api.post<Map<String, dynamic>>(
        '/library/downloads/batch',
        data: {
          'source_name': comic.sourceName,
          'comic_slug': comic.slug,
          'chapter_numbers': chapterNumbers,
          'status': 'pending',
        },
      );
      return;
    }

    final downloads = _localDownloads();
    final ref = LibraryComicRef.fromSummary(comic);
    final chapters = chapterNumbers ?? const <double>[];
    var nextId = downloads.isEmpty
        ? 1
        : downloads.map((item) => item.id).reduce((a, b) => a > b ? a : b) + 1;
    for (final chapter in chapters) {
      downloads.removeWhere(
        (item) => item.comic.key == comic.key && item.chapterNumber == chapter,
      );
      downloads.add(
        DownloadEntry(
          id: nextId++,
          comic: ref,
          chapterNumber: chapter,
          status: 'pending',
        ),
      );
    }
    await _store.library.put(
      'downloads',
      downloads.map((download) => download.toJson()).toList(),
    );
  }

  Future<void> upsertDownloadEntryStatus({
    required LibraryComicRef comic,
    required double chapterNumber,
    required String status,
    String? lastError,
  }) async {
    if (await _isLoggedIn) {
      final data = <String, dynamic>{
        'source_name': comic.sourceName,
        'comic_slug': comic.slug,
        'chapter_number': chapterNumber,
        'status': status,
      };
      if (lastError != null) {
        data['last_error'] = lastError;
      }
      await _api.put<Map<String, dynamic>>(
        '/library/downloads/${comic.sourceName}/comics/${comic.slug}/chapters/$chapterNumber',
        data: data,
      );
      return;
    }

    final downloads = _localDownloads();
    final index = downloads.indexWhere(
      (item) =>
          item.comic.key == comic.key && item.chapterNumber == chapterNumber,
    );
    final nextId = downloads.isEmpty
        ? 1
        : downloads.map((item) => item.id).reduce((a, b) => a > b ? a : b) + 1;
    final entry = DownloadEntry(
      id: index >= 0 ? downloads[index].id : nextId,
      comic: comic,
      chapterNumber: chapterNumber,
      status: status,
      lastError: lastError,
    );
    if (index >= 0) {
      downloads[index] = entry;
    } else {
      downloads.add(entry);
    }
    await _store.library.put(
      'downloads',
      downloads.map((download) => download.toJson()).toList(),
    );
  }

  Future<void> deleteDownloadEntry(DownloadEntry entry) async {
    if (await _isLoggedIn) {
      await _api.delete<Map<String, dynamic>>(
        '/library/downloads/${entry.comic.sourceName}/comics/${entry.comic.slug}/chapters/${entry.chapterNumber}',
      );
      return;
    }

    final downloads = _localDownloads()
        .where(
          (item) =>
              item.comic.key != entry.comic.key ||
              item.chapterNumber != entry.chapterNumber,
        )
        .toList();
    await _store.library.put(
      'downloads',
      downloads.map((download) => download.toJson()).toList(),
    );
  }

  Future<int?> getReadingTimeSeconds() async {
    if (!await _isLoggedIn) return null;
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/library/reading-time',
      );
      return _readInt(response.data?['total_reading_seconds']);
    } catch (_) {
      return null;
    }
  }

  Future<int?> addReadingTimeDeltaSeconds(int deltaSeconds) async {
    if (deltaSeconds <= 0 || !await _isLoggedIn) return null;
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/library/reading-time',
        data: {'delta_seconds': deltaSeconds},
      );
      return _readInt(response.data?['total_reading_seconds']);
    } catch (_) {
      return null;
    }
  }
}
