import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/app_icons.dart';
import '../core/app_update_service.dart';
import '../utils/app_assets.dart';
import 'tonztoon_modal_dialog.dart';

bool get isSupportedUpdatePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppRelease release,
  required AppUpdateService service,
}) {
  return showTonztoonModal<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppUpdateDialog(release: release, service: service),
  );
}

Future<void> showInstalledChangelogDialog(
  BuildContext context, {
  required AppRelease release,
}) {
  return showTonztoonModal<void>(
    context: context,
    builder: (context) => TonztoonModalDialog(
      eyebrow: 'Pembaruan Selesai',
      title: 'TonzToon sudah diperbarui',
      emphasis: release.displayVersion,
      message: 'Terima kasih sudah memakai versi terbaru.',
      helperText: 'Berikut perubahan yang baru dipasang di perangkat kamu.',
      helperIcon: TonztoonIcons.badgeCheck,
      variant: TonztoonModalVariant.success,
      art: TonztoonModalArt.cloudSync,
      content: _ReleaseNotes(
        notes: release.releaseNotes,
        version: release.displayVersion,
      ),
      primaryLabel: 'Mulai Membaca',
      onPrimaryPressed: () => Navigator.of(context).pop(),
    ),
  );
}

Future<void> showAppInfoDialog(
  BuildContext context, {
  required AppUpdateService service,
}) {
  return showTonztoonModal<void>(
    context: context,
    builder: (context) => AppInfoDialog(service: service),
  );
}

class AppInfoDialog extends StatefulWidget {
  const AppInfoDialog({super.key, required this.service});

  final AppUpdateService service;

  @override
  State<AppInfoDialog> createState() => _AppInfoDialogState();
}

class _AppInfoDialogState extends State<AppInfoDialog> {
  bool _loading = true;
  PackageInfo? _packageInfo;
  String? _releaseNotes;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _packageInfo = info;
      });

      final currentVer = parseAppVersion(info.version);
      if (currentVer != null) {
        try {
          final latestRelease = await widget.service.fetchLatestRelease();
          final currentRelease = AppRelease(
            tagName: 'v$currentVer',
            version: currentVer,
            description: latestRelease.description,
            releasePageUrl: latestRelease.releasePageUrl,
          );
          if (mounted) {
            setState(() {
              _releaseNotes = currentRelease.releaseNotes;
              _loading = false;
            });
            return;
          }
        } catch (_) {
          // Fallback to local release notes
        }
      }

      if (mounted) {
        setState(() {
          _releaseNotes =
              'Pembaruan ini membawa perbaikan bug dan peningkatan performa.';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _releaseNotes =
              'Pembaruan ini membawa perbaikan bug dan peningkatan performa.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _packageInfo;
    final versionLabel =
        info != null ? 'v${info.version} (${info.buildNumber})' : 'Memuat...';

    return TonztoonModalDialog(
      contentTopPadding: 74,
      titleWidget: Image.asset(
        AppAssets.logoAppLarge,
        height: 80,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
      emphasis: versionLabel,
      emphasisStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
      variant: TonztoonModalVariant.primary,
      art: TonztoonModalArt.cloudSync,
      content: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          : _ReleaseNotes(
              notes: _releaseNotes ?? 'Tidak ada catatan rilis.',
              version: info != null ? 'v${info.version}' : null,
            ),
      primaryLabel: 'Tutup',
      onPrimaryPressed: () => Navigator.of(context).pop(),
    );
  }
}


class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.service,
  });

  final AppRelease release;
  final AppUpdateService service;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  StreamSubscription<OtaEvent>? _subscription;
  bool _downloading = false;
  bool _exitScheduled = false;
  double _progress = 0;
  String? _statusText;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return PopScope(
      canPop: !_downloading,
      child: TonztoonModalDialog(
        eyebrow: 'Versi Baru Tersedia',
        title: 'Saatnya memperbarui TonzToon',
        emphasis: widget.release.displayVersion,
        message: isAndroid
            ? 'Unduh APK terbaru lalu lanjutkan konfirmasi instalasi dari Android.'
            : 'Buka artifact rilis terbaru lalu selesaikan instalasi secara manual.',
        helperText: isAndroid
            ? 'Android akan menutup aplikasi saat APK baru siap dipasang.'
            : 'iOS membatasi instalasi langsung dari aplikasi. Tautan akan dibuka di browser.',
        helperIcon: TonztoonIcons.shieldCheck,
        art: TonztoonModalArt.cloudSync,
        showCloseButton: !_downloading,
        showActions: !_downloading,
        secondaryLabel: 'Nanti Saja',
        onSecondaryPressed: () => Navigator.of(context).pop(),
        primaryLabel: isAndroid ? 'Unduh Update' : 'Buka Download',
        onPrimaryPressed: _startUpdate,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReleaseNotes(
              notes: widget.release.releaseNotes,
              version: widget.release.displayVersion,
            ),
            if (_downloading || _statusText != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _downloading ? _progress : null,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText ?? 'Menyiapkan pembaruan...',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startUpdate() async {
    if (_downloading) return;
    try {
      await widget.service.rememberPendingRelease(widget.release);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _startAndroidUpdate();
        return;
      }

      final url =
          widget.release.iosArtifactDownloadUrl ??
          widget.release.releasePageUrl;
      if (url.isEmpty) {
        throw const AppUpdateException('Tautan artifact rilis tidak tersedia.');
      }
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AppUpdateException('Tautan pembaruan tidak dapat dibuka.');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _statusText = error.toString());
    }
  }

  void _startAndroidUpdate() {
    final apkUrl = widget.release.apkDownloadUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() => _statusText = 'Asset APK tidak ditemukan pada rilis ini.');
      return;
    }
    setState(() {
      _downloading = true;
      _statusText = 'Mengunduh pembaruan...';
    });

    try {
      _subscription = OtaUpdate()
          .execute(
            apkUrl,
            destinationFilename: 'tonztoon-${widget.release.version}.apk',
          )
          .listen(_handleOtaEvent, onError: _handleOtaError);
    } catch (error) {
      _handleOtaError(error);
    }
  }

  void _handleOtaEvent(OtaEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final progress = int.tryParse(event.value ?? '') ?? 0;
        setState(() {
          _progress = (progress / 100).clamp(0, 1);
          _statusText = 'Mengunduh pembaruan... $progress%';
        });
      case OtaStatus.INSTALLING:
        setState(() {
          _progress = 1;
          _statusText = 'Membuka installer Android...';
        });
        _exitAfterInstallerStarts();
      default:
        _handleOtaError(
          event.value == null || event.value!.trim().isEmpty
              ? 'Pembaruan gagal: ${event.status.name}'
              : 'Pembaruan gagal: ${event.value}',
        );
    }
  }

  void _handleOtaError(Object error) {
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _statusText = error.toString();
    });
  }

  void _exitAfterInstallerStarts() {
    if (_exitScheduled) return;
    _exitScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      await SystemNavigator.pop();
    });
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.notes, this.version});

  final String notes;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final versionText = version ?? 'versi saat ini';
    final lines = notes.split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty && lines.first.trim().startsWith('#')) {
      lines[0] = '# 🎉 Apa yang baru di $versionText ?';
    } else {
      lines.insert(0, '# 🎉 Apa yang baru di $versionText\n ?');
    }
    final processedNotes = lines.join('\n');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: MarkdownBody(
              data: processedNotes,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                h1: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
                h2: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
                h3: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
                listBullet: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
                strong: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
                blockSpacing: 9,
                listIndent: 18,
              ),
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri == null) return;
                unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              },
            ),
          ),
        ),
      ),
    );
  }
}
