import 'package:flutter/foundation.dart';

import '../core/api_client.dart';

void logAppError(
  Object error,
  StackTrace stackTrace, {
  String context = 'Unhandled error',
}) {
  debugPrint('[TonzToon Error] $context: $error');
  debugPrintStack(
    label: '[TonzToon Error] $context stack trace',
    stackTrace: stackTrace,
  );
}

String friendlyErrorMessage(
  Object error, {
  String fallbackMessage = 'Terjadi kesalahan. Silakan coba lagi.',
}) {
  if (error is ApiException) {
    return _cleanMessage(error.message, fallbackMessage: fallbackMessage);
  }

  final raw = error.toString().trim();
  if (raw.isEmpty || _looksLikeDebugDump(raw)) return fallbackMessage;
  return _cleanMessage(raw, fallbackMessage: fallbackMessage);
}

String _cleanMessage(String message, {required String fallbackMessage}) {
  final trimmed = message.trim();
  if (trimmed.isEmpty || _looksLikeDebugDump(trimmed)) return fallbackMessage;
  return trimmed;
}

bool _looksLikeDebugDump(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('stacktrace') ||
      normalized.contains('stack trace') ||
      normalized.contains('googlesigninexception(') ||
      normalized.contains('dioexception') ||
      normalized.contains('java.lang.') ||
      normalized.contains('package:') ||
      normalized.contains('com.google.android.gms') ||
      normalized.length > 260;
}
