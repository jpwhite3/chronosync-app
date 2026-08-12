import 'package:chronosync/domain/session/live_session.dart';

Uri fragmentFreeNearbyUrl(Uri url) {
  final String serialized = url.toString();
  final int fragmentStart = serialized.indexOf('#');
  return fragmentStart < 0
      ? url
      : Uri.parse(serialized.substring(0, fragmentStart));
}

String? normalizeNearbyDisplayName(String? value) {
  final String normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.length <= maxParticipantDisplayNameLength) {
    return normalized;
  }

  final StringBuffer truncated = StringBuffer();
  for (final int rune in normalized.runes) {
    final String character = String.fromCharCode(rune);
    if (truncated.length + character.length > maxParticipantDisplayNameLength) {
      break;
    }
    truncated.write(character);
  }
  return truncated.toString();
}

Duration calculateHostClockOffset({
  required DateTime localReceivedAt,
  required DateTime authenticatedHostSentAt,
}) {
  return authenticatedHostSentAt.toUtc().difference(localReceivedAt.toUtc());
}

DateTime applyHostClockOffset(DateTime localNow, Duration? offset) {
  return localNow.toUtc().add(offset ?? Duration.zero);
}

bool isValidDeviceAuthenticationSecret(String? value) {
  return value != null && RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(value);
}

const String nearbyDeviceIdStorageKey = 'chronosync.nearby.device_id';

String nearbyAuthenticationStorageKey(String sessionId) {
  return 'chronosync.nearby.authentication_secret.$sessionId';
}

final class NearbyStoredIdentityDecision {
  const NearbyStoredIdentityDecision({
    required this.deviceId,
    required this.authenticationSecret,
  });

  final String? deviceId;
  final String? authenticationSecret;

  bool get needsDeviceId => deviceId == null;
  bool get needsAuthenticationSecret => authenticationSecret == null;
}

NearbyStoredIdentityDecision decideNearbyStoredIdentity({
  required String? storedDeviceId,
  required String? storedAuthenticationSecret,
}) {
  final String? deviceId =
      storedDeviceId != null &&
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
            r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
          ).hasMatch(storedDeviceId)
      ? storedDeviceId
      : null;
  return NearbyStoredIdentityDecision(
    deviceId: deviceId,
    authenticationSecret:
        isValidDeviceAuthenticationSecret(storedAuthenticationSecret)
        ? storedAuthenticationSecret
        : null,
  );
}

final class NearbyResolvedIdentity {
  const NearbyResolvedIdentity({
    required this.deviceId,
    required this.authenticationSecret,
  });

  final String deviceId;
  final String authenticationSecret;
}

Future<NearbyResolvedIdentity> restoreOrCreateNearbyIdentity({
  required String sessionId,
  required String? Function(String key) read,
  required void Function(String key, String value) write,
  required String Function() createDeviceId,
  required Future<String> Function() createAuthenticationSecret,
}) async {
  final String authenticationKey = nearbyAuthenticationStorageKey(sessionId);
  final NearbyStoredIdentityDecision stored = decideNearbyStoredIdentity(
    storedDeviceId: read(nearbyDeviceIdStorageKey),
    storedAuthenticationSecret: read(authenticationKey),
  );

  final String deviceId = stored.deviceId ?? createDeviceId();
  if (stored.needsDeviceId) {
    write(nearbyDeviceIdStorageKey, deviceId);
  }
  final String authenticationSecret =
      stored.authenticationSecret ?? await createAuthenticationSecret();
  if (stored.needsAuthenticationSecret) {
    write(authenticationKey, authenticationSecret);
  }
  return NearbyResolvedIdentity(
    deviceId: deviceId,
    authenticationSecret: authenticationSecret,
  );
}

/// Browser-friendly, immutable projection of a live session.
final class NearbySessionPresentation {
  const NearbySessionPresentation({
    required this.planTitle,
    required this.role,
    required this.roleLabel,
    required this.currentStepTitle,
    required this.nextStepTitle,
    required this.stepPositionLabel,
    required this.statusLabel,
    required this.elapsedLabel,
    required this.remainingLabel,
    required this.isOvertime,
    required this.progress,
    required this.hasAcknowledged,
    required this.showsActionPanel,
    required this.showsAcknowledgementControl,
    required this.showsControllerControls,
    required this.canAcknowledge,
    required this.canPauseResume,
    required this.pauseResumeLabel,
    required this.canAdvance,
    required this.canSubtractMinute,
    required this.canAddMinute,
  });

