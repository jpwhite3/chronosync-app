import 'dart:convert';
import 'dart:typed_data';

import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:cryptography/cryptography.dart';

export 'package:chronosync/domain/session/session_device_token.dart';

final class SessionSecrets {
  const SessionSecrets({required this.sessionSecret, required this.capability});

  final String sessionSecret;
  final String capability;

  static Future<SessionSecrets> generate() async {
    final AesGcm algorithm = AesGcm.with256bits();
    final List<int> sessionKey = await (await algorithm.newSecretKey())
        .extractBytes();
    final List<int> capabilityKey = await (await algorithm.newSecretKey())
        .extractBytes();
    return SessionSecrets(
      sessionSecret: _unpaddedBase64Url(sessionKey),
      capability: _unpaddedBase64Url(capabilityKey),
    );
  }
}

String _unpaddedBase64Url(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Authenticated encryption for the protocol's otherwise-visible envelope.
///
/// The session ID, sender, revision, time, and message kind are bound as
/// additional authenticated data so none can be changed without detection.
final class SessionEnvelopeCrypto {
  SessionEnvelopeCrypto(String encodedSecret)
    : _secretKey = SecretKey(
        base64Url.decode(base64Url.normalize(encodedSecret)),
      );

  final AesGcm _algorithm = AesGcm.with256bits();
  final SecretKey _secretKey;

  Future<SessionEnvelope> seal({
    required String sessionId,
    required String messageId,
    required String senderDeviceId,
    required int baseRevision,
    required DateTime sentAt,
    required SessionMessageKind kind,
    required Map<String, Object?> payload,
  }) async {
    final DateTime sentAtUtc = sentAt.toUtc();
    final List<int> aad = _aad(
      sessionId: sessionId,
      messageId: messageId,
      senderDeviceId: senderDeviceId,
      baseRevision: baseRevision,
      sentAt: sentAtUtc,
      kind: kind,
    );
    final SecretBox box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: _secretKey,
      aad: aad,
    );
    return SessionEnvelope(
      sessionId: sessionId,
      messageId: messageId,
      senderDeviceId: senderDeviceId,
      baseRevision: baseRevision,
      sentAt: sentAtUtc,
      kind: kind,
      encryptedPayload: base64UrlEncode(box.concatenation()),
    );
  }

  Future<Map<String, Object?>> open(SessionEnvelope envelope) async {
    try {
      final List<int> concatenated = base64Url.decode(
        base64Url.normalize(envelope.encryptedPayload),
      );
      final SecretBox box = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: _algorithm.nonceLength,
        macLength: _algorithm.macAlgorithm.macLength,
      );
      final List<int> clearText = await _algorithm.decrypt(
        box,
        secretKey: _secretKey,
        aad: _aad(
          sessionId: envelope.sessionId,
          messageId: envelope.messageId,
          senderDeviceId: envelope.senderDeviceId,
          baseRevision: envelope.baseRevision,
          sentAt: envelope.sentAt,
          kind: envelope.kind,
        ),
      );
      final Object? decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map<Object?, Object?>) {
        throw const FormatException('A session payload must be a JSON object.');
      }
      return Map<String, Object?>.from(decoded);
    } on SecretBoxAuthenticationError {
      throw const FormatException('The session message failed authentication.');
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('The session message could not be opened.');
    }
  }

  List<int> _aad({
    required String sessionId,
    required String messageId,
    required String senderDeviceId,
    required int baseRevision,
    required DateTime sentAt,
    required SessionMessageKind kind,
  }) {
    return utf8.encode(
      '$sessionProtocolVersion|$sessionId|$messageId|$senderDeviceId|'
      '$baseRevision|${sentAt.toUtc().toIso8601String()}|${kind.name}',
    );
  }
}

final class RelayCiphertext {
  const RelayCiphertext({required this.nonce, required this.ciphertext});

  final String nonce;
  final String ciphertext;
}

/// Encrypts the complete domain envelope before handing it to a relay.
///
/// This second layer prevents the relay from seeing device IDs and message
/// kinds that are intentionally present in [SessionEnvelope]'s outer fields.
final class RelayPayloadCrypto {
  RelayPayloadCrypto(String encodedSecret)
    : _envelopeCrypto = SessionEnvelopeCrypto(encodedSecret);

  static const String _opaqueSender = 'relay_payload';
  static const int _nonceBytes = 12;

  final SessionEnvelopeCrypto _envelopeCrypto;

  Future<RelayCiphertext> seal(SessionEnvelope envelope) async {
    final SessionEnvelope wrapper = await _envelopeCrypto.seal(
      sessionId: envelope.sessionId,
      messageId: envelope.messageId,
      senderDeviceId: _opaqueSender,
      baseRevision: envelope.baseRevision,
      sentAt: envelope.sentAt,
      kind: envelope.kind,
      payload: <String, Object?>{'envelope': envelope.toJson()},
    );
    final Uint8List combined = base64Url.decode(
      base64Url.normalize(wrapper.encryptedPayload),
    );
    if (combined.length <= _nonceBytes) {
      throw StateError('The encrypted relay payload is unexpectedly short.');
    }
    return RelayCiphertext(
      nonce: base64UrlEncode(combined.sublist(0, _nonceBytes)),
      ciphertext: base64UrlEncode(combined.sublist(_nonceBytes)),
    );
  }

  Future<SessionEnvelope> open({
    required String sessionId,
    required String messageId,
    required int revision,
    required DateTime sentAt,
    required SessionMessageKind kind,
    required String nonce,
    required String ciphertext,
  }) async {
    final Uint8List nonceBytes = base64Url.decode(base64Url.normalize(nonce));
    final Uint8List ciphertextBytes = base64Url.decode(
      base64Url.normalize(ciphertext),
    );
    final Uint8List combined =
        Uint8List(nonceBytes.length + ciphertextBytes.length)
          ..setAll(0, nonceBytes)
          ..setAll(nonceBytes.length, ciphertextBytes);
    final SessionEnvelope wrapper = SessionEnvelope(
      sessionId: sessionId,
      messageId: messageId,
      senderDeviceId: _opaqueSender,
      baseRevision: revision,
      sentAt: sentAt,
      kind: kind,
      encryptedPayload: base64UrlEncode(combined),
    );
    final Map<String, Object?> clearText = await _envelopeCrypto.open(wrapper);
    final Object? envelopeValue = clearText['envelope'];
    if (envelopeValue is! Map<Object?, Object?>) {
      throw const FormatException(
        'The relay payload does not contain a session envelope.',
      );
    }
    final SessionEnvelope envelope = SessionEnvelope.fromJson(
      Map<String, Object?>.from(envelopeValue),
    );
    if (envelope.sessionId != sessionId ||
        envelope.messageId != messageId ||
        envelope.baseRevision != revision ||
        envelope.sentAt != sentAt.toUtc()) {
      throw const FormatException(
        'The relay metadata does not match its encrypted envelope.',
      );
    }
    return envelope;
  }
}
