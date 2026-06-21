import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final appRootNavigatorKey = GlobalKey<NavigatorState>();

String? _pendingNotificationLocation;

void deferNotificationLocation(String location) {
  if (!location.startsWith('/')) return;
  _pendingNotificationLocation = location;
}

void openLocationFromNotification(String location) {
  if (!location.startsWith('/')) return;

  final context = appRootNavigatorKey.currentContext;
  if (context == null) {
    deferNotificationLocation(location);
    return;
  }

  final router = GoRouter.of(context);
  final currentPath = router.routeInformationProvider.value.uri.path;
  if (currentPath == '/splash') {
    deferNotificationLocation(location);
    return;
  }

  context.go(location);
}

String? consumePendingNotificationLocation() {
  final location = _pendingNotificationLocation;
  _pendingNotificationLocation = null;
  return location;
}
