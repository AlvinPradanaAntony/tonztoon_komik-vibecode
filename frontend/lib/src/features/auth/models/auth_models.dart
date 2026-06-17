part of '../auth_screen.dart';

class _AuthPalette {
  const _AuthPalette({
    required this.background,
    required this.surface,
    required this.input,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
    required this.shadowAlpha,
  });

  final Color background;
  final Color surface;
  final Color input;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;
  final double shadowAlpha;

  factory _AuthPalette.fromTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return _AuthPalette(
      background: theme.scaffoldBackgroundColor,
      surface: colorScheme.surface,
      input: colorScheme.surfaceContainerHighest,
      text: colorScheme.onSurface,
      muted: colorScheme.onSurfaceVariant,
      border: colorScheme.outlineVariant,
      accent: colorScheme.primary,
      shadowAlpha: isDark ? 0.30 : 0.08,
    );
  }
}
