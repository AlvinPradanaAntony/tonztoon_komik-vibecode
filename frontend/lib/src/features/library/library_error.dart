import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';

void showLibraryActionError(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
) {
  showAppErrorSnackBar(
    context,
    error: error,
    stackTrace: stackTrace,
    logContext: 'Library action failed',
    fallbackMessage: 'Aksi pustaka belum berhasil. Silakan coba lagi.',
    hideCurrent: false,
  );
}
