import 'package:chronosync/presentation/theme/chrono_colors.dart';
import 'package:chronosync/presentation/theme/chrono_spacing.dart';
import 'package:chronosync/presentation/theme/chrono_typography.dart';
import 'package:flutter/material.dart';

/// The friendly, operationally clear visual language for ChronoSync.
abstract final class ChronoTheme {
  static ThemeData light() {
    const ChronoColors colors = ChronoColors.light;
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: Brightness.light,
          surface: colors.surface,
        ).copyWith(
          primary: colors.primary,
          onPrimary: Colors.white,
          primaryContainer: colors.primaryContainer,
          onPrimaryContainer: colors.onPrimaryContainer,
          secondary: const Color(0xFF53675E),
          onSecondary: Colors.white,
          secondaryContainer: colors.surfaceMuted,
          onSecondaryContainer: colors.textPrimary,
          tertiary: colors.approaching,
          onTertiary: Colors.white,
          tertiaryContainer: colors.approachingContainer,
          onTertiaryContainer: colors.approaching,
          error: colors.overtime,
          onError: Colors.white,
          errorContainer: colors.overtimeContainer,
          onErrorContainer: colors.overtime,
          surface: colors.surface,
          onSurface: colors.textPrimary,
          outline: colors.outlineStrong,
          outlineVariant: colors.outline,
          shadow: const Color(0x240F1D17),
        );
    final TextTheme textTheme = ChronoTypography.textTheme(
      const ChronoColorsForTypography(
        primary: Color(0xFF19221E),
        secondary: Color(0xFF58645E),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      focusColor: colors.focus.withValues(alpha: 0.18),
      hoverColor: colors.primary.withValues(alpha: 0.06),
      splashColor: colors.primary.withValues(alpha: 0.10),
      highlightColor: colors.primary.withValues(alpha: 0.05),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
      textTheme: textTheme,
      extensions: const <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colors.canvas,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x140F1D17),
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: ChronoRadii.surfaceBorder,
          side: BorderSide(color: Color(0xFFD7DDD8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(
              ChronoSpacing.minimumTouchTarget,
              ChronoSpacing.minimumTouchTarget,
            ),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: ChronoSpacing.md),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: ChronoRadii.controlBorder),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle?>(textTheme.labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return colors.primary.withValues(alpha: 0.32);
            }
            if (states.contains(WidgetState.pressed)) {
              return colors.primaryPressed;
            }
            return colors.primary;
          }),
          foregroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.focused)) {
              return Colors.white.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            ChronoSpacing.minimumTouchTarget,
            ChronoSpacing.minimumTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: ChronoSpacing.md),
          shape: const RoundedRectangleBorder(
            borderRadius: ChronoRadii.controlBorder,
          ),
          side: BorderSide(color: colors.outlineStrong),
          foregroundColor: colors.textPrimary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            ChronoSpacing.minimumTouchTarget,
            ChronoSpacing.minimumTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: ChronoSpacing.sm),
          shape: const RoundedRectangleBorder(
            borderRadius: ChronoRadii.controlBorder,
          ),
          foregroundColor: colors.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF176B52),
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: ChronoRadii.surfaceBorder),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChronoSpacing.sm,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: ChronoRadii.controlBorder,
          borderSide: BorderSide(color: colors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: ChronoRadii.controlBorder,
          borderSide: BorderSide(color: colors.outlineStrong),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: ChronoRadii.controlBorder,
          borderSide: BorderSide(color: Color(0xFF176B52), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: ChronoRadii.controlBorder,
          borderSide: BorderSide(color: colors.overtime),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outline,
        thickness: ChronoSpacing.hairline,
        space: ChronoSpacing.hairline,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: ChronoRadii.featureBorder,
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: ChronoRadii.controlBorder,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          textTheme.labelSmall,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        selectedIconTheme: IconThemeData(color: colors.primary),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.primary,
        ),
        unselectedIconTheme: IconThemeData(color: colors.textSecondary),
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: BorderRadius.circular(ChronoSpacing.xs),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }
}