  factory NearbySessionPresentation.fromSession({
    required LiveSession session,
    required DateTime now,
    required String deviceId,
    required bool canSendCommands,
    required SessionRole invitedRole,
  }) {
    final Duration elapsed = session.elapsedAt(now);
    final Duration remaining = session.remainingAt(now);
    final Participant? participant = session.participantFor(deviceId);
    final SessionRole role = participant?.role ?? invitedRole;
    final bool isController = role == SessionRole.controller;
    final bool canAcknowledgeRole =
        role == SessionRole.controller || role == SessionRole.participant;
    final bool acknowledged =
        participant?.acknowledgedStepIndex == session.currentStepIndex &&
        participant?.acknowledgedAt != null;
    final int durationMicroseconds =
        session.adjustedCurrentStepDuration.inMicroseconds;
    final double rawProgress = durationMicroseconds == 0
        ? 0
        : elapsed.inMicroseconds / durationMicroseconds;

    return NearbySessionPresentation(
      planTitle: session.planSnapshot.title,
      role: role,
      roleLabel: switch (role) {
        SessionRole.host => 'Host',
        SessionRole.controller => 'Controller',
        SessionRole.participant => 'Participant',
        SessionRole.display => 'Display',
      },
      currentStepTitle: session.currentStep.title,
      nextStepTitle: session.nextStep?.title ?? 'Session complete',
      stepPositionLabel:
          'Step ${session.currentStepIndex + 1} of '
          '${session.planSnapshot.steps.length}',
      statusLabel: switch (session.status) {
        LiveSessionStatus.waiting => 'Waiting to start',
        LiveSessionStatus.running => remaining.isNegative ? 'Overtime' : 'Live',
        LiveSessionStatus.paused => 'Paused',
        LiveSessionStatus.ended => 'Ended',
      },
      elapsedLabel: formatClockDuration(elapsed),
      remainingLabel: formatRemainingClockDuration(remaining),
      isOvertime: remaining.isNegative,
      progress: rawProgress.clamp(0, 1),
      hasAcknowledged: acknowledged,
      showsActionPanel: canAcknowledgeRole,
      showsAcknowledgementControl: canAcknowledgeRole,
      showsControllerControls: isController,
      canAcknowledge:
          canSendCommands &&
          canAcknowledgeRole &&
          session.isActive &&
          !acknowledged,
      canPauseResume: canSendCommands && isController && session.isActive,
      pauseResumeLabel: session.status == LiveSessionStatus.paused
          ? 'Resume'
          : 'Pause',
      canAdvance:
          canSendCommands &&
          isController &&
          session.status == LiveSessionStatus.running,
      canSubtractMinute:
          canSendCommands &&
          isController &&
          session.isActive &&
          session.adjustedCurrentStepDuration > const Duration(minutes: 1),
      canAddMinute: canSendCommands && isController && session.isActive,
    );
  }

  final String planTitle;
  final SessionRole role;
  final String roleLabel;
  final String currentStepTitle;
  final String nextStepTitle;
  final String stepPositionLabel;
  final String statusLabel;
  final String elapsedLabel;
  final String remainingLabel;
  final bool isOvertime;
  final double progress;
  final bool hasAcknowledged;
  final bool showsActionPanel;
  final bool showsAcknowledgementControl;
  final bool showsControllerControls;
  final bool canAcknowledge;
  final bool canPauseResume;
  final String pauseResumeLabel;
  final bool canAdvance;
  final bool canSubtractMinute;
  final bool canAddMinute;

  String get progressWidth => '${(progress * 100).toStringAsFixed(1)}%';

  bool hasSameDomState(NearbySessionPresentation other) {
    return planTitle == other.planTitle &&
        role == other.role &&
        roleLabel == other.roleLabel &&
        currentStepTitle == other.currentStepTitle &&
        nextStepTitle == other.nextStepTitle &&
        stepPositionLabel == other.stepPositionLabel &&
        statusLabel == other.statusLabel &&
        elapsedLabel == other.elapsedLabel &&
        remainingLabel == other.remainingLabel &&
        isOvertime == other.isOvertime &&
        progressWidth == other.progressWidth &&
        hasAcknowledged == other.hasAcknowledged &&
        showsActionPanel == other.showsActionPanel &&
        showsAcknowledgementControl == other.showsAcknowledgementControl &&
        showsControllerControls == other.showsControllerControls &&
        canAcknowledge == other.canAcknowledge &&
        canPauseResume == other.canPauseResume &&
        pauseResumeLabel == other.pauseResumeLabel &&
        canAdvance == other.canAdvance &&
        canSubtractMinute == other.canSubtractMinute &&
        canAddMinute == other.canAddMinute;
  }
}

bool shouldAnnounceNearbyStep(
  NearbySessionPresentation? previous,
  NearbySessionPresentation current,
) {
  return previous == null ||
      previous.statusLabel != current.statusLabel ||
      previous.stepPositionLabel != current.stepPositionLabel ||
      previous.currentStepTitle != current.currentStepTitle;
}

String nearbyStepAnnouncement(NearbySessionPresentation presentation) {
  return '${presentation.statusLabel}. ${presentation.stepPositionLabel}: '
      '${presentation.currentStepTitle}.';
}

enum NearbyJoinSnapshotAction { wait, send, retry, confirm }

NearbyJoinSnapshotAction decideNearbyJoinOnSnapshot({
  required bool joinSent,
  required bool joinConfirmed,
  required int? joinBaseRevision,
  required int incomingRevision,
  required bool participantConnected,
}) {
  if (joinConfirmed) {
    return NearbyJoinSnapshotAction.wait;
  }
  if (!joinSent) {
    return NearbyJoinSnapshotAction.send;
  }
  if (joinBaseRevision != null && incomingRevision > joinBaseRevision) {
    return NearbyJoinSnapshotAction.retry;
  }
  if (participantConnected) {
    return NearbyJoinSnapshotAction.confirm;
  }
  return NearbyJoinSnapshotAction.wait;
}

String formatClockDuration(Duration duration) {
  final int totalSeconds = duration.inSeconds.abs();
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String minuteText = minutes.toString().padLeft(2, '0');
  final String secondText = seconds.toString().padLeft(2, '0');
  if (hours == 0) {
    return '$minuteText:$secondText';
  }
  return '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText';
}

String formatRemainingClockDuration(Duration remaining) {
  if (remaining.isNegative) {
    return '+${formatClockDuration(remaining.abs())}';
  }
  if (remaining == Duration.zero) {
    return formatClockDuration(remaining);
  }
  final int roundedSeconds =
      (remaining.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
  return formatClockDuration(Duration(seconds: roundedSeconds));
}
