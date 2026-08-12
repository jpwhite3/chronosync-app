import 'dart:collection';

import 'package:chronosync/core/serialization/utc_timestamp.dart';
import 'package:equatable/equatable.dart';

/// The current JSON contract for plan-domain entities.
const int planSchemaVersion = 1;
const int maxPlanTitleLength = 160;
const int maxStepTitleLength = 240;
const int maxPlanSteps = 250;
const int maxStepDurationSeconds = 359999;

/// Delivery preferences and thresholds for step timing cues.
class CueProfile extends Equatable {
  factory CueProfile({
    int approachingSeconds = 60,
    int overdueSeconds = 60,
    bool visualEnabled = true,
    bool soundEnabled = true,
    bool hapticEnabled = true,
  }) {
    if (approachingSeconds <= 0) {
      throw ArgumentError.value(
        approachingSeconds,
        'approachingSeconds',
        'An approaching threshold must be positive.',
      );
    }
    if (overdueSeconds <= 0) {
      throw ArgumentError.value(
        overdueSeconds,
        'overdueSeconds',
        'An overdue threshold must be positive.',
      );
    }
    return CueProfile._(
      approachingSeconds: approachingSeconds,
      overdueSeconds: overdueSeconds,
      visualEnabled: visualEnabled,
      soundEnabled: soundEnabled,
      hapticEnabled: hapticEnabled,
    );
  }

  const CueProfile._({
    required this.approachingSeconds,
    required this.overdueSeconds,
    required this.visualEnabled,
    required this.soundEnabled,
    required this.hapticEnabled,
  });

  final int approachingSeconds;
  final int overdueSeconds;
  final bool visualEnabled;
  final bool soundEnabled;
  final bool hapticEnabled;

  /// Whether the approaching cue should be used for [stepDuration].
  ///
  /// A plan-level default does not interrupt very short steps. Supplying a
  /// step-level override opts that step into its explicitly chosen threshold.
  bool includesApproachingCueFor(
    Duration stepDuration, {
    bool isStepOverride = false,
  }) {
    return isStepOverride || stepDuration.inSeconds > approachingSeconds;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': planSchemaVersion,
      'approachingSeconds': approachingSeconds,
      'overdueSeconds': overdueSeconds,
      'visualEnabled': visualEnabled,
      'soundEnabled': soundEnabled,
      'hapticEnabled': hapticEnabled,
    };
  }

  factory CueProfile.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'cue profile');
    final int approachingSeconds = _requiredInt(json, 'approachingSeconds');
    final int overdueSeconds = _requiredInt(json, 'overdueSeconds');
    if (approachingSeconds <= 0 || overdueSeconds <= 0) {
      throw const FormatException('Cue thresholds must be positive.');
    }
    return CueProfile(
      approachingSeconds: approachingSeconds,
      overdueSeconds: overdueSeconds,
      visualEnabled: _requiredBool(json, 'visualEnabled'),
      soundEnabled: _requiredBool(json, 'soundEnabled'),
      hapticEnabled: _requiredBool(json, 'hapticEnabled'),
    );
  }

  @override
  List<Object> get props => <Object>[
    approachingSeconds,
    overdueSeconds,
    visualEnabled,
    soundEnabled,
    hapticEnabled,
  ];
}

/// One immutable, ordered action in a [Plan].
class Step extends Equatable {
  factory Step({
    required String id,
    required String planId,
    required int position,
    required String title,
    required int durationSeconds,
    bool autoAdvance = false,
    CueProfile? cueOverride,
  }) {
    final String normalizedId = id.trim();
    final String normalizedPlanId = planId.trim();
    final String normalizedTitle = title.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'A step ID cannot be empty.');
    }
    if (normalizedPlanId.isEmpty) {
      throw ArgumentError.value(
        planId,
        'planId',
        'A step plan ID cannot be empty.',
      );
    }
    if (position < 0) {
      throw ArgumentError.value(
        position,
        'position',
        'A step position cannot be negative.',
      );
    }
    if (normalizedTitle.isEmpty ||
        normalizedTitle.length > maxStepTitleLength) {
      throw ArgumentError.value(
        title,
        'title',
        'A step title must be 1–$maxStepTitleLength characters.',
      );
    }
    if (durationSeconds <= 0 || durationSeconds > maxStepDurationSeconds) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'A step duration must be between 1 and $maxStepDurationSeconds seconds.',
      );
    }

    return Step._(
      id: normalizedId,
      planId: normalizedPlanId,
      position: position,
      title: normalizedTitle,
      durationSeconds: durationSeconds,
      autoAdvance: autoAdvance,
      cueOverride: cueOverride,
    );
  }

  const Step._({
    required this.id,
    required this.planId,
    required this.position,
    required this.title,
    required this.durationSeconds,
    required this.autoAdvance,
    required this.cueOverride,
  });

  final String id;
  final String planId;
  final int position;
  final String title;
  final int durationSeconds;
  final bool autoAdvance;
  final CueProfile? cueOverride;

  Duration get duration => Duration(seconds: durationSeconds);

  Step copyWith({
    String? id,
    String? planId,
    int? position,
    String? title,
    int? durationSeconds,
    bool? autoAdvance,
    Object? cueOverride = _unset,
  }) {
    return Step(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      position: position ?? this.position,
      title: title ?? this.title,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      autoAdvance: autoAdvance ?? this.autoAdvance,
      cueOverride: identical(cueOverride, _unset)
          ? this.cueOverride
          : cueOverride as CueProfile?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': planSchemaVersion,
      'id': id,
      'planId': planId,
      'position': position,
      'title': title,
      'durationSeconds': durationSeconds,
      'autoAdvance': autoAdvance,
      'cueOverride': cueOverride?.toJson(),
    };
  }

  factory Step.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'step');
    final Object? cueJson = json['cueOverride'];
    return Step(
      id: _requiredString(json, 'id'),
      planId: _requiredString(json, 'planId'),
      position: _requiredInt(json, 'position'),
      title: _requiredString(json, 'title'),
      durationSeconds: _requiredInt(json, 'durationSeconds'),
      autoAdvance: _requiredBool(json, 'autoAdvance'),
      cueOverride: cueJson == null
          ? null
          : CueProfile.fromJson(_jsonMap(cueJson, 'cueOverride')),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    planId,
    position,
    title,
    durationSeconds,
    autoAdvance,
    cueOverride,
  ];
}

