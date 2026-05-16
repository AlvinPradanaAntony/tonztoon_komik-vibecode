import '../core/api_client.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/comic.dart';
import '../models/library.dart';
import '../models/progress.dart';
import 'local_state_metadata.dart';

class LibraryRepository {
  LibraryRepository(this._api, this._tokenStore, this._store);

  static const _guestReadingTimeKey = 'reading_time_total_seconds_guest';

  final TonztoonApi _api;
  final TokenStore _tokenStore;
  final LocalStore _store;

  Future<bool> get _isLoggedIn async {
    final token = await _tokenStore.readAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<LibraryComicState> getComicState(ComicSummary comic) async {
    if (await _isLoggedIn) {
      try {
        final response = await _api.get<Map<String, dynamic>>(
          '/library/state/${comic.sourceName}/comics/${comic.slug}',
        );
        return _mergeLocalComicState(
          LibraryComicState.fromJson(response.data ?? const {}),
          comic,
        );
      } catch (_) {
        return _localComicState(comic);
      }
    }

    return _localComicState(comic);
  }

  LibraryComicState _mergeLocalComicState(
    LibraryComicState remote,
    ComicSummary comic,
  ) {
    final local = _localComicState(comic);
    final completedChapterNumbers = <double>{
      ...remote.completedChapterNumbers,
      ...local.completedChapterNumbers,
    }.toList()..sort();
    final remoteProgress = remote.progress;
    final localProgress = local.progress;
    final progress =
        localProgress != null &&
            (remoteProgress == null ||
                localProgress.lastReadAt.isAfter(remoteProgress.lastReadAt))
        ? localProgress
        : remoteProgress;

    return LibraryComicState(
      comic: remote.comic,
      bookmarked: remote.bookmarked,
      collections: remote.collections,
      progress: progress,
      completedChapterNumbers: completedChapterNumbers,
      favoriteSceneCount: remote.favoriteSceneCount,
      downloadStatusCounts: remote.downloadStatusCounts,
      downloadEntries: remote.downloadEntries,
    );
  }

  LibraryComicState _localComicState(ComicSummary comic) {
    final bookmark = _localBookmarks()[comic.key] != null;
    final collections = _localCollections()
        .where(
          (collection) => collection.items.any((item) => item.key == comic.key),
        )
        .map(
          (collection) => CollectionSummary(
            id: collection.id,
            name: collection.name,
            totalItems: collection.items.length,
          ),
        )
        .toList();
    final progressRaw = _store.progress.get(
      ReadingProgress.key(comic.sourceName, comic.slug),
    );
    return LibraryComicState(
      comic: LibraryComicRef.fromSummary(comic),
      bookmarked: bookmark,
      collections: collections,
      progress: progressRaw is Map
          ? ReadingProgress.fromLocalJson(progressRaw)
          : null,
      completedChapterNumbers: _localCompletedChapterNumbers(
        comic.sourceName,
        comic.slug,
      ),
      favoriteSceneCount: _localFavoriteScenes()
          .where((scene) => scene.comic.key == comic.key)
          .length,
      downloadStatusCounts: _downloadCountsFor(comic.key),
      downloadEntries: _localDownloads()
          .where((download) => download.comic.key == comic.key)
          .toList(),
    );
  }

  Future<List<LibraryComicRef>> getBookmarks() async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>('/library/bookmarks');
      return (response.data ?? const []).whereType<Map>().map((json) {
        final comicRaw = json['comic'];
        final comic = comicRaw is Map
            ? Map<String, dynamic>.from(comicRaw)
            : const <String, dynamic>{};
        return LibraryComicRef.fromJson(comic);
      }).toList();
    }
    return _localBookmarks().values.toList();
  }

  Future<bool> toggleBookmark(ComicSummary comic, bool bookmarked) async {
    if (await _isLoggedIn) {
      if (bookmarked) {
        await _api.delete<Map<String, dynamic>>(
          '/library/bookmarks/${comic.sourceName}/comics/${comic.slug}',
        );
        return false;
      }
      await _api.put<Map<String, dynamic>>(
        '/library/bookmarks/${comic.sourceName}/comics/${comic.slug}',
      );
      return true;
    }

    final bookmarks = _localBookmarks();
    if (bookmarked) {
      bookmarks.remove(comic.key);
      await _store.library.put('bookmarks', _encodeComicRefMap(bookmarks));
      return false;
    }
    bookmarks[comic.key] = LibraryComicRef.fromSummary(comic);
    await _store.library.put('bookmarks', _encodeComicRefMap(bookmarks));
    return true;
  }

  Future<List<CollectionSummary>> getCollections() async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>('/library/collections');
      return (response.data ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CollectionSummary.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    }
    return _localCollections()
        .map(
          (collection) => CollectionSummary(
            id: collection.id,
            name: collection.name,
            totalItems: collection.items.length,
          ),
        )
        .toList();
  }

  Future<CollectionDetail> getCollectionDetail(int collectionId) async {
    if (await _isLoggedIn) {
      final response = await _api.get<Map<String, dynamic>>(
        '/library/collections/$collectionId',
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collection = _localCollections()
        .where((item) => item.id == collectionId)
        .firstOrNull;
    if (collection == null) {
      throw ApiException('Collection not found.');
    }
    return collection;
  }

  Future<CollectionDetail> createCollection(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Collection name cannot be empty.');
    }
    if (await _isLoggedIn) {
      final response = await _api.post<Map<String, dynamic>>(
        '/library/collections',
        data: {'name': trimmed},
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    if (collections.any(
      (item) => item.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw ApiException('Collection name already exists.');
    }
    final nextId = collections.isEmpty
        ? 1
        : collections.map((item) => item.id).reduce((a, b) => a > b ? a : b) +
              1;
    final created = CollectionDetail(
      id: nextId,
      name: trimmed,
      totalItems: 0,
      items: const [],
    );
    collections.add(created);
    await _saveLocalCollections(collections);
    return created;
  }

  Future<CollectionDetail> renameCollection(
    int collectionId,
    String name,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Collection name cannot be empty.');
    }
    if (await _isLoggedIn) {
      final response = await _api.patch<Map<String, dynamic>>(
        '/library/collections/$collectionId',
        data: {'name': trimmed},
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    if (collections.any(
      (item) =>
          item.id != collectionId &&
          item.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw ApiException('Collection name already exists.');
    }
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index < 0) {
      throw ApiException('Collection not found.');
    }
    final current = collections[index];
    final updated = CollectionDetail(
      id: current.id,
      name: trimmed,
      totalItems: current.items.length,
      items: current.items,
    );
    collections[index] = updated;
    await _saveLocalCollections(collections);
    return updated;
  }

  Future<void> deleteCollection(int collectionId) async {
    if (await _isLoggedIn) {
      await _api.delete<Map<String, dynamic>>(
        '/library/collections/$collectionId',
      );
      return;
    }

    final collections = _localCollections()
        .where((collection) => collection.id != collectionId)
        .toList();
    await _saveLocalCollections(collections);
  }

  Future<void> setComicCollections(
    ComicSummary comic,
    Set<int> selectedCollectionIds,
  ) async {
    if (await _isLoggedIn) {
      final current = await getComicState(comic);
      final currentIds = current.collections.map((item) => item.id).toSet();
      for (final id in selectedCollectionIds.difference(currentIds)) {
        await _api.put<Map<String, dynamic>>(
          '/library/collections/$id/comics/${comic.sourceName}/${comic.slug}',
        );
      }
      for (final id in currentIds.difference(selectedCollectionIds)) {
        await _api.delete<Map<String, dynamic>>(
          '/library/collections/$id/comics/${comic.sourceName}/${comic.slug}',
        );
      }
      return;
    }

    final collections = _localCollections();
    final ref = LibraryComicRef.fromSummary(comic);
    final updated = collections.map((collection) {
      final items = collection.items
          .where((item) => item.key != comic.key)
          .toList();
      if (selectedCollectionIds.contains(collection.id)) {
        items.add(ref);
      }
      return CollectionDetail(
        id: collection.id,
        name: collection.name,
        totalItems: items.length,
        items: items,
      );
    }).toList();
    await _saveLocalCollections(updated);
  }

  Future<CollectionDetail> addComicToCollection(
    int collectionId,
    ComicSummary comic,
  ) async {
    if (await _isLoggedIn) {
      final response = await _api.put<Map<String, dynamic>>(
        '/library/collections/$collectionId/comics/${comic.sourceName}/${comic.slug}',
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index < 0) {
      throw ApiException('Collection not found.');
    }
    final current = collections[index];
    final items = current.items.where((item) => item.key != comic.key).toList()
      ..add(LibraryComicRef.fromSummary(comic));
    final updated = CollectionDetail(
      id: current.id,
      name: current.name,
      totalItems: items.length,
      items: items,
    );
    collections[index] = updated;
    await _saveLocalCollections(collections);
    return updated;
  }

  Future<CollectionDetail> removeComicFromCollection(
    int collectionId,
    ComicSummary comic,
  ) async {
    if (await _isLoggedIn) {
      final response = await _api.delete<Map<String, dynamic>>(
        '/library/collections/$collectionId/comics/${comic.sourceName}/${comic.slug}',
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index < 0) {
      throw ApiException('Collection not found.');
    }
    final current = collections[index];
    final items = current.items.where((item) => item.key != comic.key).toList();
    final updated = CollectionDetail(
      id: current.id,
      name: current.name,
      totalItems: items.length,
      items: items,
    );
    collections[index] = updated;
    await _saveLocalCollections(collections);
    return updated;
  }

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
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>('/library/history');
      return (response.data ?? const [])
          .whereType<Map>()
          .map(
            (item) => ReadingProgress.fromLibraryJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }
    return _store.progress.values
        .whereType<Map<dynamic, dynamic>>()
        .map(ReadingProgress.fromLocalJson)
        .toList()
      ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
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

  Future<ReaderPreferences> getReaderPreferences() async {
    if (await _isLoggedIn) {
      try {
        final response = await _api.get<Map<String, dynamic>>(
          '/library/reader-preferences',
        );
        final prefs = ReaderPreferences.fromJson(response.data ?? const {});
        await _store.settings.put('reader_preferences', prefs.toJson());
        await LocalStateMetadata.markReaderPreferencesAuthenticated(_store);
        return prefs;
      } catch (_) {
        return _localReaderPreferences();
      }
    }
    return _localReaderPreferences();
  }

  Future<ReaderPreferences> saveReaderPreferences(
    ReaderPreferences prefs,
  ) async {
    final loggedIn = await _isLoggedIn;
    await _store.settings.put('reader_preferences', prefs.toJson());
    if (loggedIn) {
      await LocalStateMetadata.markReaderPreferencesAuthenticated(_store);
      final response = await _api.put<Map<String, dynamic>>(
        '/library/reader-preferences',
        data: prefs.toJson(),
      );
      final saved = ReaderPreferences.fromJson(response.data ?? prefs.toJson());
      await _store.settings.put('reader_preferences', saved.toJson());
      return saved;
    }
    await LocalStateMetadata.clearReaderPreferencesOwner(_store);
    return prefs;
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

  bool hasMigratableLocalData() {
    return getGuestMigrationSummary().isEmpty == false;
  }

  GuestMigrationSummary getGuestMigrationSummary() {
    final readerPrefs = _store.settings.get('reader_preferences');
    return GuestMigrationSummary(
      bookmarks: _localBookmarks().length,
      collections: _localCollections().length,
      progress: _localGuestProgressEntries().length,
      favoriteScenes: _localFavoriteScenes().length,
      downloads: _localDownloads().length,
      hasReaderPreferences:
          readerPrefs is Map &&
          !LocalStateMetadata.isReaderPreferencesAuthenticated(_store),
      readingTimeSeconds: _guestReadingSeconds(),
    );
  }

  bool get migrationSkipped {
    return _store.settings.get('guest_cloud_migration_skipped') == true;
  }

  Future<void> skipMigration() {
    return _store.settings.put('guest_cloud_migration_skipped', true);
  }

  Future<void> importLocalSnapshotToCloud() async {
    if (!await _isLoggedIn) {
      throw ApiException('Login required before migration.');
    }

    final bookmarks = _localBookmarks().values
        .map(
          (comic) => {
            'source_name': comic.sourceName,
            'comic_slug': comic.slug,
          },
        )
        .toList();
    final collections = _localCollections()
        .map(
          (collection) => {
            'name': collection.name,
            'comics': collection.items
                .map(
                  (comic) => {
                    'source_name': comic.sourceName,
                    'comic_slug': comic.slug,
                  },
                )
                .toList(),
          },
        )
        .toList();
    final guestProgressEntries = _localGuestProgressEntries();
    final progress = guestProgressEntries
        .map((entry) => ReadingProgress.fromLocalJson(entry.value))
        .map((item) => item.toProgressPayload())
        .toList();
    final completedChapters = _localCompletedChapterImports();
    final scenes = _localFavoriteScenes()
        .map(
          (scene) => {
            'source_name': scene.comic.sourceName,
            'comic_slug': scene.comic.slug,
            'chapter_number': scene.chapterNumber,
            'page_item_index': scene.pageItemIndex,
            'image_url': scene.imageUrl,
            'note': scene.note,
          },
        )
        .toList();
    final downloads = _localDownloads()
        .map(
          (download) => {
            'source_name': download.comic.sourceName,
            'comic_slug': download.comic.slug,
            'chapter_number': download.chapterNumber,
            'status': download.status,
            'last_error': download.lastError,
          },
        )
        .toList();
    final readerPrefs = _store.settings.get('reader_preferences');
    final shouldImportReaderPrefs =
        readerPrefs is Map &&
        !LocalStateMetadata.isReaderPreferencesAuthenticated(_store);
    final readingSeconds = _guestReadingSeconds();

    await _api.post<Map<String, dynamic>>(
      '/library/sync/import',
      data: {
        'bookmarks': bookmarks,
        'collections': collections,
        'progress': progress,
        'completed_chapters': completedChapters,
        'favorite_scenes': scenes,
        'downloads': downloads,
        if (shouldImportReaderPrefs)
          'reader_preferences': Map<String, dynamic>.from(readerPrefs),
        if (readingSeconds > 0) 'reading_time_seconds': readingSeconds,
      },
    );

    await _deleteGuestProgressEntries(guestProgressEntries);
    await _deleteImportedCompletedChapters(completedChapters);
    await _store.library.delete('bookmarks');
    await _store.library.delete('collections');
    await _store.library.delete('favorite_scenes');
    await _store.library.delete('downloads');
    if (shouldImportReaderPrefs) {
      await _store.settings.delete('reader_preferences');
      await LocalStateMetadata.clearReaderPreferencesOwner(_store);
    }
    await _store.settings.delete(_guestReadingTimeKey);
    await _store.settings.delete('guest_cloud_migration_skipped');
  }

  int _guestReadingSeconds() {
    return _readInt(_store.settings.get(_guestReadingTimeKey)) ?? 0;
  }

  int? _readInt(Object? value) {
    return switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
  }

  Map<String, LibraryComicRef> _localBookmarks() {
    final raw = _store.library.get('bookmarks');
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        LibraryComicRef.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  List<CollectionDetail> _localCollections() {
    final raw = _store.library.get('collections');
    if (raw is! List) return [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => CollectionDetail.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> _saveLocalCollections(List<CollectionDetail> collections) {
    return _store.library.put(
      'collections',
      collections.map((collection) => collection.toJson()).toList(),
    );
  }

  List<FavoriteScene> _localFavoriteScenes() {
    final raw = _store.library.get('favorite_scenes');
    if (raw is! List) return [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => FavoriteScene.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  List<DownloadEntry> _localDownloads() {
    final raw = _store.library.get('downloads');
    if (raw is! List) return [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => DownloadEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Map<String, int> _downloadCountsFor(String comicKey) {
    final counts = <String, int>{};
    for (final item in _localDownloads().where(
      (item) => item.comic.key == comicKey,
    )) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    return counts;
  }

  List<double> _localCompletedChapterNumbers(String sourceName, String slug) {
    final raw = _store.progress.get(
      ReadingProgress.completedChaptersKey(sourceName, slug),
    );
    if (raw is! List) return const [];
    final numbers =
        raw.whereType<num>().map((value) => value.toDouble()).toSet().toList()
          ..sort();
    return numbers;
  }

  List<MapEntry<dynamic, Map<dynamic, dynamic>>> _localGuestProgressEntries() {
    return _store.progress
        .toMap()
        .entries
        .where((entry) {
          if (entry.value is! Map<dynamic, dynamic>) return false;
          return !LocalStateMetadata.isAuthenticatedProgressCache(
            _store,
            entry.key.toString(),
          );
        })
        .map((entry) {
          return MapEntry(entry.key, entry.value as Map<dynamic, dynamic>);
        })
        .toList();
  }

  Future<void> _deleteGuestProgressEntries(
    List<MapEntry<dynamic, Map<dynamic, dynamic>>> entries,
  ) async {
    for (final entry in entries) {
      await _store.progress.delete(entry.key);
    }
  }

  List<Map<String, Object>> _localCompletedChapterImports() {
    final imports = <Map<String, Object>>[];
    for (final entry in _store.progress.toMap().entries) {
      final key = entry.key.toString();
      if (!key.startsWith('completed_chapters|')) continue;
      final parts = key.split('|');
      if (parts.length < 3 || entry.value is! List) continue;
      final sourceName = parts[1];
      final comicSlug = parts.sublist(2).join('|');
      for (final number in (entry.value as List).whereType<num>()) {
        final chapterNumber = number.toDouble();
        if (LocalStateMetadata.isAuthenticatedCompletedChapterCache(
          _store,
          sourceName,
          comicSlug,
          chapterNumber,
        )) {
          continue;
        }
        imports.add({
          'source_name': sourceName,
          'comic_slug': comicSlug,
          'chapter_number': chapterNumber,
        });
      }
    }
    return imports;
  }

  Future<void> _deleteImportedCompletedChapters(
    List<Map<String, Object>> imports,
  ) async {
    final importedKeys = imports
        .map(
          (item) => LocalStateMetadata.completedChapterKey(
            item['source_name'] as String,
            item['comic_slug'] as String,
            item['chapter_number'] as double,
          ),
        )
        .toSet();
    if (importedKeys.isEmpty) return;

    for (final entry in _store.progress.toMap().entries) {
      final key = entry.key.toString();
      if (!key.startsWith('completed_chapters|') || entry.value is! List) {
        continue;
      }
      final parts = key.split('|');
      if (parts.length < 3) continue;
      final sourceName = parts[1];
      final comicSlug = parts.sublist(2).join('|');
      final remaining = (entry.value as List).whereType<num>().where((number) {
        return !importedKeys.contains(
          LocalStateMetadata.completedChapterKey(
            sourceName,
            comicSlug,
            number.toDouble(),
          ),
        );
      }).toList();

      if (remaining.isEmpty) {
        await _store.progress.delete(entry.key);
      } else {
        await _store.progress.put(entry.key, remaining);
      }
    }
  }

  ReaderPreferences _localReaderPreferences() {
    final raw = _store.settings.get('reader_preferences');
    if (raw is Map) {
      return ReaderPreferences.fromJson(raw);
    }
    return const ReaderPreferences();
  }

  Map<String, dynamic> _encodeComicRefMap(Map<String, LibraryComicRef> value) {
    return value.map((key, ref) => MapEntry(key, ref.toJson()));
  }
}

extension on ComicSummary {
  String get key => '$sourceName|$slug';
}
