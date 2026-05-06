import 'package:flutter/material.dart';

/// [TonztoonTheme] adalah pusat Design System untuk aplikasi.
/// Di sini kita mendefinisikan warna, gaya teks, dan bentuk (shape) dari komponen
/// UI agar konsisten di seluruh aplikasi.
class TonztoonTheme {
  const TonztoonTheme._();

  // ===========================================================================
  // 1. BRAND COLORS (Warna Utama Aplikasi)
  // ===========================================================================
  static const _primary = Color(0xFFFF9D00);   // Primary: Orange
  static const _secondary = Color(0xFF3A86FF); // Secondary: Blue
  static const _tertiary = Color.fromARGB(255, 243, 150, 0);  // Tertiary: Yellow
  static const _neutral = Color.fromARGB(255, 10, 15, 26);   // Neutral: Slate/Dark Blue

  // ===========================================================================
  // 2. LIGHT MODE & DARK MODE CONFIGURATION
  // ===========================================================================
  static ThemeData light() => _build(
    brightness: Brightness.light,
    background: const Color(0xFFF8FAFC), // Warna latar belakang aplikasi (Slate 50)
    surface: const Color(0xFFFFFFFF),    // Warna latar untuk Card, Dialog, dll
    surfaceHigh: const Color(0xFFF1F5F9),// Warna latar komponen yang sedikit lebih menonjol (Slate 100)
    text: _neutral,                      // Warna teks utama menggunakan Neutral
    mutedText: const Color(0xFF64748B),  // Warna teks sekunder (Slate 500)
    outline: const Color(0xFFCBD5E1),    // Warna border/garis tepi (Slate 300)
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    background: _neutral,                // Background utama menggunakan Neutral
    surface: const Color(0xFF1E293B),    // Slate 800
    surfaceHigh: const Color(0xFF334155),// Slate 700
    text: const Color(0xFFF8FAFC),       // Slate 50
    mutedText: const Color(0xFF94A3B8),  // Slate 400
    outline: const Color(0xFF475569),    // Slate 600
  );

  // ===========================================================================
  // 3. THEME BUILDER (Merakit ThemeData)
  // ===========================================================================
  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color text,
    required Color mutedText,
    required Color outline,
  }) {
    // Membuat ColorScheme berdasarkan warna utama (_primary)
    final scheme =
        ColorScheme.fromSeed(seedColor: _primary, brightness: brightness).copyWith(
          primary: _primary,
          secondary: _secondary,
          tertiary: _tertiary,
          surface: surface,
          surfaceContainerLowest: background,
          surfaceContainerLow: surface,
          surfaceContainer: surfaceHigh,
          surfaceContainerHigh: surfaceHigh,
          surfaceContainerHighest: surfaceHigh,
          outline: outline,
          outlineVariant: outline.withValues(alpha: 0.72),
        );

    // Konfigurasi dasar ThemeData
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory, // Efek gelombang saat ditekan
    );

    // Konfigurasi Typography (Gaya Teks)
    final textTheme = base.textTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
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

    // =========================================================================
    // 4. WIDGET THEMES (Kustomisasi Komponen Spesifik)
    // =========================================================================
    return base.copyWith(
      textTheme: textTheme,
      
      // Styling untuk AppBar (Navigasi atas)
      appBarTheme: AppBarTheme(
        elevation: 0, // Hilangkan bayangan bawaan
        centerTitle: false,
        backgroundColor: background.withValues(alpha: 0.84), // Transparan sebagian (efek blur jika ada konten di bawah)
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      
      // Styling untuk Card (Kartu komik)
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      
      // Styling untuk Form Input
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
          borderSide: const BorderSide(color: _primary, width: 1.8),
        ),
      ),
      
      // Styling untuk Tombol Utama (Filled Button)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: _primary),
    );
  }
}
