import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final appRootNavigatorKey = GlobalKey<NavigatorState>();

const libraryDownloadsLocation = '/library?tab=downloads';
const libraryBookmarksLocation = '/library';
const libraryCollectionsLocation = '/library?tab=collections';
const libraryScenesLocation = '/library?tab=scenes';

String? _pendingNotificationLocation;

void openLocationFromNotification(String location) {
  if (!location.startsWith('/')) return;

  final context = appRootNavigatorKey.currentContext;
  if (context == null) {
    _pendingNotificationLocation = location;
    return;
  }

  final router = GoRouter.of(context);
  final currentPath = router.routeInformationProvider.value.uri.path;
  if (currentPath == '/splash') {
    _pendingNotificationLocation = location;
    return;
  }

  context.go(location);
}

String? consumePendingNotificationLocation() {
  final location = _pendingNotificationLocation;
  _pendingNotificationLocation = null;
  return location;
}
