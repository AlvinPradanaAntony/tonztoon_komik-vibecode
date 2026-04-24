import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon_komik/src/models/comic.dart';
import 'package:tonztoon_komik/src/models/progress.dart';

void main() {
  test('comic summary parses backend list item shape', () {
    final comic = ComicSummary.fromJson(const {
      'title': 'Solo Leveling',
      'slug': 'solo-leveling',
      'source_name': 'komiku_asia',
      'cover_image_url': 'https://example.test/cover.jpg',
      'rating': 9.2,
      'latest_chapter_number': 201,
    });

    expect(comic.title, 'Solo Leveling');
    expect(comic.sourceName, 'komiku_asia');
    expect(comic.latestChapterNumber, 201);
  });

  test('progress payload matches backend upsert shape', () {
    final progress = ReadingProgress.fromReader(
      comic: const ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      ),
      chapterNumber: 603,
      scrollOffset: 1824.5,
      pageItemIndex: 18,
      totalPageItems: 80,
    );

    expect(progress.storageKey, 'komiku|lookism');
    expect(progress.toProgressPayload(), {
      'source_name': 'komiku',
      'comic_slug': 'lookism',
      'chapter_number': 603.0,
      'reading_mode': 'vertical',
      'scroll_offset': 1824.5,
      'page_index': null,
      'last_read_page_item_index': 18,
      'total_page_items': 80,
      'is_completed': false,
    });
  });
}
