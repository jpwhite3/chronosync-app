import 'dart:collection';

import 'package:chronosync/core/serialization/utc_timestamp.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:equatable/equatable.dart';

/// The current JSON contract for live-session entities.
const int liveSessionSchemaVersion = 1;
const int maxSessionDeviceIdLength = 128;
const int maxParticipantDisplayNameLength = 48;
const int maxConnectedSessionParticipants = 50;
const int maxSessionParticipants = 250;

enum SessionRole { host, controller, participant, display }

enum LiveSessionStatus { waiting, running, paused, ended }

enum SessionEndReason { completed, endedByHost }

enum ParticipantConnectionState { connected, stale, disconnected }

enum ActivityType {
  participantJoined,
  roleChanged,
  participantDisconnected,
  started,
  paused,
  resumed,
  advanced,
  autoAdvanced,
  remainingAdjusted,
  jumped,
  acknowledged,
  ended,
}

/// An ephemeral person or display connected to a live session.
class Participant extends Equatable {
  factory Participant({
    required String deviceId,
    required String displayName,
    required SessionRole role,
    required DateTime joinedAt,
    int lastSeenRevision = 0,
    ParticipantConnectionState connectionState =
        ParticipantConnectionState.connected,
    int? acknowledgedStepIndex,
    DateTime? acknowledgedAt,
  }) {
    final String normalizedDeviceId = deviceId.trim();
    final String normalizedDisplayName = displayName.trim();
    if (normalizedDeviceId.isEmpty ||
        normalizedDeviceId.length > maxSessionDeviceIdLength) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'A participant device ID must be 1–$maxSessionDeviceIdLength '
            'characters.',
      );
    }
    if (normalizedDisplayName.isEmpty ||
        normalizedDisplayName.length > maxParticipantDisplayNameLength) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'A participant display name must be '
            '1–$maxParticipantDisplayNameLength characters.',
      );
    }
    if (lastSeenRevision < 0) {
      throw ArgumentError.value(
        lastSeenRevision,
        'lastSeenRevision',
        'A participant revision cannot be negative.',
      );
    }
    if ((acknowledgedStepIndex == null) != (acknowledgedAt == null) ||
        (acknowledgedStepIndex != null && acknowledgedStepIndex < 0)) {
      throw ArgumentError(
        'An acknowledgement requires a non-negative step index and timestamp.',
      );
    }

    return Participant._(
      deviceId: normalizedDeviceId,
      displayName: normalizedDisplayName,
      role: role,
      joinedAt: joinedAt.toUtc(),
      lastSeenRevision: lastSeenRevision,
      connectionState: connectionState,
      acknowledgedStepIndex: acknowledgedStepIndex,
      acknowledgedAt: acknowledgedAt?.toUtc(),
    );
  }

  const Participant._({
    required this.deviceId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    required this.lastSeenRevision,
    required this.connectionState,
    required this.acknowledgedStepIndex,
    required this.acknowledgedAt,
  });

  final String deviceId;
  final String displayName;
  final SessionRole role;
  final DateTime joinedAt;
  final int lastSeenRevision;
  final ParticipantConnectionState connectionState;
  final int? acknowledgedStepIndex;
  final DateTime? acknowledgedAt;

  Participant copyWith({
    String? displayName,
    SessionRole? role,
    int? lastSeenRevision,
    ParticipantConnectionState? connectionState,
    Object? acknowledgedStepIndex = _unset,
    Object? acknowledgedAt = _unset,
  }) {
    return Participant(
      deviceId: deviceId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      joinedAt: joinedAt,
      lastSeenRevision: lastSeenRevision ?? this.lastSeenRevision,
      connectionState: connectionState ?? this.connectionState,
      acknowledgedStepIndex: identical(acknowledgedStepIndex, _unset)
          ? this.acknowledgedStepIndex
          : acknowledgedStepIndex as int?,
      acknowledgedAt: identical(acknowledgedAt, _unset)
          ? this.acknowledgedAt
          : acknowledgedAt as DateTime?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': liveSessionSchemaVersion,
      'deviceId': deviceId,
      'displayName': displayName,
      'role': role.name,
      'joinedAt': joinedAt.toIso8601String(),
      'lastSeenRevision': lastSeenRevision,
      'connectionState': connectionState.name,
      'acknowledgedStepIndex': acknowledgedStepIndex,
      'acknowledgedAt': acknowledgedAt?.toIso8601String(),
    };
  }

  factory Participant.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'participant');
    return Participant(
      deviceId: _requiredString(json, 'deviceId'),
      displayName: _requiredString(json, 'displayName'),
      role: _enumByName(
        SessionRole.values,
        _requiredString(json, 'role'),
        'role',
      ),
      joinedAt: _requiredDateTime(json, 'joinedAt'),
      lastSeenRevision: _requiredInt(json, 'lastSeenRevision'),
      connectionState: _enumByName(
        ParticipantConnectionState.values,
        _requiredString(json, 'connectionState'),
        'connectionState',
      ),
      acknowledgedStepIndex: _optionalInt(
        json['acknowledgedStepIndex'],
        'acknowledgedStepIndex',
      ),
      acknowledgedAt: _optionalDateTime(
        json['acknowledgedAt'],
        'acknowledgedAt',
      ),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    deviceId,
    displayName,
    role,
    joinedAt,
    lastSeenRevision,
    connectionState,
    acknowledgedStepIndex,
    acknowledgedAt,
  ];
}

