import 'package:flutter/material.dart';

class TonztoonTheme {
  const TonztoonTheme._();

  static const _teal = Color(0xFF00A7A7);
  static const _coral = Color(0xFFFF5A5F);
  static const _amber = Color(0xFFFFB547);

  static ThemeData light() => _build(
    brightness: Brightness.light,
    background: const Color(0xFFFFFBF6),
    surface: const Color(0xFFFFFFFF),
    surfaceHigh: const Color(0xFFF2F5F4),
    text: const Color(0xFF15171B),
    mutedText: const Color(0xFF667077),
    outline: const Color(0xFFD9E2E1),
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    background: const Color(0xFF0B0E12),
    surface: const Color(0xFF141920),
    surfaceHigh: const Color(0xFF1D242D),
    text: const Color(0xFFF3F7F7),
    mutedText: const Color(0xFF9AA7AE),
    outline: const Color(0xFF2D3742),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color text,
    required Color mutedText,
    required Color outline,
  }) {
    final scheme =
        ColorScheme.fromSeed(seedColor: _teal, brightness: brightness).copyWith(
          primary: _teal,
          secondary: _coral,
          tertiary: _amber,
          surface: surface,
          surfaceContainerLowest: background,
          surfaceContainerLow: surface,
          surfaceContainer: surfaceHigh,
          surfaceContainerHigh: surfaceHigh,
          surfaceContainerHighest: surfaceHigh,
          outline: outline,
          outlineVariant: outline.withValues(alpha: 0.72),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: mutedText),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: background.withValues(alpha: 0.84),
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceHigh,
        selectedColor: _teal.withValues(alpha: 0.18),
        side: BorderSide(color: outline.withValues(alpha: 0.8)),
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: 0.62),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: _teal, width: 1.8),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(_teal.withValues(alpha: 0.08)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: _teal.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: text,
        unselectedLabelColor: mutedText,
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        indicator: BoxDecoration(
          color: _teal.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _teal.withValues(alpha: 0.16);
            }
            return surface;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: mutedText,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFFE9F7F6)
            : const Color(0xFF182024),
        contentTextStyle: TextStyle(
          color: brightness == Brightness.dark
              ? const Color(0xFF11181B)
              : const Color(0xFFF7FAFA),
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: _teal),
    );
  }
}
