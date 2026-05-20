import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/models/library.dart';
import 'package:tonztoon/src/models/progress.dart';
import 'package:tonztoon/src/models/source_info.dart';
import 'package:tonztoon/src/widgets/comic_card.dart';

void main() {
  test('comic summary parses backend list item shape', () {
    final comic = ComicSummary.fromJson(const {
      'title': 'Solo Leveling',
      'slug': 'solo-leveling',
      'source_name': 'komiku_asia',
      'cover_image_url': 'https://example.test/cover.jpg',
      'rating': 9.2,
      'latest_chapter_number': 201,
      'genres': [
        {'id': 1, 'name': 'Action', 'slug': 'action'},
      ],
    });

    expect(comic.title, 'Solo Leveling');
    expect(comic.sourceName, 'komiku_asia');
    expect(comic.latestChapterNumber, 201);
    expect(comic.genres.single.name, 'Action');
  });

  test('comic metadata parses string ratings and end status styling', () {
    final detail = ComicDetail.fromJson(const {
      'id': 1,
      'title': 'Finished Comic',
      'slug': 'finished-comic',
      'source_name': 'komiku',
      'source_url': 'https://example.test/finished-comic',
      'status': 'End',
      'rating': '92',
      'total_chapters': 12,
    });
    final style = comicStatusStyle(const ColorScheme.light(), detail.status!);

    expect(detail.rating, 9.2);
    expect(style.color, const Color(0xFF16A34A));
  });

  test('source info parses backend source shape', () {
    final source = SourceInfo.fromJson(const {
      'id': 'komiku',
      'label': 'Komiku',
      'base_url': 'https://komiku.test',
      'enabled': true,
      'db_comic_count': 1200,
    });

    expect(source.id, 'komiku');
    expect(source.label, 'Komiku');
    expect(source.enabled, isTrue);
    expect(source.dbComicCount, 1200);
  });

  test('progress payload matches backend upsert shape', () {
    final progress = ReadingProgress.fromReader(
      comic: const ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
      ),
      chapterNumber: 603,
      readingMode: 'vertical',
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

  test('reader preferences use default binge mode payload', () {
    final prefs = ReaderPreferences.fromJson(const {
      'default_reading_mode': 'paged',
      'reading_direction': 'rtl',
      'mark_read_on_complete': false,
      'default_binge_mode': true,
    });

    expect(prefs.defaultReadingMode, 'paged');
    expect(prefs.readingDirection, 'rtl');
    expect(prefs.markReadOnComplete, isFalse);
    expect(prefs.defaultBingeMode, isTrue);
    expect(prefs.toJson(), {
      'default_reading_mode': 'paged',
      'reading_direction': 'rtl',
      'mark_read_on_complete': false,
      'default_binge_mode': true,
    });
    expect(prefs.toJson(), isNot(contains('auto_next')));
  });

  test('reader preferences default switches are off', () {
    const prefs = ReaderPreferences();

    expect(prefs.markReadOnComplete, isFalse);
    expect(prefs.defaultBingeMode, isFalse);
    expect(prefs.toJson()['mark_read_on_complete'], isFalse);
    expect(prefs.toJson()['default_binge_mode'], isFalse);
  });

  test('library comic state parses multiple completed chapters', () {
    final state = LibraryComicState.fromJson(const {
      'comic': {
        'id': 1,
        'title': 'Lookism',
        'slug': 'lookism',
        'source_name': 'komiku',
      },
      'bookmarked': false,
      'collections': [],
      'completed_chapter_numbers': [1, 2.5, 3],
    });

    expect(state.completedChapterNumbers, [1.0, 2.5, 3.0]);
  });
}