/// An editable local runbook.
class Plan extends Equatable {
  factory Plan({
    required String id,
    required String title,
    required CueProfile defaultCueProfile,
    required Iterable<Step> steps,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? plannedStartTime,
  }) {
    final String normalizedId = id.trim();
    final String normalizedTitle = title.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'A plan ID cannot be empty.');
    }
    if (normalizedTitle.isEmpty ||
        normalizedTitle.length > maxPlanTitleLength) {
      throw ArgumentError.value(
        title,
        'title',
        'A plan title must be 1–$maxPlanTitleLength characters.',
      );
    }

    final List<Step> sortedSteps = List<Step>.of(
      steps,
    )..sort((Step left, Step right) => left.position.compareTo(right.position));
    final List<Step> immutableSteps = List<Step>.unmodifiable(sortedSteps);
    _validateSteps(immutableSteps, planId: normalizedId);
    final DateTime createdAtUtc = createdAt.toUtc();
    final DateTime updatedAtUtc = updatedAt.toUtc();
    if (updatedAtUtc.isBefore(createdAtUtc)) {
      throw ArgumentError.value(
        updatedAt,
        'updatedAt',
        'A plan cannot be updated before it was created.',
      );
    }

    return Plan._(
      id: normalizedId,
      title: normalizedTitle,
      plannedStartTime: plannedStartTime?.toUtc(),
      defaultCueProfile: defaultCueProfile,
      steps: immutableSteps,
      createdAt: createdAtUtc,
      updatedAt: updatedAtUtc,
    );
  }

  const Plan._({
    required this.id,
    required this.title,
    required this.plannedStartTime,
    required this.defaultCueProfile,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime? plannedStartTime;
  final CueProfile defaultCueProfile;
  final List<Step> steps;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get totalDuration => steps.fold<Duration>(
    Duration.zero,
    (Duration total, Step step) => total + step.duration,
  );

  Plan copyWith({
    String? id,
    String? title,
    Object? plannedStartTime = _unset,
    CueProfile? defaultCueProfile,
    Iterable<Step>? steps,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final String nextId = id ?? this.id;
    final Iterable<Step> nextSteps = steps ?? this.steps;
    return Plan(
      id: nextId,
      title: title ?? this.title,
      plannedStartTime: identical(plannedStartTime, _unset)
          ? this.plannedStartTime
          : plannedStartTime as DateTime?,
      defaultCueProfile: defaultCueProfile ?? this.defaultCueProfile,
      steps: nextSteps,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  PlanSnapshot snapshot({required DateTime capturedAt}) {
    return PlanSnapshot(
      sourcePlanId: id,
      title: title,
      plannedStartTime: plannedStartTime,
      defaultCueProfile: defaultCueProfile,
      steps: steps,
      capturedAt: capturedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': planSchemaVersion,
      'id': id,
      'title': title,
      'plannedStartTime': plannedStartTime?.toIso8601String(),
      'defaultCueProfile': defaultCueProfile.toJson(),
      'steps': steps.map((Step step) => step.toJson()).toList(growable: false),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Plan.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'plan');
    return Plan(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      plannedStartTime: _optionalDateTime(json['plannedStartTime']),
      defaultCueProfile: CueProfile.fromJson(
        _jsonMap(json['defaultCueProfile'], 'defaultCueProfile'),
      ),
      steps: _jsonList(
        json['steps'],
        'steps',
      ).map<Step>((Object? value) => Step.fromJson(_jsonMap(value, 'step'))),
      createdAt: _requiredDateTime(json, 'createdAt'),
      updatedAt: _requiredDateTime(json, 'updatedAt'),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    title,
    plannedStartTime,
    defaultCueProfile,
    steps,
    createdAt,
    updatedAt,
  ];
}

/// The fixed plan content used throughout a live session.
///
/// Editing or deleting the source [Plan] cannot change an active session.
class PlanSnapshot extends Equatable {
  factory PlanSnapshot({
    required String sourcePlanId,
    required String title,
    required CueProfile defaultCueProfile,
    required Iterable<Step> steps,
    required DateTime capturedAt,
    DateTime? plannedStartTime,
  }) {
    final String normalizedPlanId = sourcePlanId.trim();
    final String normalizedTitle = title.trim();
    if (normalizedPlanId.isEmpty) {
      throw ArgumentError.value(
        sourcePlanId,
        'sourcePlanId',
        'A source plan ID cannot be empty.',
      );
    }
    if (normalizedTitle.isEmpty ||
        normalizedTitle.length > maxPlanTitleLength) {
      throw ArgumentError.value(
        title,
        'title',
        'A snapshot title must be 1–$maxPlanTitleLength characters.',
      );
    }

    final List<Step> sortedSteps = List<Step>.of(
      steps,
    )..sort((Step left, Step right) => left.position.compareTo(right.position));
    final List<Step> immutableSteps = List<Step>.unmodifiable(sortedSteps);
    _validateSteps(immutableSteps, planId: normalizedPlanId);
    if (immutableSteps.isEmpty) {
      throw ArgumentError.value(
        steps,
        'steps',
        'A live plan snapshot must contain at least one step.',
      );
    }

    return PlanSnapshot._(
      sourcePlanId: normalizedPlanId,
      title: normalizedTitle,
      plannedStartTime: plannedStartTime?.toUtc(),
      defaultCueProfile: defaultCueProfile,
      steps: immutableSteps,
      capturedAt: capturedAt.toUtc(),
    );
  }

  const PlanSnapshot._({
    required this.sourcePlanId,
    required this.title,
    required this.plannedStartTime,
    required this.defaultCueProfile,
    required this.steps,
    required this.capturedAt,
  });

  final String sourcePlanId;
  final String title;
  final DateTime? plannedStartTime;
  final CueProfile defaultCueProfile;
  final List<Step> steps;
  final DateTime capturedAt;

  Duration get totalDuration => steps.fold<Duration>(
    Duration.zero,
    (Duration total, Step step) => total + step.duration,
  );

  Duration plannedOffsetForStep(int index) {
    if (index < 0 || index >= steps.length) {
      throw RangeError.index(index, steps, 'index');
    }
    return steps
        .take(index)
        .fold<Duration>(
          Duration.zero,
          (Duration total, Step step) => total + step.duration,
        );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': planSchemaVersion,
      'sourcePlanId': sourcePlanId,
      'title': title,
      'plannedStartTime': plannedStartTime?.toIso8601String(),
      'defaultCueProfile': defaultCueProfile.toJson(),
      'steps': steps.map((Step step) => step.toJson()).toList(growable: false),
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  factory PlanSnapshot.fromJson(Map<String, Object?> json) {
    _requireVersion(json, entityName: 'plan snapshot');
    return PlanSnapshot(
      sourcePlanId: _requiredString(json, 'sourcePlanId'),
      title: _requiredString(json, 'title'),
      plannedStartTime: _optionalDateTime(json['plannedStartTime']),
      defaultCueProfile: CueProfile.fromJson(
        _jsonMap(json['defaultCueProfile'], 'defaultCueProfile'),
      ),
      steps: _jsonList(
        json['steps'],
        'steps',
      ).map<Step>((Object? value) => Step.fromJson(_jsonMap(value, 'step'))),
      capturedAt: _requiredDateTime(json, 'capturedAt'),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    sourcePlanId,
    title,
    plannedStartTime,
    defaultCueProfile,
    steps,
    capturedAt,
  ];
}

const Object _unset = Object();

void _validateSteps(List<Step> steps, {required String planId}) {
  if (steps.length > maxPlanSteps) {
    throw ArgumentError.value(
      steps.length,
      'steps',
      'A plan cannot contain more than $maxPlanSteps steps.',
    );
  }
  final Set<String> ids = <String>{};
  for (int index = 0; index < steps.length; index += 1) {
    final Step step = steps[index];
    if (step.planId != planId) {
      throw ArgumentError(
        'Step "${step.id}" belongs to "${step.planId}", not "$planId".',
      );
    }
    if (step.position != index) {
      throw ArgumentError(
        'Step "${step.id}" has position ${step.position}; expected $index.',
      );
    }
    if (!ids.add(step.id)) {
      throw ArgumentError('Step ID "${step.id}" appears more than once.');
    }
  }
}

void _requireVersion(Map<String, Object?> json, {required String entityName}) {
  final Object? value = json['schemaVersion'];
  if (value != planSchemaVersion) {
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

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final DateTime? value = _optionalDateTime(json[key]);
  if (value == null) {
    throw FormatException('$key must be an ISO-8601 timestamp.');
  }
  return value;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('A timestamp must be an ISO-8601 string.');
  }
  return parseUtcTimestamp(value);
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
  return UnmodifiableListView<Object?>(value);
}
