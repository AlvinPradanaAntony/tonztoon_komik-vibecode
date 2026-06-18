import '../models/progress.dart';

/// Shared, domain-level formatters used across feature modules. Keep purely
/// presentational helpers that are identical across screens here so they have a
/// single source of truth.

/// Fraction (0..1) of a reading progress entry, used to drive progress bars.
/// Falls back to 1 for completed items and 0 when the total page count is
/// unknown.
double readingProgressValue(ReadingProgress item) {
  final total = item.totalPageItems;
  if (total == null || total <= 0) return item.isCompleted ? 1 : 0;
  final current = (item.lastReadPageItemIndex ?? item.pageIndex ?? 0) + 1;
  return (current / total).clamp(0, 1).toDouble();
}

/// Human label for the current page of a reading progress entry,
/// e.g. "Halaman 3/20" or "Halaman 3" when the total is unknown.
String readingProgressPageLabel(ReadingProgress item) {
  final current = (item.lastReadPageItemIndex ?? item.pageIndex ?? 0) + 1;
  final total = item.totalPageItems;
  if (total == null || total <= 0) return 'Halaman $current';
  return 'Halaman $current/$total';
}

/// Compact count for large numbers: 1500 -> "1.5K", 2000000 -> "2M",
/// 3000000000 -> "3B". Trailing ".0" is dropped.
String formatCompactCount(int value) {
  if (value >= 1000000000) {
    return '${_compactDecimal(value / 1000000000)}B';
  }
  if (value >= 1000000) {
    return '${_compactDecimal(value / 1000000)}M';
  }
  if (value >= 1000) {
    return '${_compactDecimal(value / 1000)}K';
  }
  return value.toString();
}

String _compactDecimal(double value) {
  final rounded = value.toStringAsFixed(value >= 10 ? 0 : 1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}
