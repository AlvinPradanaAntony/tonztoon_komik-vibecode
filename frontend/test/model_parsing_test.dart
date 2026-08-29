import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:tonztoon/src/core/remote_push_inbox.dart';
import 'package:tonztoon/src/models/auth.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/models/library.dart';
import 'package:tonztoon/src/models/progress.dart';
import 'package:tonztoon/src/models/source_info.dart';
import 'package:tonztoon/src/widgets/comic_card.dart';

void main() {
  test('remote push message parses into app notification', () {
    const message = RemoteMessage(
      messageId: 'fcm-message-1',
      notification: RemoteNotification(
        title: 'Chapter baru tersedia',
        body: 'Solo Leveling Chapter 201 baru saja rilis.',
      ),
      data: {
        'id': 'chapter:komiku:solo-leveling:201',
        'kind': 'chapter_update',
        'category': 'Update',
        'route': '/comic/komiku/solo-leveling',
      },
    );

    final notification = appNotificationFromRemoteMessage(message);

    expect(notification, isNotNull);
    expect(notification!.id, 'remote:chapter:komiku:solo-leveling:201');
    expect(notification.title, 'Chapter baru tersedia');
    expect(notification.kind, 'chapter_update');
    expect(notification.actionRoute, '/comic/komiku/solo-leveling');
  });

  test('auth security overview exposes password availability', () {
    final overview = AuthSecurityOverview.fromJson(const {
      'email': 'reader@example.test',
      'email_verified': true,
      'provider': 'google',
      'has_password': false,
      'current_session': {
        'session_id': '00000000-0000-0000-0000-000000000001',
        'issued_at': 1710000000,
        'expires_at': 1710003600,
      },
    });

    expect(overview.email, 'reader@example.test');
    expect(overview.provider, 'google');
    expect(overview.emailVerified, isTrue);
    expect(overview.hasPassword, isFalse);
    expect(overview.currentSession.expiresAt, 1710003600);
  });

  test('comic summary parses backend list item shape', () {
    final comic = ComicSummary.fromJson(const {
      'title': 'Solo Leveling',
      'slug': 'solo-leveling',
      'source_name': 'komiku_asia',
      'cover_image_url': 'https://example.test/cover.jpg',
      'rating': 9.2,
      'latest_chapter_number': 201,
      'latest_chapter_release_date': '2026-05-30T12:00:00Z',
      'genres': [
        {'id': 1, 'name': 'Action', 'slug': 'action'},
      ],
    });

    expect(comic.title, 'Solo Leveling');
    expect(comic.sourceName, 'komiku_asia');
    expect(comic.latestChapterNumber, 201);
    expect(
      comic.hasNewChapter(now: DateTime.parse('2026-06-01T12:00:00Z')),
      isTrue,
    );
    expect(
      comic.hasNewChapter(now: DateTime.parse('2026-06-08T12:00:01Z')),
      isFalse,
    );
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

  test('chapter payload parses optional intrinsic image dimensions', () {
    final payload = ChapterPayload.fromJson(const {
      'source_name': 'komiku_asia',
      'chapter_number': 179,
      'images': [
        {
          'page': 1,
          'url': 'https://example.test/page-1.jpg',
          'width': 720,
          'height': 5700,
        },
        {'page': 2, 'url': 'https://example.test/page-2.jpg'},
      ],
      'total': 2,
    });

    expect(payload.images.first.width, 720);
    expect(payload.images.first.height, 5700);
    expect(payload.images.first.aspectRatio, closeTo(720 / 5700, 0.000001));
    expect(payload.images.last.aspectRatio, isNull);
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
      'auto_scroll_enabled': true,
      'auto_scroll_speed': 2.25,
    });

    expect(prefs.defaultReadingMode, 'paged');
    expect(prefs.readingDirection, 'rtl');
    expect(prefs.markReadOnComplete, isFalse);
    expect(prefs.defaultBingeMode, isTrue);
    expect(prefs.autoScrollEnabled, isTrue);
    expect(prefs.autoScrollSpeed, 2.25);
    expect(prefs.toJson(), {
      'default_reading_mode': 'paged',
      'reading_direction': 'rtl',
      'mark_read_on_complete': false,
      'default_binge_mode': true,
      'auto_scroll_enabled': true,
      'auto_scroll_speed': 2.25,
    });
    expect(prefs.toJson(), isNot(contains('auto_next')));
  });

  test('reader preferences default switches are off', () {
    const prefs = ReaderPreferences();

    expect(prefs.markReadOnComplete, isFalse);
    expect(prefs.defaultBingeMode, isFalse);
    expect(prefs.autoScrollEnabled, isFalse);
    expect(prefs.autoScrollSpeed, 1.0);
    expect(prefs.toJson()['mark_read_on_complete'], isFalse);
    expect(prefs.toJson()['default_binge_mode'], isFalse);
    expect(prefs.toJson()['auto_scroll_enabled'], isFalse);
    expect(prefs.toJson()['auto_scroll_speed'], 1.0);
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

  test('library comic state parses linked bookmark metadata', () {
    final state = LibraryComicState.fromJson(const {
      'comic': {
        'comic_id': 2,
        'title': 'Solo Leveling',
        'slug': 'solo-leveling',
        'source_name': 'komikcast',
      },
      'bookmarked': true,
      'bookmark_relation': 'linked',
      'bookmark_origin': {
        'comic_id': 1,
        'title': 'Solo Leveling',
        'slug': 'solo-leveling',
        'source_name': 'komiku_asia',
      },
      'linked_comics': [
        {
          'comic_id': 1,
          'title': 'Solo Leveling',
          'slug': 'solo-leveling',
          'source_name': 'komiku_asia',
        },
      ],
      'collections': [],
    });

    expect(state.bookmarked, isTrue);
    expect(state.bookmarkRelation, BookmarkRelation.linked);
    expect(state.bookmarkOrigin?.sourceName, 'komiku_asia');
    expect(state.linkedComics.single.sourceName, 'komiku_asia');
  });

  test('chapter completion sync result parses counters', () {
    final result = BookmarkLinkSaveResult.fromJson(const {
      'linked_total': 2,
      'completed_propagated': 7,
    });

    expect(result.linkedTotal, 2);
    expect(result.completedPropagated, 7);
  });
}
