/// Model sederhana untuk merepresentasikan data singkat komik.
/// Karena kita sedang fokus pada UI/UX, kita buat modelnya minimalis saja.
class ComicSummary {
  const ComicSummary({
    required this.title,
    this.coverImageUrl,
    this.type,
    this.latestChapterNumber,
  });

  final String title;
  final String? coverImageUrl;
  final String? type;
  final double? latestChapterNumber;
}

/// Fungsi pembantu untuk memformat angka chapter (misal: 10.0 jadi "10", 10.5 tetap "10.5")
String formatChapterNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

// Data dummy untuk keperluan testing UI
final List<ComicSummary> dummyComics = [
  const ComicSummary(
    title: 'Solo Leveling',
    type: 'Manhwa',
    latestChapterNumber: 179,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/222295l.jpg',
  ),
  const ComicSummary(
    title: 'One Piece',
    type: 'Manga',
    latestChapterNumber: 1111,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/2/253026l.jpg',
  ),
  const ComicSummary(
    title: 'Omniscient Reader\'s Viewpoint',
    type: 'Manhwa',
    latestChapterNumber: 200,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/240166l.jpg',
  ),
  const ComicSummary(
    title: 'Kagurabachi',
    type: 'Manga',
    latestChapterNumber: 24,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/2/292839l.jpg', // Random URL as fallback
  ),
];
