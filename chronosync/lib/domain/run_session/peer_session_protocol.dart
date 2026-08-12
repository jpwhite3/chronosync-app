import 'dart:convert';

/// The protocol revision understood by this app build.
const int peerSessionProtocolVersion = 1;

enum PeerSessionMessageType {
  joinRequest,
  sessionSnapshot,
  revisionRequest,
  activityBatch,
  acknowledgement,
  heartbeat,
  sessionEnded,
}

/// The short-lived capability transferred in a host's QR code.
///
/// Native adapters must encrypt their transport with [sessionSecret] and verify
/// the host identity represented by [hostPublicKey]. This class only encodes the
/// invitation; it does not create cryptographic keys itself.
class PeerSessionInvitation {
  const PeerSessionInvitation({
    required this.sessionId,
    required this.hostPeerId,
    required this.hostPublicKey,
    required this.sessionSecret,
    required this.expiresAt,
    this.protocolVersion = peerSessionProtocolVersion,
    this.transportServiceId = 'chronosync-runbook',
  });

  final int protocolVersion;
  final String sessionId;
  final String hostPeerId;
  final String hostPublicKey;
  final String sessionSecret;
  final DateTime expiresAt;
  final String transportServiceId;

  bool isExpiredAt(DateTime now) => !expiresAt.toUtc().isAfter(now.toUtc());

  String toQrPayload() {
    final String data = base64UrlEncode(utf8.encode(jsonEncode(toJson())));
    return Uri(
      scheme: 'chronosync',
      host: 'join',
      queryParameters: <String, String>{'data': data},
    ).toString();
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'hostPeerId': hostPeerId,
      'hostPublicKey': hostPublicKey,
      'sessionSecret': sessionSecret,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'transportServiceId': transportServiceId,
    };
  }

  factory PeerSessionInvitation.fromQrPayload(String payload) {
    final Uri uri = Uri.parse(payload);
    if (uri.scheme != 'chronosync' || uri.host != 'join') {
      throw const FormatException('This is not a ChronoSync join invitation.');
    }

    final String? data = uri.queryParameters['data'];
    if (data == null || data.isEmpty) {
      throw const FormatException('The join invitation has no data.');
    }

    try {
      final Object decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(data))),
      );
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'The join invitation has an invalid payload.',
        );
      }
      return PeerSessionInvitation.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('The join invitation could not be read.');
    }
  }

  factory PeerSessionInvitation.fromJson(Map<String, Object?> json) {
    final int protocolVersion = json['protocolVersion']! as int;
    if (protocolVersion != peerSessionProtocolVersion) {
      throw FormatException('Unsupported protocol version: $protocolVersion.');
    }

    return PeerSessionInvitation(
      protocolVersion: protocolVersion,
      sessionId: json['sessionId']! as String,
      hostPeerId: json['hostPeerId']! as String,
      hostPublicKey: json['hostPublicKey']! as String,
      sessionSecret: json['sessionSecret']! as String,
      expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
      transportServiceId: json['transportServiceId']! as String,
    );
  }
}

/// A versioned, transport-independent message for a nearby runbook session.
class PeerSessionMessage {
  const PeerSessionMessage({
    required this.sessionId,
    required this.messageId,
    required this.type,
    required this.payload,
    this.protocolVersion = peerSessionProtocolVersion,
  });

  final int protocolVersion;
  final String sessionId;
  final String messageId;
  final PeerSessionMessageType type;
  final Map<String, Object?> payload;

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'messageId': messageId,
      'type': type.name,
      'payload': payload,
    };
  }

  factory PeerSessionMessage.decode(String encoded) {
    final Object decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('A peer message must be a JSON object.');
    }
    return PeerSessionMessage.fromJson(Map<String, Object?>.from(decoded));
  }

  factory PeerSessionMessage.fromJson(Map<String, Object?> json) {
    final int protocolVersion = json['protocolVersion']! as int;
    if (protocolVersion != peerSessionProtocolVersion) {
      throw FormatException('Unsupported protocol version: $protocolVersion.');
    }

    final Object? payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException(
        'A peer message must contain an object payload.',
      );
    }

    return PeerSessionMessage(
      protocolVersion: protocolVersion,
      sessionId: json['sessionId']! as String,
      messageId: json['messageId']! as String,
      type: PeerSessionMessageType.values.byName(json['type']! as String),
      payload: Map<String, Object?>.from(payload),
    );
  }
}

/// The common boundary implemented by iOS and Android nearby transports.
///
/// No implementation may rely on a server. The platform layer owns discovery,
/// permission prompts, encrypted delivery, and reconnect attempts.
abstract interface class PeerSessionTransport {
  Stream<PeerSessionMessage> get messages;

  Future<void> host(PeerSessionInvitation invitation);

  Future<void> join(PeerSessionInvitation invitation);

  Future<void> send(PeerSessionMessage message);

  Future<void> close();
}
