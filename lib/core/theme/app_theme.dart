import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// App-wide design tokens and theme builder.
class AppTheme {
  AppTheme._();

  // ── Palette ──────────────────────────────────────────
  static const Color primaryPurple = Color(0xFF6C63FF);
  static const Color accent = Color(0xFF00D9A6);
  // Colours that depend on the theme are in [AppColors].

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

  static final ThemeData darkTheme = _build(Brightness.dark, AppColors.dark);
  static final ThemeData lightTheme = _build(Brightness.light, AppColors.light);

  /// Status and navigation bar styling for a theme of [brightness].
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS names the bar's brightness, not the icons'.
      statusBarBrightness: brightness,
      systemNavigationBarColor: (dark ? AppColors.dark : AppColors.light).card,
      systemNavigationBarIconBrightness: icons,
    );
  }

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final dark = brightness == Brightness.dark;
    final baseText = (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(fontFamily: 'Inter');
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      extensions: [colors],
      scaffoldBackgroundColor: colors.background,
      colorScheme: dark
          ? ColorScheme.dark(
              primary: primaryPurple,
              secondary: accent,
              surface: colors.card,
              error: colors.error,
              onPrimary: Colors.white,
              onSurface: colors.textPrimary,
              onSecondary: Colors.black,
            )
          : ColorScheme.light(
              primary: primaryPurple,
              secondary: accent,
              surface: colors.card,
              error: colors.error,
              onPrimary: Colors.white,
              onSurface: colors.textPrimary,
              onSecondary: Colors.black,
              onError: Colors.white,
              onSurfaceVariant: colors.textSecondary,
              outline: colors.textSecondary,
              outlineVariant: colors.divider,
            ),
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        systemOverlayStyle: overlayStyle(brightness),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary),
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
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryPurple, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: colors.textSecondary, fontSize: 14),
        labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: colors.textSecondary, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.card,
        selectedItemColor: primaryPurple,
        unselectedItemColor: colors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(color: colors.divider, thickness: 0.5),
      textTheme: baseText.copyWith(
        headlineLarge: baseText.headlineLarge?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800),
        headlineMedium: baseText.headlineMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700),
        titleLarge: baseText.titleLarge?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700),
        titleMedium: baseText.titleMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: baseText.bodyLarge?.copyWith(color: colors.textPrimary),
        bodyMedium: baseText.bodyMedium?.copyWith(color: colors.textSecondary),
        labelLarge: baseText.labelLarge?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
