import 'dart:async';
import 'dart:convert';

import 'package:chronosync/data/transports/online_relay_transport.dart';
import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_web_socket_channel.dart';

void main() {
  test(
    'WebSocket protocols include an opaque room-scoped device token',
    () async {
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'room-1',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: DateTime.utc(2099),
      );

      final List<String> protocols =
          await OnlineRelayTransport.webSocketProtocolsFor(
            invitation: invitation,
            deviceId: 'private-device-id',
            isHost: false,
          );

      expect(protocols, contains('chronosync.v1'));
      expect(protocols, contains('role.participant'));
      expect(protocols, contains('cap.${secrets.capability}'));
      expect(
        protocols.singleWhere((String value) => value.startsWith('device.')),
        isNot(contains('private-device-id')),
      );
    },
  );

  test('removal and relay host replacement are terminal close codes', () {
    expect(
      OnlineRelayTransport.shouldReconnectAfterClose(
        closeCode: 4003,
        isHost: false,
      ),
      isFalse,
    );
    expect(
      OnlineRelayTransport.shouldReconnectAfterClose(
        closeCode: 4001,
        isHost: true,
      ),
      isFalse,
    );
    expect(
      OnlineRelayTransport.shouldReconnectAfterClose(
        closeCode: 4001,
        isHost: false,
      ),
      isTrue,
    );
    expect(
      OnlineRelayTransport.shouldReconnectAfterClose(
        closeCode: 1006,
        isHost: true,
      ),
      isTrue,
    );
  });

  test('join times out when the WebSocket handshake never completes', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel(
      ready: Completer<void>().future,
    );
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'private-device-id',
      connectionTimeout: const Duration(milliseconds: 1),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
    );
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });

    await expectLater(
      transport.join(invitation),
      throwsA(isA<TimeoutException>()),
    );
    expect(transport.connectionState, SessionConnectionState.stale);
  });

  test(
    'a relay room closure is terminal even with a normal close code',
    () async {
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'room-1',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: DateTime.utc(2099),
      );
      final List<FakeWebSocketChannel> channels = <FakeWebSocketChannel>[];
      final OnlineRelayTransport transport = OnlineRelayTransport(
        deviceId: 'private-device-id',
        heartbeatInterval: const Duration(minutes: 1),
        heartbeatTimeout: const Duration(minutes: 2),
        hostPresenceTimeout: const Duration(minutes: 2),
        reconnectBaseDelay: const Duration(hours: 1),
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
      channels.single.addIncoming(
        jsonEncode(<String, Object?>{
          'type': 'welcome',
          'connectionId': 'guest-connection',
          'hostConnected': true,
        }),
      );
      await pumpEventQueue();
      expect(transport.connectionState, SessionConnectionState.connected);

      channels.single.addIncoming(
        jsonEncode(<String, Object?>{'type': 'room_closed', 'reason': 'ended'}),
      );
      await pumpEventQueue();

      expect(transport.connectionState, SessionConnectionState.closed);
      await channels.single.closeRemotely(1000, 'Room ended');
      await pumpEventQueue();
      expect(channels, hasLength(1));
    },
  );

  test('relay frames are decrypted and delivered in wire order', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel();
    final List<String> openCalls = <String>[];
    final Map<String, Completer<SessionEnvelope>> openings =
        <String, Completer<SessionEnvelope>>{
          'snapshot-first': Completer<SessionEnvelope>(),
          'snapshot-second': Completer<SessionEnvelope>(),
        };
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'private-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
      openRelayPayload:
          ({
            required RelayPayloadCrypto crypto,
            required String sessionId,
            required String messageId,
            required int revision,
            required DateTime sentAt,
            required SessionMessageKind kind,
            required String nonce,
            required String ciphertext,
          }) {
            openCalls.add(messageId);
            return openings[messageId]!.future;
          },
    );
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });
    final List<String> delivered = <String>[];
    final StreamSubscription<ReceivedSessionEnvelope> subscription = transport
        .messages
        .listen(
          (ReceivedSessionEnvelope message) =>
              delivered.add(message.envelope.messageId),
        );
    addTearDown(subscription.cancel);
    await transport.join(invitation);

    channel.addIncoming(_relaySnapshotFrame('snapshot-first', revision: 1));
    channel.addIncoming(_relaySnapshotFrame('snapshot-second', revision: 2));
    await pumpEventQueue();

    expect(openCalls, <String>['snapshot-first']);
    openings['snapshot-first']!.complete(
      _relayEnvelope('snapshot-first', revision: 1),
    );
    await pumpEventQueue();
    expect(openCalls, <String>['snapshot-first', 'snapshot-second']);
    expect(delivered, <String>['snapshot-first']);

    openings['snapshot-second']!.complete(
      _relayEnvelope('snapshot-second', revision: 2),
    );
    await pumpEventQueue();
    expect(delivered, <String>['snapshot-first', 'snapshot-second']);
  });

  test('removed guests stop without scheduling another connection', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final List<FakeWebSocketChannel> channels = <FakeWebSocketChannel>[];
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'private-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
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

  test('a guest revocation rejection is not queued for reconnect', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final List<FakeWebSocketChannel> channels = <FakeWebSocketChannel>[];
    final List<List<Map<String, Object?>>> outgoing =
        <List<Map<String, Object?>>>[];
    final Completer<void> reconnected = Completer<void>();
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'private-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      reconnectBaseDelay: const Duration(microseconds: 1),
      connectWebSocket: (Uri uri, Iterable<String> protocols) {
        final FakeWebSocketChannel channel = FakeWebSocketChannel();
        final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
        channel.outgoing.listen((Object? frame) {
          if (frame is String) {
            final Object? decoded = jsonDecode(frame);
            if (decoded is Map<Object?, Object?>) {
              frames.add(Map<String, Object?>.from(decoded));
            }
          }
        });
        channels.add(channel);
        outgoing.add(frames);
        if (channels.length == 2) {
          reconnected.complete();
        }
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
    final String token = await SessionDeviceToken.derive(
      deviceId: 'another-device',
      sessionSecret: secrets.sessionSecret,
    );

    await expectLater(transport.revokeDevice(token), throwsStateError);
    await channels.first.closeRemotely(1006, 'Network lost');
    await reconnected.future.timeout(const Duration(seconds: 1));
    await pumpEventQueue();

    expect(
      outgoing[1].where(
        (Map<String, Object?> frame) => frame['type'] == 'disconnect_peer',
      ),
      isEmpty,
    );
  });

  test('replaced relay hosts stop without reconnecting', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final List<FakeWebSocketChannel> channels = <FakeWebSocketChannel>[];
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'host-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
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

    await transport.host(invitation);
    await channels.single.closeRemotely(4001, 'Host reconnected elsewhere');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(transport.connectionState, SessionConnectionState.closed);
    expect(channels, hasLength(1));
  });

  test('peer removals wait for correlated relay acknowledgements', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel();
    final List<Map<String, Object?>> outgoing = <Map<String, Object?>>[];
    channel.outgoing.listen((Object? frame) {
      if (frame is String) {
        final Object? decoded = jsonDecode(frame);
        if (decoded is Map<Object?, Object?>) {
          outgoing.add(Map<String, Object?>.from(decoded));
        }
      }
    });
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'host-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
    );
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });
    await transport.host(invitation);
    final String deviceToken = await SessionDeviceToken.derive(
      deviceId: 'guest-device-id',
      sessionSecret: secrets.sessionSecret,
    );

    bool completed = false;
    final Future<void> revocation = transport
        .revokeDevice(deviceToken)
        .whenComplete(() => completed = true);
    final Map<String, Object?> request = await _waitForMessage(
      outgoing,
      'disconnect_peer',
    );
    expect(completed, isFalse);
    expect(request['deviceToken'], deviceToken);

    channel.addIncoming(
      jsonEncode(<String, Object?>{
        'type': 'peer_disconnect_result',
        'requestId': request['requestId']!,
        'deviceToken': deviceToken,
        'status': 'not_found',
        'disconnectedConnections': 0,
      }),
    );
    await revocation;
    expect(completed, isTrue);

    bool connectionCompleted = false;
    final Future<void> connectionRemoval = transport
        .disconnectPeer('connection-to-reject')
        .whenComplete(() => connectionCompleted = true);
    final Map<String, Object?> connectionRequest = await _waitForMessage(
      outgoing,
      'disconnect_connection',
    );
    expect(connectionCompleted, isFalse);
    expect(connectionRequest['connectionId'], 'connection-to-reject');
    channel.addIncoming(
      jsonEncode(<String, Object?>{
        'type': 'peer_disconnect_result',
        'requestId': connectionRequest['requestId']!,
        'connectionId': 'connection-to-reject',
        'status': 'disconnected',
        'disconnectedConnections': 1,
      }),
    );
    await connectionRemoval;
    expect(connectionCompleted, isTrue);
  });

  test(
    'peer role updates wait for correlated relay acknowledgements',
    () async {
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'room-1',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: DateTime.utc(2099),
      );
      final FakeWebSocketChannel channel = FakeWebSocketChannel();
      final List<Map<String, Object?>> outgoing = <Map<String, Object?>>[];
      channel.outgoing.listen((Object? frame) {
        if (frame is String) {
          final Object? decoded = jsonDecode(frame);
          if (decoded is Map<Object?, Object?>) {
            outgoing.add(Map<String, Object?>.from(decoded));
          }
        }
      });
      final OnlineRelayTransport transport = OnlineRelayTransport(
        deviceId: 'host-device-id',
        heartbeatInterval: const Duration(minutes: 1),
        heartbeatTimeout: const Duration(minutes: 2),
        hostPresenceTimeout: const Duration(minutes: 2),
        connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
      );
      addTearDown(() async {
        await transport.close();
        await channel.dispose();
      });
      await transport.host(invitation);
      final String deviceToken = await SessionDeviceToken.derive(
        deviceId: 'guest-device-id',
        sessionSecret: secrets.sessionSecret,
      );

      bool completed = false;
      final Future<void> roleUpdate = transport
          .updatePeerRole(deviceToken, SessionRole.controller)
          .whenComplete(() => completed = true);
      final Map<String, Object?> request = await _waitForMessage(
        outgoing,
        'set_peer_role',
      );
      expect(completed, isFalse);
      expect(request['deviceToken'], deviceToken);
      expect(request['role'], 'controller');

      channel.addIncoming(
        jsonEncode(<String, Object?>{
          'type': 'peer_role_result',
          'requestId': request['requestId']!,
          'deviceToken': deviceToken,
          'role': 'controller',
          'status': 'updated',
          'updatedConnections': 1,
        }),
      );
      await roleUpdate;
      expect(completed, isTrue);
    },
  );

  test('relay guests cannot update peer roles', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel();
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'guest-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
    );
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });
    await transport.join(invitation);
    final String deviceToken = await SessionDeviceToken.derive(
      deviceId: 'another-device',
      sessionSecret: secrets.sessionSecret,
    );

    await expectLater(
      transport.updatePeerRole(deviceToken, SessionRole.controller),
      throwsStateError,
    );
  });

  test('relay role changes keep the authenticated connection bound', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel();
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'host-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
    );
    final List<SessionPeerEvent> events = <SessionPeerEvent>[];
    transport.peerEvents.listen(events.add);
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });
    await transport.host(invitation);
    channel.addIncoming(
      jsonEncode(<String, Object?>{
        'type': 'welcome',
        'connectionId': 'host-connection',
        'hostConnected': true,
      }),
    );
    channel.addIncoming(
      _presenceFrame(role: SessionRole.participant, token: _token('p')),
    );
    await _waitUntil(() => events.length == 1);
    channel.addIncoming(
      _presenceFrame(role: SessionRole.controller, token: _token('p')),
    );
    await _waitUntil(() => events.length == 2);

    expect(
      events.map((SessionPeerEvent event) => event.presence),
      everyElement(SessionPeerPresence.connected),
    );
    expect(
      events.map((SessionPeerEvent event) => event.peer.role),
      <SessionRole>[SessionRole.participant, SessionRole.controller],
    );
  });

  test('relay revocation failure and timeout do not report success', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final FakeWebSocketChannel channel = FakeWebSocketChannel();
    final List<Map<String, Object?>> outgoing = <Map<String, Object?>>[];
    channel.outgoing.listen((Object? frame) {
      if (frame is String) {
        final Object? decoded = jsonDecode(frame);
        if (decoded is Map<Object?, Object?>) {
          outgoing.add(Map<String, Object?>.from(decoded));
        }
      }
    });
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'host-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      peerDisconnectTimeout: const Duration(milliseconds: 25),
      connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
    );
    addTearDown(() async {
      await transport.close();
      await channel.dispose();
    });
    await transport.host(invitation);
    final String failedToken = await SessionDeviceToken.derive(
      deviceId: 'failed-device',
      sessionSecret: secrets.sessionSecret,
    );
    final Future<void> failedRevocation = transport.revokeDevice(failedToken);
    final Map<String, Object?> failedRequest = await _waitForMessage(
      outgoing,
      'disconnect_peer',
    );
    channel.addIncoming(
      jsonEncode(<String, Object?>{
        'type': 'peer_disconnect_result',
        'requestId': failedRequest['requestId']!,
        'deviceToken': failedToken,
        'status': 'failed',
        'disconnectedConnections': 0,
        'errorCode': 'storage_unavailable',
      }),
    );
    await expectLater(failedRevocation, throwsStateError);

    final String timedOutToken = await SessionDeviceToken.derive(
      deviceId: 'timed-out-device',
      sessionSecret: secrets.sessionSecret,
    );
    await expectLater(
      transport.revokeDevice(timedOutToken),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('unacknowledged revocation is retried after host reconnect', () async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );
    final List<FakeWebSocketChannel> channels = <FakeWebSocketChannel>[];
    final List<List<Map<String, Object?>>> outgoing =
        <List<Map<String, Object?>>>[];
    final OnlineRelayTransport transport = OnlineRelayTransport(
      deviceId: 'host-device-id',
      heartbeatInterval: const Duration(minutes: 1),
      heartbeatTimeout: const Duration(minutes: 2),
      hostPresenceTimeout: const Duration(minutes: 2),
      peerDisconnectTimeout: const Duration(seconds: 1),
      reconnectBaseDelay: const Duration(milliseconds: 1),
      connectWebSocket: (Uri uri, Iterable<String> protocols) {
        final FakeWebSocketChannel channel = FakeWebSocketChannel();
        final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
        channel.outgoing.listen((Object? frame) {
          if (frame is String) {
            final Object? decoded = jsonDecode(frame);
            if (decoded is Map<Object?, Object?>) {
              frames.add(Map<String, Object?>.from(decoded));
            }
          }
        });
        channels.add(channel);
        outgoing.add(frames);
        return channel;
      },
    );
    addTearDown(() async {
      await transport.close();
      for (final FakeWebSocketChannel channel in channels) {
        await channel.dispose();
      }
    });
    await transport.host(invitation);
    final String deviceToken = await SessionDeviceToken.derive(
      deviceId: 'guest-device-id',
      sessionSecret: secrets.sessionSecret,
    );
    final Future<void> revocation = transport.revokeDevice(deviceToken);
    final Map<String, Object?> firstRequest = await _waitForMessage(
      outgoing.first,
      'disconnect_peer',
    );

    await channels.first.closeRemotely(1006, 'Network lost');
    await _waitUntil(() => channels.length == 2);
    final Map<String, Object?> retriedRequest = await _waitForMessage(
      outgoing[1],
      'disconnect_peer',
    );
    expect(retriedRequest['requestId'], firstRequest['requestId']);
    channels[1].addIncoming(
      jsonEncode(<String, Object?>{
        'type': 'peer_disconnect_result',
        'requestId': retriedRequest['requestId']!,
        'deviceToken': deviceToken,
        'status': 'disconnected',
        'disconnectedConnections': 2,
      }),
    );

    await revocation;
  });

  test('WebSocket URI is derived from relay endpoint, not PWA join URL', () {
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com/chronosync/'),
      capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionSecret: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );

    expect(
      OnlineRelayTransport.webSocketUriFor(invitation),
      Uri.parse('wss://relay.example.com/v1/rooms/room-1/connect'),
    );
  });

  test('existing relay connect path is not duplicated', () {
    final Invitation invitation = Invitation(
      sessionId: 'room-1',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com/v1/rooms/room-1/connect'),
      joinUri: Uri.parse('https://app.example.com/'),
      capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionSecret: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
      requestedRole: SessionRole.participant,
      expiresAt: DateTime.utc(2099),
    );

    expect(
      OnlineRelayTransport.webSocketUriFor(invitation),
      Uri.parse('wss://relay.example.com/v1/rooms/room-1/connect'),
    );
  });

  test('accepts only relay-attested command sender roles', () {
    final AuthenticatedSessionPeer? participant =
        OnlineRelayTransport.authenticatedCommandPeer(<String, Object?>{
          'sender': <String, Object?>{
            'connectionId': 'socket-123',
            'role': 'participant',
            'deviceToken': _token('a'),
          },
        });

    expect(participant?.connectionId, 'socket-123');
    expect(participant?.role, SessionRole.participant);
    expect(participant?.deviceToken, _token('a'));
    expect(
      OnlineRelayTransport.authenticatedCommandPeer(<String, Object?>{
        'sender': <String, Object?>{
          'connectionId': 'socket-456',
          'role': 'host',
          'deviceToken': _token('b'),
        },
      }),
      isNull,
    );
    expect(
      OnlineRelayTransport.authenticatedCommandPeer(<String, Object?>{
        'sender': <String, Object?>{'role': 'controller'},
      }),
      isNull,
    );
  });

  test('parses only relay-attested presence entries', () {
    final Map<String, AuthenticatedSessionPeer> peers =
        OnlineRelayTransport.authenticatedPresencePeers(<Object?>[
          <String, Object?>{'connectionId': 'host-socket', 'role': 'host'},
          <String, Object?>{
            'connectionId': 'display-socket',
            'role': 'display',
            'deviceToken': _token('d'),
          },
          <String, Object?>{'connectionId': '', 'role': 'participant'},
          <String, Object?>{'connectionId': 'unknown-socket', 'role': 'owner'},
          'invalid',
        ]);

    expect(peers.keys, <String>['host-socket', 'display-socket']);
    expect(peers['host-socket']?.role, SessionRole.host);
    expect(peers['display-socket']?.role, SessionRole.display);
    expect(peers['display-socket']?.deviceToken, _token('d'));
  });

  test('uses relay host assertions on welcome, pong, and presence', () {
    expect(
      OnlineRelayTransport.authoritativeHostConnected(<String, Object?>{
        'type': 'welcome',
        'hostConnected': true,
      }),
      isTrue,
    );
    expect(
      OnlineRelayTransport.authoritativeHostConnected(<String, Object?>{
        'type': 'pong',
        'hostConnected': false,
      }),
      isFalse,
    );
    expect(
      OnlineRelayTransport.authoritativeHostConnected(<String, Object?>{
        'type': 'presence',
        'connections': <Object?>[
          <String, Object?>{'connectionId': 'host-socket', 'role': 'host'},
        ],
      }),
      isTrue,
    );
    expect(
      OnlineRelayTransport.authoritativeHostConnected(<String, Object?>{
        'type': 'presence',
        'connections': <Object?>[
          <String, Object?>{
            'connectionId': 'participant-socket',
            'role': 'participant',
          },
        ],
      }),
      isFalse,
    );
    expect(
      OnlineRelayTransport.authoritativeHostConnected(<String, Object?>{
        'type': 'pong',
      }),
      isNull,
    );
  });

  test('retained snapshot cannot reverse an absent-host assertion', () {
    final RelayHostPresenceTracker tracker = RelayHostPresenceTracker(
      timeout: const Duration(seconds: 35),
    );
    final DateTime now = DateTime.utc(2026, 7, 28, 12);

    expect(
      tracker.observeRelayFrame(<String, Object?>{
        'type': 'welcome',
        'hostConnected': false,
      }, now: now),
      isFalse,
    );
    expect(
      tracker.observeRelayFrame(<String, Object?>{
        'type': 'snapshot',
        'messageId': 'retained-snapshot',
        'revision': 12,
        'hostConnected': true,
      }, now: now),
      isNull,
    );
    expect(tracker.hostConnected, isFalse);
  });

  test('bounds the age of an authoritative host-presence proof', () {
    final DateTime confirmedAt = DateTime.utc(2026, 7, 28, 12);
    const Duration timeout = Duration(seconds: 35);

    expect(
      OnlineRelayTransport.isAuthoritativeHostStale(
        lastConfirmedAt: null,
        now: confirmedAt,
        timeout: timeout,
      ),
      isTrue,
    );
    expect(
      OnlineRelayTransport.isAuthoritativeHostStale(
        lastConfirmedAt: confirmedAt,
        now: confirmedAt.add(const Duration(seconds: 34)),
        timeout: timeout,
      ),
      isFalse,
    );
    expect(
      OnlineRelayTransport.isAuthoritativeHostStale(
        lastConfirmedAt: confirmedAt,
        now: confirmedAt.add(timeout),
        timeout: timeout,
      ),
      isTrue,
    );
  });
}

