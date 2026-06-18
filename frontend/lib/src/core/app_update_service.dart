import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import 'storage.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.version,
    required this.description,
    required this.releasePageUrl,
    this.apkDownloadUrl,
    this.iosArtifactDownloadUrl,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    final version = parseAppVersion(tagName);
    if (version == null) {
      throw const FormatException(
        'Tag rilis GitHub tidak memiliki versi valid.',
      );
    }

    final assets = json['assets'] is List
        ? json['assets'] as List<dynamic>
        : const <dynamic>[];
    String? findAssetUrl(String extension) {
      for (final rawAsset in assets) {
        if (rawAsset is! Map) continue;
        final asset = Map<String, dynamic>.from(rawAsset);
        final name = (asset['name'] as String? ?? '').trim().toLowerCase();
        final url = (asset['browser_download_url'] as String? ?? '').trim();
        if (name.endsWith(extension) && url.isNotEmpty) return url;
      }
      return null;
    }

    return AppRelease(
      tagName: tagName,
      version: version,
      description: (json['body'] as String? ?? '').trim(),
      releasePageUrl: (json['html_url'] as String? ?? '').trim(),
      apkDownloadUrl: findAssetUrl('.apk'),
      iosArtifactDownloadUrl: findAssetUrl('.ipa'),
    );
  }

  factory AppRelease.fromStoredJson(Map<String, dynamic> json) {
    final version = parseAppVersion(json['version'] as String? ?? '');
    if (version == null) {
      throw const FormatException('Versi pembaruan tersimpan tidak valid.');
    }
    return AppRelease(
      tagName: (json['tag_name'] as String? ?? version.toString()).trim(),
      version: version,
      description: (json['description'] as String? ?? '').trim(),
      releasePageUrl: (json['release_page_url'] as String? ?? '').trim(),
      apkDownloadUrl: (json['apk_download_url'] as String?)?.trim(),
      iosArtifactDownloadUrl: (json['ios_artifact_download_url'] as String?)
          ?.trim(),
    );
  }

  factory AppRelease.localVersion(Version version) {
    return AppRelease(
      tagName: 'v$version',
      version: version,
      description: '',
      releasePageUrl: '',
    );
  }

  final String tagName;
  final Version version;
  final String description;
  final String releasePageUrl;
  final String? apkDownloadUrl;
  final String? iosArtifactDownloadUrl;

  String get displayVersion => tagName.isEmpty ? 'v$version' : tagName;

  String get releaseNotes => description.isEmpty
      ? 'Pembaruan ini membawa perbaikan bug dan peningkatan performa.'
      : _currentVersionReleaseNotes(description, version, tagName);

  Map<String, dynamic> toStoredJson() => {
    'tag_name': tagName,
    'version': version.toString(),
    'description': description,
    'release_page_url': releasePageUrl,
    'apk_download_url': apkDownloadUrl,
    'ios_artifact_download_url': iosArtifactDownloadUrl,
  };
}

String _currentVersionReleaseNotes(
  String description,
  Version version,
  String tagName,
) {
  final normalizedDescription = description.trim();
  if (normalizedDescription.isEmpty) {
    return 'Pembaruan ini membawa perbaikan bug dan peningkatan performa.';
  }

  final lines = normalizedDescription.split(RegExp(r'\r?\n'));
  final headings = _markdownHeadings(lines);
  if (headings.isEmpty) return normalizedDescription;

  final labels = _versionLabels(version, tagName);
  final matchingHeading = headings.firstWhere(
    (heading) => labels.any((label) => _headingMentionsVersion(heading, label)),
    orElse: () => const _MarkdownHeading.none(),
  );
  if (matchingHeading.exists) {
    return _sectionForHeading(lines, headings, matchingHeading);
  }

  final firstVersionHeading = headings.firstWhere(
    (heading) => _semverPattern.hasMatch(heading.normalizedTitle),
    orElse: () => const _MarkdownHeading.none(),
  );
  if (firstVersionHeading.exists) {
    return _sectionForHeading(lines, headings, firstVersionHeading);
  }

  return normalizedDescription;
}

List<String> _versionLabels(Version version, String tagName) {
  final labels = <String>{
    version.toString(),
    'v$version',
    version.canonicalizedVersion,
    'v${version.canonicalizedVersion}',
    tagName.trim(),
  };

  return labels
      .where((label) => label.isNotEmpty)
      .map(_normalizeVersionText)
      .where((label) => label.isNotEmpty)
      .toList();
}

String _sectionForHeading(
  List<String> lines,
  List<_MarkdownHeading> headings,
  _MarkdownHeading heading,
) {
  var endLine = lines.length;
  for (var index = heading.line + 1; index < lines.length; index++) {
    final line = lines[index].trim().toLowerCase();
    if (line == '---' ||
        line.startsWith('<details') ||
        line.startsWith('<summary')) {
      endLine = index;
      break;
    }
  }

  for (final nextHeading in headings) {
    if (nextHeading.line <= heading.line) continue;
    if (nextHeading.line >= endLine) continue;
    if (nextHeading.level <= heading.level ||
        _semverPattern.hasMatch(nextHeading.normalizedTitle)) {
      endLine = nextHeading.line;
      break;
    }
  }

  return lines.sublist(heading.line, endLine).join('\n').trim();
}

