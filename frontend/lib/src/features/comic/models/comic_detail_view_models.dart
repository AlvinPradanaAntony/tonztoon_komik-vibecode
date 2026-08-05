part of '../comic_detail_screen.dart';

enum _ChapterReadState { none, current, completed }

class _ComicDownloadState {
  const _ComicDownloadState({
    required this.offlineCount,
    required this.queuedCount,
    required this.syncedCount,
    required this.offlineChapterNumbers,
    required this.knownChapterNumbers,
  });

  factory _ComicDownloadState.from({
    required ComicSummary comic,
    required LibraryComicState? libraryState,
    required List<OfflineChapter>? offlineChapters,
    required List<OfflineDownloadBatch>? queue,
  }) {
    final comicKey = _comicKey(comic.sourceName, comic.slug);
    final knownChapterNumbers = <double>{};
    final offlineChapterNumbers = <double>{};
    final offlineCount = (offlineChapters ?? const <OfflineChapter>[])
        .where(
          (chapter) =>
              _comicKey(chapter.comic.sourceName, chapter.comic.slug) ==
              comicKey,
        )
        .where((chapter) {
          if (chapter.isCompleted) {
            offlineChapterNumbers.add(chapter.chapterNumber);
            knownChapterNumbers.add(chapter.chapterNumber);
            return true;
          }
          return false;
        })
        .length;
    final queuedCount = (queue ?? const <OfflineDownloadBatch>[])
        .where(
          (batch) =>
              _comicKey(batch.comic.sourceName, batch.comic.slug) == comicKey,
        )
        .where(
          (batch) => batch.status != 'completed' && batch.status != 'cancelled',
        )
        .fold<int>(0, (count, batch) {
          knownChapterNumbers.addAll(batch.chapterNumbers);
          return count + batch.chapterNumbers.length;
        });
    final syncedEntries =
        libraryState?.downloadEntries ?? const <DownloadEntry>[];
    for (final entry in syncedEntries) {
      knownChapterNumbers.add(entry.chapterNumber);
    }

    return _ComicDownloadState(
      offlineCount: offlineCount,
      queuedCount: queuedCount,
      syncedCount: syncedEntries.length,
      offlineChapterNumbers: offlineChapterNumbers,
      knownChapterNumbers: knownChapterNumbers,
    );
  }

  final int offlineCount;
  final int queuedCount;
  final int syncedCount;
  final Set<double> offlineChapterNumbers;
  final Set<double> knownChapterNumbers;

  IconData get icon {
    if (offlineCount > 0) return TonztoonIcons.badgeCheckFilled;
    if (queuedCount > 0 || syncedCount > 0) return TonztoonIcons.clock;
    return TonztoonIcons.download;
  }

  String? get label {
    if (offlineCount > 0) return '$offlineCount chapter tersedia offline';
    if (queuedCount > 0) return '$queuedCount chapter dalam antrean offline';
    if (syncedCount > 0) return '$syncedCount chapter punya status download';
    return null;
  }

  bool get hasActivity =>
      offlineCount > 0 || queuedCount > 0 || syncedCount > 0;
}

class _ComicDetailUi {
  const _ComicDetailUi({
    required this.title,
    required this.alternativeTitle,
    required this.coverImageUrl,
    required this.type,
    required this.status,
    required this.rating,
    required this.author,
    required this.artist,
    required this.totalChapters,
    required this.totalViews,
    required this.updatedAt,
    required this.synopsis,
    required this.genres,
    required this.chapters,
    this.sourceName = 'komiku',
    this.slug = '',
  });

  factory _ComicDetailUi.fromDetail(ComicDetail detail) {
    return _ComicDetailUi(
      title: detail.title,
      sourceName: detail.sourceName,
      slug: detail.slug,
      alternativeTitle: detail.alternativeTitles?.trim().isNotEmpty == true
          ? detail.alternativeTitles!.trim()
          : detail.title,
      coverImageUrl: detail.coverImageUrl,
      type: detail.type?.trim().isNotEmpty == true
          ? detail.type!.trim()
          : 'Komik',
      status: detail.status?.trim().isNotEmpty == true
          ? detail.status!.trim()
          : 'Ongoing',
      rating: detail.rating == null ? '-' : detail.rating!.toStringAsFixed(1),
      author: detail.author?.trim().isNotEmpty == true
          ? detail.author!.trim()
          : 'Tidak diketahui',
      artist: detail.artist?.trim().isNotEmpty == true
          ? detail.artist!.trim()
          : 'Tidak diketahui',
      totalChapters: detail.totalChapters.toString(),
      totalViews: formatCompactCount(detail.totalView ?? 0),
      updatedAt: 'Terbaru',
      synopsis: detail.synopsis?.trim().isNotEmpty == true
          ? detail.synopsis!.trim()
          : 'Sinopsis belum tersedia untuk komik ini.',
      genres: detail.genres.isEmpty
          ? const ['Komik']
          : detail.genres.map((genre) => genre.name).toList(),
      chapters: const [],
    );
  }

  _ComicDetailUi copyWith({List<_ChapterUi>? chapters}) {
    return _ComicDetailUi(
      title: title,
      sourceName: sourceName,
      slug: slug,
      alternativeTitle: alternativeTitle,
      coverImageUrl: coverImageUrl,
      type: type,
      status: status,
      rating: rating,
      author: author,
      artist: artist,
      totalChapters: totalChapters,
      totalViews: totalViews,
      updatedAt: updatedAt,
      synopsis: synopsis,
      genres: genres,
      chapters: chapters ?? this.chapters,
    );
  }

  final String title;
  final String sourceName;
  final String slug;
  final String alternativeTitle;
  final String? coverImageUrl;
  final String type;
  final String status;
  final String rating;
  final String author;
  final String artist;
  final String totalChapters;
  final String totalViews;
  final String updatedAt;
  final String synopsis;
  final List<String> genres;
  final List<_ChapterUi> chapters;

  String get firstChapterLabel => chapters.first.title;
}

class _ChapterUi {
  const _ChapterUi({
    required this.title,
    required this.subtitle,
    required this.chapterNumber,
  });

  factory _ChapterUi.fromChapterItem(ChapterListItem chapter) {
    final chapterLabel = formatChapterNumber(chapter.chapterNumber);
    final pages = chapter.totalImages <= 0
        ? 'Jumlah halaman belum tersedia'
        : '${chapter.totalImages} halaman';
    final date = chapter.releaseDate ?? chapter.createdAt;
    return _ChapterUi(
      title: chapter.title?.trim().isNotEmpty == true
          ? chapter.title!.trim()
          : 'Chapter $chapterLabel',
      subtitle: '$pages - ${_relativeDateLabel(date)}',
      chapterNumber: chapter.chapterNumber,
    );
  }

  final String title;
  final String subtitle;
  final double chapterNumber;
}