/// A revisioned, host-authorized record in the complete session history.
class Activity extends Equatable {
  factory Activity({
    required String id,
    required String commandId,
    required String sessionId,
    required int revision,
    required ActivityType type,
    required String actorDeviceId,
    required SessionRole actorRole,
    required DateTime occurredAt,
    String? actorDisplayName,
    int? stepIndex,
    String? stepId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    final String normalizedId = id.trim();
    final String normalizedCommandId = commandId.trim();
    final String normalizedSessionId = sessionId.trim();
    final String normalizedActorDeviceId = actorDeviceId.trim();
    final String? normalizedActorDisplayName = actorDisplayName?.trim();
    if (normalizedId.isEmpty ||
        normalizedCommandId.isEmpty ||
        normalizedSessionId.isEmpty ||
        normalizedActorDeviceId.isEmpty) {
      throw ArgumentError(
        'Activity IDs, command ID, session ID, and actor ID cannot be empty.',
      );
    }
    if (normalizedId.length > maxSessionDeviceIdLength ||
        normalizedCommandId.length > maxSessionDeviceIdLength ||
        normalizedSessionId.length > maxSessionDeviceIdLength ||
        normalizedActorDeviceId.length > maxSessionDeviceIdLength) {
      throw ArgumentError(
        'Activity identifiers cannot exceed $maxSessionDeviceIdLength '
        'characters.',
      );
    }
    if (revision <= 0) {
      throw ArgumentError.value(
        revision,
        'revision',
        'An activity revision must be positive.',
      );
    }
    if (stepIndex != null && stepIndex < 0) {
      throw ArgumentError.value(
        stepIndex,
        'stepIndex',
        'An activity step index cannot be negative.',
      );
    }
    if (stepId != null && stepId.trim().isEmpty) {
      throw ArgumentError.value(
        stepId,
        'stepId',
        'An activity step ID cannot be empty.',
      );
    }
    if (normalizedActorDisplayName != null &&
        (normalizedActorDisplayName.isEmpty ||
            normalizedActorDisplayName.length >
                maxParticipantDisplayNameLength)) {
      throw ArgumentError.value(
        actorDisplayName,
        'actorDisplayName',
        'An activity actor name must be '
            '1–$maxParticipantDisplayNameLength characters.',
      );
    }

    return Activity._(
      id: normalizedId,
      commandId: normalizedCommandId,
      sessionId: normalizedSessionId,
      revision: revision,
      type: type,
      stepIndex: stepIndex,
      stepId: stepId?.trim(),
      actorDeviceId: normalizedActorDeviceId,
      actorDisplayName: normalizedActorDisplayName,
      actorRole: actorRole,
      occurredAt: occurredAt.toUtc(),
      payload: _immutableJsonMap(payload),
    );
  }

  const Activity._({
    required this.id,
    required this.commandId,
    required this.sessionId,
    required this.revision,
    required this.type,
    required this.stepIndex,
    required this.stepId,
    required this.actorDeviceId,
    required this.actorDisplayName,
    required this.actorRole,
    required this.occurredAt,
    required this.payload,
  });

  final String id;
  final String commandId;
  final String sessionId;
  final int revision;
  final ActivityType type;
  final int? stepIndex;
  final String? stepId;
  final String actorDeviceId;
  final String? actorDisplayName;
  final SessionRole actorRole;
  final DateTime occurredAt;
  final Map<String, Object?> payload;

  Activity withActorDisplayName(String displayName) {
    return Activity(
      id: id,
      commandId: commandId,
      sessionId: sessionId,
      revision: revision,
      type: type,
      stepIndex: stepIndex,
      stepId: stepId,
      actorDeviceId: actorDeviceId,
      actorDisplayName: displayName,
      actorRole: actorRole,
      occurredAt: occurredAt,
      payload: payload,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': liveSessionSchemaVersion,
      'id': id,
      'commandId': commandId,
      'sessionId': sessionId,
      'revision': revision,
      'type': type.name,
      'stepIndex': stepIndex,
      'stepId': stepId,
      'actorDeviceId': actorDeviceId,
      'actorDisplayName': actorDisplayName,
      'actorRole': actorRole.name,
      'occurredAt': occurredAt.toIso8601String(),
      'payload': _mutableJsonCopy(payload),
    };
  }

  factory Activity.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'activity');
    return Activity(
      id: _requiredString(json, 'id'),
      commandId: _requiredString(json, 'commandId'),
      sessionId: _requiredString(json, 'sessionId'),
      revision: _requiredInt(json, 'revision'),
      type: _enumByName(
        ActivityType.values,
        _requiredString(json, 'type'),
        'type',
      ),
      stepIndex: _optionalInt(json['stepIndex'], 'stepIndex'),
      stepId: _optionalString(json['stepId'], 'stepId'),
      actorDeviceId: _requiredString(json, 'actorDeviceId'),
      actorDisplayName: _optionalString(
        json['actorDisplayName'],
        'actorDisplayName',
      ),
      actorRole: _enumByName(
        SessionRole.values,
        _requiredString(json, 'actorRole'),
        'actorRole',
      ),
      occurredAt: _requiredDateTime(json, 'occurredAt'),
      payload: _jsonMap(json['payload'], 'payload'),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    commandId,
    sessionId,
    revision,
    type,
    stepIndex,
    stepId,
    actorDeviceId,
    actorDisplayName,
    actorRole,
    occurredAt,
    payload,
  ];
}

