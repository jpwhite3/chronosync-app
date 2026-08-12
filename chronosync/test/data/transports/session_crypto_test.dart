import 'dart:convert';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated secrets are 256-bit URL-safe protocol tokens', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();

    expect(secrets.sessionSecret, isNot(contains('=')));
    expect(secrets.capability, isNot(contains('=')));
    expect(
      base64Url.decode(base64Url.normalize(secrets.sessionSecret)),
      hasLength(32),
    );
    expect(
      base64Url.decode(base64Url.normalize(secrets.capability)),
      hasLength(32),
    );
  });

  test('device transport tokens are opaque, stable, and room scoped', () async {
    final SessionSecrets firstRoom = await SessionSecrets.generate();
    final SessionSecrets secondRoom = await SessionSecrets.generate();

    final String token = await SessionDeviceToken.derive(
      deviceId: 'private-device-id',
      sessionSecret: firstRoom.sessionSecret,
    );

    expect(token, hasLength(43));
    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(token, isNot(contains('private-device-id')));
    expect(
      await SessionDeviceToken.derive(
        deviceId: 'private-device-id',
        sessionSecret: firstRoom.sessionSecret,
      ),
      token,
    );
    expect(
      await SessionDeviceToken.derive(
        deviceId: 'another-device-id',
        sessionSecret: firstRoom.sessionSecret,
      ),
      isNot(token),
    );
    expect(
      await SessionDeviceToken.derive(
        deviceId: 'private-device-id',
        sessionSecret: secondRoom.sessionSecret,
      ),
      isNot(token),
    );
  });

  test('authenticates envelope metadata and payload', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final SessionEnvelopeCrypto crypto = SessionEnvelopeCrypto(
      secrets.sessionSecret,
    );
    final DateTime sentAt = DateTime.utc(2026, 7, 28, 12);
    final SessionEnvelope envelope = await crypto.seal(
      sessionId: 'session-1',
      messageId: 'message-1',
      senderDeviceId: 'device-1',
      baseRevision: 4,
      sentAt: sentAt,
      kind: SessionMessageKind.command,
      payload: <String, Object?>{
        'type': 'command',
        'value': <String, Object?>{'seconds': 60},
      },
    );

    expect(await crypto.open(envelope), <String, Object?>{
      'type': 'command',
      'value': <String, Object?>{'seconds': 60},
    });

    final SessionEnvelope tampered = SessionEnvelope(
      sessionId: envelope.sessionId,
      messageId: envelope.messageId,
      senderDeviceId: envelope.senderDeviceId,
      baseRevision: envelope.baseRevision + 1,
      sentAt: envelope.sentAt,
      kind: envelope.kind,
      encryptedPayload: envelope.encryptedPayload,
    );
    expect(() => crypto.open(tampered), throwsA(isA<FormatException>()));
  });

  test('relay encryption hides and restores the complete envelope', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final SessionEnvelopeCrypto inner = SessionEnvelopeCrypto(
      secrets.sessionSecret,
    );
    final RelayPayloadCrypto relay = RelayPayloadCrypto(secrets.sessionSecret);
    final SessionEnvelope envelope = await inner.seal(
      sessionId: 'session-1',
      messageId: 'message-1',
      senderDeviceId: 'private-device-id',
      baseRevision: 2,
      sentAt: DateTime.utc(2026, 7, 28),
      kind: SessionMessageKind.snapshot,
      payload: <String, Object?>{'state': 'running'},
    );

    final RelayCiphertext ciphertext = await relay.seal(envelope);
    final SessionEnvelope restored = await relay.open(
      sessionId: envelope.sessionId,
      messageId: envelope.messageId,
      revision: envelope.baseRevision,
      sentAt: envelope.sentAt,
      kind: envelope.kind,
      nonce: ciphertext.nonce,
      ciphertext: ciphertext.ciphertext,
    );

    expect(restored, envelope);
    expect(ciphertext.ciphertext, isNot(contains('private-device-id')));
  });
}
