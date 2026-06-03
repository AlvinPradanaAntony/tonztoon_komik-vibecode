import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../models/app_notification.dart';
import '../models/auth.dart';
import '../models/push_notification_preferences.dart';
import '../repositories/push_device_repository.dart';
import 'app_error.dart';
import 'push_notification_service.dart';
import 'remote_push_bootstrap.dart';
import 'remote_push_inbox.dart';
import 'storage.dart';

class RemotePushNotificationService with WidgetsBindingObserver {
  RemotePushNotificationService({
    required PushDeviceRepository repository,
    required LocalStore store,
    required PushNotificationService localNotifications,
    required PushNotificationPreferences Function() readPreferences,
    required AuthState Function() readAuth,
    required void Function(String location) onOpenLocation,
    Future<void> Function(AppNotification notification)? onAppNotification,
    FirebaseMessaging? messaging,
  }) : _repository = repository,
       _store = store,
       _localNotifications = localNotifications,
       _readPreferences = readPreferences,
       _readAuth = readAuth,
       _onOpenLocation = onOpenLocation,
       _onAppNotification = onAppNotification,
       _messaging = messaging ?? FirebaseMessaging.instance;

  static const _registeredTokenKey = 'registered_fcm_device_token';
  static const _registeredUserKey = 'registered_fcm_user_id';

  final PushDeviceRepository _repository;
  final LocalStore _store;
  final PushNotificationService _localNotifications;
  final PushNotificationPreferences Function() _readPreferences;
  final AuthState Function() _readAuth;
  final void Function(String location) _onOpenLocation;
  final Future<void> Function(AppNotification notification)? _onAppNotification;
  final FirebaseMessaging _messaging;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _started = false;
  bool _observingLifecycle = false;
  bool _drainingPendingNotifications = false;

  Future<void> initialize() async {
    await _startMessageListeners();
    unawaited(_drainPendingNotifications());
    unawaited(syncRegistration());
  }

  Future<bool> requestPermissions() async {
    if (!RemotePushBootstrap.isSupported) return true;

    final available = await RemotePushBootstrap.initialize();
    if (!available) return false;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error, stackTrace) {
      logAppError(
        error,
        stackTrace,
        context: 'Request Firebase Cloud Messaging permission failed',
      );
      return false;
    }
  }

  Future<void> syncRegistration() async {
    await _startMessageListeners();
    if (!RemotePushBootstrap.isAvailable) return;

    if (!_shouldRegister) {
      await unregisterDevice();
      return;
    }

    final auth = _readAuth();
    final userId = auth.user?.id;
    if (userId == null || userId.isEmpty) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      final previousToken = _registeredToken;
      final previousUser = _registeredUser;
      if (previousToken == token && previousUser == userId) return;

      if (previousToken != null && previousToken != token) {
        await _unregisterToken(previousToken);
      }

      await _repository.registerFcmToken(token: token, userId: userId);
      await Future.wait([
        _store.settings.put(_registeredTokenKey, token),
        _store.settings.put(_registeredUserKey, userId),
      ]);
    } catch (error, stackTrace) {
      logAppError(
        error,
        stackTrace,
        context: 'Register Firebase Cloud Messaging token failed',
      );
    }
  }

  Future<void> unregisterDevice() async {
    final token = _registeredToken;
    if (token == null || token.isEmpty) return;

    await _unregisterToken(token);
    await Future.wait([
      _store.settings.delete(_registeredTokenKey),
      _store.settings.delete(_registeredUserKey),
    ]);
  }

  Future<void> dispose() async {
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    final futures = <Future<void>>[];
    final foregroundSubscription = _foregroundSubscription;
    final openedSubscription = _openedSubscription;
    final tokenRefreshSubscription = _tokenRefreshSubscription;
    if (foregroundSubscription != null) {
      futures.add(foregroundSubscription.cancel());
    }
    if (openedSubscription != null) futures.add(openedSubscription.cancel());
    if (tokenRefreshSubscription != null) {
      futures.add(tokenRefreshSubscription.cancel());
    }
    await Future.wait(futures);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainPendingNotifications());
    }
  }

  Future<void> _startMessageListeners() async {
    if (_started) return;
    final available = await RemotePushBootstrap.initialize();
    if (!available) return;

    _started = true;
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
      onError: _logStreamError,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
      onError: _logStreamError,
    );
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_handleTokenRefresh(token)),
      onError: _logStreamError,
    );

    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        await _handleOpenedMessage(initialMessage);
      }
    } catch (error, stackTrace) {
      logAppError(
        error,
        stackTrace,
        context: 'Read initial Firebase Cloud Messaging message failed',
      );
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = appNotificationFromRemoteMessage(message);
    if (notification == null) return;
    await _onAppNotification?.call(notification);
    await _localNotifications.showAppNotification(notification);
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    await _drainPendingNotifications();

    final notification = appNotificationFromRemoteMessage(message);
    if (notification != null) {
      await _onAppNotification?.call(notification);
    }

    final route = routeFromRemoteMessage(message);
    if (route != null) _onOpenLocation(route);
  }

  Future<void> _handleTokenRefresh(String token) async {
    if (token.isEmpty || !_shouldRegister) return;
    await Future.wait([
      _store.settings.delete(_registeredTokenKey),
      _store.settings.delete(_registeredUserKey),
    ]);
    await syncRegistration();
  }

  Future<void> _unregisterToken(String token) async {
    try {
      await _repository.unregisterFcmToken(token);
    } catch (error, stackTrace) {
      logAppError(
        error,
        stackTrace,
        context: 'Unregister Firebase Cloud Messaging token failed',
      );
    }
  }

  void _logStreamError(Object error) {
    logAppError(
      error,
      StackTrace.current,
      context: 'Firebase Cloud Messaging stream error',
    );
  }

  bool get _shouldRegister =>
      _readPreferences().shouldDeliver && _readAuth().isAuthenticated;

  Future<void> _drainPendingNotifications() async {
    if (_drainingPendingNotifications) return;
    _drainingPendingNotifications = true;
    try {
      final pending = await RemotePushInbox.drainPendingNotifications();
      for (final notification in pending) {
        await _onAppNotification?.call(notification);
      }
    } catch (error, stackTrace) {
      logAppError(
        error,
        stackTrace,
        context: 'Drain background Firebase Cloud Messaging notifications failed',
      );
    } finally {
      _drainingPendingNotifications = false;
    }
  }

  String? get _registeredToken {
    final value = _store.settings.get(_registeredTokenKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  String? get _registeredUser {
    final value = _store.settings.get(_registeredUserKey);
    return value is String && value.isNotEmpty ? value : null;
  }
}
