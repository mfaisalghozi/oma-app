import 'package:flutter/material.dart';

import 'oma_colors.dart';

abstract final class OmaTheme {
  static const fontFamily = 'Nunito';

  static ThemeData lagoon() => _build(OmaColors.lagoon, Brightness.light);

  static ThemeData deepSea() => _build(OmaColors.deepSea, Brightness.dark);

  static ThemeData _build(OmaColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: c.onPrimary,
      error: c.error,
      onError: c.background,
      surface: c.background,
      onSurface: c.text,
      surfaceContainerHighest: c.card,
      outline: c.border,
      outlineVariant: c.border,
    );

    final text = _textTheme(c.text);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: c.background,
      textTheme: text,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: c.textMuted, fontSize: 16),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.error, width: 2),
        ),
        errorStyle: TextStyle(color: c.error, fontSize: 13),
        helperStyle: TextStyle(color: c.textMuted, fontSize: 13),
        counterStyle: TextStyle(color: c.textMuted, fontSize: 13),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: c.border, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.primary : c.background,
        ),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.card,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.text,
        contentTextStyle: TextStyle(
          color: c.background,
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme _textTheme(Color color) {
    TextStyle s(double size, FontWeight weight, [double height = 1.4]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
        );
    return TextTheme(
      displaySmall: s(34, FontWeight.w800, 1.15),
      headlineSmall: s(24, FontWeight.w700, 1.25),
      titleLarge: s(22, FontWeight.w700, 1.25),
      titleMedium: s(16, FontWeight.w700),
      titleSmall: s(14, FontWeight.w700),
      bodyLarge: s(16, FontWeight.w400, 1.45),
      bodyMedium: s(14, FontWeight.w400),
      bodySmall: s(13, FontWeight.w400),
      labelLarge: s(16, FontWeight.w700),
      labelMedium: s(14, FontWeight.w600),
      labelSmall: s(12, FontWeight.w600),
    );
  }
}
