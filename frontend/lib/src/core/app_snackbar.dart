import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';

import 'app_error.dart';

enum AppSnackBarType { success, failure, warning, help }

void showAppSnackBar(
  BuildContext context, {
  required String message,
  String? title,
  AppSnackBarType type = AppSnackBarType.help,
  Duration duration = const Duration(seconds: 3),
  bool hideCurrent = true,
}) {
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  if (hideCurrent) {
    messenger.hideCurrentSnackBar();
  }

  messenger.showSnackBar(
    SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      duration: duration,
      content: AwesomeSnackbarContent(
        title: title ?? _defaultTitle(type),
        message: message,
        contentType: _contentType(type),
      ),
    ),
  );
}

void showAppErrorSnackBar(
  BuildContext context, {
  required Object error,
  StackTrace? stackTrace,
  String logContext = 'UI flow failed',
  String fallbackMessage = 'Terjadi kesalahan. Silakan coba lagi.',
  String? title,
  Duration duration = const Duration(seconds: 3),
  bool hideCurrent = true,
}) {
  if (stackTrace != null) {
    logAppError(error, stackTrace, context: logContext);
  }
  showAppSnackBar(
    context,
    title: title,
    message: friendlyErrorMessage(error, fallbackMessage: fallbackMessage),
    type: AppSnackBarType.failure,
    duration: duration,
    hideCurrent: hideCurrent,
  );
}

ContentType _contentType(AppSnackBarType type) {
  return switch (type) {
    AppSnackBarType.success => ContentType.success,
    AppSnackBarType.failure => ContentType.failure,
    AppSnackBarType.warning => ContentType.warning,
    AppSnackBarType.help => ContentType.help,
  };
}

String _defaultTitle(AppSnackBarType type) {
  return switch (type) {
    AppSnackBarType.success => 'Berhasil',
    AppSnackBarType.failure => 'Gagal',
    AppSnackBarType.warning => 'Perhatian',
    AppSnackBarType.help => 'Info',
  };
}
