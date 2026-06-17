part of '../auth_screen.dart';

String _authErrorMessage(
  Object error, {
  String fallbackMessage = 'Terjadi kesalahan. Silakan coba lagi.',
}) {
  return friendlyErrorMessage(error, fallbackMessage: fallbackMessage);
}

bool _isValidEmail(String value) {
  return RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  ).hasMatch(value);
}

String? _validateRecoveryEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Email wajib diisi.';
  final valid = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  ).hasMatch(email);
  if (!valid) return 'Format email tidak valid.';
  return null;
}

String? _validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Password baru wajib diisi.';
  if (password.length < 8) return 'Password minimal 8 karakter.';
  return null;
}

String? _validateConfirmNewPassword(String? value, String password) {
  if ((value ?? '').isEmpty) return 'Konfirmasi password wajib diisi.';
  if (value != password) return 'Konfirmasi password tidak sama.';
  return null;
}

SystemUiOverlayStyle _authSystemOverlayStyle(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: theme.scaffoldBackgroundColor,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  );
}
