import 'package:material_ui/material_ui.dart';

/// The colours that differ between the light and dark themes. Read them with
/// `context.colors`. The brand purple is the same in both and stays on
/// [AppTheme].
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.accent,
    required this.warning,
    required this.error,
    required this.success,
    required this.shadow,
    required this.buttonSpinner,
  });

  final Color background;
  final Color card;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  // Used as text on the surfaces above and as snack bar backgrounds.
  final Color accent;
  final Color warning;
  final Color error;
  final Color success;
  /// Shadow of the bottom bar and cart panel.
  final Color shadow;
  /// Progress indicator inside a button that is disabled while busy.
  final Color buttonSpinner;

  static const dark = AppColors(
    background: Color(0xFF1E1E2C),
    card: Color(0xFF2A2A3D),
    textPrimary: Color(0xFFF0F0F5),
    textSecondary: Color(0xFF9E9EB8),
    divider: Color(0xFF3A3A52),
    accent: Color(0xFF00D9A6),
    warning: Color(0xFFFFB347),
    error: Color(0xFFFF6B6B),
    success: Color(0xFF4ECB71),
    shadow: Color(0x4D000000),
    buttonSpinner: Color(0xFFFFFFFF),
  );

  // The status colours are darker shades of the dark theme's, so that they
  // stay readable as text on white.
  static const light = AppColors(
    background: Color(0xFFF8F9FE),
    card: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1E1E2C),
    textSecondary: Color(0xFF5C5C75),
    divider: Color(0xFFD5D6E4),
    accent: Color(0xFF00755A),
    warning: Color(0xFF8F5300),
    error: Color(0xFFC62828),
    success: Color(0xFF1B7339),
    shadow: Color(0x1A000000),
    buttonSpinner: Color(0xFF6C63FF),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? accent,
    Color? warning,
    Color? error,
    Color? success,
    Color? shadow,
    Color? buttonSpinner,
  }) =>
      AppColors(
        background: background ?? this.background,
        card: card ?? this.card,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        divider: divider ?? this.divider,
        accent: accent ?? this.accent,
        warning: warning ?? this.warning,
        error: error ?? this.error,
        success: success ?? this.success,
        shadow: shadow ?? this.shadow,
        buttonSpinner: buttonSpinner ?? this.buttonSpinner,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      card: mix(card, other.card),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      divider: mix(divider, other.divider),
      accent: mix(accent, other.accent),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      success: mix(success, other.success),
      shadow: mix(shadow, other.shadow),
      buttonSpinner: mix(buttonSpinner, other.buttonSpinner),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The active theme's colours. A theme without them (a bare [MaterialApp]
  /// in a test) gets the set matching its brightness.
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? AppColors.dark : AppColors.light);
  }
}
