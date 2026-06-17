part of '../library_repository.dart';

/// Guest → cloud migration: summarizing local-only data and importing the full
/// local snapshot to the server on first login.
extension LibraryGuestMigration on LibraryRepository {
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
    final bookmarkLinks = _localBookmarkLinks()
        .map(
          (link) => {
            'bookmark': {
              'source_name': link.bookmark.sourceName,
              'comic_slug': link.bookmark.slug,
            },
            'linked_comic': {
              'source_name': link.linked.sourceName,
              'comic_slug': link.linked.slug,
            },
            'confidence': link.confidence,
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
    final history = _localHistory()
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

    final response = await _api.post<Map<String, dynamic>>(
      '/library/sync/import',
      data: {
        'bookmarks': bookmarks,
        'bookmark_links': bookmarkLinks,
        'collections': collections,
        'progress': progress,
        'history': history,
        'completed_chapters': completedChapters,
        'favorite_scenes': scenes,
        'downloads': downloads,
        if (shouldImportReaderPrefs)
          'reader_preferences': Map<String, dynamic>.from(readerPrefs),
        if (readingSeconds > 0) 'reading_time_seconds': readingSeconds,
      },
    );
    final syncBookmarkIds =
        (response.data?['completion_sync_bookmark_ids'] as List?)
            ?.whereType<num>()
            .map((item) => item.toInt())
            .toList() ??
        const <int>[];
    await _synchronizeBookmarkLinkCompletions(syncBookmarkIds);
    await _deleteGuestProgressEntries(guestProgressEntries);
    await _deleteImportedCompletedChapters(completedChapters);
    await _store.library.delete('bookmarks');
    await _store.library.delete('bookmark_links');
    await _store.library.delete('collections');
    await _store.library.delete('history_entries');
    await _store.library.delete('favorite_scenes');
    await _store.library.delete('downloads');
    if (shouldImportReaderPrefs) {
      await _store.settings.delete('reader_preferences');
      await LocalStateMetadata.clearReaderPreferencesOwner(_store);
    }
    await _store.settings.delete(_guestReadingTimeKey);
    await _store.settings.delete('guest_cloud_migration_skipped');
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
}
