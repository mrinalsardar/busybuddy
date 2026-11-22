import 'package:flutter/material.dart';

/// App-wide design tokens and theme builder.
class AppTheme {
  AppTheme._();

  // ── Palette ──────────────────────────────────────────
  static const Color primaryPurple = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF3F3D56);
  static const Color surfaceDark = Color(0xFF1E1E2C);
  static const Color surfaceCard = Color(0xFF2A2A3D);
  static const Color surfaceLight = Color(0xFFF8F9FE);
  static const Color accent = Color(0xFF00D9A6);
  static const Color warning = Color(0xFFFFB347);
  static const Color error = Color(0xFFFF6B6B);
  static const Color success = Color(0xFF4ECB71);
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF9E9EB8);
  static const Color dividerColor = Color(0xFF3A3A52);

  // ── Radius ───────────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;

  // ── Spacing ──────────────────────────────────────────
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
    final baseText = ThemeData.dark().textTheme.apply(fontFamily: 'Inter');
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: surfaceDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryPurple,
        secondary: accent,
        surface: surfaceCard,
        error: error,
        onPrimary: Colors.white,
        onSurface: textPrimary,
        onSecondary: Colors.black,
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryPurple,
          side: const BorderSide(color: primaryPurple),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryPurple, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: textSecondary, fontSize: 14),
        labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: textSecondary, fontSize: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceCard,
        selectedItemColor: primaryPurple,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 0.5),
      textTheme: baseText.copyWith(
        headlineLarge: baseText.headlineLarge?.copyWith(color: textPrimary, fontWeight: FontWeight.w800),
        headlineMedium: baseText.headlineMedium?.copyWith(color: textPrimary, fontWeight: FontWeight.w700),
        titleLarge: baseText.titleLarge?.copyWith(color: textPrimary, fontWeight: FontWeight.w700),
        titleMedium: baseText.titleMedium?.copyWith(color: textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: baseText.bodyLarge?.copyWith(color: textPrimary),
        bodyMedium: baseText.bodyMedium?.copyWith(color: textSecondary),
        labelLarge: baseText.labelLarge?.copyWith(color: textPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
