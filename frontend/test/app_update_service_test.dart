import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tonztoon/src/core/app_update_service.dart';
import 'package:tonztoon/src/core/storage.dart';

void main() {
  late Directory hiveDir;
  late Box<dynamic> settings;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('tonztoon_update_test_');
    Hive.init(hiveDir.path);
    settings = await Hive.openBox<dynamic>('app_update_test_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() => settings.clear());

  test('parses semantic versions from GitHub release labels', () {
    expect(parseAppVersion('v1.12.0').toString(), '1.12.0');
    expect(parseAppVersion('release-v2.0.1-beta.2').toString(), '2.0.1-beta.2');
    expect(parseAppVersion('latest'), isNull);
  });

  test('parses APK and IPA assets from GitHub release', () {
    final release = AppRelease.fromJson(const {
      'tag_name': 'v1.12.0',
      'body': 'New reader controls',
      'html_url': 'https://github.test/releases/tag/v1.12.0',
      'assets': [
        {
          'name': 'tonztoon-v1.12.0.apk',
          'browser_download_url': 'https://github.test/tonztoon.apk',
        },
        {
          'name': 'tonztoon-v1.12.0.ipa',
          'browser_download_url': 'https://github.test/tonztoon.ipa',
        },
      ],
    });

    expect(release.version.toString(), '1.12.0');
    expect(release.apkDownloadUrl, 'https://github.test/tonztoon.apk');
    expect(release.iosArtifactDownloadUrl, 'https://github.test/tonztoon.ipa');
    expect(release.releaseNotes, 'New reader controls');
  });

  test(
    'shows pending changelog once after installed version changes',
    () async {
      final store = LocalStore(
        settings: settings,
        auth: settings,
        progress: settings,
        library: settings,
        cache: settings,
      );
      final service = AppUpdateService(
        githubRepository: 'owner/repository',
        store: store,
        loadPackageInfo: () async => PackageInfo(
          appName: 'TonzToon',
          packageName: 'com.tonzdev.tonztoon',
          version: '1.12.0',
          buildNumber: '11',
        ),
      );
      final release = AppRelease.fromJson(const {
        'tag_name': 'v1.12.0',
        'body': 'Fresh changelog',
        'html_url': 'https://github.test/releases/tag/v1.12.0',
        'assets': <dynamic>[],
      });
      await settings.put('app_update_last_seen_version', '1.11.0');
      await service.rememberPendingRelease(release);

      final changelog = await service.consumeInstalledChangelog();

      expect(changelog?.displayVersion, 'v1.12.0');
      expect(changelog?.releaseNotes, 'Fresh changelog');
      expect(await service.consumeInstalledChangelog(), isNull);
      expect(settings.get('app_update_pending_release'), isNull);
    },
  );
}
