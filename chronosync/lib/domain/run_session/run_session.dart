import 'package:equatable/equatable.dart';

/// The lifecycle of a locally hosted runbook session.
enum RunSessionStatus { lobby, running, completed, ended }

/// An immutable record of a host-authorized change to a [RunSession].
enum RunActivityType {
  started,
  advanced,
  autoAdvanced,
  acknowledged,
  completed,
  ended,
}

/// A local, host-authoritative execution of a runbook.
///
/// This entity deliberately has no Hive or transport dependency. It can be
/// persisted locally, sent over a nearby connection, or exported unchanged.
class RunSession extends Equatable {
  factory RunSession({
    required String id,
    required String runbookId,
    required String hostPeerId,
    required int stepCount,
    RunSessionStatus status = RunSessionStatus.lobby,
    int currentStepIndex = 0,
    DateTime? startedAt,
    DateTime? currentStepStartedAt,
    DateTime? completedAt,
    int revision = 0,
  }) {
    if (stepCount <= 0) {
      throw ArgumentError.value(
        stepCount,
        'stepCount',
        'A run session must contain at least one step.',
      );
    }
    if (currentStepIndex < 0 || currentStepIndex >= stepCount) {
      throw RangeError.range(
        currentStepIndex,
        0,
        stepCount - 1,
        'currentStepIndex',
      );
    }
    return RunSession._(
      id: id,
      runbookId: runbookId,
      hostPeerId: hostPeerId,
      stepCount: stepCount,
      status: status,
      currentStepIndex: currentStepIndex,
      startedAt: startedAt,
      currentStepStartedAt: currentStepStartedAt,
      completedAt: completedAt,
      revision: revision,
    );
  }

  const RunSession._({
    required this.id,
    required this.runbookId,
    required this.hostPeerId,
    required this.stepCount,
    required this.status,
    required this.currentStepIndex,
    required this.startedAt,
    required this.currentStepStartedAt,
    required this.completedAt,
    required this.revision,
  });

  final String id;
  final String runbookId;
  final String hostPeerId;
  final int stepCount;
  final RunSessionStatus status;
  final int currentStepIndex;
  final DateTime? startedAt;
  final DateTime? currentStepStartedAt;
  final DateTime? completedAt;
  final int revision;

  bool get isLive => status == RunSessionStatus.running;

