import 'dart:convert';

import 'package:chronosync/core/serialization/utc_timestamp.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:equatable/equatable.dart';

/// The wire protocol understood by this build.
const int sessionProtocolVersion = 1;
const int maxInvitationQrPayloadLength = 16 * 1024;
const int maxInvitationUrlLength = 2048;
const int maxSessionEncryptedPayloadLength = 256 * 1024;
const int maxSessionEnvelopeEncodedLength = 320 * 1024;

enum SessionTransportKind { nearbyLan, onlineRelay }

enum SessionMessageKind { join, command, activity, snapshot, heartbeat, error }

/// Maximum activity tail carried by an authoritative live snapshot.
///
/// Complete history remains on the host. Replicas merge overlapping tails so
/// continuously connected devices still retain every activity they observed.
const int maxLiveSnapshotActivities = 64;

/// Bounded, versioned representation of authoritative state sent to replicas.
final class LiveSessionSnapshot {
  factory LiveSessionSnapshot.fromSession(LiveSession source) {
    final int retainedCount =
        source.activities.length > maxLiveSnapshotActivities
        ? maxLiveSnapshotActivities
        : source.activities.length;
    final List<Activity> retainedActivities = source.activities
        .skip(source.activities.length - retainedCount)
        .toList(growable: false);
    final List<Participant> retainedParticipants = source.participants
        .where(
          (Participant participant) =>
              participant.connectionState !=
              ParticipantConnectionState.disconnected,
        )
        .toList(growable: false);
    return LiveSessionSnapshot._(
      source.copyWith(
        activityRevisionOffset: source.revision - retainedActivities.length,
        participants: retainedParticipants,
        activities: retainedActivities,
      ),
    );
  }

  LiveSessionSnapshot._(this.session);

  final LiveSession session;

  Map<String, Object?> toJson() => session.toJson();

  factory LiveSessionSnapshot.fromJson(Map<String, Object?> json) {
    return LiveSessionSnapshot._(LiveSession.fromJson(json));
  }

  /// Applies this authoritative state while retaining any contiguous activity
  /// prefix already held by the replica.
  LiveSession mergeOnto(LiveSession? previous) {
    final LiveSession incoming = session;
    if (previous == null ||
        previous.id != incoming.id ||
        previous.revision > incoming.revision ||
        previous.activities.isEmpty ||
        incoming.activities.isEmpty) {
      return incoming;
    }

    final Map<int, Activity> byRevision = <int, Activity>{
      for (final Activity activity in previous.activities)
        if (activity.revision <= incoming.revision) activity.revision: activity,
      for (final Activity activity in incoming.activities)
        activity.revision: activity,
    };
    final List<Activity> merged = byRevision.values.toList(growable: false)
      ..sort(
        (Activity left, Activity right) =>
            left.revision.compareTo(right.revision),
      );
    if (merged.isEmpty || merged.last.revision != incoming.revision) {
      return incoming;
    }
    final int offset = merged.first.revision - 1;
    for (int index = 0; index < merged.length; index += 1) {
      if (merged[index].revision != offset + index + 1) {
        return incoming;
      }
    }
    return incoming.copyWith(
      activityRevisionOffset: offset,
      activities: merged,
    );
  }
}

/// A short-lived, role-scoped capability shared by link or QR code.
class Invitation extends Equatable {
  factory Invitation({
    required String sessionId,
    required SessionTransportKind transport,
    required Uri endpoint,
    Uri? joinUri,
    required String capability,
    required String sessionSecret,
    required SessionRole requestedRole,
    required DateTime expiresAt,
    int protocolVersion = sessionProtocolVersion,
  }) {
    return Invitation._validated(
      sessionId: sessionId,
      transport: transport,
      endpoint: endpoint,
      joinUri: joinUri,
      capability: capability,
      sessionSecret: sessionSecret,
      requestedRole: requestedRole,
      expiresAt: expiresAt,
      protocolVersion: protocolVersion,
      allowControllerGrant: false,
    );
  }

