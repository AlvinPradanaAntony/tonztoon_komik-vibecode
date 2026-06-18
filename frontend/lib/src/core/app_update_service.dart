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
      : description;

  Map<String, dynamic> toStoredJson() => {
    'tag_name': tagName,
    'version': version.toString(),
    'description': description,
    'release_page_url': releasePageUrl,
    'apk_download_url': apkDownloadUrl,
    'ios_artifact_download_url': iosArtifactDownloadUrl,
  };
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
      throw AppUpdateException(_githubUpdateErrorMessage(error), cause: error);
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

String _githubUpdateErrorMessage(DioException error) {
  final statusCode = error.response?.statusCode;
  final detail = _githubErrorDetail(error.response?.data);
  final suffix = detail == null ? '' : ' ($detail)';

  return switch (statusCode) {
    403 =>
      'Tidak dapat memeriksa pembaruan dari GitHub: batas akses API tercapai atau akses ditolak$suffix.',
    404 =>
      'Tidak dapat memeriksa pembaruan dari GitHub: repository atau release tidak ditemukan$suffix.',
    401 =>
      'Tidak dapat memeriksa pembaruan dari GitHub: akses tidak diizinkan$suffix.',
    500 || 502 || 503 || 504 =>
      'Tidak dapat memeriksa pembaruan dari GitHub: layanan GitHub sedang bermasalah$suffix.',
    _ => _networkUpdateErrorMessage(error, suffix),
  };
}

String _networkUpdateErrorMessage(DioException error, String suffix) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'Tidak dapat memeriksa pembaruan dari GitHub: koneksi ke GitHub timeout$suffix.',
    DioExceptionType.connectionError =>
      'Tidak dapat memeriksa pembaruan dari GitHub: koneksi internet atau DNS bermasalah$suffix.',
    DioExceptionType.badCertificate =>
      'Tidak dapat memeriksa pembaruan dari GitHub: sertifikat koneksi tidak valid$suffix.',
    _ => 'Tidak dapat memeriksa pembaruan dari GitHub$suffix.',
  };
}

String? _githubErrorDetail(Object? data) {
  if (data is Map) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  }
  if (data is String && data.trim().isNotEmpty && data.length <= 140) {
    return data.trim();
  }
  return null;
}
