import 'package:chronosync/presentation/theme/chrono_colors.dart';
import 'package:flutter/material.dart';

/// Semantic states used consistently by timers, pills, and live-session views.
enum ChronoStatus {
  neutral,
  live,
  approaching,
  due,
  overtime,
  paused,
  ended,
  complete,
  disconnected,
}

extension ChronoStatusLabel on ChronoStatus {
  String get label => switch (this) {
    ChronoStatus.neutral => 'Scheduled',
    ChronoStatus.live => 'Live',
    ChronoStatus.approaching => 'Approaching',
    ChronoStatus.due => 'Due now',
    ChronoStatus.overtime => 'Overtime',
    ChronoStatus.paused => 'Paused',
    ChronoStatus.ended => 'Ended',
    ChronoStatus.complete => 'Complete',
    ChronoStatus.disconnected => 'Disconnected',
  };

  IconData get icon => switch (this) {
    ChronoStatus.neutral => Icons.schedule_rounded,
    ChronoStatus.live => Icons.play_arrow_rounded,
    ChronoStatus.approaching => Icons.notifications_active_outlined,
    ChronoStatus.due => Icons.priority_high_rounded,
    ChronoStatus.overtime => Icons.timer_off_outlined,
    ChronoStatus.paused => Icons.pause_rounded,
    ChronoStatus.ended => Icons.stop_circle_outlined,
    ChronoStatus.complete => Icons.check_rounded,
    ChronoStatus.disconnected => Icons.cloud_off_outlined,
  };
}

@immutable
class ChronoStatusVisual {
  const ChronoStatusVisual({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;

  static ChronoStatusVisual resolve(BuildContext context, ChronoStatus status) {
    final ChronoColors colors = context.chronoColors;

    return switch (status) {
      ChronoStatus.neutral => ChronoStatusVisual(
        foreground: colors.textSecondary,
        background: colors.surfaceMuted,
        border: colors.outline,
      ),
      ChronoStatus.live => ChronoStatusVisual(
        foreground: colors.live,
        background: colors.liveContainer,
        border: colors.live,
      ),
      ChronoStatus.approaching => ChronoStatusVisual(
        foreground: colors.approaching,
        background: colors.approachingContainer,
        border: colors.approaching,
      ),
      ChronoStatus.due => ChronoStatusVisual(
        foreground: colors.due,
        background: colors.dueContainer,
        border: colors.due,
      ),
      ChronoStatus.overtime => ChronoStatusVisual(
        foreground: colors.overtime,
        background: colors.overtimeContainer,
        border: colors.overtime,
      ),
      ChronoStatus.paused => ChronoStatusVisual(
        foreground: colors.textPrimary,
        background: colors.surfaceMuted,
        border: colors.outlineStrong,
      ),
      ChronoStatus.ended => ChronoStatusVisual(
        foreground: colors.textPrimary,
        background: colors.surfaceMuted,
        border: colors.outlineStrong,
      ),
      ChronoStatus.complete => ChronoStatusVisual(
        foreground: colors.success,
        background: colors.successContainer,
        border: colors.success,
      ),
      ChronoStatus.disconnected => ChronoStatusVisual(
        foreground: colors.disconnected,
        background: colors.disconnectedContainer,
        border: colors.disconnected,
      ),
    };
  }
}
