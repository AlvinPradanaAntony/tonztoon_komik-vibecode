part of '../settings_screen.dart';

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };
}

String _readerModeLabel(String mode) {
  return mode == 'paged' ? 'Paged' : 'Vertical';
}

String _directionLabel(String direction) {
  return direction == 'rtl' ? 'RTL' : 'LTR';
}

String? _validateUsernameValue(String? value) {
  final username = value?.trim() ?? '';
  if (username.isEmpty) return 'Username wajib diisi.';
  if (username.length < 3) return 'Username minimal 3 karakter.';
  if (username.length > 50) return 'Username maksimal 50 karakter.';
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username)) {
    return 'Gunakan huruf, angka, titik, strip, atau underscore.';
  }
  return null;
}

void _openAccountFlow(BuildContext context, Widget page) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (context) => page));
}

String _readingTimeLabel(Duration duration) {
  if (duration.inSeconds <= 0) return '0m';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}j ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) return '${minutes}m';
  return '${duration.inSeconds}s';
}
