import 'package:chronosync/domain/session/live_session.dart';
import 'package:flutter/foundation.dart';

/// The timer's visual phase after applying the current interval's cue profile.
enum LiveTimingPhase { normal, approaching, due, overtime }

/// One device's acknowledgement of a step.
@immutable
class AcknowledgementViewData {
  const AcknowledgementViewData({
    required this.actorDeviceId,
    required this.displayName,
    required this.role,
    required this.acknowledgedAt,
    this.isCurrentDevice = false,
  });

  final String actorDeviceId;
  final String displayName;
  final SessionRole role;
  final DateTime acknowledgedAt;
  final bool isCurrentDevice;
}

/// Presentation-ready invitation content for a lobby QR and share link.
@immutable
class LobbyInvitationViewData {
  const LobbyInvitationViewData({
    required this.label,
    required this.role,
    required this.link,
    this.detail,
    this.expiresAt,
  });

  final String label;
  final SessionRole role;
  final String link;
  final String? detail;
  final DateTime? expiresAt;
}

/// A connected device shown in the session lobby.
@immutable
class LobbyParticipantViewData {
  const LobbyParticipantViewData({
    required this.deviceId,
    required this.displayName,
    required this.role,
    required this.connectionState,
    this.isReady = false,
    this.isCurrentDevice = false,
    this.isManageable = true,
  });

  final String deviceId;
  final String displayName;
  final SessionRole role;
  final ParticipantConnectionState connectionState;
  final bool isReady;
  final bool isCurrentDevice;
  final bool isManageable;
}

/// Everything the lobby needs, without depending on a session controller.
@immutable
class LobbyViewData {
  const LobbyViewData({
    required this.planTitle,
    required this.transportLabel,
    required this.stepCount,
    required this.totalDuration,
    required this.participants,
    required this.isHostReady,
    this.participantInvitation,
    this.displayInvitation,
    this.sessionCode,
    this.connectionNote,
    this.isStarting = false,
  });

  final String planTitle;
  final String transportLabel;
  final int stepCount;
  final Duration totalDuration;
  final List<LobbyParticipantViewData> participants;
  final bool isHostReady;
  final LobbyInvitationViewData? participantInvitation;
  final LobbyInvitationViewData? displayInvitation;
  final String? sessionCode;
  final String? connectionNote;
  final bool isStarting;
}

/// Render-ready live state. Timing remains owned by the caller.
@immutable
class LiveSessionViewData {
  const LiveSessionViewData({
    required this.planTitle,
    required this.role,
    required this.status,
    this.endReason,
    required this.currentStepTitle,
    required this.currentStepIndex,
    required this.stepCount,
    required this.elapsed,
    required this.remaining,
    required this.variance,
    required this.participantCount,
    this.nextStepTitle,
    this.nextStepDuration,
    this.timingPhase = LiveTimingPhase.normal,
    this.currentStepAcknowledgements = const <AcknowledgementViewData>[],
    this.isStale = false,
    this.staleMessage,
    this.hasAcknowledged = false,
    required this.hasCompleteActivityHistory,
    this.revision = 0,
  });

  final String planTitle;
  final SessionRole role;
  final LiveSessionStatus status;
  final SessionEndReason? endReason;
  final String currentStepTitle;
  final int currentStepIndex;
  final int stepCount;
  final Duration elapsed;
  final Duration remaining;
  final Duration variance;
  final int participantCount;
  final String? nextStepTitle;
  final Duration? nextStepDuration;
  final LiveTimingPhase timingPhase;
  final List<AcknowledgementViewData> currentStepAcknowledgements;
  final bool isStale;
  final String? staleMessage;
  final bool hasAcknowledged;
  final bool hasCompleteActivityHistory;
  final int revision;
}

/// One row in the planned-versus-actual session summary.
@immutable
class StepSummaryViewData {
  const StepSummaryViewData({
    required this.title,
    required this.plannedDuration,
    required this.actualDuration,
    required this.variance,
    this.acknowledgements = const <AcknowledgementViewData>[],
    this.wasAcknowledged = false,
    this.wasCompleted = true,
  });

  final String title;
  final Duration plannedDuration;
  final Duration actualDuration;
  final Duration variance;
  final List<AcknowledgementViewData> acknowledgements;
  final bool wasAcknowledged;
  final bool wasCompleted;

  bool get hasAcknowledgements =>
      wasAcknowledged || acknowledgements.isNotEmpty;
}

/// Aggregate values and rows for the post-session summary.
@immutable
class SessionSummaryViewData {
  const SessionSummaryViewData({
    required this.planTitle,
    required this.startedAt,
    required this.endReason,
    required this.plannedDuration,
    required this.actualDuration,
    required this.variance,
    required this.steps,
    required this.activityCount,
    required this.hasCompleteActivityHistory,
    this.endedAt,
  });

  final String planTitle;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final SessionEndReason? endReason;
  final Duration plannedDuration;
  final Duration actualDuration;
  final Duration variance;
  final List<StepSummaryViewData> steps;
  final int activityCount;
  final bool hasCompleteActivityHistory;
}
