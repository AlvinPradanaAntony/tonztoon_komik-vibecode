import 'package:flutter/material.dart';

class DynamicBadgePalette {
  const DynamicBadgePalette({
    required this.accent,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color accent;
  final Color background;
  final Color foreground;
  final Color border;

  static DynamicBadgePalette fromSeed(
    BuildContext context,
    String seed, {
    double saturation = 0.72,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hue = _hueFromSeed(seed);

    return DynamicBadgePalette(
      accent: HSLColor.fromAHSL(
        1,
        hue,
        saturation,
        isDark ? 0.66 : 0.42,
      ).toColor(),
      background: HSLColor.fromAHSL(
        1,
        hue,
        isDark ? 0.34 : saturation,
        isDark ? 0.20 : 0.92,
      ).toColor(),
      foreground: HSLColor.fromAHSL(
        1,
        hue,
        saturation,
        isDark ? 0.82 : 0.30,
      ).toColor(),
      border: HSLColor.fromAHSL(
        1,
        hue,
        isDark ? 0.50 : 0.62,
        isDark ? 0.34 : 0.80,
      ).toColor(),
    );
  }

  static double _hueFromSeed(String seed) {
    final value = seed.trim().toLowerCase();
    final input = value.isEmpty ? 'tonztoon' : value;
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x3fffffff;
    }
    return (hash % 360).toDouble();
  }
}
