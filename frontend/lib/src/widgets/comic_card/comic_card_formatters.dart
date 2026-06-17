part of '../comic_card.dart';

String _comicStatusLabel(String? status) {
  final value = status?.trim() ?? '';
  return value.isEmpty ? 'Ongoing' : comicBadgeLabel(value);
}

String _formatCompactMetric(int value) {
  if (value >= 1000000000) {
    return '${_formatCompactDecimal(value / 1000000000)}B';
  }
  if (value >= 1000000) {
    return '${_formatCompactDecimal(value / 1000000)}M';
  }
  if (value >= 1000) {
    return '${_formatCompactDecimal(value / 1000)}K';
  }
  return value.toString();
}

String _formatCompactDecimal(double value) {
  final formatted = value.toStringAsFixed(value >= 10 ? 0 : 1);
  return formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
}

String _relativeComicUpdateTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.isNegative || difference.inMinutes < 1) return 'Baru saja';
  if (difference.inMinutes < 60) return '${difference.inMinutes} menit lalu';
  if (difference.inHours < 24) return '${difference.inHours} jam lalu';
  if (difference.inDays < 7) return '${difference.inDays} hari lalu';
  if (difference.inDays < 30) return '${difference.inDays ~/ 7} minggu lalu';
  if (difference.inDays < 365) return '${difference.inDays ~/ 30} bulan lalu';
  return '${difference.inDays ~/ 365} tahun lalu';
}

String comicSourceLabel(ComicSummary comic) {
  return comicSourceNameLabel(comic.sourceName);
}

String comicSourceNameLabel(String sourceName) {
  final value = sourceName.trim();
  if (value.isEmpty) return 'Komiku';
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map(_capitalizeBadgeWord)
      .join(' ');
}

String comicTypeFlag(String? type) {
  return switch (type?.toLowerCase()) {
    'manhwa' => '🇰🇷',
    'manga' => '🇯🇵',
    'manhua' => '🇨🇳',
    _ => '🏳️',
  };
}

String comicBadgeLabel(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
  if (normalized.isEmpty) return value;
  return normalized
      .split(' ')
      .map((word) => word.split('-').map(_capitalizeBadgeWord).join('-'))
      .join(' ');
}

String _capitalizeBadgeWord(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}

Color comicGenreColor(String genre) {
  return switch (genre.toLowerCase()) {
    'action' => const Color(0xFFE11D48),
    'adventure' => const Color(0xFF2563EB),
    'fantasy' => const Color(0xFF7C3AED),
    'drama' => const Color(0xFFDB2777),
    'system' => const Color(0xFF0891B2),
    'comedy' => const Color(0xFFF59E0B),
    'shounen' => const Color(0xFFEA580C),
    'apocalypse' => const Color(0xFF475569),
    'psychological' => const Color(0xFF9333EA),
    'supernatural' => const Color(0xFF059669),
    'swordplay' => const Color(0xFFDC2626),
    'sports' => const Color(0xFF16A34A),
    'romance' => const Color(0xFFEC4899),
    _ => const Color(0xFF3A86FF),
  };
}

ComicStatusStyle comicStatusStyle(ColorScheme colorScheme, String status) {
  final normalized = status.trim().toLowerCase();
  return switch (normalized) {
    'completed' ||
    'complete' ||
    'end' ||
    'ended' ||
    'tamat' ||
    'finish' ||
    'finished' => const ComicStatusStyle(
      icon: TonztoonIcons.badgeCheckFilled,
      color: Color(0xFF16A34A),
    ),
    'hiatus' => const ComicStatusStyle(
      icon: TonztoonIcons.circleDotDashed,
      color: Color(0xFFF59E0B),
    ),
    _ => ComicStatusStyle(
      icon: TonztoonIcons.clock,
      color: colorScheme.secondary,
    ),
  };
}

class ComicStatusStyle {
  const ComicStatusStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}
