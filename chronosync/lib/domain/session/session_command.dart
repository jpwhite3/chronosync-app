import 'package:chronosync/core/serialization/utc_timestamp.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:equatable/equatable.dart';

const int sessionCommandSchemaVersion = 1;

enum SessionCommandType {
  join,
  changeRole,
  disconnectParticipant,
  start,
  pause,
  resume,
  advance,
  adjustRemaining,
  jump,
  acknowledge,
  end,
}

/// A client request that must be validated and serialized by the host.
class SessionCommand extends Equatable {
  factory SessionCommand.join({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required int baseRevision,
    required DateTime issuedAt,
    required String displayName,
    required SessionRole requestedRole,
    required String authenticationSecret,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: requestedRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.join,
      displayName: displayName,
      requestedRole: requestedRole,
      authenticationSecret: authenticationSecret,
    );
  }

  factory SessionCommand.changeRole({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required String targetDeviceId,
    required SessionRole targetRole,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.changeRole,
      targetDeviceId: targetDeviceId,
      targetRole: targetRole,
    );
  }

  factory SessionCommand.disconnectParticipant({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required String targetDeviceId,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.disconnectParticipant,
      targetDeviceId: targetDeviceId,
    );
  }

  factory SessionCommand.start({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.start,
    );
  }

  factory SessionCommand.pause({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.pause,
    );
  }

  factory SessionCommand.resume({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.resume,
    );
  }

  factory SessionCommand.advance({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    bool automatically = false,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.advance,
      automatically: automatically,
    );
  }

  factory SessionCommand.adjustRemaining({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required int adjustmentSeconds,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.adjustRemaining,
      adjustmentSeconds: adjustmentSeconds,
    );
  }

  factory SessionCommand.jump({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required int targetStepIndex,
    required bool confirmed,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.jump,
      targetStepIndex: targetStepIndex,
      confirmed: confirmed,
    );
  }

  factory SessionCommand.acknowledge({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required int stepIndex,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.acknowledge,
      acknowledgedStepIndex: stepIndex,
    );
  }