  /// Returns elapsed time for the current step using a synchronized host clock.
  ///
  /// Redraw ticks must call this function; they must not increment a counter.
  Duration elapsedAt(DateTime now) {
    final DateTime? stepStartedAt = currentStepStartedAt;
    if (!isLive || stepStartedAt == null) {
      return Duration.zero;
    }

    final Duration elapsed = now.toUtc().difference(stepStartedAt.toUtc());
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration totalElapsedAt(DateTime now) {
    final DateTime? sessionStartedAt = startedAt;
    if (sessionStartedAt == null) {
      return Duration.zero;
    }

    final DateTime end = completedAt ?? now;
    final Duration elapsed = end.toUtc().difference(sessionStartedAt.toUtc());
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  RunSession copyWith({
    RunSessionStatus? status,
    int? currentStepIndex,
    DateTime? startedAt,
    DateTime? currentStepStartedAt,
    DateTime? completedAt,
    int? revision,
  }) {
    return RunSession(
      id: id,
      runbookId: runbookId,
      hostPeerId: hostPeerId,
      stepCount: stepCount,
      status: status ?? this.status,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      startedAt: startedAt ?? this.startedAt,
      currentStepStartedAt: currentStepStartedAt ?? this.currentStepStartedAt,
      completedAt: completedAt ?? this.completedAt,
      revision: revision ?? this.revision,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'runbookId': runbookId,
      'hostPeerId': hostPeerId,
      'stepCount': stepCount,
      'status': status.name,
      'currentStepIndex': currentStepIndex,
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'currentStepStartedAt': currentStepStartedAt?.toUtc().toIso8601String(),
      'completedAt': completedAt?.toUtc().toIso8601String(),
      'revision': revision,
    };
  }

  factory RunSession.fromJson(Map<String, Object?> json) {
    return RunSession(
      id: json['id']! as String,
      runbookId: json['runbookId']! as String,
      hostPeerId: json['hostPeerId']! as String,
      stepCount: json['stepCount']! as int,
      status: RunSessionStatus.values.byName(json['status']! as String),
      currentStepIndex: json['currentStepIndex']! as int,
      startedAt: _dateTimeFromJson(json['startedAt']),
      currentStepStartedAt: _dateTimeFromJson(json['currentStepStartedAt']),
      completedAt: _dateTimeFromJson(json['completedAt']),
      revision: json['revision']! as int,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    runbookId,
    hostPeerId,
    stepCount,
    status,
    currentStepIndex,
    startedAt,
    currentStepStartedAt,
    completedAt,
    revision,
  ];
}

/// A revisioned action that a host broadcasts to nearby participants.
class RunActivity extends Equatable {
  const RunActivity({
    required this.id,
    required this.sessionId,
    required this.revision,
    required this.type,
    required this.stepIndex,
    required this.actorPeerId,
    required this.occurredAt,
  });

  final String id;
  final String sessionId;
  final int revision;
  final RunActivityType type;
  final int stepIndex;
  final String actorPeerId;
  final DateTime occurredAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'sessionId': sessionId,
      'revision': revision,
      'type': type.name,
      'stepIndex': stepIndex,
      'actorPeerId': actorPeerId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
  }

  factory RunActivity.fromJson(Map<String, Object?> json) {
    return RunActivity(
      id: json['id']! as String,
      sessionId: json['sessionId']! as String,
      revision: json['revision']! as int,
      type: RunActivityType.values.byName(json['type']! as String),
      stepIndex: json['stepIndex']! as int,
      actorPeerId: json['actorPeerId']! as String,
      occurredAt: DateTime.parse(json['occurredAt']! as String).toUtc(),
    );
  }

  @override
  List<Object> get props => <Object>[
    id,
    sessionId,
    revision,
    type,
    stepIndex,
    actorPeerId,
    occurredAt,
  ];
}

/// The result of a host command. The activity is persisted and broadcast after
/// its [session] has been persisted locally.
class RunSessionTransition {
  const RunSessionTransition({required this.session, required this.activity});

  final RunSession session;
  final RunActivity activity;
}

/// Applies the same revisioned state machine on the host and every participant.
///
/// Only a host creates activities. Participants use [applyActivity] for
/// validated host messages and send acknowledgement *requests* to the host.
class RunSessionReducer {
  const RunSessionReducer._();

  static RunSessionTransition start({
    required RunSession session,
    required String activityId,
    required DateTime occurredAt,
  }) {
    return _transition(
      session: session,
      activityId: activityId,
      type: RunActivityType.started,
      stepIndex: 0,
      actorPeerId: session.hostPeerId,
      occurredAt: occurredAt,
    );
  }

  static RunSessionTransition advance({
    required RunSession session,
    required String activityId,
    required DateTime occurredAt,
    bool automatically = false,
  }) {
    _requireRunning(session);

    final bool isFinalStep = session.currentStepIndex == session.stepCount - 1;
    return _transition(
      session: session,
      activityId: activityId,
      type: isFinalStep
          ? RunActivityType.completed
          : automatically
          ? RunActivityType.autoAdvanced
          : RunActivityType.advanced,
      stepIndex: isFinalStep
          ? session.currentStepIndex
          : session.currentStepIndex + 1,
      actorPeerId: session.hostPeerId,
      occurredAt: occurredAt,
    );
  }

  static RunSessionTransition acknowledge({
    required RunSession session,
    required String activityId,
    required String actorPeerId,
    required DateTime occurredAt,
  }) {
    _requireRunning(session);
    return _transition(
      session: session,
      activityId: activityId,
      type: RunActivityType.acknowledged,
      stepIndex: session.currentStepIndex,
      actorPeerId: actorPeerId,
      occurredAt: occurredAt,
    );
  }

  static RunSessionTransition end({
    required RunSession session,
    required String activityId,
    required DateTime occurredAt,
  }) {
    if (!session.isLive && session.status != RunSessionStatus.lobby) {
      throw StateError('Only a live or lobby session can be ended.');
    }

    return _transition(
      session: session,
      activityId: activityId,
      type: RunActivityType.ended,
      stepIndex: session.currentStepIndex,
      actorPeerId: session.hostPeerId,
      occurredAt: occurredAt,
    );
  }

  /// Applies exactly one host-issued activity to a local session copy.
  static RunSession applyActivity({
    required RunSession session,
    required RunActivity activity,
  }) {
    if (activity.sessionId != session.id) {
      throw StateError('Activity does not belong to this session.');
    }
    if (activity.revision != session.revision + 1) {
      throw StateError('Activity revision is not consecutive.');
    }
    if (activity.stepIndex < 0 || activity.stepIndex >= session.stepCount) {
      throw StateError('Activity step index is outside the runbook.');
    }

    switch (activity.type) {
      case RunActivityType.started:
        if (session.status != RunSessionStatus.lobby ||
            activity.stepIndex != 0) {
          throw StateError('Only a lobby session can be started at step zero.');
        }
        return session.copyWith(
          status: RunSessionStatus.running,
          currentStepIndex: 0,
          startedAt: activity.occurredAt,
          currentStepStartedAt: activity.occurredAt,
          revision: activity.revision,
        );
      case RunActivityType.advanced:
      case RunActivityType.autoAdvanced:
        _requireRunning(session);
        if (activity.stepIndex != session.currentStepIndex + 1) {
          throw StateError('An advance must move to the next step.');
        }
        return session.copyWith(
          currentStepIndex: activity.stepIndex,
          currentStepStartedAt: activity.occurredAt,
          revision: activity.revision,
        );
      case RunActivityType.acknowledged:
        _requireRunning(session);
        if (activity.stepIndex != session.currentStepIndex) {
          throw StateError('An acknowledgement must target the current step.');
        }
        return session.copyWith(revision: activity.revision);
      case RunActivityType.completed:
        _requireRunning(session);
        if (activity.stepIndex != session.currentStepIndex ||
            activity.stepIndex != session.stepCount - 1) {
          throw StateError(
            'Only the final current step can complete a session.',
          );
        }
        return session.copyWith(
          status: RunSessionStatus.completed,
          completedAt: activity.occurredAt,
          revision: activity.revision,
        );
      case RunActivityType.ended:
        if (!session.isLive && session.status != RunSessionStatus.lobby) {
          throw StateError('Only a live or lobby session can be ended.');
        }
        if (activity.stepIndex != session.currentStepIndex) {
          throw StateError('An end activity must reference the current step.');
        }
        return session.copyWith(
          status: RunSessionStatus.ended,
          completedAt: activity.occurredAt,
          revision: activity.revision,
        );
    }
  }

  static RunSessionTransition _transition({
    required RunSession session,
    required String activityId,
    required RunActivityType type,
    required int stepIndex,
    required String actorPeerId,
    required DateTime occurredAt,
  }) {
    final RunActivity activity = RunActivity(
      id: activityId,
      sessionId: session.id,
      revision: session.revision + 1,
      type: type,
      stepIndex: stepIndex,
      actorPeerId: actorPeerId,
      occurredAt: occurredAt.toUtc(),
    );
    return RunSessionTransition(
      session: applyActivity(session: session, activity: activity),
      activity: activity,
    );
  }

  static void _requireRunning(RunSession session) {
    if (!session.isLive) {
      throw StateError('The session is not running.');
    }
  }
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
