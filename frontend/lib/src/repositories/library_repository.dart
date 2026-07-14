import 'dart:math' as math;

import '../core/api_client.dart';
import '../core/storage.dart';
import '../utils/string_similarity.dart';
import '../core/token_store.dart';
import '../models/comic.dart';
import '../models/library.dart';
import '../models/progress.dart';
import 'local_state_metadata.dart';

// Per-domain operations live in `part` files under `library/`, implemented as
// extensions on [LibraryRepository]. Because they share this library's scope,
// they can use the repository's private fields/helpers and these top-level
// constants directly, and external importers still see one flat public API.
part 'library/bookmark_links_repository.dart';
part 'library/collections_repository.dart';
part 'library/scenes_downloads_repository.dart';
part 'library/guest_migration_repository.dart';

const _guestReadingTimeKey = 'reading_time_total_seconds_guest';
const _bookmarkCandidatePageSize = 5;
const _bookmarkCandidateMaxAttempts = 3;
const _bookmarkLinkBatchSize = 100;
const _bookmarkCompletionSyncBatchSize = 20;
const _bookmarkLinkMaxAttempts = 3;

/// Data access for everything in the user's library: bookmarks (and their
/// cross-source links), collections, favorite scenes, history, downloads,
/// reader preferences, reading time, and guest→cloud migration.
///
/// Each call transparently targets the remote API when authenticated and falls
/// back to local storage for guests. The class itself holds the shared plumbing
/// (API client, local store, bookmark-scan state, and the `_local*` readers);
/// per-domain methods are split into `part` extensions for readability.
class LibraryRepository {
  LibraryRepository(this._api, this._tokenStore, this._store);

