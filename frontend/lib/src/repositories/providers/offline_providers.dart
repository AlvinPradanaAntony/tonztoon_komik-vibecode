part of '../providers.dart';

final offlineChaptersProvider = FutureProvider<List<OfflineChapter>>((ref) {
  return ref.watch(offlineRepositoryProvider).getOfflineChapters();
});

final offlineQueueProvider =
    AsyncNotifierProvider<OfflineQueueController, List<OfflineDownloadBatch>>(
      OfflineQueueController.new,
    );

class OfflineQueueController extends AsyncNotifier<List<OfflineDownloadBatch>> {
  final Map<String, CancelToken> _cancelTokens = {};
  final Set<String> _deletedBatchIds = {};
  final Set<String> _startingChapterKeys = {};

  @override
  Future<List<OfflineDownloadBatch>> build() {
    return ref.watch(offlineRepositoryProvider).getBatches();
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(offlineRepositoryProvider).getBatches());
  }

  Future<void> startBatch({
    required ComicSummary comic,
    required List<ChapterListItem> chapters,
  }) async {
    if (chapters.isEmpty) return;
    final batches = state.asData?.value ?? await build();
    final comicKey = '${comic.sourceName}|${comic.slug}';
    final activeChapterNumbers = batches
        .where(
          (batch) =>
              batch.comic.key == comicKey &&
              (batch.status == 'pending' ||
                  batch.status == 'downloading' ||
                  batch.status == 'paused'),
        )
        .expand((batch) => batch.chapterNumbers)
        .toSet();
    final queuedChapters = <ChapterListItem>[];
    final queuedKeys = <String>{};
    for (final chapter in chapters) {
      final key = '$comicKey|${chapter.chapterNumber}';
      if (activeChapterNumbers.contains(chapter.chapterNumber) ||
          _startingChapterKeys.contains(key) ||
          !queuedKeys.add(key)) {
        continue;
      }
      queuedChapters.add(chapter);
    }
    if (queuedChapters.isEmpty) return;

    _startingChapterKeys.addAll(queuedKeys);
    try {
      final chapterNumbers = queuedChapters
          .map((item) => item.chapterNumber)
          .toList();
      final batch = OfflineDownloadBatch.create(
        id: '${comic.sourceName}|${comic.slug}|${DateTime.now().microsecondsSinceEpoch}',
        comic: comic,
        chapterNumbers: chapterNumbers,
      );
      await ref
          .read(libraryRepositoryProvider)
          .enqueueDownloadBatch(comic, chapterNumbers);
      await ref.read(offlineRepositoryProvider).saveBatch(batch);
      await refresh();
      unawaited(_runBatch(batch));
    } finally {
      _startingChapterKeys.removeAll(queuedKeys);
    }
  }

  Future<void> resumeBatch(String batchId) async {
    final batches = state.asData?.value ?? await build();
    OfflineDownloadBatch? batch;
    for (final item in batches) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch == null || !batch.canResume) return;
    unawaited(_runBatch(batch));
  }

  Future<void> resumeRecoverableBatches() async {
    final batches = await ref.read(offlineRepositoryProvider).getBatches();
    state = AsyncData(batches);
    for (final batch in batches.where((batch) => batch.canAutoResume)) {
      unawaited(_runBatch(batch));
    }
  }

  Future<void> cancelBatch(String batchId) async {
    _cancelTokens[batchId]?.cancel('Download batch cancelled.');
    OfflineDownloadBatch? batch;
    for (final item in state.asData?.value ?? const <OfflineDownloadBatch>[]) {
      if (item.id == batchId) {
        batch = item;
        break;
      }
    }
    if (batch != null) {
      await _upsertRemainingDownloadStatuses(
        batch,
        status: 'cancelled',
        lastError: 'Cancelled by user.',
      );
      final cancelledBatch = batch.copyWith(
        status: 'cancelled',
        clearCurrentChapterNumber: true,
        lastError: 'Cancelled by user.',
      );
      await _saveBatch(cancelledBatch);
      unawaited(
        ref
            .read(downloadNotificationServiceProvider)
            .showCancelled(cancelledBatch),
      );
      unawaited(_addNotificationForCancelled(cancelledBatch));
    }
  }

  Future<void> deleteBatch(String batchId) async {
    _deletedBatchIds.add(batchId);
    _cancelTokens[batchId]?.cancel('Download batch deleted.');
    _cancelTokens.remove(batchId);
    await ref.read(offlineRepositoryProvider).deleteBatch(batchId);
    unawaited(ref.read(downloadNotificationServiceProvider).dismiss(batchId));
    await refresh();
  }

  Future<void> _runBatch(OfflineDownloadBatch initialBatch) async {
    if (_cancelTokens.containsKey(initialBatch.id)) return;
    final token = CancelToken();
    _cancelTokens[initialBatch.id] = token;
    var batch = initialBatch.copyWith(
      status: 'downloading',
      completedImages: 0,
      totalImages: 0,
      progressValue: initialBatch.totalChapters == 0
          ? 0
          : initialBatch.completedChapters / initialBatch.totalChapters,
      clearCurrentChapterNumber: true,
      clearLastError: true,
    );
    await _saveBatch(batch);
    unawaited(ref.read(downloadNotificationServiceProvider).showStarted(batch));

    try {
      final startIndex = batch.completedChapters.clamp(
        0,
        batch.chapterNumbers.length,
      );
      for (
        var chapterIndex = startIndex;
        chapterIndex < batch.chapterNumbers.length;
        chapterIndex++
      ) {
        if (token.isCancelled) {
          if (_deletedBatchIds.contains(initialBatch.id)) return;
          final cancelledBatch = batch.copyWith(
            status: 'cancelled',
            clearCurrentChapterNumber: true,
            lastError: 'Cancelled by user.',
          );
          await _saveBatch(cancelledBatch);
          unawaited(
            ref
                .read(downloadNotificationServiceProvider)
                .showCancelled(cancelledBatch),
          );
          unawaited(_addNotificationForCancelled(cancelledBatch));
          return;
        }
        final chapterNumber = batch.chapterNumbers[chapterIndex];
        final existing = await ref
            .read(offlineRepositoryProvider)
            .getOfflineChapter(
              batch.comic.sourceName,
              batch.comic.slug,
              chapterNumber,
            );
        if (existing?.isCompleted == true) {
          await _upsertDownloadStatus(
            batch.comic,
            chapterNumber,
            status: 'completed',
          );
          batch = batch.copyWith(
            completedChapters: chapterIndex + 1,
            progressValue: (chapterIndex + 1) / batch.totalChapters,
          );
          await _saveBatch(batch);
          unawaited(
            ref.read(downloadNotificationServiceProvider).showProgress(batch),
          );
          continue;
        }
        batch = batch.copyWith(
          status: 'downloading',
          currentChapterNumber: chapterNumber,
          completedChapters: chapterIndex,
          progressValue: chapterIndex / batch.totalChapters,
        );
        await _upsertDownloadStatus(
          batch.comic,
          chapterNumber,
          status: 'downloading',
        );
        await _saveBatch(batch);
        unawaited(
          ref.read(downloadNotificationServiceProvider).showProgress(batch),
        );

        final payload = await ref
            .read(catalogRepositoryProvider)
            .getChapter(
              batch.comic.sourceName,
              batch.comic.slug,
              chapterNumber,
            );
        final totalPages = payload.images.length;
        batch = batch.copyWith(totalImages: totalPages);
        await _saveBatch(batch);
        unawaited(
          ref.read(downloadNotificationServiceProvider).showProgress(batch),
        );

        final downloaded = await ref
            .read(offlineRepositoryProvider)
            .downloadChapter(
              comic: batch.comic.toSummary(),
              chapterNumber: chapterNumber,
              payload: payload,
              cancelToken: token,
              onImageProgress: (pageIndex, received, total) {
                final pageFraction = total <= 0 ? 0.0 : received / total;
                final chapterFraction = totalPages == 0
                    ? 1.0
                    : ((pageIndex + pageFraction) / totalPages).clamp(0, 1);
                final overall =
                    ((chapterIndex + chapterFraction) / batch.totalChapters)
                        .clamp(0, 1)
                        .toDouble();
                final live = batch.copyWith(
                  completedChapters: chapterIndex,
                  completedImages: pageIndex,
                  totalImages: totalPages,
                  progressValue: overall,
                );
                unawaited(_saveBatch(live));
                unawaited(
                  ref
                      .read(downloadNotificationServiceProvider)
                      .showProgress(live),
                );
              },
            );
        if (token.isCancelled || downloaded.status == 'cancelled') {
          if (_deletedBatchIds.contains(initialBatch.id)) return;
          await _upsertDownloadStatus(
            batch.comic,
            chapterNumber,
            status: 'cancelled',
            lastError: 'Cancelled by user.',
          );
          final cancelledBatch = batch.copyWith(
            status: 'cancelled',
            clearCurrentChapterNumber: true,
            lastError: 'Cancelled by user.',
          );
          await _saveBatch(cancelledBatch);
          unawaited(
            ref
                .read(downloadNotificationServiceProvider)
                .showCancelled(cancelledBatch),
          );
          unawaited(_addNotificationForCancelled(cancelledBatch));
          return;
        }
        if (!downloaded.isCompleted) {
          await _upsertDownloadStatus(
            batch.comic,
            chapterNumber,
            status: downloaded.status,
            lastError: downloaded.lastError,
          );
          throw ApiException(downloaded.lastError ?? 'Download gagal.');
        }

        await _upsertDownloadStatus(
          batch.comic,
          chapterNumber,
          status: 'completed',
        );
        batch = batch.copyWith(
          completedChapters: chapterIndex + 1,
          progressValue: (chapterIndex + 1) / batch.totalChapters,
        );
        await _saveBatch(batch);
        unawaited(
          ref.read(downloadNotificationServiceProvider).showProgress(batch),
        );
        ref.invalidate(offlineChaptersProvider);
      }

      final completedBatch = batch.copyWith(
        status: 'completed',
        completedChapters: batch.totalChapters,
        progressValue: 1,
        clearCurrentChapterNumber: true,
      );
      await _saveBatch(completedBatch);
      unawaited(
        ref
            .read(downloadNotificationServiceProvider)
            .showCompleted(completedBatch),
      );
      unawaited(_addNotificationForCompleted(completedBatch));
    } on DioException catch (error) {
      final cancelled = CancelToken.isCancel(error);
      if (cancelled && _deletedBatchIds.contains(initialBatch.id)) return;
      await _upsertRemainingDownloadStatuses(
        batch,
        status: cancelled ? 'cancelled' : 'failed',
        lastError: error.message ?? error.toString(),
      );
      final failedBatch = batch.copyWith(
        status: cancelled ? 'cancelled' : 'failed',
        clearCurrentChapterNumber: true,
        lastError: error.message ?? error.toString(),
      );
      await _saveBatch(failedBatch);
      unawaited(
        cancelled
            ? ref
                  .read(downloadNotificationServiceProvider)
                  .showCancelled(failedBatch)
            : ref
                  .read(downloadNotificationServiceProvider)
                  .showFailed(failedBatch),
      );
      unawaited(
        cancelled
            ? _addNotificationForCancelled(failedBatch)
            : _addNotificationForFailed(failedBatch),
      );
    } catch (error) {
      await _upsertRemainingDownloadStatuses(
        batch,
        status: 'failed',
        lastError: error.toString(),
      );
      final failedBatch = batch.copyWith(
        status: 'failed',
        clearCurrentChapterNumber: true,
        lastError: error.toString(),
      );
      await _saveBatch(failedBatch);
      unawaited(
        ref.read(downloadNotificationServiceProvider).showFailed(failedBatch),
      );
      unawaited(_addNotificationForFailed(failedBatch));
    } finally {
      _cancelTokens.remove(initialBatch.id);
      _deletedBatchIds.remove(initialBatch.id);
      ref.invalidate(offlineChaptersProvider);
      ref.invalidate(downloadsProvider);
    }
  }

  Future<void> _upsertDownloadStatus(
    LibraryComicRef comic,
    double chapterNumber, {
    required String status,
    String? lastError,
  }) async {
    try {
      await ref
          .read(libraryRepositoryProvider)
          .upsertDownloadEntryStatus(
            comic: comic,
            chapterNumber: chapterNumber,
            status: status,
            lastError: lastError,
          );
      ref.invalidate(downloadsProvider);
    } catch (_) {
      // Offline files remain the source of truth for local reading.
    }
  }

  Future<void> _upsertRemainingDownloadStatuses(
    OfflineDownloadBatch batch, {
    required String status,
    String? lastError,
  }) async {
    final startIndex = batch.completedChapters.clamp(
      0,
      batch.chapterNumbers.length,
    );
    for (var index = startIndex; index < batch.chapterNumbers.length; index++) {
      await _upsertDownloadStatus(
        batch.comic,
        batch.chapterNumbers[index],
        status: status,
        lastError: lastError,
      );
    }
  }

  Future<void> _saveBatch(OfflineDownloadBatch batch) async {
    await ref.read(offlineRepositoryProvider).saveBatch(batch);
    final current = [...?state.asData?.value];
    final index = current.indexWhere((item) => item.id == batch.id);
    if (index >= 0) {
      current[index] = batch;
    } else {
      current.insert(0, batch);
    }
    current.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncData(current);
  }

  Future<void> _addNotificationForCompleted(OfflineDownloadBatch batch) {
    return ref
        .read(notificationsProvider.notifier)
        .add(ref.read(notificationRepositoryProvider).downloadCompleted(batch));
  }

  Future<void> _addNotificationForFailed(OfflineDownloadBatch batch) {
    return ref
        .read(notificationsProvider.notifier)
        .add(ref.read(notificationRepositoryProvider).downloadFailed(batch));
  }

  Future<void> _addNotificationForCancelled(OfflineDownloadBatch batch) {
    return ref
        .read(notificationsProvider.notifier)
        .add(ref.read(notificationRepositoryProvider).downloadCancelled(batch));
  }
}