/// The immutable, replayable state of a shared run.
class LiveSession extends Equatable {
  factory LiveSession({
    required String id,
    required PlanSnapshot planSnapshot,
    required String hostDeviceId,
    LiveSessionStatus status = LiveSessionStatus.waiting,
    int currentStepIndex = 0,
    int revision = 0,
    int activityRevisionOffset = 0,
    DateTime? startedAt,
    DateTime? currentStepStartedAt,
    DateTime? pausedAt,
    Duration currentStepPausedDuration = Duration.zero,
    Duration totalPausedDuration = Duration.zero,
    int remainingAdjustmentSeconds = 0,
    DateTime? endedAt,
    SessionEndReason? endReason,
    Iterable<Participant> participants = const <Participant>[],
    Iterable<Activity> activities = const <Activity>[],
  }) {
    return LiveSession._validated(
      id: id,
      planSnapshot: planSnapshot,
      hostDeviceId: hostDeviceId,
      status: status,
      currentStepIndex: currentStepIndex,
      revision: revision,
      activityRevisionOffset: activityRevisionOffset,
      startedAt: startedAt,
      currentStepStartedAt: currentStepStartedAt,
      pausedAt: pausedAt,
      currentStepPausedDuration: currentStepPausedDuration,
      totalPausedDuration: totalPausedDuration,
      remainingAdjustmentSeconds: remainingAdjustmentSeconds,
      endedAt: endedAt,
      endReason: endReason,
      participants: participants,
      activities: activities,
    );
  }

  factory LiveSession._validated({
    required String id,
    required PlanSnapshot planSnapshot,
    required String hostDeviceId,
    required LiveSessionStatus status,
    required int currentStepIndex,
    required int revision,
    required int activityRevisionOffset,
    required DateTime? startedAt,
    required DateTime? currentStepStartedAt,
    required DateTime? pausedAt,
    required Duration currentStepPausedDuration,
    required Duration totalPausedDuration,
    required int remainingAdjustmentSeconds,
    required DateTime? endedAt,
    required SessionEndReason? endReason,
    required Iterable<Participant> participants,
    required Iterable<Activity> activities,
    _ActivityHistoryView? trustedActivityView,
  }) {
    final String normalizedId = id.trim();
    final String normalizedHostDeviceId = hostDeviceId.trim();
    if (normalizedId.isEmpty ||
        normalizedId.length > maxSessionDeviceIdLength) {
      throw ArgumentError.value(id, 'id', 'A session ID cannot be empty.');
    }
    if (normalizedHostDeviceId.isEmpty ||
        normalizedHostDeviceId.length > maxSessionDeviceIdLength) {
      throw ArgumentError.value(
        hostDeviceId,
        'hostDeviceId',
        'A host device ID must be 1–$maxSessionDeviceIdLength characters.',
      );
    }
    if (currentStepIndex < 0 || currentStepIndex >= planSnapshot.steps.length) {
      throw RangeError.range(
        currentStepIndex,
        0,
        planSnapshot.steps.length - 1,
        'currentStepIndex',
      );
    }
    if (revision < 0) {
      throw ArgumentError.value(
        revision,
        'revision',
        'A session revision cannot be negative.',
      );
    }
    if (activityRevisionOffset < 0 || activityRevisionOffset > revision) {
      throw ArgumentError.value(
        activityRevisionOffset,
        'activityRevisionOffset',
        'An activity-history offset must be within the session revision.',
      );
    }
    if (currentStepPausedDuration.isNegative ||
        totalPausedDuration.isNegative ||
        totalPausedDuration < currentStepPausedDuration) {
      throw ArgumentError(
        'Pause durations must be non-negative and internally consistent.',
      );
    }
    final int adjustedDurationSeconds =
        planSnapshot.steps[currentStepIndex].durationSeconds +
        remainingAdjustmentSeconds;
    if (adjustedDurationSeconds <= 0 ||
        adjustedDurationSeconds > maxStepDurationSeconds) {
      throw ArgumentError.value(
        remainingAdjustmentSeconds,
        'remainingAdjustmentSeconds',
        'An adjustment must leave the step between 1 and '
            '$maxStepDurationSeconds seconds.',
      );
    }

    final List<Participant> immutableParticipants =
        List<Participant>.unmodifiable(participants);
    _validateParticipants(immutableParticipants);
    final _ActivityHistoryView immutableActivities;
    if (trustedActivityView == null) {
      final List<Activity> activityValues = List<Activity>.of(
        activities,
        growable: false,
      );
      _validateActivities(
        activityValues,
        sessionId: normalizedId,
        revision: revision,
        revisionOffset: activityRevisionOffset,
        planSnapshot: planSnapshot,
      );
      immutableActivities = _ActivityHistoryStorage.fromValidated(
        activityValues,
      ).fullView;
    } else {
      _validateTrustedActivityWindow(
        trustedActivityView,
        revision: revision,
        revisionOffset: activityRevisionOffset,
      );
      immutableActivities = trustedActivityView;
    }

    final DateTime? startedAtUtc = startedAt?.toUtc();
    final DateTime? stepStartedAtUtc = currentStepStartedAt?.toUtc();
    final DateTime? pausedAtUtc = pausedAt?.toUtc();
    final DateTime? endedAtUtc = endedAt?.toUtc();
    _validateStatusTimestamps(
      status: status,
      startedAt: startedAtUtc,
      currentStepStartedAt: stepStartedAtUtc,
      pausedAt: pausedAtUtc,
      endedAt: endedAtUtc,
      endReason: endReason,
    );
    _validatePauseDurations(
      status: status,
      startedAt: startedAtUtc,
      currentStepStartedAt: stepStartedAtUtc,
      pausedAt: pausedAtUtc,
      endedAt: endedAtUtc,
      lastActivityAt: immutableActivities.isEmpty
          ? null
          : immutableActivities.last.occurredAt,
      currentStepPausedDuration: currentStepPausedDuration,
      totalPausedDuration: totalPausedDuration,
    );

    return LiveSession._(
      id: normalizedId,
      planSnapshot: planSnapshot,
      hostDeviceId: normalizedHostDeviceId,
      status: status,
      currentStepIndex: currentStepIndex,
      revision: revision,
      activityRevisionOffset: activityRevisionOffset,
      startedAt: startedAtUtc,
      currentStepStartedAt: stepStartedAtUtc,
      pausedAt: pausedAtUtc,
      currentStepPausedDuration: currentStepPausedDuration,
      totalPausedDuration: totalPausedDuration,
      remainingAdjustmentSeconds: remainingAdjustmentSeconds,
      endedAt: endedAtUtc,
      endReason: endReason,
      participants: immutableParticipants,
      activities: immutableActivities,
      activityHistoryStorage: immutableActivities._storage,
    );
  }

