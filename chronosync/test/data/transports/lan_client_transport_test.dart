import 'dart:async';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/data/transports/lan_client_transport.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_web_socket_channel.dart';

void main() {
  test('uses the injected clock when validating invitation expiry', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'nearby-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://192.168.1.20:4567/'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2030),
    );
    int connectionAttempts = 0;
    final LanClientTransport transport = LanClientTransport(
      deviceId: 'private-device-id',
      now: () => DateTime.utc(2040),
      connectWebSocket: (Uri uri, Iterable<String> protocols) {
        connectionAttempts += 1;
        return FakeWebSocketChannel();
      },
    );
    addTearDown(transport.close);

    await expectLater(transport.join(invitation), throwsStateError);

    expect(connectionAttempts, 0);
    expect(transport.connectionState, SessionConnectionState.idle);
  });

  test('nearby protocols include an opaque room-scoped device token', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'nearby-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://192.168.1.20:4567/'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );

    final List<String> protocols =
        await LanClientTransport.webSocketProtocolsFor(
          invitation: invitation,
          deviceId: 'private-device-id',
        );

    expect(protocols, contains('chronosync.v1'));
    expect(protocols, contains('role.participant'));
    expect(protocols, contains('cap.${secrets.capability}'));
    expect(
      protocols.singleWhere((String value) => value.startsWith('device.')),
      isNot(contains('private-device-id')),
    );
  });

  test('host removal is terminal but ordinary loss reconnects', () {
    expect(LanClientTransport.shouldReconnectAfterClose(4003), isFalse);
    expect(LanClientTransport.shouldReconnectAfterClose(1006), isTrue);
    expect(LanClientTransport.shouldReconnectAfterClose(null), isTrue);
  });

  test('removed nearby clients stop without reconnecting', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'nearby-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://192.168.1.20:4567/'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final List<FakeWebSocketChannel> channels = <FakeWebSocketChannel>[];
    final LanClientTransport transport = LanClientTransport(
      deviceId: 'private-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      reconnectBaseDelay: const Duration(milliseconds: 1),
      connectWebSocket: (Uri uri, Iterable<String> protocols) {
        final FakeWebSocketChannel channel = FakeWebSocketChannel();
        channels.add(channel);
        return channel;
      },
    );
    addTearDown(() async {
      await transport.close();
      for (final FakeWebSocketChannel channel in channels) {
        await channel.dispose();
      }
    });

    await transport.join(invitation);
    await channels.single.closeRemotely(4003, 'Removed by host');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(transport.connectionState, SessionConnectionState.closed);
    expect(channels, hasLength(1));
  });

  test('nearby WebSocket URI contains no query or fragment marker', () {
    final Invitation invitation = Invitation(
      sessionId: 'nearby-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://192.168.1.20:4567/'),
      capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionSecret: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );

    final Uri socketUri = LanClientTransport.webSocketUriFor(invitation);

    expect(socketUri, Uri.parse('ws://192.168.1.20:4567/ws'));
    expect(socketUri.hasQuery, isFalse);
    expect(socketUri.hasFragment, isFalse);
  });

  test('accepts only host snapshots for the invited session', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'nearby-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://192.168.1.20:4567/'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel();
    final LanClientTransport transport = LanClientTransport(
      deviceId: 'private-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
    );
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });
    final List<ReceivedSessionEnvelope> received = <ReceivedSessionEnvelope>[];
    final StreamSubscription<ReceivedSessionEnvelope> subscription = transport
        .messages
        .listen(received.add);
    addTearDown(subscription.cancel);
    await transport.join(invitation);

    channel.addIncoming(
      _envelope(
        sessionId: 'another-session',
        kind: SessionMessageKind.snapshot,
        messageId: 'wrong-session',
      ).encode(),
    );
    channel.addIncoming(
      _envelope(
        sessionId: invitation.sessionId,
        kind: SessionMessageKind.command,
        messageId: 'wrong-kind',
      ).encode(),
    );
    channel.addIncoming(
      _envelope(
        sessionId: invitation.sessionId,
        kind: SessionMessageKind.snapshot,
        messageId: 'valid-snapshot',
      ).encode(),
    );
    await pumpEventQueue();

    expect(
      received.map((ReceivedSessionEnvelope value) => value.envelope.messageId),
      <String>['valid-snapshot'],
    );
  });
}

SessionEnvelope _envelope({
  required String sessionId,
  required SessionMessageKind kind,
  required String messageId,
}) {
  return SessionEnvelope(
    sessionId: sessionId,
    messageId: messageId,
    senderDeviceId: 'host-device',
    baseRevision: 0,
    sentAt: DateTime.utc(2026),
    kind: kind,
    encryptedPayload: 'opaque',
  );
}