  factory SessionCommand.end({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required bool confirmed,
  }) {
    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: SessionCommandType.end,
      confirmed: confirmed,
    );
  }

  factory SessionCommand._validated({
    required String id,
    required String sessionId,
    required String actorDeviceId,
    required SessionRole actorRole,
    required int baseRevision,
    required DateTime issuedAt,
    required SessionCommandType type,
    bool automatically = false,
    bool confirmed = false,
    int? adjustmentSeconds,
    int? targetStepIndex,
    int? acknowledgedStepIndex,
    String? displayName,
    SessionRole? requestedRole,
    String? authenticationSecret,
    String? targetDeviceId,
    SessionRole? targetRole,
  }) {
    final String normalizedId = id.trim();
    final String normalizedSessionId = sessionId.trim();
    final String normalizedActorDeviceId = actorDeviceId.trim();
    if (normalizedId.isEmpty ||
        normalizedSessionId.isEmpty ||
        normalizedActorDeviceId.isEmpty) {
      throw ArgumentError('Command, session, and actor IDs cannot be empty.');
    }
    if (normalizedId.length > maxSessionDeviceIdLength ||
        normalizedSessionId.length > maxSessionDeviceIdLength ||
        normalizedActorDeviceId.length > maxSessionDeviceIdLength) {
      throw ArgumentError(
        'Command, session, and actor IDs cannot exceed '
        '$maxSessionDeviceIdLength characters.',
      );
    }
    if (baseRevision < 0) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'A base revision cannot be negative.',
      );
    }
    if (automatically && type != SessionCommandType.advance) {
      throw ArgumentError('Only an advance command can be marked automatic.');
    }

    switch (type) {
      case SessionCommandType.join:
        if (displayName == null ||
            displayName.trim().isEmpty ||
            displayName.trim().length > maxParticipantDisplayNameLength) {
          throw ArgumentError.value(
            displayName,
            'displayName',
            'A joining participant needs a 1–'
                '$maxParticipantDisplayNameLength character display name.',
          );
        }
        if (requestedRole != SessionRole.participant &&
            requestedRole != SessionRole.display) {
          throw ArgumentError.value(
            requestedRole,
            'requestedRole',
            'A public join can request Participant or Display only.',
          );
        }
        if (actorRole != requestedRole) {
          throw ArgumentError(
            'A join actor role must match the requested role.',
          );
        }
        if (authenticationSecret == null ||
            !RegExp(
              r'^[A-Za-z0-9_-]{32,128}$',
            ).hasMatch(authenticationSecret)) {
          throw ArgumentError.value(
            authenticationSecret,
            'authenticationSecret',
            'A join authentication secret must be 32–128 base64url '
                'characters.',
          );
        }
      case SessionCommandType.changeRole:
        if (targetDeviceId == null ||
            targetDeviceId.trim().isEmpty ||
            targetDeviceId.trim().length > maxSessionDeviceIdLength) {
          throw ArgumentError.value(
            targetDeviceId,
            'targetDeviceId',
            'A role change needs a target device.',
          );
        }
        if (targetRole == null || targetRole == SessionRole.host) {
          throw ArgumentError.value(
            targetRole,
            'targetRole',
            'A participant role cannot be Host.',
          );
        }
      case SessionCommandType.disconnectParticipant:
        if (targetDeviceId == null ||
            targetDeviceId.trim().isEmpty ||
            targetDeviceId.trim().length > maxSessionDeviceIdLength) {
          throw ArgumentError.value(
            targetDeviceId,
            'targetDeviceId',
            'A disconnect needs a target device.',
          );
        }
      case SessionCommandType.adjustRemaining:
        if (adjustmentSeconds == null || adjustmentSeconds == 0) {
          throw ArgumentError.value(
            adjustmentSeconds,
            'adjustmentSeconds',
            'A remaining-time adjustment cannot be zero.',
          );
        }
      case SessionCommandType.jump:
        if (targetStepIndex == null || targetStepIndex < 0) {
          throw ArgumentError.value(
            targetStepIndex,
            'targetStepIndex',
            'A jump target must be non-negative.',
          );
        }
      case SessionCommandType.acknowledge:
        if (acknowledgedStepIndex == null || acknowledgedStepIndex < 0) {
          throw ArgumentError.value(
            acknowledgedStepIndex,
            'acknowledgedStepIndex',
            'An acknowledgement step must be non-negative.',
          );
        }
      case SessionCommandType.start:
      case SessionCommandType.pause:
      case SessionCommandType.resume:
      case SessionCommandType.advance:
      case SessionCommandType.end:
        break;
    }

    return SessionCommand._(
      id: normalizedId,
      sessionId: normalizedSessionId,
      actorDeviceId: normalizedActorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt.toUtc(),
      type: type,
      automatically: automatically,
      confirmed: confirmed,
      adjustmentSeconds: adjustmentSeconds,
      targetStepIndex: targetStepIndex,
      acknowledgedStepIndex: acknowledgedStepIndex,
      displayName: displayName?.trim(),
      requestedRole: requestedRole,
      authenticationSecret: authenticationSecret,
      targetDeviceId: targetDeviceId?.trim(),
      targetRole: targetRole,
    );
  }

  const SessionCommand._({
    required this.id,
    required this.sessionId,
    required this.actorDeviceId,
    required this.actorRole,
    required this.baseRevision,
    required this.issuedAt,
    required this.type,
    required this.automatically,
    required this.confirmed,
    required this.adjustmentSeconds,
    required this.targetStepIndex,
    required this.acknowledgedStepIndex,
    required this.displayName,
    required this.requestedRole,
    required this.authenticationSecret,
    required this.targetDeviceId,
    required this.targetRole,
  });

  final String id;
  final String sessionId;
  final String actorDeviceId;
  final SessionRole actorRole;
  final int baseRevision;
  final DateTime issuedAt;
  final SessionCommandType type;
  final bool automatically;
  final bool confirmed;
  final int? adjustmentSeconds;
  final int? targetStepIndex;
  final int? acknowledgedStepIndex;
  final String? displayName;
  final SessionRole? requestedRole;
  final String? authenticationSecret;
  final String? targetDeviceId;
  final SessionRole? targetRole;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': sessionCommandSchemaVersion,
      'id': id,
      'sessionId': sessionId,
      'actorDeviceId': actorDeviceId,
      'actorRole': actorRole.name,
      'baseRevision': baseRevision,
      'issuedAt': issuedAt.toIso8601String(),
      'type': type.name,
      'automatically': automatically,
      'confirmed': confirmed,
      'adjustmentSeconds': adjustmentSeconds,
      'targetStepIndex': targetStepIndex,
      'acknowledgedStepIndex': acknowledgedStepIndex,
      'displayName': displayName,
      'requestedRole': requestedRole?.name,
      'authenticationSecret': authenticationSecret,
      'targetDeviceId': targetDeviceId,
      'targetRole': targetRole?.name,
    };
  }

  factory SessionCommand.fromJson(Map<String, Object?> json) {
    final Object? version = json['schemaVersion'];
    if (version != sessionCommandSchemaVersion) {
      throw FormatException('Unsupported command schema version: $version.');
    }
    final SessionCommandType type = _enumByName(
      SessionCommandType.values,
      _requiredString(json, 'type'),
      'type',
    );
    final SessionRole actorRole = _enumByName(
      SessionRole.values,
      _requiredString(json, 'actorRole'),
      'actorRole',
    );
    final DateTime issuedAt = _requiredDateTime(json, 'issuedAt');
    final String id = _requiredString(json, 'id');
    final String sessionId = _requiredString(json, 'sessionId');
    final String actorDeviceId = _requiredString(json, 'actorDeviceId');
    final int baseRevision = _requiredInt(json, 'baseRevision');
    final bool automatically = _requiredBool(json, 'automatically');
    final bool confirmed = _requiredBool(json, 'confirmed');
    final int? adjustmentSeconds = _optionalInt(
      json['adjustmentSeconds'],
      'adjustmentSeconds',
    );
    final int? targetStepIndex = _optionalInt(
      json['targetStepIndex'],
      'targetStepIndex',
    );
    final int? acknowledgedStepIndex = _optionalInt(
      json['acknowledgedStepIndex'],
      'acknowledgedStepIndex',
    );
    final String? displayName = _optionalString(
      json['displayName'],
      'displayName',
    );
    final SessionRole? requestedRole = _optionalEnumByName(
      SessionRole.values,
      _optionalString(json['requestedRole'], 'requestedRole'),
      'requestedRole',
    );
    final String? authenticationSecret = _optionalString(
      json['authenticationSecret'],
      'authenticationSecret',
    );
    final String? targetDeviceId = _optionalString(
      json['targetDeviceId'],
      'targetDeviceId',
    );
    final SessionRole? targetRole = _optionalEnumByName(
      SessionRole.values,
      _optionalString(json['targetRole'], 'targetRole'),
      'targetRole',
    );

    return SessionCommand._validated(
      id: id,
      sessionId: sessionId,
      actorDeviceId: actorDeviceId,
      actorRole: actorRole,
      baseRevision: baseRevision,
      issuedAt: issuedAt,
      type: type,
      automatically: automatically,
      confirmed: confirmed,
      adjustmentSeconds: adjustmentSeconds,
      targetStepIndex: targetStepIndex,
      acknowledgedStepIndex: acknowledgedStepIndex,
      displayName: displayName,
      requestedRole: requestedRole,
      authenticationSecret: authenticationSecret,
      targetDeviceId: targetDeviceId,
      targetRole: targetRole,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    sessionId,
    actorDeviceId,
    actorRole,
    baseRevision,
    issuedAt,
    type,
    automatically,
    confirmed,
    adjustmentSeconds,
    targetStepIndex,
    acknowledgedStepIndex,
    displayName,
    requestedRole,
    authenticationSecret,
    targetDeviceId,
    targetRole,
  ];
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

int? _optionalInt(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('$key must be an integer when provided.');
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

bool _requiredBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) {
    throw FormatException('$key must be an ISO-8601 string.');
  }
  return parseUtcTimestamp(value, fieldName: key);
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
