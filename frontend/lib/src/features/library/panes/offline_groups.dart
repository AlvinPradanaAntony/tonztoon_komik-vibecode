part of '../library_shared_panes.dart';

List<_OfflineChapterGroup> _groupOfflineChaptersByComic(
  List<OfflineChapter> chapters,
) {
  final groups = <String, _OfflineChapterGroup>{};
  for (final chapter in chapters) {
    final key = chapter.comic.key;
    groups.putIfAbsent(key, () => _OfflineChapterGroup(comic: chapter.comic));
    groups[key]!.chapters.add(chapter);
  }
  for (final group in groups.values) {
    group.chapters.sort((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
  }
  return groups.values.toList();
}

List<_DownloadEntryGroup> _groupDownloadEntriesByComic(
  List<DownloadEntry> entries,
) {
  final groups = <String, _DownloadEntryGroup>{};
  for (final entry in entries) {
    final key = entry.comic.key;
    groups.putIfAbsent(key, () => _DownloadEntryGroup(comic: entry.comic));
    groups[key]!.entries.add(entry);
  }
  for (final group in groups.values) {
    group.entries.sort((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
  }
  return groups.values.toList();
}

class _OfflineChapterGroup {
  _OfflineChapterGroup({required this.comic});

  final LibraryComicRef comic;
  final List<OfflineChapter> chapters = [];

  int get readyCount => chapters.where((chapter) => chapter.isCompleted).length;
}

class _DownloadEntryGroup {
  _DownloadEntryGroup({required this.comic});

  final LibraryComicRef comic;
  final List<DownloadEntry> entries = [];
}

String _offlineChapterKey(OfflineChapter chapter) {
  return '${chapter.comic.key}|${chapter.chapterNumber}';
}

String _downloadEntryKey(DownloadEntry entry) {
  return '${entry.comic.key}|${entry.chapterNumber}';
}

OfflineDownloadBatch? _queuedBatchForEntry(
  DownloadEntry entry,
  List<OfflineDownloadBatch> batches,
) {
  for (final status in const ['downloading', 'pending', 'paused', 'failed']) {
    for (final batch in batches) {
      if (batch.status == status &&
          batch.comic.key == entry.comic.key &&
          batch.chapterNumbers.contains(entry.chapterNumber)) {
        return batch;
      }
    }
  }
  return null;
}

double _queuedChapterProgress(DownloadEntry entry, OfflineDownloadBatch batch) {
  final chapterIndex = batch.chapterNumbers.indexOf(entry.chapterNumber);
  if (chapterIndex < 0 || batch.totalChapters <= 0) return 0;
  return (batch.progress * batch.totalChapters - chapterIndex)
      .clamp(0, 1)
      .toDouble();
}