  const LiveSession._({
    required this.id,
    required this.planSnapshot,
    required this.hostDeviceId,
    required this.status,
    required this.currentStepIndex,
    required this.revision,
    required this.activityRevisionOffset,
    required this.startedAt,
    required this.currentStepStartedAt,
    required this.pausedAt,
    required this.currentStepPausedDuration,
    required this.totalPausedDuration,
    required this.remainingAdjustmentSeconds,
    required this.endedAt,
    required this.endReason,
    required this.participants,
    required this.activities,
    required _ActivityHistoryStorage activityHistoryStorage,
  }) : _activityHistoryStorage = activityHistoryStorage;

  final String id;
  final PlanSnapshot planSnapshot;
  final String hostDeviceId;
  final LiveSessionStatus status;
  final int currentStepIndex;
  final int revision;

  /// Number of earlier activities omitted from a compact replica snapshot.
  ///
  /// Authoritative hosts and exported histories always use zero.
  final int activityRevisionOffset;
  final DateTime? startedAt;
  final DateTime? currentStepStartedAt;
  final DateTime? pausedAt;
  final Duration currentStepPausedDuration;
  final Duration totalPausedDuration;
  final int remainingAdjustmentSeconds;
  final DateTime? endedAt;
  final SessionEndReason? endReason;
  final List<Participant> participants;
  final List<Activity> activities;
  final _ActivityHistoryStorage _activityHistoryStorage;

  Step get currentStep => planSnapshot.steps[currentStepIndex];

  Step? get nextStep => currentStepIndex + 1 < planSnapshot.steps.length
      ? planSnapshot.steps[currentStepIndex + 1]
      : null;

  bool get isActive =>
      status == LiveSessionStatus.running || status == LiveSessionStatus.paused;

  Duration get adjustedCurrentStepDuration => Duration(
    seconds: currentStep.durationSeconds + remainingAdjustmentSeconds,
  );

  bool hasProcessedCommand(String commandId) {
    return _activityHistoryStorage.containsCommandWithin(
      commandId,
      activities.length,
    );
  }

  /// Reports structural sharing for deterministic performance tests.
  ///
  /// Product code must not depend on the backing-storage implementation.
  bool debugSharesActivityStorageWith(LiveSession other) {
    return identical(_activityHistoryStorage, other._activityHistoryStorage);
  }

  /// Number of indexed activity reads performed in checked builds.
  ///
  /// This counter exists only for deterministic algorithmic-complexity tests.
  int get debugActivityReadCount => _activityHistoryStorage._debugReadCount;

  bool get hasCompleteActivityHistory => activityRevisionOffset == 0;

  Participant? participantFor(String deviceId) {
    for (final Participant participant in participants) {
      if (participant.deviceId == deviceId) {
        return participant;
      }
    }
    return null;
  }

