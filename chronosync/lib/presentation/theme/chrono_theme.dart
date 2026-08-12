import 'package:chronosync/presentation/theme/chrono_colors.dart';
import 'package:chronosync/presentation/theme/chrono_spacing.dart';
import 'package:chronosync/presentation/theme/chrono_typography.dart';
import 'package:flutter/material.dart';

/// The friendly, operationally clear visual language for ChronoSync.
abstract final class ChronoTheme {
  static ThemeData light() =>
      _build(colors: ChronoColors.light, brightness: Brightness.light);

  static ThemeData dark() =>
      _build(colors: ChronoColors.dark, brightness: Brightness.dark);

  static ThemeData _build({
    required ChronoColors colors,
    required Brightness brightness,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final Color onPrimary = isDark ? const Color(0xFF003829) : Colors.white;
    final Color onAccent = isDark ? const Color(0xFF302100) : Colors.white;
    final Color shadow = isDark
        ? const Color(0x99000000)
        : const Color(0x240F1D17);
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: brightness,
          surface: colors.surface,
        ).copyWith(
          primary: colors.primary,
          onPrimary: onPrimary,
          primaryContainer: colors.primaryContainer,
          onPrimaryContainer: colors.onPrimaryContainer,
          secondary: isDark ? const Color(0xFFB8CEC2) : const Color(0xFF53675E),
          onSecondary: isDark ? const Color(0xFF23362D) : Colors.white,
          secondaryContainer: colors.surfaceMuted,
          onSecondaryContainer: colors.textPrimary,
          tertiary: colors.approaching,
          onTertiary: onAccent,
          tertiaryContainer: colors.approachingContainer,
          onTertiaryContainer: colors.approaching,
          error: colors.overtime,
          onError: isDark ? const Color(0xFF3B0906) : Colors.white,
          errorContainer: colors.overtimeContainer,
          onErrorContainer: colors.overtime,
          surface: colors.surface,
          onSurface: colors.textPrimary,
          outline: colors.outlineStrong,
          outlineVariant: colors.outline,
          shadow: shadow,
        );
    final TextTheme textTheme = ChronoTypography.textTheme(
      ChronoColorsForTypography(
        primary: colors.textPrimary,
        secondary: colors.textSecondary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
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
      extensions: <ThemeExtension<dynamic>>[colors],
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
        shadowColor: shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: ChronoRadii.surfaceBorder,
          side: BorderSide(color: colors.outline),
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
          foregroundColor: WidgetStatePropertyAll<Color>(onPrimary),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.focused)) {
              return onPrimary.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return onPrimary.withValues(alpha: 0.08);
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
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: onPrimary,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: ChronoRadii.surfaceBorder,
        ),
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
        focusedBorder: OutlineInputBorder(
          borderRadius: ChronoRadii.controlBorder,
          borderSide: BorderSide(color: colors.primary, width: 2),
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
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
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
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(ChronoSpacing.xs),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }
}
