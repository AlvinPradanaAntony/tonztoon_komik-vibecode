import 'dart:math' as math;

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
  static const _bookmarkCandidatePageSize = 5;
  static const _bookmarkCandidateMaxAttempts = 3;
  static const _bookmarkLinkBatchSize = 100;
  static const _bookmarkCompletionSyncBatchSize = 20;
  static const _bookmarkLinkMaxAttempts = 3;

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
  }) async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>(
        '/library/bookmarks',
        queryParameters: {'page': page, 'page_size': pageSize},
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
    return _localBookmarks().values.skip(start).take(pageSize).map((bookmark) {
      return LibraryComicRef.fromJson({
        ...bookmark.toJson(),
        'linked_comics': links
            .where((link) => link.bookmark.key == bookmark.key)
            .map((link) => link.linked.toJson())
            .toList(),
      });
    }).toList();
  }

  Future<LibrarySummary> getLibrarySummary() async {
    if (await _isLoggedIn) {
      final response = await _api.get<Map<String, dynamic>>('/library/summary');
      return LibrarySummary.fromJson(response.data ?? const {});
    }

    return LibrarySummary(
      counts: LibrarySummaryCounts(
        bookmarks: _localBookmarks().length,
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

  Future<List<BookmarkLinkCandidate>> scanBookmarkLinkCandidates({
    void Function(int scanned)? onProgress,
  }) async {
    final authenticated = await _isLoggedIn;
    if (_bookmarkCandidateScanAuthenticated != authenticated) {
      _resetBookmarkCandidateScan();
      _bookmarkCandidateScanAuthenticated = authenticated;
    }
    onProgress?.call(_bookmarkCandidateScanOffset);
    if (_bookmarkCandidateScanComplete) {
      return _bookmarkCandidateScanResults.values.toList();
    }

    if (authenticated) {
      var offset = _bookmarkCandidateScanOffset;
      var hasMore = true;
      while (hasMore) {
        final page = await _loadBookmarkCandidatePage(offset);
        for (final rawGroup
            in (page['items'] as List? ?? const []).whereType<Map>()) {
          final group = Map<String, dynamic>.from(rawGroup);
          final bookmark = LibraryComicRef.fromJson(
            Map<String, dynamic>.from(group['bookmark'] as Map? ?? const {}),
          );
          for (final item
              in ((group['candidates'] as List?) ?? const [])
                  .whereType<Map>()) {
            final candidate = BookmarkLinkCandidate.fromJson(
              bookmark,
              Map<String, dynamic>.from(item),
            );
            _bookmarkCandidateScanResults[candidate.key] = candidate;
          }
        }
        final nextOffset = (page['next_offset'] as num?)?.toInt() ?? offset;
        hasMore = page['has_more'] == true && nextOffset > offset;
        offset = nextOffset;
        _bookmarkCandidateScanOffset = offset;
        onProgress?.call(offset);
      }
      final candidates = _bookmarkCandidateScanResults.values.toList();
      _bookmarkCandidateScanComplete = true;
      return candidates;
    }

    final bookmarks = _localBookmarks().values.toList();
    final usedKeys = <String>{
      ...bookmarks.map((item) => item.key),
      ..._localBookmarkLinks().map((item) => item.linked.key),
    };
    for (
      var index = _bookmarkCandidateScanOffset;
      index < bookmarks.length;
      index++
    ) {
      final bookmark = bookmarks[index];
      final linkedSourcesForThisBookmark = _localBookmarkLinks()
          .where((link) => link.bookmark.key == bookmark.key)
          .map((link) => link.linked.sourceName)
          .toSet();

      final response = await _api.get<List<dynamic>>(
        '/search',
        queryParameters: {'q': bookmark.title, 'page_size': 50},
      );
      final bestBySource = <String, BookmarkLinkCandidate>{};
      for (final raw in (response.data ?? const []).whereType<Map>()) {
        final comic = LibraryComicRef.fromJson(Map<String, dynamic>.from(raw));
        if (comic.sourceName == bookmark.sourceName ||
            linkedSourcesForThisBookmark.contains(comic.sourceName) ||
            usedKeys.contains(comic.key)) {
          continue;
        }
        final confidence = _titleSimilarity(bookmark.title, comic.title);
        if (confidence < 0.55) continue;
        final candidate = BookmarkLinkCandidate(
          bookmark: bookmark,
          comic: comic,
          confidence: confidence,
        );
        final current = bestBySource[comic.sourceName];
        if (current == null || current.confidence < confidence) {
          bestBySource[comic.sourceName] = candidate;
        }
      }
      for (final candidate in bestBySource.values) {
        _bookmarkCandidateScanResults[candidate.key] = candidate;
      }
      _bookmarkCandidateScanOffset = index + 1;
      onProgress?.call(index + 1);
    }
    final candidates = _bookmarkCandidateScanResults.values.toList();
    _bookmarkCandidateScanComplete = true;
    return candidates;
  }

  Future<Map<String, dynamic>> _loadBookmarkCandidatePage(int offset) async {
    for (var attempt = 1; attempt <= _bookmarkCandidateMaxAttempts; attempt++) {
      try {
        final response = await _api.get<Map<String, dynamic>>(
          '/library/bookmark-links/candidates',
          queryParameters: {
            'offset': offset,
            'page_size': _bookmarkCandidatePageSize,
          },
        );
        return response.data ?? const {};
      } on ApiException catch (error) {
        final retryable =
            error.statusCode == null ||
            error.statusCode == 408 ||
            error.statusCode == 429 ||
            (error.statusCode ?? 0) >= 500;
        if (!retryable || attempt == _bookmarkCandidateMaxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw StateError('Bookmark candidate retry loop ended unexpectedly.');
  }

  void _resetBookmarkCandidateScan() {
    _bookmarkCandidateScanOffset = 0;
    _bookmarkCandidateScanAuthenticated = null;
    _bookmarkCandidateScanComplete = false;
    _bookmarkCandidateScanResults.clear();
  }

  Future<BookmarkLinkSaveResult> saveBookmarkLinks(
    List<BookmarkLinkCandidate> candidates, {
    void Function(BookmarkLinkSaveProgress progress)? onProgress,
  }) async {
    if (candidates.isEmpty) {
      return const BookmarkLinkSaveResult(completedPropagated: 0);
    }
    if (await _isLoggedIn) {
      var linkedTotal = 0;
      var propagated = 0;
      final syncBookmarkIds = <int>{};
      onProgress?.call(
        BookmarkLinkSaveProgress(
          stage: BookmarkLinkSaveStage.linking,
          completed: 0,
          total: candidates.length,
        ),
      );
      for (
        var start = 0;
        start < candidates.length;
        start += _bookmarkLinkBatchSize
      ) {
        final end = math.min(start + _bookmarkLinkBatchSize, candidates.length);
        final batch = candidates.sublist(start, end);
        final saved = await _saveBookmarkLinkBatch(batch);
        linkedTotal += saved.linkedTotal;
        propagated += saved.completedPropagated;
        syncBookmarkIds.addAll(saved.completionSyncBookmarkIds);
        onProgress?.call(
          BookmarkLinkSaveProgress(
            stage: BookmarkLinkSaveStage.linking,
            completed: end,
            total: candidates.length,
          ),
        );
      }
      propagated += await _synchronizeBookmarkLinkCompletions(
        syncBookmarkIds.toList(),
        onProgress: onProgress,
      );
      _resetBookmarkCandidateScan();
      return BookmarkLinkSaveResult(
        linkedTotal: linkedTotal,
        completedPropagated: propagated,
      );
    }

    final links = _localBookmarkLinks();
    onProgress?.call(
      BookmarkLinkSaveProgress(
        stage: BookmarkLinkSaveStage.linking,
        completed: 0,
        total: candidates.length,
      ),
    );
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      links.removeWhere(
        (link) =>
            link.linked.key == candidate.comic.key ||
            (link.bookmark.key == candidate.bookmark.key &&
                link.linked.sourceName == candidate.comic.sourceName),
      );
      links.add(
        _LocalBookmarkLink(
          bookmark: candidate.bookmark,
          linked: candidate.comic,
          confidence: candidate.confidence,
        ),
      );
      onProgress?.call(
        BookmarkLinkSaveProgress(
          stage: BookmarkLinkSaveStage.linking,
          completed: index + 1,
          total: candidates.length,
        ),
      );
    }
    await _saveLocalBookmarkLinks(links);
    final syncResult = await _propagateExistingLocalCompletionsForLinks();
    _resetBookmarkCandidateScan();
    return BookmarkLinkSaveResult(
      linkedTotal: candidates.length,
      completedPropagated: syncResult.completedPropagated,
    );
  }

  Future<BookmarkLinkSaveResult> _saveBookmarkLinkBatch(
    List<BookmarkLinkCandidate> batch,
  ) async {
    for (var attempt = 1; attempt <= _bookmarkLinkMaxAttempts; attempt++) {
      try {
        final response = await _api.post<Map<String, dynamic>>(
          '/library/bookmark-links',
          data: {
            'links': batch
                .map(
                  (item) => {
                    'bookmark': {
                      'source_name': item.bookmark.sourceName,
                      'comic_slug': item.bookmark.slug,
                    },
                    'linked_comic': {
                      'source_name': item.comic.sourceName,
                      'comic_slug': item.comic.slug,
                    },
                    'confidence': item.confidence,
                  },
                )
                .toList(),
          },
        );
        return BookmarkLinkSaveResult.fromJson(response.data ?? const {});
      } on ApiException catch (error) {
        if (!_isRetryableBatchError(error) ||
            attempt == _bookmarkLinkMaxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw StateError('Bookmark link retry loop ended unexpectedly.');
  }

  Future<int> _synchronizeBookmarkLinkCompletions(
    List<int> bookmarkIds, {
    void Function(BookmarkLinkSaveProgress progress)? onProgress,
  }) async {
    var propagated = 0;
    onProgress?.call(
      BookmarkLinkSaveProgress(
        stage: BookmarkLinkSaveStage.syncingCompleted,
        completed: 0,
        total: bookmarkIds.length,
      ),
    );
    for (
      var start = 0;
      start < bookmarkIds.length;
      start += _bookmarkCompletionSyncBatchSize
    ) {
      final end = math.min(
        start + _bookmarkCompletionSyncBatchSize,
        bookmarkIds.length,
      );
      final data = await _postCompletedSyncBatch(
        bookmarkIds.sublist(start, end),
      );
      propagated += (data['completed_propagated'] as num?)?.toInt() ?? 0;
      onProgress?.call(
        BookmarkLinkSaveProgress(
          stage: BookmarkLinkSaveStage.syncingCompleted,
          completed: end,
          total: bookmarkIds.length,
        ),
      );
    }
    return propagated;
  }

  Future<Map<String, dynamic>> _postCompletedSyncBatch(
    List<int> bookmarkIds,
  ) async {
    for (var attempt = 1; attempt <= _bookmarkLinkMaxAttempts; attempt++) {
      try {
        final response = await _api.post<Map<String, dynamic>>(
          '/library/bookmark-links/completed-sync',
          data: {'bookmark_ids': bookmarkIds},
        );
        return response.data ?? const {};
      } on ApiException catch (error) {
        if (!_isRetryableBatchError(error) ||
            attempt == _bookmarkLinkMaxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw StateError('Completed sync retry loop ended unexpectedly.');
  }

  bool _isRetryableBatchError(ApiException error) {
    return error.statusCode == null ||
        error.statusCode == 408 ||
        error.statusCode == 429 ||
        (error.statusCode ?? 0) >= 500;
  }

  Future<void> unlinkComicSource(ComicSummary comic) async {
    if (await _isLoggedIn) {
      await _api.delete<Map<String, dynamic>>(
        '/library/bookmark-links/${comic.sourceName}/comics/${comic.slug}',
      );
      _resetBookmarkCandidateScan();
      return;
    }
    await _saveLocalBookmarkLinks(
      _localBookmarkLinks()
          .where((link) => link.linked.key != comic.key)
          .toList(),
    );
    _resetBookmarkCandidateScan();
  }

  Future<BookmarkLinkSaveResult>
  _propagateExistingLocalCompletionsForLinks() async {
    final links = _localBookmarkLinks();
    var propagated = 0;
    final linksByBookmark = <String, List<_LocalBookmarkLink>>{};
    for (final link in links) {
      linksByBookmark.putIfAbsent(link.bookmark.key, () => []).add(link);
    }

    for (final groupLinks in linksByBookmark.values) {
      final comics = <String, LibraryComicRef>{
        groupLinks.first.bookmark.key: groupLinks.first.bookmark,
        for (final link in groupLinks) link.linked.key: link.linked,
      };
      final chaptersByComic = <String, List<ChapterListItem>>{};
      for (final comic in comics.values) {
        try {
          chaptersByComic[comic.key] = await _getChapterList(comic);
        } catch (_) {
          chaptersByComic[comic.key] = const [];
        }
      }

      final completedByComic = <String, Set<double>>{
        for (final comic in comics.values)
          comic.key: _localCompletedChapterNumbers(
            comic.sourceName,
            comic.slug,
          ).toSet(),
      };
      final completedNumbers = completedByComic.values
          .expand((numbers) => numbers)
          .toSet();

      for (final completedNumber in completedNumbers) {
        for (final comic in comics.values) {
          final completed = completedByComic[comic.key]!;
          if (completed.any(
            (number) => (number - completedNumber).abs() <= 0.0001,
          )) {
            continue;
          }
          ChapterListItem? matchingChapter;
          for (final chapter in chaptersByComic[comic.key] ?? const []) {
            if ((chapter.chapterNumber - completedNumber).abs() <= 0.0001) {
              matchingChapter = chapter;
              break;
            }
          }
          if (matchingChapter == null) continue;
          await _addLocalCompletedChapter(
            comic.sourceName,
            comic.slug,
            matchingChapter.chapterNumber,
          );
          completed.add(matchingChapter.chapterNumber);
          propagated++;
        }
      }
    }
    return BookmarkLinkSaveResult(completedPropagated: propagated);
  }

  Future<List<ChapterListItem>> _getChapterList(LibraryComicRef comic) async {
    final response = await _api.get<List<dynamic>>(
      '/sources/${comic.sourceName}/comics/${comic.slug}/chapters',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => ChapterListItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> _addLocalCompletedChapter(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    final key = ReadingProgress.completedChaptersKey(sourceName, slug);
    final numbers = _localCompletedChapterNumbers(sourceName, slug).toSet()
      ..add(chapterNumber);
    await _store.progress.put(key, numbers.toList()..sort());
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

double _titleSimilarity(String left, String right) {
  final a = _normalizeTitle(left);
  final b = _normalizeTitle(right);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.contains(b) || b.contains(a)) return 0.88;

  final aTokens = a.split(' ').toSet();
  final bTokens = b.split(' ').toSet();
  final union = aTokens.union(bTokens).length;
  final tokenScore = union == 0
      ? 0.0
      : aTokens.intersection(bTokens).length / union;
  final aPairs = _characterPairs(a);
  final bPairs = _characterPairs(b);
  final pairUnion = aPairs.length + bPairs.length;
  final pairScore = pairUnion == 0
      ? 0.0
      : (2 * aPairs.intersection(bPairs).length) / pairUnion;
  return (tokenScore * 0.55 + pairScore * 0.45).clamp(0, 1);
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

Set<String> _characterPairs(String value) {
  final compact = value.replaceAll(' ', '');
  if (compact.length < 2) return {compact};
  return {
    for (var index = 0; index < compact.length - 1; index++)
      compact.substring(index, index + 2),
  };
}

extension on ComicSummary {
  String get key => '$sourceName|$slug';
}
