import '../core/storage.dart';
import '../models/progress.dart';

class LocalStateMetadata {
  const LocalStateMetadata._();

  static const _authProgressCacheKeysKey = 'auth_progress_cache_keys';
  static const _authCompletedChapterCacheKeysKey =
      'auth_completed_chapter_cache_keys';
  static const _readerPreferencesOwnerKey = 'reader_preferences_owner';
  static const _authCacheOwner = 'auth_cache';

  static Future<void> markAuthenticatedProgressCache(
    LocalStore store,
    ReadingProgress progress,
  ) async {
    await _addStringSetValue(
      store,
      _authProgressCacheKeysKey,
      progress.storageKey,
    );
    if (progress.isCompleted) {
      await _addStringSetValue(
        store,
        _authCompletedChapterCacheKeysKey,
        completedChapterKey(
          progress.sourceName,
          progress.comicSlug,
          progress.chapterNumber,
        ),
      );
    }
  }

  static Future<void> clearAuthenticatedProgressCache(
    LocalStore store,
    ReadingProgress progress,
  ) async {
    await _removeStringSetValue(
      store,
      _authProgressCacheKeysKey,
      progress.storageKey,
    );
    if (progress.isCompleted) {
      await _removeStringSetValue(
        store,
        _authCompletedChapterCacheKeysKey,
        completedChapterKey(
          progress.sourceName,
          progress.comicSlug,
          progress.chapterNumber,
        ),
      );
    }
  }

  static bool isAuthenticatedProgressCache(LocalStore store, String key) {
    return _readStringSet(store, _authProgressCacheKeysKey).contains(key);
  }

  static bool isAuthenticatedCompletedChapterCache(
    LocalStore store,
    String sourceName,
    String comicSlug,
    double chapterNumber,
  ) {
    return _readStringSet(
      store,
      _authCompletedChapterCacheKeysKey,
    ).contains(completedChapterKey(sourceName, comicSlug, chapterNumber));
  }

  static String completedChapterKey(
    String sourceName,
    String comicSlug,
    double chapterNumber,
  ) {
    return '$sourceName|$comicSlug|$chapterNumber';
  }

  static Future<void> markReaderPreferencesAuthenticated(
    LocalStore store,
  ) async {
    await store.settings.put(_readerPreferencesOwnerKey, _authCacheOwner);
  }

  static Future<void> clearReaderPreferencesOwner(LocalStore store) async {
    await store.settings.delete(_readerPreferencesOwnerKey);
  }

  static bool isReaderPreferencesAuthenticated(LocalStore store) {
    return store.settings.get(_readerPreferencesOwnerKey) == _authCacheOwner;
  }

  static Set<String> _readStringSet(LocalStore store, String key) {
    final raw = store.settings.get(key);
    if (raw is! List) return <String>{};
    return raw.whereType<String>().toSet();
  }

  static Future<void> _addStringSetValue(
    LocalStore store,
    String key,
    String value,
  ) async {
    final values = _readStringSet(store, key)..add(value);
    await store.settings.put(key, values.toList()..sort());
  }

  static Future<void> _removeStringSetValue(
    LocalStore store,
    String key,
    String value,
  ) async {
    final values = _readStringSet(store, key)..remove(value);
    if (values.isEmpty) {
      await store.settings.delete(key);
      return;
    }
    await store.settings.put(key, values.toList()..sort());
  }
}
