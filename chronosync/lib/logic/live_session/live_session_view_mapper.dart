import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/live/live.dart';

LiveSessionViewData mapLiveSessionView({
  required LiveSession session,
  required SessionRole role,
  required String deviceId,
  required DateTime now,
  required bool isStale,
  String? staleMessage,
  String? currentDeviceDisplayName,
  String? hostDisplayName,
  int? connectedParticipantCount,
  int connectedDisplayCount = 0,
}) {
  final List<AcknowledgementViewData> acknowledgements =
      _acknowledgementsForStep(
        session: session,
        stepIndex: session.currentStepIndex,
        currentDeviceId: deviceId,
        currentDeviceDisplayName: currentDeviceDisplayName,
        hostDisplayName: hostDisplayName,
      );
  final bool acknowledged = acknowledgements.any(
    (AcknowledgementViewData acknowledgement) =>
        acknowledgement.isCurrentDevice,
  );
  final int connectedParticipants =
      connectedParticipantCount ??
      session.participants
          .where(
            (Participant participant) =>
                participant.connectionState ==
                ParticipantConnectionState.connected,
          )
          .length;
  return LiveSessionViewData(
    planTitle: session.planSnapshot.title,
    role: role,
    status: session.status,
    endReason: session.endReason,
    currentStepTitle: session.currentStep.title,
    currentStepIndex: session.currentStepIndex,
    stepCount: session.planSnapshot.steps.length,
    elapsed: session.elapsedAt(now),
    remaining: session.remainingAt(now),
    variance: session.scheduleVarianceAt(now),
    participantCount: connectedParticipants + connectedDisplayCount + 1,
    nextStepTitle: session.nextStep?.title,
    nextStepDuration: session.nextStep?.duration,
    timingPhase: _timingPhaseFor(session, now),
    currentStepAcknowledgements: acknowledgements,
    isStale: isStale,
    staleMessage: staleMessage,
    hasAcknowledged: acknowledged,
    hasCompleteActivityHistory: session.hasCompleteActivityHistory,
    revision: session.revision,
  );
}

SessionSummaryViewData mapSessionSummaryView({
  required LiveSession session,
  required DateTime now,
  String? hostDisplayName,
  String? currentDeviceId,
  String? currentDeviceDisplayName,
}) {
  final List<Duration> actualDurations = List<Duration>.filled(
    session.planSnapshot.steps.length,
    Duration.zero,
  );
  final Set<int> completedSteps = <int>{};

  int? activeStep;
  DateTime? activeSince;
  for (final Activity activity in session.activities) {
    final bool opensStep =
        activity.type == ActivityType.started ||
        activity.type == ActivityType.advanced ||
        activity.type == ActivityType.autoAdvanced ||
        activity.type == ActivityType.jumped;
    if (opensStep) {
      if (activeStep != null && activeSince != null) {
        actualDurations[activeStep] += activity.occurredAt.difference(
          activeSince,
        );
        completedSteps.add(activeStep);
      }
      activeStep = activity.stepIndex;
      activeSince = activity.occurredAt;
    } else if (activity.type == ActivityType.ended &&
        activeStep != null &&
        activeSince != null) {
      actualDurations[activeStep] += activity.occurredAt.difference(
        activeSince,
      );
      if (activity.payload['reason'] == SessionEndReason.completed.name) {
        completedSteps.add(activeStep);
      }
      activeStep = null;
      activeSince = null;
    }
  }
  if (activeStep != null && activeSince != null) {
    actualDurations[activeStep] += (session.endedAt ?? now.toUtc()).difference(
      activeSince,
    );
  }

  final List<StepSummaryViewData> stepRows = <StepSummaryViewData>[];
  for (int index = 0; index < session.planSnapshot.steps.length; index += 1) {
    final List<AcknowledgementViewData> acknowledgements =
        _acknowledgementsForStep(
          session: session,
          stepIndex: index,
          currentDeviceId: currentDeviceId,
          currentDeviceDisplayName: currentDeviceDisplayName,
          hostDisplayName: hostDisplayName,
        );
    stepRows.add(
      StepSummaryViewData(
        title: session.planSnapshot.steps[index].title,
        plannedDuration: session.planSnapshot.steps[index].duration,
        actualDuration: actualDurations[index],
        variance:
            actualDurations[index] - session.planSnapshot.steps[index].duration,
        acknowledgements: acknowledgements,
        wasAcknowledged: acknowledgements.isNotEmpty,
        wasCompleted: completedSteps.contains(index),
      ),
    );
  }
  final Duration actualDuration = session.totalElapsedAt(now);
  return SessionSummaryViewData(
    planTitle: session.planSnapshot.title,
    startedAt: session.startedAt,
    endedAt: session.endedAt,
    endReason: session.endReason,
    plannedDuration: session.planSnapshot.totalDuration,
    actualDuration: actualDuration,
    variance: actualDuration - session.planSnapshot.totalDuration,
    steps: stepRows,
    activityCount: session.activities.length,
    hasCompleteActivityHistory: session.hasCompleteActivityHistory,
  );
}

