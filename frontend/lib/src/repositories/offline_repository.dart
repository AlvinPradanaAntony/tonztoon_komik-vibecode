import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/storage.dart';
import '../models/comic.dart';
import '../models/library.dart';

class OfflineRepository {
  OfflineRepository(this._api, this._store);

  final TonztoonApi _api;
  final LocalStore _store;

  Future<List<OfflineChapter>> getOfflineChapters() async {
    final values = _offlineMap().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  Future<List<OfflineDownloadBatch>> getBatches() async {
    final values = _batchMap().values.map((batch) {
      if (batch.status == 'downloading') {
        return batch.copyWith(
          status: 'paused',
          lastError: 'Download paused while the app was closed.',
          clearCurrentChapterNumber: true,
        );
      }
      return batch;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _store.library.put(
      'offline_batches',
      _encodeBatchMap({for (final batch in values) batch.id: batch}),
    );
    return values;
  }

  Future<void> saveBatch(OfflineDownloadBatch batch) async {
    final map = _batchMap();
    map[batch.id] = batch;
    await _store.library.put('offline_batches', _encodeBatchMap(map));
  }

  Future<void> deleteBatch(String batchId) async {
    final map = _batchMap();
    map.remove(batchId);
    await _store.library.put('offline_batches', _encodeBatchMap(map));
  }

  Future<OfflineChapter?> getOfflineChapter(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    final key = _key(sourceName, slug, chapterNumber);
    final chapter = _offlineMap()[key];
    if (chapter == null) return null;
    if (!chapter.isCompleted) return chapter;

    final exists = await _allFilesExist(chapter.localPaths);
    if (exists) return chapter;

    final missing = OfflineChapter(
      comic: chapter.comic,
      chapterNumber: chapter.chapterNumber,
      status: 'missing',
      localPaths: chapter.localPaths,
      updatedAt: DateTime.now(),
      lastError: 'File offline tidak ditemukan. Silakan download ulang.',
    );
    await _putOfflineChapter(missing);
    return missing;
  }

  Future<ChapterPayload?> getOfflinePayload(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    final chapter = await getOfflineChapter(sourceName, slug, chapterNumber);
    if (chapter == null || !chapter.isCompleted) return null;
    final exists = await _allFilesExist(chapter.localPaths);
    if (!exists) return null;
    return ChapterPayload(
      sourceName: sourceName,
      chapterNumber: chapterNumber,
      images: [
        for (var i = 0; i < chapter.localPaths.length; i++)
          ChapterImageItem(
            page: i + 1,
            url: File(chapter.localPaths[i]).uri.toString(),
          ),
      ],
      total: chapter.localPaths.length,
    );
  }

  Future<OfflineChapter> downloadChapter({
    required ComicSummary comic,
    required double chapterNumber,
    required ChapterPayload payload,
    CancelToken? cancelToken,
    void Function(int pageIndex, int received, int total)? onImageProgress,
  }) async {
    final ref = LibraryComicRef.fromSummary(comic);
    final pending = OfflineChapter(
      comic: ref,
      chapterNumber: chapterNumber,
      status: 'downloading',
      localPaths: const [],
      updatedAt: DateTime.now(),
    );
    await _putOfflineChapter(pending);

    try {
      final dir = await _chapterDirectory(
        comic.sourceName,
        comic.slug,
        chapterNumber,
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);

      final paths = <String>[];
      for (var i = 0; i < payload.images.length; i++) {
        final image = payload.images[i];
        final extension = _extensionFor(image.url);
        final path =
            '${dir.path}${Platform.pathSeparator}${(i + 1).toString().padLeft(4, '0')}.$extension';
        await _api.dio.download(
          image.url,
          path,
          cancelToken: cancelToken,
          deleteOnError: true,
          onReceiveProgress: (received, total) {
            onImageProgress?.call(i, received, total);
          },
        );
        paths.add(path);
      }

      final completed = OfflineChapter(
        comic: ref,
        chapterNumber: chapterNumber,
        status: 'completed',
        localPaths: paths,
        updatedAt: DateTime.now(),
      );
      await _putOfflineChapter(completed);
      return completed;
    } catch (error) {
      final cancelled = error is DioException && CancelToken.isCancel(error);
      final failed = OfflineChapter(
        comic: ref,
        chapterNumber: chapterNumber,
        status: cancelled ? 'cancelled' : 'failed',
        localPaths: const [],
        updatedAt: DateTime.now(),
        lastError: error.toString(),
      );
      await _putOfflineChapter(failed);
      return failed;
    }
  }

  Future<void> deleteOfflineChapter(OfflineChapter chapter) async {
    final dir = await _chapterDirectory(
      chapter.comic.sourceName,
      chapter.comic.slug,
      chapter.chapterNumber,
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final map = _offlineMap();
    map.remove(chapter.key);
    await _store.library.put('offline_chapters', _encodeOfflineMap(map));
  }

  Future<void> clearAllOfflineChapters() async {
    final root = await _offlineRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await _store.library.put('offline_chapters', <String, dynamic>{});
  }

  Map<String, OfflineChapter> _offlineMap() {
    final raw = _store.library.get('offline_chapters');
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        OfflineChapter.fromJson(Map<dynamic, dynamic>.from(value as Map)),
      ),
    );
  }

  Map<String, OfflineDownloadBatch> _batchMap() {
    final raw = _store.library.get('offline_batches');
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        OfflineDownloadBatch.fromJson(Map<dynamic, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<void> _putOfflineChapter(OfflineChapter chapter) async {
    final map = _offlineMap();
    map[chapter.key] = chapter;
    await _store.library.put('offline_chapters', _encodeOfflineMap(map));
  }

  Map<String, dynamic> _encodeOfflineMap(Map<String, OfflineChapter> map) {
    return map.map((key, value) => MapEntry(key, value.toJson()));
  }

  Map<String, dynamic> _encodeBatchMap(Map<String, OfflineDownloadBatch> map) {
    return map.map((key, value) => MapEntry(key, value.toJson()));
  }

  Future<Directory> _chapterDirectory(
    String sourceName,
    String slug,
    double chapterNumber,
  ) async {
    final root = await _offlineRoot();
    return Directory(
      '${root.path}${Platform.pathSeparator}${_safe(sourceName)}${Platform.pathSeparator}${_safe(slug)}${Platform.pathSeparator}${formatChapterNumber(chapterNumber)}',
    );
  }

  Future<Directory> _offlineRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}tonztoon_offline');
  }

  Future<bool> _allFilesExist(List<String> paths) async {
    if (paths.isEmpty) return false;
    for (final path in paths) {
      if (!await File(path).exists()) return false;
    }
    return true;
  }

  String _extensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'jpg';
  }

  String _safe(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  String _key(String sourceName, String slug, double chapterNumber) {
    return '$sourceName|$slug|$chapterNumber';
  }
}
