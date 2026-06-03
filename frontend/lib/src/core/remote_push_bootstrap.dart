import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'app_error.dart';
import 'remote_push_inbox.dart';

@pragma('vm:entry-point')
Future<void> tonztoonFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  DartPluginRegistrant.ensureInitialized();
  await RemotePushBootstrap.initializeFirebaseForAndroid();
  await RemotePushInbox.enqueueBackgroundMessage(message);
}

class RemotePushBootstrap {
  RemotePushBootstrap._();

  static bool _available = false;
  static bool _initialized = false;

  static bool get isAvailable => _available;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;

    if (!isSupported) return false;

    try {
      await initializeFirebaseForAndroid();
      FirebaseMessaging.onBackgroundMessage(
        tonztoonFirebaseMessagingBackgroundHandler,
      );
      _available = true;
    } catch (error, stackTrace) {
      _available = false;
      logAppError(
        error,
        stackTrace,
        context:
            'Firebase Cloud Messaging belum aktif. Pastikan google-services.json sudah tersedia.',
      );
    }
    return _available;
  }

  static Future<void> initializeFirebaseForAndroid() async {
    if (!isSupported || Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp();
  }
}