  /// Active time on the current step; redraws derive it from timestamps.
  Duration elapsedAt(DateTime now) {
    final DateTime? stepStartedAt = currentStepStartedAt;
    if (stepStartedAt == null) {
      return Duration.zero;
    }

    final DateTime effectiveNow = status == LiveSessionStatus.paused
        ? pausedAt!
        : status == LiveSessionStatus.ended
        ? endedAt!
        : now.toUtc();
    final Duration elapsed =
        effectiveNow.difference(stepStartedAt) - currentStepPausedDuration;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration remainingAt(DateTime now) {
    return adjustedCurrentStepDuration - elapsedAt(now);
  }

  /// Wall-clock session duration. Pause time intentionally remains included.
  Duration totalElapsedAt(DateTime now) {
    final DateTime? actualStart = startedAt;
    if (actualStart == null) {
      return Duration.zero;
    }
    final DateTime effectiveEnd = endedAt ?? now.toUtc();
    final Duration elapsed = effectiveEnd.difference(actualStart);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Positive is behind the original plan; negative is ahead.
  ///
  /// The planned schedule never shifts for pauses or remaining-time
  /// adjustments, so both naturally appear as variance.
  Duration scheduleVarianceAt(DateTime now) {
    final DateTime? actualStart = startedAt;
    if (actualStart == null) {
      return Duration.zero;
    }

    final DateTime baseline = planSnapshot.plannedStartTime ?? actualStart;
    final DateTime effectiveNow = endedAt ?? now.toUtc();
    final Duration wallFromBaseline = effectiveNow.difference(baseline);
    final Duration activeOnStep = elapsedAt(now);
    final Duration cappedActiveOnStep = activeOnStep > currentStep.duration
        ? currentStep.duration
        : activeOnStep;
    final Duration plannedProgress =
        planSnapshot.plannedOffsetForStep(currentStepIndex) +
        cappedActiveOnStep;
    return wallFromBaseline - plannedProgress;
  }

  LiveSession copyWith({
    LiveSessionStatus? status,
    int? currentStepIndex,
    int? revision,
    int? activityRevisionOffset,
    Object? startedAt = _unset,
    Object? currentStepStartedAt = _unset,
    Object? pausedAt = _unset,
    Duration? currentStepPausedDuration,
    Duration? totalPausedDuration,
    int? remainingAdjustmentSeconds,
    Object? endedAt = _unset,
    Object? endReason = _unset,
    Iterable<Participant>? participants,
    Iterable<Activity>? activities,
    Activity? appendedActivity,
  }) {
    if (activities != null && appendedActivity != null) {
      throw ArgumentError(
        'Replace activities or append one activity, but do not do both.',
      );
    }
    if (activities != null) {
      return LiveSession._validated(
        id: id,
        planSnapshot: planSnapshot,
        hostDeviceId: hostDeviceId,
        status: status ?? this.status,
        currentStepIndex: currentStepIndex ?? this.currentStepIndex,
        revision: revision ?? this.revision,
        activityRevisionOffset:
            activityRevisionOffset ?? this.activityRevisionOffset,
        startedAt: identical(startedAt, _unset)
            ? this.startedAt
            : startedAt as DateTime?,
        currentStepStartedAt: identical(currentStepStartedAt, _unset)
            ? this.currentStepStartedAt
            : currentStepStartedAt as DateTime?,
        pausedAt: identical(pausedAt, _unset)
            ? this.pausedAt
            : pausedAt as DateTime?,
        currentStepPausedDuration:
            currentStepPausedDuration ?? this.currentStepPausedDuration,
        totalPausedDuration: totalPausedDuration ?? this.totalPausedDuration,
        remainingAdjustmentSeconds:
            remainingAdjustmentSeconds ?? this.remainingAdjustmentSeconds,
        endedAt: identical(endedAt, _unset)
            ? this.endedAt
            : endedAt as DateTime?,
        endReason: identical(endReason, _unset)
            ? this.endReason
            : endReason as SessionEndReason?,
        participants: participants ?? this.participants,
        activities: activities,
      );
    }

    final _ActivityHistoryView currentActivityView =
        this.activities as _ActivityHistoryView;
    final _ActivityHistoryView nextActivityView;
    if (appendedActivity == null) {
      nextActivityView = currentActivityView;
    } else {
      _validateAppendedActivity(
        appendedActivity,
        sessionId: id,
        expectedRevision: this.revision + 1,
        planSnapshot: planSnapshot,
        activityView: currentActivityView,
      );
      nextActivityView = _activityHistoryStorage.append(
        currentActivityView,
        appendedActivity,
      );
    }

    return LiveSession._validated(
      id: id,
      planSnapshot: planSnapshot,
      hostDeviceId: hostDeviceId,
      status: status ?? this.status,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      revision: revision ?? this.revision,
      activityRevisionOffset:
          activityRevisionOffset ?? this.activityRevisionOffset,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      currentStepStartedAt: identical(currentStepStartedAt, _unset)
          ? this.currentStepStartedAt
          : currentStepStartedAt as DateTime?,
      pausedAt: identical(pausedAt, _unset)
          ? this.pausedAt
          : pausedAt as DateTime?,
      currentStepPausedDuration:
          currentStepPausedDuration ?? this.currentStepPausedDuration,
      totalPausedDuration: totalPausedDuration ?? this.totalPausedDuration,
      remainingAdjustmentSeconds:
          remainingAdjustmentSeconds ?? this.remainingAdjustmentSeconds,
      endedAt: identical(endedAt, _unset) ? this.endedAt : endedAt as DateTime?,
      endReason: identical(endReason, _unset)
          ? this.endReason
          : endReason as SessionEndReason?,
      participants: participants ?? this.participants,
      activities: const <Activity>[],
      trustedActivityView: nextActivityView,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': liveSessionSchemaVersion,
      'id': id,
      'planSnapshot': planSnapshot.toJson(),
      'hostDeviceId': hostDeviceId,
      'status': status.name,
      'currentStepIndex': currentStepIndex,
      'revision': revision,
      'activityRevisionOffset': activityRevisionOffset,
      'startedAt': startedAt?.toIso8601String(),
      'currentStepStartedAt': currentStepStartedAt?.toIso8601String(),
      'pausedAt': pausedAt?.toIso8601String(),
      'currentStepPausedMicroseconds': currentStepPausedDuration.inMicroseconds,
      'totalPausedMicroseconds': totalPausedDuration.inMicroseconds,
      'remainingAdjustmentSeconds': remainingAdjustmentSeconds,
      'endedAt': endedAt?.toIso8601String(),
      'endReason': endReason?.name,
      'participants': participants
          .map((Participant participant) => participant.toJson())
          .toList(growable: false),
      'activities': activities
          .map((Activity activity) => activity.toJson())
          .toList(growable: false),
    };
  }

  factory LiveSession.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'live session');
    return LiveSession(
      id: _requiredString(json, 'id'),
      planSnapshot: PlanSnapshot.fromJson(
        _jsonMap(json['planSnapshot'], 'planSnapshot'),
      ),
      hostDeviceId: _requiredString(json, 'hostDeviceId'),
      status: _enumByName(
        LiveSessionStatus.values,
        _requiredString(json, 'status'),
        'status',
      ),
      currentStepIndex: _requiredInt(json, 'currentStepIndex'),
      revision: _requiredInt(json, 'revision'),
      activityRevisionOffset:
          _optionalInt(
            json['activityRevisionOffset'],
            'activityRevisionOffset',
          ) ??
          0,
      startedAt: _optionalDateTime(json['startedAt'], 'startedAt'),
      currentStepStartedAt: _optionalDateTime(
        json['currentStepStartedAt'],
        'currentStepStartedAt',
      ),
      pausedAt: _optionalDateTime(json['pausedAt'], 'pausedAt'),
      currentStepPausedDuration: Duration(
        microseconds: _requiredInt(json, 'currentStepPausedMicroseconds'),
      ),
      totalPausedDuration: Duration(
        microseconds: _requiredInt(json, 'totalPausedMicroseconds'),
      ),
      remainingAdjustmentSeconds: _requiredInt(
        json,
        'remainingAdjustmentSeconds',
      ),
      endedAt: _optionalDateTime(json['endedAt'], 'endedAt'),
      endReason: _optionalEnumByName(
        SessionEndReason.values,
        _optionalString(json['endReason'], 'endReason'),
        'endReason',
      ),
      participants: _jsonList(json['participants'], 'participants')
          .map<Participant>(
            (Object? value) =>
                Participant.fromJson(_jsonMap(value, 'participant')),
          ),
      activities: _jsonList(json['activities'], 'activities').map<Activity>(
        (Object? value) => Activity.fromJson(_jsonMap(value, 'activity')),
      ),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    planSnapshot,
    hostDeviceId,
    status,
    currentStepIndex,
    revision,
    activityRevisionOffset,
    startedAt,
    currentStepStartedAt,
    pausedAt,
    currentStepPausedDuration,
    totalPausedDuration,
    remainingAdjustmentSeconds,
    endedAt,
    endReason,
    participants,
    activities,
  ];
}

const Object _unset = Object();

/// Append-only backing storage shared by successive immutable session views.
///
/// A view captures a fixed visible length, so adding a value never changes the
/// public history of an older [LiveSession]. Applying an activity to an older
/// branch forks the visible prefix instead of mutating the newer branch.
final class _ActivityHistoryStorage {
  _ActivityHistoryStorage.fromValidated(Iterable<Activity> activities)
    : _activities = List<Activity>.of(activities),
      _activityIndexes = <String, int>{},
      _commandIndexes = <String, int>{} {
    for (int index = 0; index < _activities.length; index += 1) {
      final Activity activity = _activities[index];
      _activityIndexes[activity.id] = index;
      _commandIndexes[activity.commandId] = index;
    }
  }

