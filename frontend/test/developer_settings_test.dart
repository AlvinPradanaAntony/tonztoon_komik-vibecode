import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tonztoon/src/core/config.dart';
import 'package:tonztoon/src/core/storage.dart';
import 'package:tonztoon/src/repositories/providers.dart';

void main() {
  late Directory hiveDir;
  late Box<dynamic> settingsBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('tonztoon_developer_test_');
    Hive.init(hiveDir.path);
    final boxes = await Future.wait([
      Hive.openBox<dynamic>(HiveBoxes.settings),
      Hive.openBox<dynamic>(HiveBoxes.auth),
      Hive.openBox<dynamic>(HiveBoxes.progress),
      Hive.openBox<dynamic>(HiveBoxes.library),
      Hive.openBox<dynamic>(HiveBoxes.cache),
    ]);
    settingsBox = boxes.first;
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  group('developer API URL', () {
    test('accepts HTTP(S) API URLs and removes only a trailing slash', () {
      expect(
        normalizeDeveloperApiBaseUrl(' https://api.tonztoon.test/api/v1/ '),
        'https://api.tonztoon.test/api/v1',
      );
      expect(
        normalizeDeveloperApiBaseUrl('http://192.168.1.3:8000'),
        'http://192.168.1.3:8000',
      );
    });

    test('rejects unsafe or malformed URLs', () {
      expect(normalizeDeveloperApiBaseUrl('api.tonztoon.test'), isNull);
      expect(normalizeDeveloperApiBaseUrl('ftp://api.tonztoon.test'), isNull);
      expect(
        normalizeDeveloperApiBaseUrl('https://user@api.tonztoon.test'),
        isNull,
      );
      expect(
        normalizeDeveloperApiBaseUrl('https://api.tonztoon.test/api?debug=1'),
        isNull,
      );
    });

    test('AppConfig keeps non-API build configuration on URL override', () {
      const config = AppConfig(
        apiBaseUrl: 'https://production.tonztoon.test/api/v1',
        githubRepository: 'tonztoon/repository',
        googleWebClientId: 'web-client',
      );

      final overridden = config.copyWith(
        apiBaseUrl: 'http://10.0.2.2:8000/api/v1',
      );

      expect(overridden.apiBaseUrl, 'http://10.0.2.2:8000/api/v1');
      expect(overridden.githubRepository, config.githubRepository);
      expect(overridden.googleWebClientId, config.googleWebClientId);
    });

    test('uses the override only while developer mode is enabled', () async {
      await settingsBox.clear();
      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'https://production.tonztoon.test/api/v1',
            ),
          ),
          localStoreProvider.overrideWithValue(
            LocalStore(settings: settingsBox),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(effectiveApiBaseUrlProvider),
        'https://production.tonztoon.test/api/v1',
      );

      await container.read(developerSettingsProvider.notifier).setEnabled(true);
      await container
          .read(developerSettingsProvider.notifier)
          .setApiBaseUrl('http://10.0.2.2:8000/api/v1/');
      expect(
        container.read(effectiveApiBaseUrlProvider),
        'http://10.0.2.2:8000/api/v1',
      );

      await container
          .read(developerSettingsProvider.notifier)
          .setEnabled(false);
      expect(
        container.read(effectiveApiBaseUrlProvider),
        'https://production.tonztoon.test/api/v1',
      );
      expect(settingsBox.get('developer_api_base_url'), isNull);
    });
  });
}
