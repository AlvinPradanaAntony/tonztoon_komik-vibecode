import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/comic.dart';
import '../models/library.dart';

class DownloadNotificationService {
  DownloadNotificationService({
    required VoidCallback onOpenDownloads,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _onOpenDownloads = onOpenDownloads,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _progressChannelId = 'download_progress';
  static const _progressChannelName = 'Progress download';
  static const _statusChannelId = 'download_status';
  static const _statusChannelName = 'Status download';
  static const _androidSmallIcon = 'ic_stat_tonztoon';

  final FlutterLocalNotificationsPlugin _plugin;
  final VoidCallback _onOpenDownloads;
  final Map<String, int> _lastProgressByBatch = {};
  bool _available = true;
  bool _initialized = false;
  bool _permissionsRequested = false;
  Future<void>? _initializing;

  Future<void> initialize() {
    return _ensureInitialized();
  }

  Future<void> showStarted(OfflineDownloadBatch batch) {
    return showProgress(batch, force: true);
  }

  Future<void> showProgress(
    OfflineDownloadBatch batch, {
    bool force = false,
  }) async {
    final percent = _percent(batch);
    if (!force && _lastProgressByBatch[batch.id] == percent) return;
    _lastProgressByBatch[batch.id] = percent;

    await _ensureInitialized();
    if (!_canShowNotifications) return;
    if (!await _requestPermissions()) return;

    try {
      await _plugin.show(
        id: _notificationId(batch.id),
        title: 'Mengunduh ${batch.comic.title}',
        body: _progressBody(batch, percent),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _progressChannelId,
            _progressChannelName,
            channelDescription: 'Progress download komik offline',
            icon: _androidSmallIcon,
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false,
            silent: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentSound: false,
            threadIdentifier: 'tonztoon_downloads',
          ),
          macOS: const DarwinNotificationDetails(
            presentSound: false,
            threadIdentifier: 'tonztoon_downloads',
          ),
          linux: const LinuxNotificationDetails(
            category: LinuxNotificationCategory.transfer,
            suppressSound: true,
            transient: true,
          ),
          windows: WindowsNotificationDetails(
            progressBars: [
              WindowsProgressBar(
                id: 'download',
                title: 'Progress',
                status: 'Downloading',
                value: percent / 100,
                label: '$percent%',
              ),
            ],
          ),
        ),
        payload: batch.id,
      );
    } catch (_) {
      _available = false;
    }
  }

  Future<void> showCompleted(OfflineDownloadBatch batch) {
    _lastProgressByBatch.remove(batch.id);
    return _showStatus(
      batch,
      title: 'Download selesai',
      body: '${batch.comic.title} siap dibaca offline.',
    );
  }

  Future<void> showFailed(OfflineDownloadBatch batch) {
    _lastProgressByBatch.remove(batch.id);
    return _showStatus(
      batch,
      title: 'Download gagal',
      body: batch.lastError?.isNotEmpty == true
          ? batch.lastError!
          : '${batch.comic.title} gagal diunduh.',
    );
  }

  Future<void> showCancelled(OfflineDownloadBatch batch) {
    _lastProgressByBatch.remove(batch.id);
    return _showStatus(
      batch,
      title: 'Download dibatalkan',
      body: '${batch.comic.title} tidak jadi diunduh.',
    );
  }

  Future<void> dismiss(String batchId) async {
    _lastProgressByBatch.remove(batchId);
    await _ensureInitialized();
    if (!_canShowNotifications) return;
    try {
      await _plugin.cancel(id: _notificationId(batchId));
    } catch (_) {
      _available = false;
    }
  }

  Future<void> _showStatus(
    OfflineDownloadBatch batch, {
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    if (!_canShowNotifications) return;
    if (!await _requestPermissions()) return;

    try {
      await _plugin.show(
        id: _notificationId(batch.id),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _statusChannelId,
            _statusChannelName,
            channelDescription: 'Status download komik offline',
            icon: _androidSmallIcon,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            onlyAlertOnce: true,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(
            threadIdentifier: 'tonztoon_downloads',
          ),
          macOS: DarwinNotificationDetails(
            threadIdentifier: 'tonztoon_downloads',
          ),
          linux: LinuxNotificationDetails(
            category: LinuxNotificationCategory.transferComplete,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: batch.id,
      );
    } catch (_) {
      _available = false;
    }
  }

  Future<void> _ensureInitialized() {
    if (_initialized || !_canShowNotifications) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized || !_canShowNotifications) return;

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_androidSmallIcon),
          iOS: darwinSettings,
          macOS: darwinSettings,
          linux: LinuxInitializationSettings(
            defaultActionName: 'Buka TonzToon',
          ),
          windows: WindowsInitializationSettings(
            appName: 'TonzToon',
            appUserModelId: 'TonzToon.Comic.App',
            guid: '75a2c6f3-8f9b-4d19-8de5-09f1f0ec79d6',
          ),
        ),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _onOpenDownloads();
      }
    } catch (_) {
      _available = false;
    }

    _initialized = true;
  }

  Future<bool> _requestPermissions() async {
    if (_permissionsRequested || !_canShowNotifications) return true;
    _permissionsRequested = true;

    try {
      final androidGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (androidGranted == false) return false;

      final iosGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
      if (iosGranted == false) return false;

      final macGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
      if (macGranted == false) return false;

      return true;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.payload == null) return;
    _onOpenDownloads();
  }

  String _progressBody(OfflineDownloadBatch batch, int percent) {
    final chapter = batch.currentChapterNumber;
    final chapterText = chapter == null
        ? ''
        : ' - Ch ${formatChapterNumber(chapter)}';
    return '$percent%$chapterText (${batch.completedChapters}/${batch.totalChapters} chapter)';
  }

  int _percent(OfflineDownloadBatch batch) {
    return (batch.progress * 100).clamp(0, 100).round();
  }

  int _notificationId(String batchId) {
    var hash = 0;
    for (final unit in batchId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  bool get _canShowNotifications => !kIsWeb && _available;
}
