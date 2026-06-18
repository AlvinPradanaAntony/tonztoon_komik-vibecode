part of '../library_screen.dart';

String _formatBookmarkMetric(int value) => formatCompactCount(value);

Future<void> _refreshCollections(WidgetRef ref) async {
  ref.invalidate(collectionsProvider);
  await ref.read(collectionsProvider.future);
}

Future<void> _refreshCollectionDetail(WidgetRef ref, int collectionId) async {
  ref.invalidate(collectionDetailProvider(collectionId));
  ref.invalidate(collectionsProvider);
  await Future.wait([
    ref.read(collectionDetailProvider(collectionId).future),
    ref.read(collectionsProvider.future),
  ]);
}

void _openComicDetail(BuildContext context, ComicSummary comic) =>
    openComicDetail(context, comic);

void _openReader(BuildContext context, ReadingProgress progress) =>
    openReaderForProgress(context, progress, includeLatestChapter: false);

double _progressValue(ReadingProgress item) => readingProgressValue(item);

String _dateLabel(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'baru saja';
  if (difference.inHours < 1) return '${difference.inMinutes} menit lalu';
  if (difference.inDays < 1) return '${difference.inHours} jam lalu';
  if (difference.inDays < 7) return '${difference.inDays} hari lalu';
  return '${value.day}/${value.month}/${value.year}';
}

void _showMessage(BuildContext context, String message) {
  showAppSnackBar(
    context,
    message: message,
    type: AppSnackBarType.success,
    hideCurrent: false,
  );
}
