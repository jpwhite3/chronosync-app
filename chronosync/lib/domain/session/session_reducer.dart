import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:equatable/equatable.dart';

enum SessionCommandError {
  wrongSession,
  staleRevision,
  unauthorized,
  invalidState,
  invalidStep,
  confirmationRequired,
  invalidAdjustment,
}

class SessionCommandException implements Exception {
  const SessionCommandException(this.code, this.message);

  final SessionCommandError code;
  final String message;

  @override
  String toString() => 'SessionCommandException(${code.name}): $message';
}

/// The outcome of host-side command processing.
class SessionTransition extends Equatable {
  const SessionTransition({
    required this.session,
    required this.activity,
    required this.wasDuplicate,
  });

  final LiveSession session;
  final Activity? activity;
  final bool wasDuplicate;

  @override
  List<Object?> get props => <Object?>[session, activity, wasDuplicate];
}

/// The sole state-transition boundary for a [LiveSession].
///
/// Hosts call [applyCommand]. Replicas call [applyActivity] with the resulting
/// host activity, producing the same state and revision.
class SessionReducer {
  const SessionReducer._();

  static SessionTransition applyCommand({
    required LiveSession session,
    required SessionCommand command,
    required DateTime occurredAt,
    String? activityId,
  }) {
    if (command.sessionId != session.id) {
      throw const SessionCommandException(
        SessionCommandError.wrongSession,
        'The command belongs to a different session.',
      );
    }

    // Idempotency is checked before baseRevision so a transport retry remains
    // harmless after the original command has advanced the host revision.
    if (session.hasProcessedCommand(command.id)) {
      return SessionTransition(
        session: session,
        activity: null,
        wasDuplicate: true,
      );
    }
    if (command.baseRevision != session.revision) {
      throw SessionCommandException(
        SessionCommandError.staleRevision,
        'Expected base revision ${session.revision}, '
        'received ${command.baseRevision}.',
      );
    }

    _authorize(session, command);
    if (command.type == SessionCommandType.acknowledge &&
        _hasAcknowledgedCurrentStep(session, command.actorDeviceId)) {
      return SessionTransition(
        session: session,
        activity: null,
        wasDuplicate: true,
      );
    }
    final DateTime hostTime = occurredAt.toUtc();
    final Activity activity = _createActivity(
      session: session,
      command: command,
      activityId: activityId ?? command.id,
      occurredAt: hostTime,
    );
    return SessionTransition(
      session: applyActivity(session: session, activity: activity),
      activity: activity,
      wasDuplicate: false,
    );
  }

