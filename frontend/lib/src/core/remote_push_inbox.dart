import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';

class RemotePushInbox {
  RemotePushInbox._();

  static const _pendingNotificationsKey =
      'pending_remote_push_notifications';
  static const _maxPendingNotifications = 60;

  static Future<void> enqueueBackgroundMessage(RemoteMessage message) async {
    final notification = appNotificationFromRemoteMessage(message);
    if (notification == null) return;

    final preferences = SharedPreferencesAsync();
    final existing =
        await preferences.getStringList(_pendingNotificationsKey) ??
        const <String>[];
    final encoded = jsonEncode(notification.toJson());
    final withoutDuplicate = existing.where((item) {
      final decoded = _decodeNotification(item);
      return decoded?.id != notification.id;
    }).toList();
    final next = <String>[encoded, ...withoutDuplicate]
        .take(_maxPendingNotifications)
        .toList();
    await preferences.setStringList(_pendingNotificationsKey, next);
  }

  static Future<List<AppNotification>> drainPendingNotifications() async {
    final preferences = SharedPreferencesAsync();
    final raw =
        await preferences.getStringList(_pendingNotificationsKey) ??
        const <String>[];
    if (raw.isEmpty) return const [];

    await preferences.remove(_pendingNotificationsKey);
    final notifications = raw
        .map(_decodeNotification)
        .nonNulls
        .where((item) => item.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notifications;
  }

  static AppNotification? _decodeNotification(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      return AppNotification.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

AppNotification? appNotificationFromRemoteMessage(RemoteMessage message) {
  final title = message.notification?.title ?? _dataString(message, 'title');
  final body =
      message.notification?.body ??
      _dataString(message, 'body') ??
      _dataString(message, 'message');

  if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
    return null;
  }

  final id =
      _dataString(message, 'id') ??
      message.messageId ??
      'remote:${DateTime.now().microsecondsSinceEpoch}';

  return AppNotification(
    id: 'remote:$id',
    title: title?.isNotEmpty == true ? title! : 'TonzToon',
    message: body?.isNotEmpty == true ? body! : 'Ada update baru.',
    category: _dataString(message, 'category') ?? 'Update',
    kind:
        _dataString(message, 'kind') ??
        _dataString(message, 'type') ??
        'remote_push',
    createdAt: DateTime.now(),
    actionRoute: routeFromRemoteMessage(message),
  );
}

String? routeFromRemoteMessage(RemoteMessage message) {
  final route =
      _dataString(message, 'route') ??
      _dataString(message, 'action_route') ??
      _dataString(message, 'actionRoute') ??
      _dataString(message, 'click_action_route');
  if (route == null || !route.startsWith('/')) return null;
  return route;
}

String? _dataString(RemoteMessage message, String key) {
  final value = message.data[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