  final List<Activity> _activities;
  final Map<String, int> _activityIndexes;
  final Map<String, int> _commandIndexes;
  int _debugReadCount = 0;

  _ActivityHistoryView get fullView =>
      _ActivityHistoryView._(this, _activities.length);

  bool containsActivityWithin(String id, int visibleLength) {
    final int? index = _activityIndexes[id];
    return index != null && index < visibleLength;
  }

  bool containsCommandWithin(String id, int visibleLength) {
    final int? index = _commandIndexes[id];
    return index != null && index < visibleLength;
  }

  _ActivityHistoryView append(_ActivityHistoryView base, Activity activity) {
    if (!identical(base._storage, this)) {
      throw StateError('The activity view belongs to different storage.');
    }
    if (base.length < _activities.length) {
      final _ActivityHistoryStorage fork =
          _ActivityHistoryStorage.fromValidated(_activities.take(base.length));
      return fork.append(fork.fullView, activity);
    }

    final int index = _activities.length;
    _activities.add(activity);
    _activityIndexes[activity.id] = index;
    _commandIndexes[activity.commandId] = index;
    return fullView;
  }
}

/// A fixed-length, unmodifiable prefix of append-only activity storage.
final class _ActivityHistoryView extends UnmodifiableListView<Activity> {
  _ActivityHistoryView._(this._storage, int visibleLength)
    : super(_ActivityHistoryPrefix(_storage, visibleLength));

  final _ActivityHistoryStorage _storage;
}

/// Read-only list primitive wrapped by [_ActivityHistoryView].
final class _ActivityHistoryPrefix extends ListBase<Activity> {
  _ActivityHistoryPrefix(this._storage, this._visibleLength);

