import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import '../helpers/dynamic_badge_palette.dart';
import 'comic_card.dart' show comicSourceNameLabel;

/// Visual style for a [SourceTag] pill.
enum SourceTagStyle {
  /// The comic's own source.
  primary,

  /// A linked/secondary source, shown with a link icon to distinguish it from
  /// the primary source.
  linked,
}

/// Rounded pill showing a comic's source name, themed by [style].
///
/// Shared between the library bookmark list and the bookmark-candidate dialog,
/// which previously kept two near-identical local badge widgets.
class SourceTag extends StatelessWidget {
  const SourceTag({
    super.key,
    required this.sourceName,
    this.style = SourceTagStyle.primary,
  });

  final String sourceName;
  final SourceTagStyle style;

  @override
  Widget build(BuildContext context) {
    final isLinked = style == SourceTagStyle.linked;
    final palette = _SourceTagPalette.resolve(
      context,
      sourceName,
      soft: isLinked,
    );
    final icon = isLinked ? TonztoonIcons.link : TonztoonIcons.travelExplore;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        gradient: palette.gradient,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: palette.foreground),
              const SizedBox(width: 4),
              Text(
                comicSourceNameLabel(sourceName),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTagPalette {
  const _SourceTagPalette({
    this.gradient,
    this.background,
    required this.foreground,
    required this.border,
  }) : assert(gradient != null || background != null);

  final Gradient? gradient;
  final Color? background;
  final Color foreground;
  final Color border;

  static _SourceTagPalette resolve(
    BuildContext context,
    String sourceName, {
    required bool soft,
  }) {
    final accent = _sourceAccent(sourceName);
    if (accent != null) {
      return soft
          ? _SourceTagPalette.softFromAccent(context, accent)
          : _SourceTagPalette.gradientFromAccent(accent);
    }

    final palette = DynamicBadgePalette.fromSeed(context, sourceName);
    if (soft) {
      return _SourceTagPalette(
        background: palette.background,
        foreground: palette.foreground,
        border: palette.border,
      );
    }
    return _SourceTagPalette.gradientFromAccent(palette.accent);
  }

  static _SourceTagPalette gradientFromAccent(Color accent) {
    final darker = HSLColor.fromColor(accent)
        .withLightness(
          (HSLColor.fromColor(accent).lightness - 0.10).clamp(0.22, 0.58),
        )
        .withSaturation(
          (HSLColor.fromColor(accent).saturation + 0.08).clamp(0.50, 0.95),
        )
        .toColor();
    final lighter = HSLColor.fromColor(accent)
        .withLightness(
          (HSLColor.fromColor(accent).lightness + 0.08).clamp(0.36, 0.68),
        )
        .withSaturation(
          (HSLColor.fromColor(accent).saturation + 0.04).clamp(0.50, 0.95),
        )
        .toColor();

    return _SourceTagPalette(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [lighter, accent, darker],
      ),
      foreground: Colors.white,
      border: Colors.white.withValues(alpha: 0.22),
    );
  }

  static _SourceTagPalette softFromAccent(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final background = Color.lerp(
      accent,
      colors.surface,
      isDark ? 0.70 : 0.84,
    )!;

    return _SourceTagPalette(
      background: background,
      foreground: Color.lerp(
        accent,
        isDark ? Colors.white : Colors.black,
        isDark ? 0.78 : 0.30,
      )!,
      border: Color.lerp(accent, background, isDark ? 0.40 : 0.58)!,
    );
  }

  static Color? _sourceAccent(String sourceName) {
    return switch (_normalize(sourceName)) {
      '' || 'komiku' => const Color(0xFFFF9D00),
      'komiku_asia' => const Color(0xFF3A86FF),
      'komikcast' => const Color(0xFF10B981),
      'shinigami' => const Color(0xFF8B5CF6),
      'voratoon' => const Color(0xFF06B6D4),
      _ => null,
    };
  }

  static String _normalize(String sourceName) {
    return sourceName.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  }
}
