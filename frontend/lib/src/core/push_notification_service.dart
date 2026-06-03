import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';
import '../models/comic.dart';
import '../models/library.dart';
import '../models/push_notification_preferences.dart';
import 'app_navigation.dart';

class PushNotificationService {
  PushNotificationService({
    required PushNotificationPreferences Function() readPreferences,
    required ValueChanged<String> onOpenLocation,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _readPreferences = readPreferences,
       _onOpenLocation = onOpenLocation,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _progressChannelId = 'download_progress';
  static const _progressChannelName = 'Progress download';
  static const _legacyStatusChannelId = 'download_status';
  static const _updatesChannelId = 'comic_updates';
  static const _updatesChannelName = 'Notifikasi TonzToon';
  static const _updatesChannelDescription =
      'Update chapter dan status pustaka';
  static const _androidSmallIcon = 'ic_stat_tonztoon';

  final FlutterLocalNotificationsPlugin _plugin;
  final PushNotificationPreferences Function() _readPreferences;
  final ValueChanged<String> _onOpenLocation;
  final Map<String, int> _lastProgressByBatch = {};
  bool _available = true;
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> initialize() {
    return _ensureInitialized();
  }

  Future<bool> requestPermissions() async {
    await _ensureInitialized();
    if (!_canShowNotifications) return false;

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
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (iosGranted == false) return false;

      final macGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return macGranted != false;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  Future<bool> showAppNotification(AppNotification notification) async {
    if (!_shouldDeliver) return false;
    await _ensureInitialized();
    if (!_canShowNotifications) return false;

    try {
      await _plugin.show(
        id: _notificationId(notification.id),
        title: notification.title,
        body: notification.message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _updatesChannelId,
            _updatesChannelName,
            channelDescription: _updatesChannelDescription,
            icon: _androidSmallIcon,
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(threadIdentifier: 'tonztoon_updates'),
          macOS: DarwinNotificationDetails(
            threadIdentifier: 'tonztoon_updates',
          ),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
        payload: notification.actionRoute ?? '/notifications',
      );
      return true;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  Future<void> showStarted(OfflineDownloadBatch batch) {
    return showProgress(batch, force: true);
  }

  Future<void> showProgress(
    OfflineDownloadBatch batch, {
    bool force = false,
  }) async {
    if (!_shouldDeliver) return;

    final percent = _percent(batch);
    if (!force && _lastProgressByBatch[batch.id] == percent) return;
    _lastProgressByBatch[batch.id] = percent;

    await _ensureInitialized();
    if (!_canShowNotifications) return;

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
        payload: libraryDownloadsLocation,
      );
    } catch (_) {
      _available = false;
    }
  }

  Future<void> showCompleted(OfflineDownloadBatch batch) {
    _lastProgressByBatch.remove(batch.id);
    return _showDownloadStatus(
      batch,
      title: 'Download selesai',
      body: '${batch.comic.title} siap dibaca offline.',
    );
  }

  Future<void> showFailed(OfflineDownloadBatch batch) {
    _lastProgressByBatch.remove(batch.id);
    return _showDownloadStatus(
      batch,
      title: 'Download gagal',
      body: batch.lastError?.isNotEmpty == true
          ? batch.lastError!
          : '${batch.comic.title} gagal diunduh.',
    );
  }

  Future<void> showCancelled(OfflineDownloadBatch batch) {
    _lastProgressByBatch.remove(batch.id);
    return _showDownloadStatus(
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

  Future<void> dismissAll() async {
    await _ensureInitialized();
    if (!_canShowNotifications) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      _available = false;
    }
  }

  Future<void> _showDownloadStatus(
    OfflineDownloadBatch batch, {
    required String title,
    required String body,
  }) async {
    if (!_shouldDeliver) return;
    await _ensureInitialized();
    if (!_canShowNotifications) return;

    try {
      await _plugin.show(
        id: _notificationId(batch.id),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _updatesChannelId,
            _updatesChannelName,
            channelDescription: _updatesChannelDescription,
            icon: _androidSmallIcon,
            importance: Importance.high,
            priority: Priority.high,
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
        payload: libraryDownloadsLocation,
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
      await _createAndroidNotificationChannels();
      await _deleteLegacyAndroidChannels();

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null) {
        _onOpenLocation(launchPayload);
      }
    } catch (_) {
      _available = false;
    }

    _initialized = true;
  }

  Future<void> _createAndroidNotificationChannels() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _updatesChannelId,
          _updatesChannelName,
          description: _updatesChannelDescription,
          importance: Importance.high,
        ),
      );
    } catch (_) {
      // FCM can still use the manifest default channel if explicit creation fails.
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final location = response.payload;
    if (location == null || location.isEmpty) return;
    _onOpenLocation(location);
  }

  Future<void> _deleteLegacyAndroidChannels() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.deleteNotificationChannel(channelId: _legacyStatusChannelId);
    } catch (_) {
      // Keep notifications available if a platform cannot remove stale channels.
    }
  }

  bool get _shouldDeliver => _readPreferences().shouldDeliver;

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

  int _notificationId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  bool get _canShowNotifications => !kIsWeb && _available;
}
