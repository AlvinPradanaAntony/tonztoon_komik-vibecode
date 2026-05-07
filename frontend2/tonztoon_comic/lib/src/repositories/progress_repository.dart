import '../core/api_client.dart';
import '../core/storage.dart';
import '../core/token_store.dart';
import '../models/progress.dart';

class ProgressRepository {
  ProgressRepository(this._api, this._tokenStore, this._store);

  final TonztoonApi _api;
  final TokenStore _tokenStore;
  final LocalStore _store;

  Future<List<ReadingProgress>> getContinueReading() async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _api.get<List<dynamic>>(
          '/library/progress/continue-reading',
        );
        return (response.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReadingProgress.fromLibraryJson)
            .toList();
      } catch (_) {
        return _localContinueReading();
      }
    }
    return _localContinueReading();
  }

  Future<ReadingProgress?> getProgress(String sourceName, String slug) async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _api.get<Map<String, dynamic>?>(
          '/library/progress/$sourceName/comics/$slug',
        );
        final data = response.data;
        return data == null ? null : ReadingProgress.fromLibraryJson(data);
      } catch (_) {
        return _localProgress(sourceName, slug);
      }
    }
    return _localProgress(sourceName, slug);
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    await _store.progress.put(progress.storageKey, progress.toLocalJson());

    final token = await _tokenStore.readAccessToken();
    if (token == null || token.isEmpty) return;

    await _api.put<Map<String, dynamic>>(
      '/library/progress/${progress.sourceName}/comics/${progress.comicSlug}/chapters/${progress.chapterNumber}',
      data: progress.toProgressPayload(),
    );
  }

  ReadingProgress? _localProgress(String sourceName, String slug) {
    final raw = _store.progress.get(ReadingProgress.key(sourceName, slug));
    if (raw is Map) {
      return ReadingProgress.fromLocalJson(raw);
    }
    return null;
  }

  List<ReadingProgress> _localContinueReading() {
    return _store.progress.values
        .whereType<Map<dynamic, dynamic>>()
        .map(ReadingProgress.fromLocalJson)
        .toList()
      ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
  }
}
