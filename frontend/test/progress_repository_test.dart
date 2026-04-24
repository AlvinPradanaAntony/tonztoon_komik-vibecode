import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon_komik/src/core/api_client.dart';
import 'package:tonztoon_komik/src/core/config.dart';
import 'package:tonztoon_komik/src/core/storage.dart';
import 'package:tonztoon_komik/src/core/token_store.dart';
import 'package:tonztoon_komik/src/models/comic.dart';
import 'package:tonztoon_komik/src/models/progress.dart';
import 'package:tonztoon_komik/src/repositories/progress_repository.dart';

void main() {
  late Directory tempDir;
  late LocalStore store;
  late MemoryTokenStore tokenStore;
  late ProgressRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tonztoon_test_');
    Hive.init(tempDir.path);
    final settings = await Hive.openBox<dynamic>('settings_test');
    final auth = await Hive.openBox<dynamic>('auth_test');
    final progress = await Hive.openBox<dynamic>('progress_test');
    final cache = await Hive.openBox<dynamic>('cache_test');
    store = LocalStore(
      settings: settings,
      auth: auth,
      progress: progress,
      cache: cache,
    );
    tokenStore = MemoryTokenStore();
    final api = TonztoonApi(
      config: const AppConfig(apiBaseUrl: 'http://localhost/api/v1'),
      tokenStore: tokenStore,
    );
    repository = ProgressRepository(api, tokenStore, store);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('guest progress is stored and returned locally', () async {
    final progress = ReadingProgress.fromReader(
      comic: const ComicSummary(
        title: 'Lookism',
        slug: 'lookism',
        sourceName: 'komiku',
        coverImageUrl: 'https://example.test/cover.jpg',
      ),
      chapterNumber: 603,
      scrollOffset: 900,
      pageItemIndex: 1,
      totalPageItems: 5,
    );

    await repository.saveProgress(progress);

    final restored = await repository.getProgress('komiku', 'lookism');
    final continueReading = await repository.getContinueReading();

    expect(restored?.chapterNumber, 603);
    expect(restored?.scrollOffset, 900);
    expect(continueReading.single.comicTitle, 'Lookism');
  });
}
