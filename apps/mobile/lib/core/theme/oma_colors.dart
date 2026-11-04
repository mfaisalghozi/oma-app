import 'package:flutter/material.dart';

/// OMA design tokens for the two v0.1 palettes.
///
/// Values come from the v0.1 design canvas (Swatches and screen boards).
/// "Deep Sea swaps token values only; layout, sizes and copy stay the same."
///
/// TODO(tokens): generate this file from the shared tokens JSON once it exists
/// (architecture doc, "Theme"), so Flutter and Vue read one source.
@immutable
class OmaColors extends ThemeExtension<OmaColors> {
  const OmaColors({
    required this.background,
    required this.card,
    required this.primary,
    required this.onPrimary,
    required this.primaryStrong,
    required this.accent,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.mint,
    required this.tag,
    required this.onTag,
    required this.error,
    required this.errorSurface,
    required this.splash,
  });

  /// Lagoon, the light palette.
  static const lagoon = OmaColors(
    background: Color(0xFFFFFFFF),
    card: Color(0xFFEDF1F2),
    primary: Color(0xFF0E7C7B),
    onPrimary: Color(0xFFFFFFFF),
    primaryStrong: Color(0xFF0B5554),
    accent: Color(0xFFD9604A),
    text: Color(0xFF10303A),
    textMuted: Color(0xFF4A6A70),
    border: Color(0xFFCFE6E3),
    mint: Color(0xFFD5EFEC),
    tag: Color(0xFFFFE3DC),
    onTag: Color(0xFF10303A),
    error: Color(0xFFB42318),
    errorSurface: Color(0xFFFDECEA),
    splash: Color(0xFFD6F1EE),
  );

  /// Deep Sea, the dark palette.
  static const deepSea = OmaColors(
    background: Color(0xFF0B1F33),
    card: Color(0xFF12304C),
    primary: Color(0xFF5EE0D2),
    onPrimary: Color(0xFF0B1F33),
    primaryStrong: Color(0xFF9FF0E6),
    accent: Color(0xFFF6C177),
    text: Color(0xFFEAF2F8),
    textMuted: Color(0xFFA9BED1),
    border: Color(0xFF21476B),
    mint: Color(0xFF163B5C),
    tag: Color(0xFF1E3F60),
    onTag: Color(0xFFF6D8A8),
    // Not on the v0.1 board: picked to keep 4.5:1 on the Deep Sea background.
    error: Color(0xFFFF8A7A),
    errorSurface: Color(0xFF3A2230),
    splash: Color(0xFF0B1F33),
  );

  final Color background;
  final Color card;
  final Color primary;
  final Color onPrimary;

  /// Darker primary used for text on mint surfaces (Lagoon #0B5554).
  final Color primaryStrong;
  final Color accent;
  final Color text;
  final Color textMuted;
  final Color border;

  /// Soft primary-tinted surface (hero cards, icon circles).
  final Color mint;
  final Color tag;
  final Color onTag;
  final Color error;
  final Color errorSurface;

  /// Background behind the M00 splash.
  final Color splash;

  @override
  OmaColors copyWith({
    Color? background,
    Color? card,
    Color? primary,
    Color? onPrimary,
    Color? primaryStrong,
    Color? accent,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? mint,
    Color? tag,
    Color? onTag,
    Color? error,
    Color? errorSurface,
    Color? splash,
  }) {
    return OmaColors(
      background: background ?? this.background,
      card: card ?? this.card,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      accent: accent ?? this.accent,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      mint: mint ?? this.mint,
      tag: tag ?? this.tag,
      onTag: onTag ?? this.onTag,
      error: error ?? this.error,
      errorSurface: errorSurface ?? this.errorSurface,
      splash: splash ?? this.splash,
    );
  }

  @override
  OmaColors lerp(OmaColors? other, double t) {
    if (other == null) return this;
    return OmaColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryStrong: Color.lerp(primaryStrong, other.primaryStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      tag: Color.lerp(tag, other.tag, t)!,
      onTag: Color.lerp(onTag, other.onTag, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSurface: Color.lerp(errorSurface, other.errorSurface, t)!,
      splash: Color.lerp(splash, other.splash, t)!,
    );
  }
}

extension OmaThemeX on BuildContext {
  OmaColors get oma => Theme.of(this).extension<OmaColors>()!;
}