  /// Creates a private capability after the host promotes a participant.
  factory Invitation.controllerGrant({
    required String sessionId,
    required SessionTransportKind transport,
    required Uri endpoint,
    Uri? joinUri,
    required String capability,
    required String sessionSecret,
    required DateTime expiresAt,
    int protocolVersion = sessionProtocolVersion,
  }) {
    return Invitation._validated(
      sessionId: sessionId,
      transport: transport,
      endpoint: endpoint,
      joinUri: joinUri,
      capability: capability,
      sessionSecret: sessionSecret,
      requestedRole: SessionRole.controller,
      expiresAt: expiresAt,
      protocolVersion: protocolVersion,
      allowControllerGrant: true,
    );
  }

  factory Invitation._validated({
    required String sessionId,
    required SessionTransportKind transport,
    required Uri endpoint,
    required Uri? joinUri,
    required String capability,
    required String sessionSecret,
    required SessionRole requestedRole,
    required DateTime expiresAt,
    required bool allowControllerGrant,
    int protocolVersion = sessionProtocolVersion,
  }) {
    final String normalizedSessionId = sessionId.trim();
    final String normalizedCapability = capability.trim();
    final String normalizedSessionSecret = sessionSecret.trim();
    if (protocolVersion != sessionProtocolVersion) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'Unsupported session protocol version.',
      );
    }
    if (normalizedSessionId.isEmpty ||
        normalizedSessionId.length > maxSessionDeviceIdLength) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'A session ID must be 1–$maxSessionDeviceIdLength characters.',
      );
    }
    if (!_isStrongRoomToken(normalizedCapability) ||
        !_isStrongRoomToken(normalizedSessionSecret)) {
      throw ArgumentError(
        'Capabilities and session secrets must be 256-bit base64url tokens.',
      );
    }
    if (!endpoint.hasScheme ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.host.isEmpty ||
        endpoint.toString().length > maxInvitationUrlLength) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'An invitation endpoint must be an HTTP or HTTPS URI.',
      );
    }
    if (transport == SessionTransportKind.onlineRelay &&
        endpoint.scheme != 'https') {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'An online relay invitation must use HTTPS.',
      );
    }
    final Uri resolvedJoinUri = joinUri ?? endpoint;
    if (!resolvedJoinUri.hasScheme ||
        (resolvedJoinUri.scheme != 'http' &&
            resolvedJoinUri.scheme != 'https') ||
        resolvedJoinUri.host.isEmpty ||
        resolvedJoinUri.hasFragment ||
        resolvedJoinUri.toString().length > maxInvitationUrlLength ||
        (transport == SessionTransportKind.onlineRelay &&
            resolvedJoinUri.scheme != 'https')) {
      throw ArgumentError.value(
        resolvedJoinUri,
        'joinUri',
        'An invitation join URI must be an HTTP or HTTPS URL without a '
            'fragment.',
      );
    }
    final bool isPublicRole =
        requestedRole == SessionRole.participant ||
        requestedRole == SessionRole.display;
    final bool isControllerGrant =
        allowControllerGrant && requestedRole == SessionRole.controller;
    if (!isPublicRole && !isControllerGrant) {
      throw ArgumentError.value(
        requestedRole,
        'requestedRole',
        'Invitations can initially grant Participant or Display access only.',
      );
    }

    return Invitation._(
      protocolVersion: protocolVersion,
      sessionId: normalizedSessionId,
      transport: transport,
      endpoint: endpoint,
      joinUri: resolvedJoinUri,
      capability: normalizedCapability,
      sessionSecret: normalizedSessionSecret,
      requestedRole: requestedRole,
      expiresAt: expiresAt.toUtc(),
    );
  }

  const Invitation._({
    required this.protocolVersion,
    required this.sessionId,
    required this.transport,
    required this.endpoint,
    required this.joinUri,
    required this.capability,
    required this.sessionSecret,
    required this.requestedRole,
    required this.expiresAt,
  });

  final int protocolVersion;
  final String sessionId;
  final SessionTransportKind transport;

  /// The transport service endpoint used after the invitation is parsed.
  final Uri endpoint;

  /// The user-facing app URL opened by a QR code or shared link.
  final Uri joinUri;

  final String capability;
  final String sessionSecret;
  final SessionRole requestedRole;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());

  /// Returns a browser-openable URL with secrets in the fragment.
  ///
  /// URL fragments are not sent to the HTTP server during navigation.
  String toQrPayload() {
    final String encoded = base64UrlEncode(utf8.encode(jsonEncode(toJson())));
    return joinUri
        .replace(
          fragment: Uri(
            queryParameters: <String, String>{'invite': encoded},
          ).query,
        )
        .toString();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'transport': transport.name,
      'endpoint': endpoint.toString(),
      'joinUrl': joinUri.toString(),
      'capability': capability,
      'sessionSecret': sessionSecret,
      'requestedRole': requestedRole.name,
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  factory Invitation.fromQrPayload(String payload) {
    if (payload.length > maxInvitationQrPayloadLength) {
      throw const FormatException('The ChronoSync invitation is too large.');
    }
    final Uri uri = Uri.parse(payload);
    final String? encoded = Uri.splitQueryString(uri.fragment)['invite'];
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException(
        'The ChronoSync invitation has no invite fragment.',
      );
    }

    try {
      final Object? decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      if (decoded is! Map<Object?, Object?>) {
        throw const FormatException(
          'A ChronoSync invitation must contain a JSON object.',
        );
      }
      final Invitation invitation = Invitation.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (_withoutFragment(uri) != _withoutFragment(invitation.joinUri)) {
        throw const FormatException(
          'The invitation join URL does not match its QR URL.',
        );
      }
      return invitation;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('The ChronoSync invitation is malformed.');
    }
  }

  factory Invitation.fromJson(Map<String, Object?> json) {
    final int protocolVersion = _requiredInt(json, 'protocolVersion');
    if (protocolVersion != sessionProtocolVersion) {
      throw FormatException(
        'Unsupported session protocol version: $protocolVersion.',
      );
    }
    final SessionRole requestedRole = _enumByName(
      SessionRole.values,
      _requiredString(json, 'requestedRole'),
      'requestedRole',
    );
    return Invitation._validated(
      protocolVersion: protocolVersion,
      sessionId: _requiredString(json, 'sessionId'),
      transport: _enumByName(
        SessionTransportKind.values,
        _requiredString(json, 'transport'),
        'transport',
      ),
      endpoint: Uri.parse(_requiredString(json, 'endpoint')),
      joinUri: _optionalUri(json, 'joinUrl'),
      capability: _requiredString(json, 'capability'),
      sessionSecret: _requiredString(json, 'sessionSecret'),
      requestedRole: requestedRole,
      expiresAt: _requiredDateTime(json, 'expiresAt'),
      allowControllerGrant: requestedRole == SessionRole.controller,
    );
  }

  @override
  List<Object> get props => <Object>[
    protocolVersion,
    sessionId,
    transport,
    endpoint,
    joinUri,
    capability,
    sessionSecret,
    requestedRole,
    expiresAt,
  ];
}

