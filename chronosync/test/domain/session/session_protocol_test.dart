import 'dart:convert';

import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fixtures.dart';

void main() {
  final String validCapability = 'A' * 43;
  final String validSessionSecret = 'A' * 43;

  Invitation invitation({
    SessionRole role = SessionRole.participant,
    DateTime? expiresAt,
  }) {
    return Invitation(
      sessionId: 'session-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse(
        'https://relay.example.com/v1/rooms/session-1/connect',
      ),
      joinUri: Uri.parse('https://app.example.com/join'),
      capability: validCapability,
      sessionSecret: validSessionSecret,
      requestedRole: role,
      expiresAt: expiresAt ?? fixtureStart.add(const Duration(hours: 1)),
    );
  }

  group('Invitation', () {
    test('round-trips a browser-safe QR URL', () {
      final Invitation original = invitation();
      final String payload = original.toQrPayload();
      final Uri uri = Uri.parse(payload);
      final Invitation decoded = Invitation.fromQrPayload(payload);

      expect(decoded, original);
      expect(uri.scheme, 'https');
      expect(uri.host, 'app.example.com');
      expect(
        decoded.endpoint,
        Uri.parse('https://relay.example.com/v1/rooms/session-1/connect'),
      );
      expect(uri.query, isEmpty);
      expect(uri.fragment, startsWith('invite='));
      expect(payload, isNot(contains(validSessionSecret)));
      expect(payload, isNot(contains(validCapability)));
    });

    test('expiry is inclusive at the expiry instant', () {
      final DateTime expiry = fixtureStart.add(const Duration(minutes: 5));
      final Invitation value = invitation(expiresAt: expiry);

      expect(
        value.isExpiredAt(expiry.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(value.isExpiredAt(expiry), isTrue);
    });

    test(
      'public invitation rejects Controller but grant factory permits it',
      () {
        expect(
          () => invitation(role: SessionRole.controller),
          throwsArgumentError,
        );

        final Invitation grant = Invitation.controllerGrant(
          sessionId: 'session-1',
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse(
            'https://relay.example.com/v1/rooms/session-1/connect',
          ),
          joinUri: Uri.parse('https://app.example.com/join'),
          capability: validCapability,
          sessionSecret: validSessionSecret,
          expiresAt: fixtureStart.add(const Duration(minutes: 10)),
        );

        expect(grant.requestedRole, SessionRole.controller);
        expect(Invitation.fromQrPayload(grant.toQrPayload()), grant);
      },
    );

    test('online relay requires HTTPS', () {
      expect(
        () => Invitation(
          sessionId: 'session-1',
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse('http://sessions.example.com/room/session-1'),
          capability: validCapability,
          sessionSecret: validSessionSecret,
          requestedRole: SessionRole.participant,
          expiresAt: fixtureStart.add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
    });

    test('transport endpoint must be an absolute network URL', () {
      expect(
        () => Invitation(
          sessionId: 'session-1',
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse('https:relative-endpoint'),
          joinUri: Uri.parse('https://app.example.com/join'),
          capability: validCapability,
          sessionSecret: validSessionSecret,
          requestedRole: SessionRole.participant,
          expiresAt: fixtureStart.add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a QR URL whose user-facing join URL was changed', () {
      final Uri payload = Uri.parse(invitation().toQrPayload());
      final String tampered = payload
          .replace(host: 'attacker.example.com')
          .toString();

      expect(() => Invitation.fromQrPayload(tampered), throwsFormatException);
    });

    test('accepts legacy JSON without a separate join URL', () {
      final Map<String, Object?> json = invitation().toJson()
        ..remove('joinUrl');
      final Invitation decoded = Invitation.fromJson(json);

      expect(decoded.joinUri, decoded.endpoint);
    });

    test('rejects a join URL that already contains a fragment', () {
      expect(
        () => Invitation(
          sessionId: 'session-1',
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse('https://relay.example.com'),
          joinUri: Uri.parse('https://app.example.com/#unsafe'),
          capability: validCapability,
          sessionSecret: validSessionSecret,
          requestedRole: SessionRole.participant,
          expiresAt: fixtureStart.add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
    });

    test('rejects weak room secrets and capabilities', () {
      for (final ({String capability, String secret}) credentials
          in <({String capability, String secret})>[
            (capability: 'short', secret: validSessionSecret),
            (capability: validCapability, secret: 'short'),
            (capability: '*' * 43, secret: validSessionSecret),
          ]) {
        expect(
          () => Invitation(
            sessionId: 'session-1',
            transport: SessionTransportKind.onlineRelay,
            endpoint: Uri.parse('https://relay.example.com/room'),
            joinUri: Uri.parse('https://app.example.com/join'),
            capability: credentials.capability,
            sessionSecret: credentials.secret,
            requestedRole: SessionRole.participant,
            expiresAt: fixtureStart.add(const Duration(minutes: 5)),
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects non-canonical base64url room tokens', () {
      final String nonCanonicalCapability = '${'A' * 42}B';

      expect(
        () => Invitation(
          sessionId: 'session-1',
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse('https://relay.example.com/room'),
          joinUri: Uri.parse('https://app.example.com/join'),
          capability: nonCanonicalCapability,
          sessionSecret: validSessionSecret,
          requestedRole: SessionRole.participant,
          expiresAt: fixtureStart.add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
    });

    test('online invitations reject an insecure user-facing join URL', () {
      expect(
        () => Invitation(
          sessionId: 'session-1',
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse('https://relay.example.com/room'),
          joinUri: Uri.parse('http://app.example.com/join'),
          capability: validCapability,
          sessionSecret: validSessionSecret,
          requestedRole: SessionRole.participant,
          expiresAt: fixtureStart.add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
    });

    test('bounds invitation identifiers and pasted QR payloads', () {
      expect(
        () => Invitation(
          sessionId: 's' * (maxSessionDeviceIdLength + 1),
          transport: SessionTransportKind.onlineRelay,
          endpoint: Uri.parse('https://relay.example.com/room'),
          joinUri: Uri.parse('https://app.example.com/join'),
          capability: validCapability,
          sessionSecret: validSessionSecret,
          requestedRole: SessionRole.participant,
          expiresAt: fixtureStart.add(const Duration(minutes: 5)),
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            Invitation.fromQrPayload('x' * (maxInvitationQrPayloadLength + 1)),
        throwsFormatException,
      );
    });
  });

  group('SessionEnvelope', () {
    test('round-trips every required versioned envelope field', () {
      final SessionEnvelope original = SessionEnvelope(
        sessionId: 'session-1',
        messageId: 'message-1',
        senderDeviceId: 'device-1',
        baseRevision: 7,
        sentAt: fixtureStart,
        kind: SessionMessageKind.command,
        encryptedPayload: 'nonce.ciphertext.mac',
      );

      expect(SessionEnvelope.decode(original.encode()), original);
      expect(original.toJson().keys, <String>[
        'protocolVersion',
        'sessionId',
        'messageId',
        'senderDeviceId',
        'baseRevision',
        'sentAt',
        'kind',
        'encryptedPayload',
      ]);
    });

    test('rejects malformed JSON and unsupported protocol versions', () {
      expect(() => SessionEnvelope.decode('[]'), throwsFormatException);
      expect(
        () => SessionEnvelope.fromJson(<String, Object?>{
          'protocolVersion': 999,
          'sessionId': 'session-1',
          'messageId': 'message-1',
          'senderDeviceId': 'device-1',
          'baseRevision': 0,
          'sentAt': fixtureStart.toIso8601String(),
          'kind': 'heartbeat',
          'encryptedPayload': 'ciphertext',
        }),
        throwsFormatException,
      );
    });

    test('wire timestamps require an explicit time zone', () {
      final Map<String, Object?> missingZone = SessionEnvelope(
        sessionId: 'session-1',
        messageId: 'message-1',
        senderDeviceId: 'device-1',
        baseRevision: 0,
        sentAt: fixtureStart,
        kind: SessionMessageKind.heartbeat,
        encryptedPayload: 'ciphertext',
      ).toJson()..['sentAt'] = '2026-07-28T12:00:00';

      expect(
        () => SessionEnvelope.fromJson(missingZone),
        throwsFormatException,
      );
    });

    test(
      'rejects oversized encoded envelopes before accepting unknown data',
      () {
        final Map<String, Object?> json = SessionEnvelope(
          sessionId: 'session-1',
          messageId: 'message-1',
          senderDeviceId: 'device-1',
          baseRevision: 0,
          sentAt: fixtureStart,
          kind: SessionMessageKind.heartbeat,
          encryptedPayload: 'ciphertext',
        ).toJson()..['padding'] = 'x' * maxSessionEnvelopeEncodedLength;

        expect(
          () => SessionEnvelope.decode(jsonEncode(json)),
          throwsFormatException,
        );
      },
    );
  });
}