  /// Applies one consecutive, host-issued activity to a replica.
  static LiveSession applyActivity({
    required LiveSession session,
    required Activity activity,
  }) {
    if (activity.sessionId != session.id) {
      throw StateError('The activity belongs to a different session.');
    }
    if (session.hasProcessedCommand(activity.commandId)) {
      throw StateError('The activity command was already applied.');
    }
    if (activity.revision != session.revision + 1) {
      throw StateError(
        'Expected activity revision ${session.revision + 1}, '
        'received ${activity.revision}.',
      );
    }
    if (session.activities.isNotEmpty &&
        activity.occurredAt.isBefore(session.activities.last.occurredAt)) {
      throw StateError('Activity timestamps cannot move backwards.');
    }

    switch (activity.type) {
      case ActivityType.participantJoined:
        _requireNotEnded(session);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        if (session.participantFor(activity.actorDeviceId) != null ||
            activity.actorDeviceId == session.hostDeviceId) {
          throw StateError('The joining device is already in this session.');
        }
        final SessionRole requestedRole = _requiredPayloadRole(
          activity,
          'requestedRole',
        );
        if (requestedRole != SessionRole.participant &&
            requestedRole != SessionRole.display) {
          throw StateError(
            'A public join can grant Participant or Display only.',
          );
        }
        return session.copyWith(
          revision: activity.revision,
          participants: <Participant>[
            ...session.participants,
            Participant(
              deviceId: activity.actorDeviceId,
              displayName: _requiredPayloadString(activity, 'displayName'),
              role: requestedRole,
              joinedAt: activity.occurredAt,
              lastSeenRevision: activity.revision,
            ),
          ],
          appendedActivity: activity,
        );
      case ActivityType.roleChanged:
        _requireNotEnded(session);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        final String roleTargetDeviceId = _requiredPayloadString(
          activity,
          'targetDeviceId',
        );
        final SessionRole targetRole = _requiredPayloadRole(
          activity,
          'targetRole',
        );
        if (targetRole == SessionRole.host) {
          throw StateError('A participant cannot be promoted to Host.');
        }
        final int roleTargetIndex = session.participants.indexWhere(
          (Participant participant) =>
              participant.deviceId == roleTargetDeviceId,
        );
        if (roleTargetIndex < 0) {
          throw StateError('The role-change target is not in this session.');
        }
        final List<Participant> roleParticipants = List<Participant>.of(
          session.participants,
        );
        roleParticipants[roleTargetIndex] = roleParticipants[roleTargetIndex]
            .copyWith(role: targetRole, lastSeenRevision: activity.revision);
        return session.copyWith(
          revision: activity.revision,
          participants: roleParticipants,
          appendedActivity: activity,
        );
      case ActivityType.participantDisconnected:
        _requireNotEnded(session);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        final String disconnectTargetDeviceId = _requiredPayloadString(
          activity,
          'targetDeviceId',
        );
        final int disconnectTargetIndex = session.participants.indexWhere(
          (Participant participant) =>
              participant.deviceId == disconnectTargetDeviceId,
        );
        if (disconnectTargetIndex < 0) {
          throw StateError('The disconnect target is not in this session.');
        }
        final List<Participant> disconnectParticipants = List<Participant>.of(
          session.participants,
        );
        disconnectParticipants[disconnectTargetIndex] =
            disconnectParticipants[disconnectTargetIndex].copyWith(
              lastSeenRevision: activity.revision,
              connectionState: ParticipantConnectionState.disconnected,
            );
        return session.copyWith(
          revision: activity.revision,
          participants: disconnectParticipants,
          appendedActivity: activity,
        );
      case ActivityType.started:
        _requireStatus(session, LiveSessionStatus.waiting);
        _requireActivityStep(session, activity, expectedIndex: 0);
        return session.copyWith(
          status: LiveSessionStatus.running,
          revision: activity.revision,
          startedAt: activity.occurredAt,
          currentStepStartedAt: activity.occurredAt,
          appendedActivity: activity,
        );
      case ActivityType.paused:
        _requireStatus(session, LiveSessionStatus.running);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        return session.copyWith(
          status: LiveSessionStatus.paused,
          revision: activity.revision,
          pausedAt: activity.occurredAt,
          appendedActivity: activity,
        );
      case ActivityType.resumed:
        _requireStatus(session, LiveSessionStatus.paused);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        final Duration pause = activity.occurredAt.difference(
          session.pausedAt!,
        );
        if (pause.isNegative) {
          throw StateError('A resume cannot precede its pause.');
        }
        return session.copyWith(
          status: LiveSessionStatus.running,
          revision: activity.revision,
          pausedAt: null,
          currentStepPausedDuration: session.currentStepPausedDuration + pause,
          totalPausedDuration: session.totalPausedDuration + pause,
          appendedActivity: activity,
        );
      case ActivityType.advanced:
      case ActivityType.autoAdvanced:
        _requireStatus(session, LiveSessionStatus.running);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex + 1,
        );
        return session.copyWith(
          currentStepIndex: activity.stepIndex!,
          revision: activity.revision,
          currentStepStartedAt: activity.occurredAt,
          currentStepPausedDuration: Duration.zero,
          remainingAdjustmentSeconds: 0,
          participants: _clearAcknowledgements(session.participants),
          appendedActivity: activity,
        );
      case ActivityType.remainingAdjusted:
        _requireActive(session);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        final int adjustmentSeconds = _requiredPayloadInt(
          activity,
          'adjustmentSeconds',
        );
        final int nextAdjustment =
            session.remainingAdjustmentSeconds + adjustmentSeconds;
        final int adjustedDuration =
            session.currentStep.durationSeconds + nextAdjustment;
        if (adjustedDuration <= 0 ||
            adjustedDuration > maxStepDurationSeconds) {
          throw StateError(
            'An adjustment must leave the step within the supported duration.',
          );
        }
        return session.copyWith(
          revision: activity.revision,
          remainingAdjustmentSeconds: nextAdjustment,
          appendedActivity: activity,
        );
      case ActivityType.jumped:
        _requireActive(session);
        final int targetStepIndex = _requiredPayloadInt(
          activity,
          'targetStepIndex',
        );
        _requireActivityStep(session, activity, expectedIndex: targetStepIndex);
        if (targetStepIndex == session.currentStepIndex) {
          throw StateError('A jump must select a different step.');
        }
        Duration totalPausedDuration = session.totalPausedDuration;
        if (session.status == LiveSessionStatus.paused) {
          final Duration pauseBeforeJump = activity.occurredAt.difference(
            session.pausedAt!,
          );
          if (pauseBeforeJump.isNegative) {
            throw StateError('A jump cannot precede its pause.');
          }
          totalPausedDuration += pauseBeforeJump;
        }
        return session.copyWith(
          currentStepIndex: targetStepIndex,
          revision: activity.revision,
          currentStepStartedAt: activity.occurredAt,
          pausedAt: session.status == LiveSessionStatus.paused
              ? activity.occurredAt
              : null,
          currentStepPausedDuration: Duration.zero,
          totalPausedDuration: totalPausedDuration,
          remainingAdjustmentSeconds: 0,
          participants: _clearAcknowledgements(session.participants),
          appendedActivity: activity,
        );
      case ActivityType.acknowledged:
        _requireActive(session);
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        final List<Participant> acknowledgementParticipants =
            List<Participant>.of(session.participants);
        final int acknowledgingParticipantIndex = acknowledgementParticipants
            .indexWhere(
              (Participant participant) =>
                  participant.deviceId == activity.actorDeviceId,
            );
        if (acknowledgingParticipantIndex >= 0) {
          acknowledgementParticipants[acknowledgingParticipantIndex] =
              acknowledgementParticipants[acknowledgingParticipantIndex]
                  .copyWith(
                    lastSeenRevision: activity.revision,
                    acknowledgedStepIndex: activity.stepIndex,
                    acknowledgedAt: activity.occurredAt,
                  );
        }
        return session.copyWith(
          revision: activity.revision,
          participants: acknowledgementParticipants,
          appendedActivity: activity,
        );
      case ActivityType.ended:
        if (session.status == LiveSessionStatus.ended) {
          throw StateError('The session has already ended.');
        }
        _requireActivityStep(
          session,
          activity,
          expectedIndex: session.currentStepIndex,
        );
        final SessionEndReason reason = _endReason(activity);
        if (reason == SessionEndReason.completed &&
            session.currentStepIndex != session.planSnapshot.steps.length - 1) {
          throw StateError('Only the final step can complete a session.');
        }

        Duration currentStepPause = session.currentStepPausedDuration;
        Duration totalPause = session.totalPausedDuration;
        if (session.status == LiveSessionStatus.paused) {
          final Duration finalPause = activity.occurredAt.difference(
            session.pausedAt!,
          );
          if (finalPause.isNegative) {
            throw StateError('An end cannot precede its pause.');
          }
          currentStepPause += finalPause;
          totalPause += finalPause;
        }
        return session.copyWith(
          status: LiveSessionStatus.ended,
          revision: activity.revision,
          pausedAt: null,
          currentStepPausedDuration: currentStepPause,
          totalPausedDuration: totalPause,
          endedAt: activity.occurredAt,
          endReason: reason,
          appendedActivity: activity,
        );
    }
  }

  static Activity _createActivity({
    required LiveSession session,
    required SessionCommand command,
    required String activityId,
    required DateTime occurredAt,
  }) {
    ActivityType type;
    int stepIndex = session.currentStepIndex;
    Map<String, Object?> payload = const <String, Object?>{};

    switch (command.type) {
      case SessionCommandType.join:
        if (session.status == LiveSessionStatus.ended) {
          throw const SessionCommandException(
            SessionCommandError.invalidState,
            'An ended session cannot accept new participants.',
          );
        }
        type = ActivityType.participantJoined;
        payload = <String, Object?>{
          'displayName': command.displayName!,
          'requestedRole': command.requestedRole!.name,
        };
      case SessionCommandType.changeRole:
        if (session.status == LiveSessionStatus.ended) {
          throw const SessionCommandException(
            SessionCommandError.invalidState,
            'An ended session cannot change participant roles.',
          );
        }
        final Participant? roleTarget = session.participantFor(
          command.targetDeviceId!,
        );
        if (roleTarget == null) {
          throw const SessionCommandException(
            SessionCommandError.invalidStep,
            'The role-change target is not in this session.',
          );
        }
        if (roleTarget.role == command.targetRole) {
          throw const SessionCommandException(
            SessionCommandError.invalidState,
            'The participant already has this role.',
          );
        }
        type = ActivityType.roleChanged;
        payload = <String, Object?>{
          'targetDeviceId': command.targetDeviceId!,
          'targetRole': command.targetRole!.name,
        };
      case SessionCommandType.disconnectParticipant:
        if (session.status == LiveSessionStatus.ended) {
          throw const SessionCommandException(
            SessionCommandError.invalidState,
            'An ended session cannot disconnect participants.',
          );
        }
        final Participant? disconnectTarget = session.participantFor(
          command.targetDeviceId!,
        );
        if (disconnectTarget == null) {
          throw const SessionCommandException(
            SessionCommandError.invalidStep,
            'The disconnect target is not in this session.',
          );
        }
        if (disconnectTarget.connectionState ==
            ParticipantConnectionState.disconnected) {
          throw const SessionCommandException(
            SessionCommandError.invalidState,
            'The participant is already disconnected.',
          );
        }
        type = ActivityType.participantDisconnected;
        payload = <String, Object?>{'targetDeviceId': command.targetDeviceId!};
      case SessionCommandType.start:
        _requireCommandStatus(session, LiveSessionStatus.waiting);
        type = ActivityType.started;
      case SessionCommandType.pause:
        _requireCommandStatus(session, LiveSessionStatus.running);
        type = ActivityType.paused;
      case SessionCommandType.resume:
        _requireCommandStatus(session, LiveSessionStatus.paused);
        type = ActivityType.resumed;
      case SessionCommandType.advance:
        _requireCommandStatus(session, LiveSessionStatus.running);
        final bool isFinal =
            session.currentStepIndex == session.planSnapshot.steps.length - 1;
        if (isFinal) {
          type = ActivityType.ended;
          payload = <String, Object?>{
            'reason': SessionEndReason.completed.name,
          };
        } else {
          stepIndex += 1;
          type = command.automatically
              ? ActivityType.autoAdvanced
              : ActivityType.advanced;
        }
      case SessionCommandType.adjustRemaining:
        _requireCommandActive(session);
        final int adjustment = command.adjustmentSeconds!;
        final int adjustedDuration =
            session.currentStep.durationSeconds +
            session.remainingAdjustmentSeconds +
            adjustment;
        if (adjustedDuration <= 0 ||
            adjustedDuration > maxStepDurationSeconds) {
          throw const SessionCommandException(
            SessionCommandError.invalidAdjustment,
            'An adjustment must leave the step within the supported duration.',
          );
        }
        type = ActivityType.remainingAdjusted;
        payload = <String, Object?>{'adjustmentSeconds': adjustment};
      case SessionCommandType.jump:
        _requireCommandActive(session);
        if (!command.confirmed) {
          throw const SessionCommandException(
            SessionCommandError.confirmationRequired,
            'Jumping to another step requires confirmation.',
          );
        }
        final int targetStepIndex = command.targetStepIndex!;
        if (targetStepIndex >= session.planSnapshot.steps.length ||
            targetStepIndex == session.currentStepIndex) {
          throw const SessionCommandException(
            SessionCommandError.invalidStep,
            'The jump target must be a different step in this plan.',
          );
        }
        stepIndex = targetStepIndex;
        type = ActivityType.jumped;
        payload = <String, Object?>{'targetStepIndex': targetStepIndex};
      case SessionCommandType.acknowledge:
        _requireCommandActive(session);
        if (command.acknowledgedStepIndex != session.currentStepIndex) {
          throw const SessionCommandException(
            SessionCommandError.invalidStep,
            'An acknowledgement must target the current step.',
          );
        }
        type = ActivityType.acknowledged;
      case SessionCommandType.end:
        if (session.status == LiveSessionStatus.ended) {
          throw const SessionCommandException(
            SessionCommandError.invalidState,
            'The session has already ended.',
          );
        }
        if (!command.confirmed) {
          throw const SessionCommandException(
            SessionCommandError.confirmationRequired,
            'Ending a session requires confirmation.',
          );
        }
        type = ActivityType.ended;
        payload = <String, Object?>{
          'reason': SessionEndReason.endedByHost.name,
        };
    }

    return Activity(
      id: activityId,
      commandId: command.id,
      sessionId: session.id,
      revision: session.revision + 1,
      type: type,
      stepIndex: stepIndex,
      stepId: session.planSnapshot.steps[stepIndex].id,
      actorDeviceId: command.actorDeviceId,
      actorRole: command.actorRole,
      occurredAt: occurredAt,
      payload: payload,
    );
  }

  static void _authorize(LiveSession session, SessionCommand command) {
    if (command.type == SessionCommandType.join) {
      if (command.actorDeviceId == session.hostDeviceId ||
          session.participantFor(command.actorDeviceId) != null ||
          command.actorRole != command.requestedRole ||
          (command.requestedRole != SessionRole.participant &&
              command.requestedRole != SessionRole.display)) {
        throw const SessionCommandException(
          SessionCommandError.unauthorized,
          'Only an unknown device may request Participant or Display access.',
        );
      }
      return;
    }

    if (command.actorDeviceId == session.hostDeviceId) {
      if (command.actorRole != SessionRole.host) {
        throw const SessionCommandException(
          SessionCommandError.unauthorized,
          'The host device must use the host role.',
        );
      }
    } else {
      if (command.actorRole == SessionRole.host) {
        throw const SessionCommandException(
          SessionCommandError.unauthorized,
          'Only the configured host device can hold the host role.',
        );
      }
      final Participant? participant = session.participantFor(
        command.actorDeviceId,
      );
      if (participant == null ||
          participant.role != command.actorRole ||
          participant.connectionState != ParticipantConnectionState.connected) {
        throw const SessionCommandException(
          SessionCommandError.unauthorized,
          'The actor does not hold this connected session role.',
        );
      }
    }

    final bool allowed = switch (command.actorRole) {
      SessionRole.host => true,
      SessionRole.controller =>
        command.type == SessionCommandType.pause ||
            command.type == SessionCommandType.resume ||
            command.type == SessionCommandType.advance ||
            command.type == SessionCommandType.adjustRemaining ||
            command.type == SessionCommandType.jump ||
            command.type == SessionCommandType.acknowledge,
      SessionRole.participant => command.type == SessionCommandType.acknowledge,
      SessionRole.display => false,
    };
    if (!allowed ||
        (command.automatically && command.actorRole != SessionRole.host)) {
      throw const SessionCommandException(
        SessionCommandError.unauthorized,
        'This role cannot issue the requested command.',
      );
    }
  }

  static void _requireCommandStatus(
    LiveSession session,
    LiveSessionStatus expected,
  ) {
    if (session.status != expected) {
      throw SessionCommandException(
        SessionCommandError.invalidState,
        'Expected ${expected.name}; session is ${session.status.name}.',
      );
    }
  }

  static bool _hasAcknowledgedCurrentStep(
    LiveSession session,
    String actorDeviceId,
  ) {
    final Participant? participant = session.participantFor(actorDeviceId);
    if (participant?.acknowledgedStepIndex == session.currentStepIndex) {
      return true;
    }
    for (final Activity activity in session.activities.reversed) {
      if (activity.stepIndex == session.currentStepIndex &&
          activity.actorDeviceId == actorDeviceId &&
          activity.type == ActivityType.acknowledged) {
        return true;
      }
      if (activity.stepIndex == session.currentStepIndex &&
          (activity.type == ActivityType.started ||
              activity.type == ActivityType.advanced ||
              activity.type == ActivityType.autoAdvanced ||
              activity.type == ActivityType.jumped)) {
        return false;
      }
    }
    return false;
  }

  static void _requireCommandActive(LiveSession session) {
    if (!session.isActive) {
      throw SessionCommandException(
        SessionCommandError.invalidState,
        'The session is ${session.status.name}, not active.',
      );
    }
  }

  static void _requireStatus(LiveSession session, LiveSessionStatus expected) {
    if (session.status != expected) {
      throw StateError(
        'Expected ${expected.name}; session is ${session.status.name}.',
      );
    }
  }

  static void _requireActive(LiveSession session) {
    if (!session.isActive) {
      throw StateError('The session is not active.');
    }
  }

  static void _requireNotEnded(LiveSession session) {
    if (session.status == LiveSessionStatus.ended) {
      throw StateError('The session has ended.');
    }
  }

  static void _requireActivityStep(
    LiveSession session,
    Activity activity, {
    required int expectedIndex,
  }) {
    if (expectedIndex < 0 ||
        expectedIndex >= session.planSnapshot.steps.length ||
        activity.stepIndex != expectedIndex ||
        activity.stepId != session.planSnapshot.steps[expectedIndex].id) {
      throw StateError('The activity references an unexpected step.');
    }
  }

  static int _requiredPayloadInt(Activity activity, String key) {
    final Object? value = activity.payload[key];
    if (value is! int) {
      throw StateError('Activity payload field "$key" must be an integer.');
    }
    return value;
  }

  static String _requiredPayloadString(Activity activity, String key) {
    final Object? value = activity.payload[key];
    if (value is! String || value.trim().isEmpty) {
      throw StateError(
        'Activity payload field "$key" must be a non-empty string.',
      );
    }
    return value;
  }

  static SessionRole _requiredPayloadRole(Activity activity, String key) {
    final String value = _requiredPayloadString(activity, key);
    for (final SessionRole role in SessionRole.values) {
      if (role.name == value) {
        return role;
      }
    }
    throw StateError('Unsupported session role: $value.');
  }

  static SessionEndReason _endReason(Activity activity) {
    final Object? value = activity.payload['reason'];
    if (value is! String) {
      throw StateError('An end activity must include a reason.');
    }
    for (final SessionEndReason reason in SessionEndReason.values) {
      if (reason.name == value) {
        return reason;
      }
    }
    throw StateError('Unsupported session end reason: $value.');
  }
}

List<Participant> _clearAcknowledgements(Iterable<Participant> participants) {
  return participants
      .map<Participant>(
        (Participant participant) => participant.copyWith(
          acknowledgedStepIndex: null,
          acknowledgedAt: null,
        ),
      )
      .toList(growable: false);
}
