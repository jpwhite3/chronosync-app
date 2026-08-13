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
    canvas: Color(0xFFF4F5FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFE8EAF2),
    textPrimary: Color(0xFF11131C),
    textSecondary: Color(0xFF4B526D),
    outline: Color(0xFF7D849E),
    outlineStrong: Color(0xFF5A6077),
    primary: Color(0xFF1E3A8A),
    primaryPressed: Color(0xFF152A67),
    primaryContainer: Color(0xFFDCE6FF),
    onPrimaryContainer: Color(0xFF13265C),
    approaching: Color(0xFF765300),
    approachingContainer: Color(0xFFFFF0C2),
    due: Color(0xFF922B3A),
    dueContainer: Color(0xFFFFE1E5),
    overtime: Color(0xFF842331),
    overtimeContainer: Color(0xFFFADCE1),
    live: Color(0xFF174D8F),
    liveContainer: Color(0xFFDCEBFF),
    success: Color(0xFF4A5D23),
    successContainer: Color(0xFFE7EECF),
    disconnected: Color(0xFF51576B),
    disconnectedContainer: Color(0xFFE8EAF0),
    focus: Color(0xFF6366F1),
  );

  static const ChronoColors dark = ChronoColors(
    canvas: Color(0xFF050608),
    surface: Color(0xFF0B0C0E),
    surfaceMuted: Color(0xFF1A1D24),
    textPrimary: Color(0xFFE8E8E8),
    textSecondary: Color(0xFFBABED8),
    outline: Color(0xFF5A6077),
    outlineStrong: Color(0xFF8A92B2),
    primary: Color(0xFF666AF5),
    primaryPressed: Color(0xFF7A7DFF),
    primaryContainer: Color(0xFF1E2951),
    onPrimaryContainer: Color(0xFFC5CAE9),
    approaching: Color(0xFFFFCB6B),
    approachingContainer: Color(0xFF3B2A0B),
    due: Color(0xFFFF9CAC),
    dueContainer: Color(0xFF4C1B25),
    overtime: Color(0xFFFF8994),
    overtimeContainer: Color(0xFF501A24),
    live: Color(0xFF82AAFF),
    liveContainer: Color(0xFF142A4B),
    success: Color(0xFF9FB36B),
    successContainer: Color(0xFF293318),
    disconnected: Color(0xFFC5CAE9),
    disconnectedContainer: Color(0xFF2C2F40),
    focus: Color(0xFF82AAFF),
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