Future<Map<String, Object?>> _waitForMessage(
  List<Map<String, Object?>> messages,
  String type,
) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    for (final Map<String, Object?> message in messages) {
      if (message['type'] == type) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Timed out waiting for a $type relay frame.');
}

String _relaySnapshotFrame(String messageId, {required int revision}) {
  return jsonEncode(<String, Object?>{
    'type': 'snapshot',
    'messageId': messageId,
    'revision': revision,
    'sentAt': DateTime.utc(2026).toIso8601String(),
    'nonce': 'abcdefghijklmnop',
    'ciphertext': 'opaque',
  });
}

SessionEnvelope _relayEnvelope(String messageId, {required int revision}) {
  return SessionEnvelope(
    sessionId: 'room-1',
    messageId: messageId,
    senderDeviceId: 'host-device-id',
    baseRevision: revision,
    sentAt: DateTime.utc(2026),
    kind: SessionMessageKind.snapshot,
    encryptedPayload: 'opaque',
  );
}

String _token(String character) => List<String>.filled(43, character).join();

String _presenceFrame({required SessionRole role, required String token}) {
  return jsonEncode(<String, Object?>{
    'type': 'presence',
    'hostConnected': true,
    'connections': <Object?>[
      <String, Object?>{'connectionId': 'host-connection', 'role': 'host'},
      <String, Object?>{
        'connectionId': 'guest-connection',
        'role': role.name,
        'deviceToken': token,
      },
    ],
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Timed out waiting for the relay transport to settle.');
}
