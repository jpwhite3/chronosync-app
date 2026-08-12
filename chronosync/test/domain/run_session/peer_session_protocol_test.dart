import 'package:chronosync/domain/run_session/peer_session_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime expiry = DateTime.utc(2026, 7, 27, 10);

  PeerSessionInvitation createInvitation() {
    return PeerSessionInvitation(
      sessionId: 'session-1',
      hostPeerId: 'host-1',
      hostPublicKey: 'public-key',
      sessionSecret: 'random-secret',
      expiresAt: expiry,
    );
  }

  group('PeerSessionInvitation', () {
    test('round-trips through a QR-safe payload', () {
      final PeerSessionInvitation invitation = createInvitation();

      final PeerSessionInvitation decoded = PeerSessionInvitation.fromQrPayload(
        invitation.toQrPayload(),
      );

      expect(decoded.protocolVersion, peerSessionProtocolVersion);
      expect(decoded.sessionId, invitation.sessionId);
      expect(decoded.hostPeerId, invitation.hostPeerId);
      expect(decoded.hostPublicKey, invitation.hostPublicKey);
      expect(decoded.sessionSecret, invitation.sessionSecret);
      expect(decoded.expiresAt, invitation.expiresAt);
      expect(
        decoded.isExpiredAt(expiry.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(decoded.isExpiredAt(expiry), isTrue);
    });

    test('rejects a non-ChronoSync QR code', () {
      expect(
        () => PeerSessionInvitation.fromQrPayload('https://example.com/join'),
        throwsFormatException,
      );
    });
  });

  group('PeerSessionMessage', () {
    test('round-trips a versioned JSON message', () {
      const PeerSessionMessage message = PeerSessionMessage(
        sessionId: 'session-1',
        messageId: 'message-1',
        type: PeerSessionMessageType.acknowledgement,
        payload: <String, Object?>{
          'stepIndex': 2,
          'displayName': 'Stage manager',
        },
      );

      final PeerSessionMessage decoded = PeerSessionMessage.decode(
        message.encode(),
      );

      expect(decoded.sessionId, message.sessionId);
      expect(decoded.messageId, message.messageId);
      expect(decoded.type, PeerSessionMessageType.acknowledgement);
      expect(decoded.payload, message.payload);
    });

    test('rejects an unsupported protocol version', () {
      expect(
        () => PeerSessionMessage.fromJson(<String, Object?>{
          'protocolVersion': 2,
          'sessionId': 'session-1',
          'messageId': 'message-1',
          'type': 'heartbeat',
          'payload': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });
  });
}