/// An encrypted, transport-independent wire envelope.
///
/// Encryption adapters encode their nonce, ciphertext, and authentication tag
/// together in [encryptedPayload]. Domain payloads never travel in plaintext.
class SessionEnvelope extends Equatable {
  factory SessionEnvelope({
    required String sessionId,
    required String messageId,
    required String senderDeviceId,
    required int baseRevision,
    required DateTime sentAt,
    required SessionMessageKind kind,
    required String encryptedPayload,
    int protocolVersion = sessionProtocolVersion,
  }) {
    final String normalizedSessionId = sessionId.trim();
    final String normalizedMessageId = messageId.trim();
    final String normalizedSenderDeviceId = senderDeviceId.trim();
    final String normalizedPayload = encryptedPayload.trim();
    if (protocolVersion != sessionProtocolVersion) {
      throw ArgumentError.value(
        protocolVersion,
        'protocolVersion',
        'Unsupported session protocol version.',
      );
    }
    if (normalizedSessionId.isEmpty ||
        normalizedMessageId.isEmpty ||
        normalizedSenderDeviceId.isEmpty ||
        normalizedPayload.isEmpty) {
      throw ArgumentError(
        'Envelope IDs, sender, and encrypted payload cannot be empty.',
      );
    }
    if (normalizedSessionId.length > maxSessionDeviceIdLength ||
        normalizedMessageId.length > maxSessionDeviceIdLength ||
        normalizedSenderDeviceId.length > maxSessionDeviceIdLength) {
      throw ArgumentError(
        'Envelope identifiers cannot exceed $maxSessionDeviceIdLength '
        'characters.',
      );
    }
    if (normalizedPayload.length > maxSessionEncryptedPayloadLength) {
      throw ArgumentError.value(
        encryptedPayload,
        'encryptedPayload',
        'An encrypted session payload cannot exceed 256 KB.',
      );
    }
    if (baseRevision < 0) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'An envelope revision cannot be negative.',
      );
    }

    return SessionEnvelope._(
      protocolVersion: protocolVersion,
      sessionId: normalizedSessionId,
      messageId: normalizedMessageId,
      senderDeviceId: normalizedSenderDeviceId,
      baseRevision: baseRevision,
      sentAt: sentAt.toUtc(),
      kind: kind,
      encryptedPayload: normalizedPayload,
    );
  }

  const SessionEnvelope._({
    required this.protocolVersion,
    required this.sessionId,
    required this.messageId,
    required this.senderDeviceId,
    required this.baseRevision,
    required this.sentAt,
    required this.kind,
    required this.encryptedPayload,
  });

  final int protocolVersion;
  final String sessionId;
  final String messageId;
  final String senderDeviceId;
  final int baseRevision;
  final DateTime sentAt;
  final SessionMessageKind kind;
  final String encryptedPayload;

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'messageId': messageId,
      'senderDeviceId': senderDeviceId,
      'baseRevision': baseRevision,
      'sentAt': sentAt.toIso8601String(),
      'kind': kind.name,
      'encryptedPayload': encryptedPayload,
    };
  }

  factory SessionEnvelope.decode(String encoded) {
    if (encoded.length > maxSessionEnvelopeEncodedLength ||
        utf8.encode(encoded).length > maxSessionEnvelopeEncodedLength) {
      throw const FormatException('The encoded session envelope is too large.');
    }
    final Object? value;
    try {
      value = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('A session envelope is not valid JSON.');
    }
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('A session envelope must be a JSON object.');
    }
    return SessionEnvelope.fromJson(Map<String, Object?>.from(value));
  }

  factory SessionEnvelope.fromJson(Map<String, Object?> json) {
    final int protocolVersion = _requiredInt(json, 'protocolVersion');
    if (protocolVersion != sessionProtocolVersion) {
      throw FormatException(
        'Unsupported session protocol version: $protocolVersion.',
      );
    }
    return SessionEnvelope(
      protocolVersion: protocolVersion,
      sessionId: _requiredString(json, 'sessionId'),
      messageId: _requiredString(json, 'messageId'),
      senderDeviceId: _requiredString(json, 'senderDeviceId'),
      baseRevision: _requiredInt(json, 'baseRevision'),
      sentAt: _requiredDateTime(json, 'sentAt'),
      kind: _enumByName(
        SessionMessageKind.values,
        _requiredString(json, 'kind'),
        'kind',
      ),
      encryptedPayload: _requiredString(json, 'encryptedPayload'),
    );
  }

  @override
  List<Object> get props => <Object>[
    protocolVersion,
    sessionId,
    messageId,
    senderDeviceId,
    baseRevision,
    sentAt,
    kind,
    encryptedPayload,
  ];
}

Uri _withoutFragment(Uri uri) => uri.replace(fragment: '');

bool _isStrongRoomToken(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    return false;
  }
  try {
    final List<int> decoded = base64Url.decode(base64Url.normalize(value));
    final String canonical = base64UrlEncode(decoded).replaceAll('=', '');
    return decoded.length == 32 && canonical == value;
  } on Object {
    return false;
  }
}

Uri? _optionalUri(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    return null;
  }
  final Object? value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty URL.');
  }
  return Uri.parse(value);
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