  final _ActivityHistoryStorage _storage;
  final int _visibleLength;

  @override
  int get length => _visibleLength;

  @override
  set length(int value) {
    throw UnsupportedError('Activity history is immutable.');
  }

  @override
  Activity operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _visibleLength);
    assert(() {
      _storage._debugReadCount += 1;
      return true;
    }());
    return _storage._activities[index];
  }

  @override
  void operator []=(int index, Activity value) {
    throw UnsupportedError('Activity history is immutable.');
  }
}

void _validateParticipants(List<Participant> participants) {
  if (participants.length > maxSessionParticipants) {
    throw ArgumentError.value(
      participants.length,
      'participants',
      'A live session cannot retain more than $maxSessionParticipants '
          'participants.',
    );
  }
  final Set<String> deviceIds = <String>{};
  int connectedParticipantCount = 0;
  for (final Participant participant in participants) {
    if (participant.role == SessionRole.host) {
      throw ArgumentError(
        'The host is identified by hostDeviceId, not as a participant.',
      );
    }
    if (!deviceIds.add(participant.deviceId)) {
      throw ArgumentError(
        'Participant "${participant.deviceId}" appears more than once.',
      );
    }
    if (participant.connectionState !=
        ParticipantConnectionState.disconnected) {
      connectedParticipantCount += 1;
    }
  }
  if (connectedParticipantCount > maxConnectedSessionParticipants) {
    throw ArgumentError.value(
      connectedParticipantCount,
      'participants',
      'A live session cannot have more than '
          '$maxConnectedSessionParticipants connected or stale participants.',
    );
  }
}

void _validateTrustedActivityWindow(
  _ActivityHistoryView activities, {
  required int revision,
  required int revisionOffset,
}) {
  if (activities.length + revisionOffset != revision) {
    throw ArgumentError(
      'Activity window length plus its offset must equal the session revision.',
    );
  }
}

void _validateAppendedActivity(
  Activity activity, {
  required String sessionId,
  required int expectedRevision,
  required PlanSnapshot planSnapshot,
  required _ActivityHistoryView activityView,
}) {
  if (activity.sessionId != sessionId) {
    throw ArgumentError('An activity belongs to a different session.');
  }
  if (activity.revision != expectedRevision) {
    throw ArgumentError(
      'An appended activity must have revision $expectedRevision.',
    );
  }
  if (activityView._storage.containsActivityWithin(
    activity.id,
    activityView.length,
  )) {
    throw ArgumentError('Activity ID "${activity.id}" is duplicated.');
  }
  if (activityView._storage.containsCommandWithin(
    activity.commandId,
    activityView.length,
  )) {
    throw ArgumentError('Command ID "${activity.commandId}" is duplicated.');
  }
  final int? stepIndex = activity.stepIndex;
  final String? stepId = activity.stepId;
  if ((stepIndex == null) != (stepId == null)) {
    throw ArgumentError(
      'An activity step index and step ID must be provided together.',
    );
  }
  if (stepIndex != null &&
      (stepIndex >= planSnapshot.steps.length ||
          planSnapshot.steps[stepIndex].id != stepId)) {
    throw ArgumentError('An activity references a step outside the plan.');
  }
  if (activityView.isNotEmpty &&
      activity.occurredAt.isBefore(activityView.last.occurredAt)) {
    throw ArgumentError('Activity timestamps cannot move backwards.');
  }
}

void _validateActivities(
  List<Activity> activities, {
  required String sessionId,
  required int revision,
  required int revisionOffset,
  required PlanSnapshot planSnapshot,
}) {
  if (activities.isEmpty) {
    if (revisionOffset != revision) {
      throw ArgumentError(
        'An empty activity window must omit every prior revision.',
      );
    }
    return;
  }
  if (activities.length + revisionOffset != revision) {
    throw ArgumentError(
      'Activity window length plus its offset must equal the session revision.',
    );
  }

  final Set<String> activityIds = <String>{};
  final Set<String> commandIds = <String>{};
  for (int index = 0; index < activities.length; index += 1) {
    final Activity activity = activities[index];
    if (activity.sessionId != sessionId) {
      throw ArgumentError('An activity belongs to a different session.');
    }
    if (activity.revision != revisionOffset + index + 1) {
      throw ArgumentError(
        'Activity revisions must be consecutive after the window offset.',
      );
    }
    if (!activityIds.add(activity.id)) {
      throw ArgumentError('Activity ID "${activity.id}" is duplicated.');
    }
    if (!commandIds.add(activity.commandId)) {
      throw ArgumentError('Command ID "${activity.commandId}" is duplicated.');
    }
    final int? stepIndex = activity.stepIndex;
    final String? stepId = activity.stepId;
    if ((stepIndex == null) != (stepId == null)) {
      throw ArgumentError(
        'An activity step index and step ID must be provided together.',
      );
    }
    if (stepIndex != null &&
        (stepIndex >= planSnapshot.steps.length ||
            planSnapshot.steps[stepIndex].id != stepId)) {
      throw ArgumentError('An activity references a step outside the plan.');
    }
    if (index > 0 &&
        activity.occurredAt.isBefore(activities[index - 1].occurredAt)) {
      throw ArgumentError('Activity timestamps cannot move backwards.');
    }
  }
}

