part of '../library_repository.dart';

/// Cross-source bookmark linking: scanning for candidate links, saving them,
/// and propagating "completed chapter" status across linked comics.
extension LibraryBookmarkLinks on LibraryRepository {
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
        final confidence = titleSimilarity(bookmark.title, comic.title);
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
        await _cacheBookmarkLinkCandidates(batch);
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

  Future<void> _cacheBookmarkLinksFromState(LibraryComicState state) async {
    final origin = state.bookmarkOrigin;
    if (origin == null || state.bookmarkRelation == BookmarkRelation.none) {
      return;
    }

    final linkedByKey = <String, LibraryComicRef>{};
    void addLinked(LibraryComicRef comic) {
      if (comic.key == origin.key) return;
      linkedByKey[comic.key] = comic;
    }

    addLinked(state.comic);
    for (final comic in state.linkedComics) {
      addLinked(comic);
    }
    if (linkedByKey.isEmpty) return;

    await _cacheLocalBookmarkLinks(
      linkedByKey.values
          .map(
            (linked) => _LocalBookmarkLink(
              bookmark: origin,
              linked: linked,
              confidence: 1,
            ),
          )
          .toList(),
    );
  }

  Future<void> _cacheBookmarkLinkCandidates(
    List<BookmarkLinkCandidate> candidates,
  ) {
    return _cacheLocalBookmarkLinks(
      candidates
          .map(
            (candidate) => _LocalBookmarkLink(
              bookmark: candidate.bookmark,
              linked: candidate.comic,
              confidence: candidate.confidence,
            ),
          )
          .toList(),
    );
  }

  Future<void> _cacheLocalBookmarkLinks(List<_LocalBookmarkLink> newLinks) {
    if (newLinks.isEmpty) return Future<void>.value();
    final links = _localBookmarkLinks();
    for (final link in newLinks) {
      links.removeWhere(
        (existing) =>
            existing.linked.key == link.linked.key ||
            (existing.bookmark.key == link.bookmark.key &&
                existing.linked.sourceName == link.linked.sourceName),
      );
      links.add(link);
    }
    return _saveLocalBookmarkLinks(links);
  }

  Future<ReadStatusSyncResult> synchronizeReadStatusForComic({
    required ComicSummary comic,
    required List<ChapterListItem> chapters,
    LibraryComicState? state,
    ReadingProgress? progress,
  }) async {
    if (state != null) {
      await _cacheBookmarkLinksFromState(state);
    }

    final currentRef = LibraryComicRef.fromSummary(comic);
    final origin = state?.bookmarkOrigin;
    final groupComics = <String, LibraryComicRef>{currentRef.key: currentRef};
    if (state != null) {
      groupComics[state.comic.key] = state.comic;
    }
    if (origin != null) {
      groupComics[origin.key] = origin;
    }
    for (final linked in state?.linkedComics ?? const <LibraryComicRef>[]) {
      groupComics[linked.key] = linked;
    }

    final numbersByComic = <String, Set<double>>{};
    for (final item in groupComics.values) {
      numbersByComic[item.key] = _localCompletedChapterNumbers(
        item.sourceName,
        item.slug,
      ).toSet();
    }
    if (state != null) {
      numbersByComic[state.comic.key]?.addAll(state.completedChapterNumbers);
      numbersByComic[currentRef.key]?.addAll(state.completedChapterNumbers);
    }

    if (progress != null &&
        progress.sourceName == comic.sourceName &&
        progress.comicSlug == comic.slug) {
      if (progress.isCompleted) {
        numbersByComic[currentRef.key]?.add(progress.chapterNumber);
      }
      final prefs = await getReaderPreferences();
      if (prefs.markReadOnComplete) {
        var availableChapters = chapters;
        if (availableChapters.isEmpty) {
          try {
            availableChapters = await _getChapterList(currentRef);
          } catch (_) {
            availableChapters = const [];
          }
        }
        final previous = _previousChapterNumberBeforeProgress(
          availableChapters,
          progress.chapterNumber,
        );
        if (previous != null) {
          numbersByComic[currentRef.key]?.add(previous);
        }
      }
    }

    var completedSynced = 0;
    final loggedIn = await _isLoggedIn;
    for (final item in groupComics.values) {
      final numbers = numbersByComic[item.key] ?? const <double>{};
      for (final chapterNumber in numbers) {
        await _addLocalCompletedChapter(
          item.sourceName,
          item.slug,
          chapterNumber,
        );
        if (loggedIn) {
          await _markCompletedChapterRemote(item, chapterNumber);
          await LocalStateMetadata.markAuthenticatedCompletedChapterCache(
            _store,
            item.sourceName,
            item.slug,
            chapterNumber,
          );
        }
        completedSynced++;
      }
    }

    final localPropagation = await _propagateExistingLocalCompletionsForLinks();
    return ReadStatusSyncResult(
      completedSynced: completedSynced,
      completedPropagated: localPropagation.completedPropagated,
    );
  }

  double? _previousChapterNumberBeforeProgress(
    List<ChapterListItem> chapters,
    double progressChapterNumber,
  ) {
    if (chapters.isEmpty) return null;
    final sorted = [...chapters]
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    final index = sorted.indexWhere(
      (chapter) =>
          _sameChapterNumber(chapter.chapterNumber, progressChapterNumber),
    );
    if (index <= 0) return null;
    return sorted[index - 1].chapterNumber;
  }

  bool _sameChapterNumber(double left, double right) {
    return (left - right).abs() <= 0.0001;
  }

  Future<void> _markCompletedChapterRemote(
    LibraryComicRef comic,
    double chapterNumber,
  ) async {
    await _api.post<Map<String, dynamic>>(
      '/library/completed-chapters',
      data: {
        'source_name': comic.sourceName,
        'comic_slug': comic.slug,
        'chapter_number': chapterNumber,
      },
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
}
