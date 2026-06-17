part of '../full_catalog_screen.dart';

class _CatalogEntry {
  const _CatalogEntry({
    required this.comic,
    required this.source,
    required this.type,
    required this.status,
    required this.genre,
    required this.rating,
    required this.updateRank,
    required this.popularityRank,
  });

  factory _CatalogEntry.fromSummary(ComicSummary comic, int index) {
    final source = comicSourceDisplayName(comic.sourceName);
    final type = comicTypeFilterLabel(comic.type);
    final status = comicStatusFilterLabel(comic.status);
    final genre = comic.genres.isEmpty ? type : comic.genres.first.name;
    final rating = comic.rating ?? 0;
    final totalView = comic.totalView ?? 0;
    return _CatalogEntry(
      comic: comic,
      source: source,
      type: type,
      status: status,
      genre: genre,
      rating: rating,
      updateRank: comic.latestChapterNumber?.round() ?? (1000 - index),
      popularityRank: totalView > 0 ? totalView : (rating * 1000).round(),
    );
  }

  final ComicSummary comic;
  final String source;
  final String type;
  final String status;
  final String genre;
  final double rating;
  final int updateRank;
  final int popularityRank;
}