List<_MarkdownHeading> _markdownHeadings(List<String> lines) {
  final headings = <_MarkdownHeading>[];
  for (var index = 0; index < lines.length; index++) {
    final match = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(lines[index]);
    if (match == null) continue;
    headings.add(
      _MarkdownHeading(
        line: index,
        level: match.group(1)!.length,
        title: match.group(2)!,
      ),
    );
  }
  return headings;
}

bool _headingMentionsVersion(_MarkdownHeading heading, String versionLabel) {
  return heading.normalizedTitle.contains(versionLabel);
}

String _normalizeVersionText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^[\[\(]+|[\]\)]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

final _semverPattern = RegExp(r'\bv?\d+\.\d+\.\d+(?:[-+][0-9a-z.-]+)?\b');

class _MarkdownHeading {
  const _MarkdownHeading({
    required this.line,
    required this.level,
    required this.title,
  });

  const _MarkdownHeading.none() : line = -1, level = -1, title = '';

  final int line;
  final int level;
  final String title;

  bool get exists => line >= 0;

  String get normalizedTitle => _normalizeVersionText(title);
}

class AppUpdateService {
  AppUpdateService({
    required this.githubRepository,
    required LocalStore store,
    Dio? dio,
    PackageInfoLoader? loadPackageInfo,
  }) : _store = store,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 12),
               headers: const {
                 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2022-11-28',
               },
             ),
           ),
       _loadPackageInfo = loadPackageInfo ?? PackageInfo.fromPlatform;

  static const _lastSeenVersionKey = 'app_update_last_seen_version';
  static const _pendingReleaseKey = 'app_update_pending_release';

  final String githubRepository;
  final LocalStore _store;
  final Dio _dio;
  final PackageInfoLoader _loadPackageInfo;

  Future<AppRelease?> checkForUpdate() async {
    final results = await Future.wait([fetchLatestRelease(), currentVersion()]);
    final release = results[0] as AppRelease;
    final installedVersion = results[1] as Version;
    return release.version > installedVersion ? release : null;
  }

  Future<AppRelease> fetchLatestRelease() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$githubRepository/releases/latest',
      );
      final data = response.data;
      if (response.statusCode != 200 || data == null) {
        throw AppUpdateException('Respons GitHub Releases tidak valid.');
      }
      return AppRelease.fromJson(data);
    } on AppUpdateException {
      rethrow;
    } on DioException catch (error) {
      throw AppUpdateException(
        'Tidak dapat memeriksa pembaruan dari GitHub.',
        cause: error,
      );
    } on FormatException catch (error) {
      throw AppUpdateException(error.message, cause: error);
    }
  }

  Future<Version> currentVersion() async {
    final packageInfo = await _loadPackageInfo();
    final version = parseAppVersion(packageInfo.version);
    if (version == null) {
      throw AppUpdateException('Versi aplikasi saat ini tidak valid.');
    }
    return version;
  }

  Future<void> rememberPendingRelease(AppRelease release) {
    return _store.settings.put(_pendingReleaseKey, release.toStoredJson());
  }

  Future<AppRelease?> consumeInstalledChangelog() async {
    final installedVersion = await currentVersion();
    final installedLabel = installedVersion.toString();
    final lastSeenVersion = _store.settings.get(_lastSeenVersionKey);
    if (lastSeenVersion == null) {
      await _store.settings.put(_lastSeenVersionKey, installedLabel);
      return null;
    }
    if (lastSeenVersion == installedLabel) return null;

    await _store.settings.put(_lastSeenVersionKey, installedLabel);
    final pendingRelease = _readPendingRelease(_store.settings);
    if (pendingRelease != null && pendingRelease.version <= installedVersion) {
      await _store.settings.delete(_pendingReleaseKey);
      return pendingRelease;
    }

    try {
      final latestRelease = await fetchLatestRelease();
      if (latestRelease.version == installedVersion) return latestRelease;
    } catch (_) {
      // A generic changelog is still useful if GitHub is temporarily offline.
    }
    return AppRelease.localVersion(installedVersion);
  }

  AppRelease? _readPendingRelease(Box<dynamic> settings) {
    final value = settings.get(_pendingReleaseKey);
    if (value is! Map) return null;
    try {
      return AppRelease.fromStoredJson(Map<String, dynamic>.from(value));
    } on FormatException {
      return null;
    }
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

Version? parseAppVersion(String value) {
  final match = RegExp(
    r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?',
  ).firstMatch(value.trim());
  if (match == null) return null;
  try {
    return Version.parse(match.group(0)!);
  } on FormatException {
    return null;
  }
}
