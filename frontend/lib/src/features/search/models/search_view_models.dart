part of '../search_screen.dart';

class _SearchComicUi {
  const _SearchComicUi({
    required this.summary,
    required this.source,
    required this.type,
    required this.rating,
    required this.status,
    required this.genre,
    required this.genres,
    required this.chapter,
    required this.description,
    required this.updateRank,
    required this.popularityRank,
    required this.totalViewRank,
  });

  factory _SearchComicUi.fromSummary(ComicSummary summary) {
    final source = comicSourceDisplayName(summary.sourceName);
    final chapterNumber = summary.latestChapterNumber;
    final type = comicTypeFilterLabel(summary.type, fallback: 'Komik');
    final genres = summary.genres
        .map((genre) => genre.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final ratingValue = summary.rating ?? 0;
    final totalView = summary.totalView ?? 0;
    return _SearchComicUi(
      summary: summary,
      source: source,
      type: type,
      rating: ratingValue.toStringAsFixed(1),
      status: comicStatusFilterLabel(summary.status),
      genre: genres.isEmpty ? 'Genre' : genres.first,
      genres: genres,
      chapter: chapterNumber == null
          ? 'Chapter terbaru'
          : 'Chapter ${formatChapterNumber(chapterNumber)}',
      description:
          'Komik dari $source dengan pembaruan chapter dan informasi katalog terbaru.',
      updateRank: chapterNumber?.round() ?? totalView,
      popularityRank: totalView > 0 ? totalView : (ratingValue * 1000).round(),
      totalViewRank: totalView,
    );
  }

  final ComicSummary summary;
  final String source;
  final String type;
  final String rating;
  final String status;
  final String genre;
  final List<String> genres;
  final String chapter;
  final String description;
  final int updateRank;
  final int popularityRank;
  final int totalViewRank;

  double get ratingValue => double.tryParse(rating) ?? 0;
}