LiveTimingPhase _timingPhaseFor(LiveSession session, DateTime now) {
  final Duration remaining = session.remainingAt(now);
  final CueProfile cue =
      session.currentStep.cueOverride ?? session.planSnapshot.defaultCueProfile;
  // The timer remains numerically accurate when visual cues are disabled,
  // while threshold-driven color and status treatments stay neutral. Sound
  // and haptic delivery continue to follow their independent settings.
  if (!cue.visualEnabled) {
    return LiveTimingPhase.normal;
  }
  final Duration overdueThreshold = Duration(seconds: cue.overdueSeconds);
  if (remaining <= -overdueThreshold) {
    return LiveTimingPhase.overtime;
  }
  if (remaining <= Duration.zero) {
    return LiveTimingPhase.due;
  }
  final bool includesApproaching = cue.includesApproachingCueFor(
    session.currentStep.duration,
    isStepOverride: session.currentStep.cueOverride != null,
  );
  if (includesApproaching &&
      remaining <= Duration(seconds: cue.approachingSeconds)) {
    return LiveTimingPhase.approaching;
  }
  return LiveTimingPhase.normal;
}

List<AcknowledgementViewData> _acknowledgementsForStep({
  required LiveSession session,
  required int stepIndex,
  String? currentDeviceId,
  String? currentDeviceDisplayName,
  String? hostDisplayName,
}) {
  final Map<String, Activity> firstByActor = <String, Activity>{};
  for (final Activity activity in session.activities) {
    if (activity.type == ActivityType.acknowledged &&
        activity.stepIndex == stepIndex) {
      firstByActor.putIfAbsent(activity.actorDeviceId, () => activity);
    }
  }
  final List<AcknowledgementViewData> values = firstByActor.values
      .map<AcknowledgementViewData>((Activity activity) {
        return AcknowledgementViewData(
          actorDeviceId: activity.actorDeviceId,
          displayName:
              _nonEmpty(activity.actorDisplayName) ??
              _displayNameFor(
                session: session,
                actorDeviceId: activity.actorDeviceId,
                actorRole: activity.actorRole,
                currentDeviceId: currentDeviceId,
                currentDeviceDisplayName: currentDeviceDisplayName,
                hostDisplayName: hostDisplayName,
              ),
          role: activity.actorRole,
          acknowledgedAt: activity.occurredAt,
          isCurrentDevice: activity.actorDeviceId == currentDeviceId,
        );
      })
      .toList();
  for (final Participant participant in session.participants) {
    final DateTime? acknowledgedAt = participant.acknowledgedAt;
    if (participant.acknowledgedStepIndex == stepIndex &&
        acknowledgedAt != null &&
        !firstByActor.containsKey(participant.deviceId)) {
      values.add(
        AcknowledgementViewData(
          actorDeviceId: participant.deviceId,
          displayName: participant.displayName,
          role: participant.role,
          acknowledgedAt: acknowledgedAt,
          isCurrentDevice: participant.deviceId == currentDeviceId,
        ),
      );
    }
  }
  values.sort(
    (AcknowledgementViewData left, AcknowledgementViewData right) =>
        left.acknowledgedAt.compareTo(right.acknowledgedAt),
  );
  return List<AcknowledgementViewData>.unmodifiable(values);
}

String _displayNameFor({
  required LiveSession session,
  required String actorDeviceId,
  required SessionRole actorRole,
  String? currentDeviceId,
  String? currentDeviceDisplayName,
  String? hostDisplayName,
}) {
  if (actorDeviceId == session.hostDeviceId) {
    return _nonEmpty(hostDisplayName) ?? 'Host';
  }
  for (final Participant participant in session.participants) {
    if (participant.deviceId == actorDeviceId) {
      return participant.displayName;
    }
  }
  if (actorDeviceId == currentDeviceId) {
    final String? displayName = _nonEmpty(currentDeviceDisplayName);
    if (displayName != null) {
      return displayName;
    }
  }
  return switch (actorRole) {
    SessionRole.host => 'Host',
    SessionRole.controller => 'Timekeeper',
    SessionRole.participant => 'Participant',
    SessionRole.display => 'Display',
  };
}

String? _nonEmpty(String? value) {
  final String? normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