  final TonztoonApi _api;
  final TokenStore _tokenStore;
  final LocalStore _store;
  int _bookmarkCandidateScanOffset = 0;
  bool? _bookmarkCandidateScanAuthenticated;
  bool _bookmarkCandidateScanComplete = false;
  final Map<String, BookmarkLinkCandidate> _bookmarkCandidateScanResults = {};

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
        final remote = LibraryComicState.fromJson(response.data ?? const {});
        await _cacheBookmarkLinksFromState(remote);
        return _mergeLocalComicState(remote, comic);
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
      bookmarkRelation: remote.bookmarkRelation,
      bookmarkOrigin: remote.bookmarkOrigin,
      linkedComics: remote.linkedComics,
      collections: remote.collections,
      progress: progress,
      completedChapterNumbers: completedChapterNumbers,
      favoriteSceneCount: remote.favoriteSceneCount,
      downloadStatusCounts: remote.downloadStatusCounts,
      downloadEntries: remote.downloadEntries,
    );
  }

  LibraryComicState _localComicState(ComicSummary comic) {
    final bookmarks = _localBookmarks();
    final directBookmark = bookmarks[comic.key];
    final links = _localBookmarkLinks();
    _LocalBookmarkLink? linkedEntry;
    for (final link in links) {
      if (link.linked.key == comic.key) {
        linkedEntry = link;
        break;
      }
    }
    final origin = directBookmark ?? linkedEntry?.bookmark;
    final relation = directBookmark != null
        ? BookmarkRelation.direct
        : linkedEntry != null
        ? BookmarkRelation.linked
        : BookmarkRelation.none;
    final linkedComics = origin == null
        ? const <LibraryComicRef>[]
        : [
            if (origin.key != comic.key) origin,
            ...links
                .where(
                  (link) =>
                      link.bookmark.key == origin.key &&
                      link.linked.key != comic.key,
                )
                .map((link) => link.linked),
          ];
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
      bookmarked: origin != null,
      bookmarkRelation: relation,
      bookmarkOrigin: origin,
      linkedComics: linkedComics,
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
    return getBookmarksPage(page: 1, pageSize: 20);
  }

  Future<List<LibraryComicRef>> getBookmarksPage({
    required int page,
    required int pageSize,
    String? type,
    String? status,
    String? sort,
  }) async {
    if (await _isLoggedIn) {
      final queryParameters = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        ...?sort == null ? null : {'sort': sort},
        ...?type == null ? null : {'type': type},
        ...?status == null ? null : {'status': status},
      };
      final response = await _api.get<List<dynamic>>(
        '/library/bookmarks',
        queryParameters: queryParameters,
      );
      return (response.data ?? const []).whereType<Map>().map((json) {
        final comicRaw = json['comic'];
        final comic = comicRaw is Map
            ? Map<String, dynamic>.from(comicRaw)
            : const <String, dynamic>{};
        return LibraryComicRef.fromJson({
          ...comic,
          'linked_comics': json['linked_comics'] ?? const [],
        });
      }).toList();
    }
    final start = (page - 1) * pageSize;
    final links = _localBookmarkLinks();

    final localBookmarks = _localBookmarks().values
        .where((bookmark) {
          final typeMatches =
              type == null || bookmark.type?.toLowerCase() == type;
          final statusMatches =
              status == null || bookmark.status?.toLowerCase() == status;
          final newChapterMatches = sort != 'latest' || bookmark.hasNewChapter;
          return typeMatches && statusMatches && newChapterMatches;
        })
        .toList()
        .reversed
        .toList();
    localBookmarks.sort(
      (a, b) => switch (sort) {
        'az' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'za' => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        _ => _compareBookmarksByLatestUpdate(a, b),
      },
    );

    return localBookmarks.skip(start).take(pageSize).map((bookmark) {
      return LibraryComicRef.fromJson({
        ...bookmark.toJson(),
        'linked_comics': links
            .where((link) => link.bookmark.key == bookmark.key)
            .map((link) => link.linked.toJson())
            .toList(),
      });
    }).toList();
  }

  int _compareBookmarksByLatestUpdate(
    LibraryComicRef first,
    LibraryComicRef second,
  ) {
    if (first.hasNewChapter && !second.hasNewChapter) return -1;
    if (!first.hasNewChapter && second.hasNewChapter) return 1;
    return 0;
  }

  Future<LibrarySummary> getLibrarySummary() async {
    if (await _isLoggedIn) {
      final response = await _api.get<Map<String, dynamic>>('/library/summary');
      return LibrarySummary.fromJson(response.data ?? const {});
    }

    final localBookmarks = _localBookmarks();
    final bookmarkStatusCounts = <String, int>{};
    for (final bookmark in localBookmarks.values) {
      final status = bookmark.status?.trim().toLowerCase();
      if (status == null || status.isEmpty) continue;
      bookmarkStatusCounts[status] = (bookmarkStatusCounts[status] ?? 0) + 1;
    }

    return LibrarySummary(
      counts: LibrarySummaryCounts(
        bookmarks: localBookmarks.length,
        bookmarkStatusCounts: bookmarkStatusCounts,
        collections: _localCollections().length,
        favoriteScenes: _localFavoriteScenes().length,
        history: _localHistory().length,
        downloads: _localDownloads().length,
        continueReading: _localGuestProgressEntries().length,
      ),
      readingTimeSeconds: _guestReadingSeconds(),
    );
  }

  Future<bool> toggleBookmark(ComicSummary comic, bool bookmarked) async {
    if (await _isLoggedIn) {
      if (bookmarked) {
        await _api.delete<Map<String, dynamic>>(
          '/library/bookmarks/${comic.sourceName}/comics/${comic.slug}',
        );
        _resetBookmarkCandidateScan();
        return false;
      }
      await _api.put<Map<String, dynamic>>(
        '/library/bookmarks/${comic.sourceName}/comics/${comic.slug}',
      );
      _resetBookmarkCandidateScan();
      return true;
    }

    final bookmarks = _localBookmarks();
    if (bookmarked) {
      bookmarks.remove(comic.key);
      await _store.library.put('bookmarks', _encodeComicRefMap(bookmarks));
      await _saveLocalBookmarkLinks(
        _localBookmarkLinks()
            .where((link) => link.bookmark.key != comic.key)
            .toList(),
      );
      _resetBookmarkCandidateScan();
      return false;
    }
    bookmarks[comic.key] = LibraryComicRef.fromSummary(comic);
    await _store.library.put('bookmarks', _encodeComicRefMap(bookmarks));
    _resetBookmarkCandidateScan();
    return true;
  }

  Future<void> updateBookmarkStatus(ComicSummary comic, String status) async {
    if (await _isLoggedIn) {
      await _api.patch<void>(
        '/library/bookmarks/${comic.sourceName}/comics/${comic.slug}/status',
        data: {'status': status},
      );
      return;
    }

    final bookmarks = _localBookmarks();
    final bookmark = bookmarks[comic.key];
    if (bookmark == null) throw StateError('Bookmark tidak ditemukan.');
    bookmarks[comic.key] = bookmark.copyWith(status: status);
    await _store.library.put('bookmarks', _encodeComicRefMap(bookmarks));
  }

  void _resetBookmarkCandidateScan() {
    _bookmarkCandidateScanOffset = 0;
    _bookmarkCandidateScanAuthenticated = null;
    _bookmarkCandidateScanComplete = false;
    _bookmarkCandidateScanResults.clear();
  }

  // --- Shared local-storage readers used across the part extensions ---------

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

  List<_LocalBookmarkLink> _localBookmarkLinks() {
    final raw = _store.library.get('bookmark_links');
    if (raw is! List) return [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(_LocalBookmarkLink.fromJson)
        .toList();
  }

  Future<void> _saveLocalBookmarkLinks(List<_LocalBookmarkLink> links) {
    return _store.library.put(
      'bookmark_links',
      links.map((link) => link.toJson()).toList(),
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

  List<ReadingProgress> _localHistory() {
    final raw = _store.library.get('history_entries');
    final items = raw is List
        ? raw
              .whereType<Map<dynamic, dynamic>>()
              .map(ReadingProgress.fromLocalJson)
              .toList()
        : _store.progress.values
              .whereType<Map<dynamic, dynamic>>()
              .map(ReadingProgress.fromLocalJson)
              .toList();
    items.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    return items;
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

  // Reader preferences stay on the core class (not a part extension) because
  // tests fake `getReaderPreferences` via `implements LibraryRepository`, which
  // only works for real instance members.
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

class _LocalBookmarkLink {
  const _LocalBookmarkLink({
    required this.bookmark,
    required this.linked,
    required this.confidence,
  });

  factory _LocalBookmarkLink.fromJson(Map<dynamic, dynamic> json) {
    return _LocalBookmarkLink(
      bookmark: LibraryComicRef.fromJson(
        Map<String, dynamic>.from(json['bookmark'] as Map? ?? const {}),
      ),
      linked: LibraryComicRef.fromJson(
        Map<String, dynamic>.from(json['linked'] as Map? ?? const {}),
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'bookmark': bookmark.toJson(),
    'linked': linked.toJson(),
    'confidence': confidence,
  };

  final LibraryComicRef bookmark;
  final LibraryComicRef linked;
  final double confidence;
}

extension on ComicSummary {
  String get key => '$sourceName|$slug';
}
