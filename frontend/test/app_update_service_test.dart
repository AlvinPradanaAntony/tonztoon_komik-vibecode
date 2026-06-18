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

  test('limits release notes to the matching current version section', () {
    final release = AppRelease.fromJson(const {
      'tag_name': 'v1.12.0',
      'body': '''
# Changelog

## v1.12.0

- Auto scroll reader
- Source tag polish

## v1.11.0

- Older reader update

## v1.10.0

- Older catalog update
''',
      'html_url': 'https://github.test/releases/tag/v1.12.0',
      'assets': <dynamic>[],
    });

    expect(release.releaseNotes, contains('## v1.12.0'));
    expect(release.releaseNotes, contains('Auto scroll reader'));
    expect(release.releaseNotes, isNot(contains('## v1.11.0')));
    expect(release.releaseNotes, isNot(contains('Older reader update')));
  });

  test('limits release notes to the first version section as fallback', () {
    final release = AppRelease.fromJson(const {
      'tag_name': 'v1.12.0',
      'body': '''
# Changelog

## 2026.06.18

- Latest app update

## 2026.06.01

- Older app update
''',
      'html_url': 'https://github.test/releases/tag/v1.12.0',
      'assets': <dynamic>[],
    });

    expect(release.releaseNotes, contains('## 2026.06.18'));
    expect(release.releaseNotes, contains('Latest app update'));
    expect(release.releaseNotes, isNot(contains('Older app update')));
  });

  test('excludes previous version details from current changelog section', () {
    final release = AppRelease.fromJson(const {
      'tag_name': 'v1.16.0',
      'body': '''
# Changelog

Semua perubahan penting pada proyek TonzToon.

## [1.16.0] - 2026-06-17

### Added
- AutoScroll reader.

### Changed
- Reader polish.

---

<details>
<summary><strong>Riwayat versi sebelumnya</strong></summary>

### [1.15.3] - 2026-06-09

- Older update.
</details>
''',
      'html_url': 'https://github.test/releases/tag/v1.16.0',
      'assets': <dynamic>[],
    });

    expect(release.releaseNotes, contains('## [1.16.0]'));
    expect(release.releaseNotes, contains('AutoScroll reader'));
    expect(release.releaseNotes, isNot(contains('Riwayat versi sebelumnya')));
    expect(release.releaseNotes, isNot(contains('Older update')));
    expect(release.releaseNotes, isNot(contains('Semua perubahan penting')));
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
