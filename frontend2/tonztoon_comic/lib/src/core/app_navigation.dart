import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final appRootNavigatorKey = GlobalKey<NavigatorState>();

const libraryDownloadsLocation = '/library?tab=downloads';

bool _pendingDownloadsNavigation = false;

void openDownloadsFromNotification() {
  final context = appRootNavigatorKey.currentContext;
  if (context == null) {
    _pendingDownloadsNavigation = true;
    return;
  }

  final router = GoRouter.of(context);
  final currentPath = router.routeInformationProvider.value.uri.path;
  if (currentPath == '/splash') {
    _pendingDownloadsNavigation = true;
    return;
  }

  context.go(libraryDownloadsLocation);
}

bool consumePendingDownloadsNavigation() {
  final pending = _pendingDownloadsNavigation;
  _pendingDownloadsNavigation = false;
  return pending;
}