void _validateStatusTimestamps({
  required LiveSessionStatus status,
  required DateTime? startedAt,
  required DateTime? currentStepStartedAt,
  required DateTime? pausedAt,
  required DateTime? endedAt,
  required SessionEndReason? endReason,
}) {
  switch (status) {
    case LiveSessionStatus.waiting:
      if (startedAt != null ||
          currentStepStartedAt != null ||
          pausedAt != null ||
          endedAt != null ||
          endReason != null) {
        throw ArgumentError(
          'A waiting session cannot have runtime timestamps.',
        );
      }
    case LiveSessionStatus.running:
      if (startedAt == null ||
          currentStepStartedAt == null ||
          pausedAt != null ||
          endedAt != null ||
          endReason != null) {
        throw ArgumentError('A running session has inconsistent timestamps.');
      }
    case LiveSessionStatus.paused:
      if (startedAt == null ||
          currentStepStartedAt == null ||
          pausedAt == null ||
          endedAt != null ||
          endReason != null) {
        throw ArgumentError('A paused session has inconsistent timestamps.');
      }
    case LiveSessionStatus.ended:
      if (endedAt == null || endReason == null || pausedAt != null) {
        throw ArgumentError('An ended session has inconsistent timestamps.');
      }
      if ((startedAt == null) != (currentStepStartedAt == null)) {
        throw ArgumentError(
          'An ended session must have both runtime start timestamps or neither.',
        );
      }
  }
  if (startedAt != null &&
      currentStepStartedAt != null &&
      currentStepStartedAt.isBefore(startedAt)) {
    throw ArgumentError('A step cannot start before its session.');
  }
  if (pausedAt != null &&
      currentStepStartedAt != null &&
      pausedAt.isBefore(currentStepStartedAt)) {
    throw ArgumentError('A pause cannot precede the current step.');
  }
  if (endedAt != null &&
      ((startedAt != null && endedAt.isBefore(startedAt)) ||
          (currentStepStartedAt != null &&
              endedAt.isBefore(currentStepStartedAt)))) {
    throw ArgumentError('A session cannot end before it starts.');
  }
}

void _validatePauseDurations({
  required LiveSessionStatus status,
  required DateTime? startedAt,
  required DateTime? currentStepStartedAt,
  required DateTime? pausedAt,
  required DateTime? endedAt,
  required DateTime? lastActivityAt,
  required Duration currentStepPausedDuration,
  required Duration totalPausedDuration,
}) {
  final DateTime? accountingThrough = switch (status) {
    LiveSessionStatus.paused => pausedAt,
    LiveSessionStatus.ended => endedAt,
    LiveSessionStatus.running => lastActivityAt,
    LiveSessionStatus.waiting => null,
  };
  if (accountingThrough == null) {
    return;
  }
  if (startedAt != null &&
      totalPausedDuration > accountingThrough.difference(startedAt)) {
    throw ArgumentError('Total pause time cannot exceed session wall time.');
  }
  if (currentStepStartedAt != null &&
      currentStepPausedDuration >
          accountingThrough.difference(currentStepStartedAt)) {
    throw ArgumentError(
      'Current-step pause time cannot exceed current-step wall time.',
    );
  }
}

Map<String, Object?> _immutableJsonMap(Map<String, Object?> source) {
  return UnmodifiableMapView<String, Object?>(
    source.map<String, Object?>(
      (String key, Object? value) =>
          MapEntry<String, Object?>(key, _immutableJsonValue(value)),
    ),
  );
}

Object? _immutableJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    final Map<String, Object?> mapped = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('JSON object keys must be strings.');
      }
      mapped[entry.key! as String] = _immutableJsonValue(entry.value);
    }
    return UnmodifiableMapView<String, Object?>(mapped);
  }
  if (value is Iterable<Object?>) {
    return UnmodifiableListView<Object?>(
      value.map<Object?>(_immutableJsonValue),
    );
  }
  throw ArgumentError.value(value, 'value', 'Value is not JSON-compatible.');
}

Object? _mutableJsonCopy(Object? value) {
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key! as String: _mutableJsonCopy(entry.value),
    };
  }
  if (value is Iterable<Object?>) {
    return value.map<Object?>(_mutableJsonCopy).toList(growable: false);
  }
  return value;
}

void _requireVersion(Map<String, Object?> json, {required String entityName}) {
  final Object? value = json['schemaVersion'];
  if (value != liveSessionSchemaVersion) {
    throw FormatException('Unsupported $entityName schema version: $value.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string when provided.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

int? _optionalInt(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('$key must be an integer when provided.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final DateTime? value = _optionalDateTime(json[key], key);
  if (value == null) {
    throw FormatException('$key must be an ISO-8601 timestamp.');
  }
  return value;
}

DateTime? _optionalDateTime(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$key must be an ISO-8601 string.');
  }
  return parseUtcTimestamp(value, fieldName: key);
}

Map<String, Object?> _jsonMap(Object? value, String key) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$key must be a JSON object.');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _jsonList(Object? value, String key) {
  if (value is! List<Object?>) {
    throw FormatException('$key must be a JSON array.');
  }
  return value;
}

T _enumByName<T extends Enum>(List<T> values, String name, String key) {
  for (final T value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw FormatException('$key has an unsupported value: $name.');
}

T? _optionalEnumByName<T extends Enum>(
  List<T> values,
  String? name,
  String key,
) {
  return name == null ? null : _enumByName<T>(values, name, key);
}
