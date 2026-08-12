import 'package:flutter/material.dart';

/// Bundled Inter typography tuned for quick scanning during live work.
abstract final class ChronoTypography {
  static TextTheme textTheme(ChronoColorsForTypography colors) {
    return TextTheme(
      displayLarge: TextStyle(
        color: colors.primary,
        fontSize: 64,
        fontWeight: FontWeight.w700,
        height: 1,
        letterSpacing: -2,
      ),
      displayMedium: TextStyle(
        color: colors.primary,
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -1.5,
      ),
      displaySmall: TextStyle(
        color: colors.primary,
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -1,
      ),
      headlineLarge: TextStyle(
        color: colors.primary,
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.75,
      ),
      headlineMedium: TextStyle(
        color: colors.primary,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.4,
      ),
      headlineSmall: TextStyle(
        color: colors.primary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: colors.primary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        color: colors.primary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      titleSmall: TextStyle(
        color: colors.primary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: TextStyle(
        color: colors.primary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: colors.primary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: colors.secondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: colors.primary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        color: colors.secondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.1,
      ),
      labelSmall: TextStyle(
        color: colors.secondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: 0.5,
      ),
    );
  }

  static const TextStyle timerCompact = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 1,
    letterSpacing: -1,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle timerStandard = TextStyle(
    fontSize: 64,
    fontWeight: FontWeight.w700,
    height: 1,
    letterSpacing: -2,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle timerHero = TextStyle(
    fontSize: 88,
    fontWeight: FontWeight.w700,
    height: 0.95,
    letterSpacing: -3,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}

/// Keeps [ChronoTypography] independent from a complete Material palette.
@immutable
class ChronoColorsForTypography {
  const ChronoColorsForTypography({
    required this.primary,
    required this.secondary,
  });

  final Color primary;
  final Color secondary;
}
