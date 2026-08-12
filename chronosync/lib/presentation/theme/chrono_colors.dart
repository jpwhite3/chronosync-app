import 'package:flutter/material.dart';

/// ChronoSync colors not represented by Material's standard [ColorScheme].
@immutable
class ChronoColors extends ThemeExtension<ChronoColors> {
  const ChronoColors({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.outline,
    required this.outlineStrong,
    required this.primary,
    required this.primaryPressed,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.approaching,
    required this.approachingContainer,
    required this.due,
    required this.dueContainer,
    required this.overtime,
    required this.overtimeContainer,
    required this.live,
    required this.liveContainer,
    required this.success,
    required this.successContainer,
    required this.disconnected,
    required this.disconnectedContainer,
    required this.focus,
  });

  static const ChronoColors light = ChronoColors(
    canvas: Color(0xFFF7F5EF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0EEE7),
    textPrimary: Color(0xFF19221E),
    textSecondary: Color(0xFF58645E),
    outline: Color(0xFFD7DDD8),
    outlineStrong: Color(0xFF7A877F),
    primary: Color(0xFF176B52),
    primaryPressed: Color(0xFF0B4A37),
    primaryContainer: Color(0xFFDDEFE8),
    onPrimaryContainer: Color(0xFF073D2E),
    approaching: Color(0xFF825200),
    approachingContainer: Color(0xFFFFE8B2),
    due: Color(0xFFA33D2F),
    dueContainer: Color(0xFFFBE2DD),
    overtime: Color(0xFF842B22),
    overtimeContainer: Color(0xFFF7D7D1),
    live: Color(0xFF245C89),
    liveContainer: Color(0xFFE0EEF8),
    success: Color(0xFF176544),
    successContainer: Color(0xFFDDF1E6),
    disconnected: Color(0xFF645C57),
    disconnectedContainer: Color(0xFFECE8E4),
    focus: Color(0xFF2E7DFF),
  );

  static const ChronoColors dark = ChronoColors(
    canvas: Color(0xFF0F1713),
    surface: Color(0xFF17201C),
    surfaceMuted: Color(0xFF202B25),
    textPrimary: Color(0xFFEEF5F1),
    textSecondary: Color(0xFFB4C2BA),
    outline: Color(0xFF607067),
    outlineStrong: Color(0xFF8A9A91),
    primary: Color(0xFF7EDDBA),
    primaryPressed: Color(0xFF5EC39F),
    primaryContainer: Color(0xFF164B3B),
    onPrimaryContainer: Color(0xFFB6F2DB),
    approaching: Color(0xFFFFD27A),
    approachingContainer: Color(0xFF4A3300),
    due: Color(0xFFFFB4A8),
    dueContainer: Color(0xFF5D201A),
    overtime: Color(0xFFFFB4AB),
    overtimeContainer: Color(0xFF5E211C),
    live: Color(0xFFA8CEFF),
    liveContainer: Color(0xFF143E60),
    success: Color(0xFF78D9A9),
    successContainer: Color(0xFF16462F),
    disconnected: Color(0xFFCFC4BD),
    disconnectedContainer: Color(0xFF3D3631),
    focus: Color(0xFF8BB8FF),
  );

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color outline;
  final Color outlineStrong;
  final Color primary;
  final Color primaryPressed;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color approaching;
  final Color approachingContainer;
  final Color due;
  final Color dueContainer;
  final Color overtime;
  final Color overtimeContainer;
  final Color live;
  final Color liveContainer;
  final Color success;
  final Color successContainer;
  final Color disconnected;
  final Color disconnectedContainer;
  final Color focus;

  @override
  ChronoColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? outline,
    Color? outlineStrong,
    Color? primary,
    Color? primaryPressed,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? approaching,
    Color? approachingContainer,
    Color? due,
    Color? dueContainer,
    Color? overtime,
    Color? overtimeContainer,
    Color? live,
    Color? liveContainer,
    Color? success,
    Color? successContainer,
    Color? disconnected,
    Color? disconnectedContainer,
    Color? focus,
  }) {
    return ChronoColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      primary: primary ?? this.primary,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      approaching: approaching ?? this.approaching,
      approachingContainer: approachingContainer ?? this.approachingContainer,
      due: due ?? this.due,
      dueContainer: dueContainer ?? this.dueContainer,
      overtime: overtime ?? this.overtime,
      overtimeContainer: overtimeContainer ?? this.overtimeContainer,
      live: live ?? this.live,
      liveContainer: liveContainer ?? this.liveContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      disconnected: disconnected ?? this.disconnected,
      disconnectedContainer:
          disconnectedContainer ?? this.disconnectedContainer,
      focus: focus ?? this.focus,
    );
  }

  @override
  ChronoColors lerp(covariant ChronoColors? other, double t) {
    if (other == null) {
      return this;
    }

    return ChronoColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      primaryContainer: Color.lerp(
        primaryContainer,
        other.primaryContainer,
        t,
      )!,
      onPrimaryContainer: Color.lerp(
        onPrimaryContainer,
        other.onPrimaryContainer,
        t,
      )!,
      approaching: Color.lerp(approaching, other.approaching, t)!,
      approachingContainer: Color.lerp(
        approachingContainer,
        other.approachingContainer,
        t,
      )!,
      due: Color.lerp(due, other.due, t)!,
      dueContainer: Color.lerp(dueContainer, other.dueContainer, t)!,
      overtime: Color.lerp(overtime, other.overtime, t)!,
      overtimeContainer: Color.lerp(
        overtimeContainer,
        other.overtimeContainer,
        t,
      )!,
      live: Color.lerp(live, other.live, t)!,
      liveContainer: Color.lerp(liveContainer, other.liveContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      disconnected: Color.lerp(disconnected, other.disconnected, t)!,
      disconnectedContainer: Color.lerp(
        disconnectedContainer,
        other.disconnectedContainer,
        t,
      )!,
      focus: Color.lerp(focus, other.focus, t)!,
    );
  }
}

extension ChronoThemeColors on BuildContext {
  /// Returns the active semantic palette, matching brightness as a fallback.
  ChronoColors get chronoColors {
    final ThemeData theme = Theme.of(this);
    return theme.extension<ChronoColors>() ??
        (theme.brightness == Brightness.dark
            ? ChronoColors.dark
            : ChronoColors.light);
  }
}
