import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/comic.dart';
import '../models/progress.dart';

/// Shared navigation helpers so every feature opens comic detail / reader
/// routes the same way, instead of re-deriving the route strings locally.

/// Pushes the comic detail route for [comic].
void openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

/// Pushes the reader route for an already-resolved [comic] at [chapterNumber].
Future<void> openReaderForComic(
  BuildContext context,
  ComicSummary comic,
  double chapterNumber,
) {
  return context.push<void>(
    '/reader/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}/${formatChapterNumber(chapterNumber)}',
    extra: comic,
  );
}

/// Pushes the reader route for a [ReadingProgress] entry, rebuilding the
/// [ComicSummary] the reader expects as route `extra`.
///
/// [includeLatestChapter] mirrors the existing call sites: continue-reading
/// surfaces pass the progress chapter as the comic's latest chapter, the
/// library bookmark/history list does not.
void openReaderForProgress(
  BuildContext context,
  ReadingProgress progress, {
  bool includeLatestChapter = true,
}) {
  final comic = ComicSummary(
    title: progress.comicTitle,
    slug: progress.comicSlug,
    sourceName: progress.sourceName,
    coverImageUrl: progress.coverImageUrl,
    latestChapterNumber: includeLatestChapter ? progress.chapterNumber : null,
  );
  unawaited(_openReaderForProgress(context, progress, comic));
}

Future<void> _openReaderForProgress(
  BuildContext context,
  ReadingProgress progress,
  ComicSummary comic,
) async {
  final coverUrl = progress.coverImageUrl?.trim();
  if (coverUrl != null && coverUrl.isNotEmpty) {
    try {
      // Decode the same source URL used by the reader before pushing the
      // route, so its loading cover can reuse Flutter's image cache.
      await precacheImage(
        CachedNetworkImageProvider(coverUrl),
        context,
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Navigation must still continue; ComicCover handles the fallback.
    }
  }

  if (!context.mounted) return;
  context.push(
    '/reader/${Uri.encodeComponent(progress.sourceName)}/${Uri.encodeComponent(progress.comicSlug)}/${formatChapterNumber(progress.chapterNumber)}',
    extra: comic,
  );
}
