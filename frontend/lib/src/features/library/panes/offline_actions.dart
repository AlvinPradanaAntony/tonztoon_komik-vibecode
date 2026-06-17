part of '../library_shared_panes.dart';

Future<void> refreshFavoriteScenes(WidgetRef ref) async {
  ref.invalidate(favoriteScenesProvider);
  await ref.read(favoriteScenesProvider.future);
}

Future<void> refreshDownloads(WidgetRef ref) async {
  ref.invalidate(downloadsProvider);
  ref.invalidate(offlineChaptersProvider);
  ref.invalidate(offlineQueueProvider);
  await Future.wait([
    ref.read(downloadsProvider.future),
    ref.read(offlineChaptersProvider.future),
    ref.read(offlineQueueProvider.future),
  ]);
}

Future<void> refreshReadyDownloads(WidgetRef ref) async {
  ref.invalidate(offlineChaptersProvider);
  await ref.read(offlineChaptersProvider.future);
}

void _openComicDetail(BuildContext context, ComicSummary comic) =>
    openComicDetail(context, comic);

void _openSceneReader(BuildContext context, FavoriteScene scene) {
  openReaderForComic(context, scene.comic.toSummary(), scene.chapterNumber);
}

void _openOfflineChapter(BuildContext context, OfflineChapter chapter) {
  openReaderForComic(
    context,
    chapter.comic.toSummary(),
    chapter.chapterNumber,
  );
}

void _showMessage(BuildContext context, String message) {
  showAppSnackBar(
    context,
    message: message,
    type: AppSnackBarType.success,
    hideCurrent: false,
  );
}

void _returnToDownloadsAfterDelete(BuildContext context, String message) {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  _showMessage(context, message);
  navigator.popUntil((route) => route.isFirst);
  router.go(libraryDownloadsLocation);
}

Future<void> _reloadDownloadsAfterDelete(WidgetRef ref) async {
  ref.invalidate(downloadsProvider);
  ref.invalidate(offlineChaptersProvider);
  ref.invalidate(librarySummaryProvider);
  await Future.wait([
    ref.read(downloadsProvider.future),
    ref.read(offlineChaptersProvider.future),
    ref.read(librarySummaryProvider.future),
  ]);
}
