import 'dart:async';
import 'dart:convert';

import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fixtures.dart';

void main() {
  String token(int byte) =>
      base64UrlEncode(List<int>.filled(32, byte)).replaceAll('=', '');

  Invitation invitation({
    DateTime? expiresAt,
    SessionRole role = SessionRole.participant,
    String? capability,
  }) {
    if (role == SessionRole.controller) {
      return Invitation.controllerGrant(
        sessionId: 'session-1',
        transport: SessionTransportKind.nearbyLan,
        endpoint: Uri.parse('http://192.168.1.2:8787/join'),
        capability: capability ?? token(3),
        sessionSecret: token(0),
        expiresAt: expiresAt ?? fixtureStart.add(const Duration(hours: 1)),
      );
    }
    return Invitation(
      sessionId: 'session-1',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://192.168.1.2:8787/join'),
      capability: capability ?? token(1),
      sessionSecret: token(0),
      requestedRole: role,
      expiresAt: expiresAt ?? fixtureStart.add(const Duration(hours: 1)),
    );
  }

  SessionEnvelope envelope({
    required String id,
    required String sender,
    SessionMessageKind kind = SessionMessageKind.command,
  }) {
    return SessionEnvelope(
      sessionId: 'session-1',
      messageId: id,
      senderDeviceId: sender,
      baseRevision: 0,
      sentAt: fixtureStart,
      kind: kind,
      encryptedPayload: 'ciphertext-$id',
    );
  }

  group('InMemoryTransport', () {
    test('routes peers only to host and host broadcasts in order', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport host = hub.createTransport(
        deviceId: 'host-1',
        clock: clock,
      );
      final InMemoryTransport peerA = hub.createTransport(
        deviceId: 'peer-a',
        clock: clock,
      );
      final InMemoryTransport peerB = hub.createTransport(
        deviceId: 'peer-b',
        clock: clock,
      );
      addTearDown(host.close);
      addTearDown(peerA.close);
      addTearDown(peerB.close);

      final List<ReceivedSessionEnvelope> hostMessages =
          <ReceivedSessionEnvelope>[];
      final List<ReceivedSessionEnvelope> peerAMessages =
          <ReceivedSessionEnvelope>[];
      final List<ReceivedSessionEnvelope> peerBMessages =
          <ReceivedSessionEnvelope>[];
      final List<SessionPeerEvent> hostPeerEvents = <SessionPeerEvent>[];
      final StreamSubscription<ReceivedSessionEnvelope> hostSubscription = host
          .messages
          .listen(hostMessages.add);
      final StreamSubscription<ReceivedSessionEnvelope> peerASubscription =
          peerA.messages.listen(peerAMessages.add);
      final StreamSubscription<ReceivedSessionEnvelope> peerBSubscription =
          peerB.messages.listen(peerBMessages.add);
      final StreamSubscription<SessionPeerEvent> hostPeerSubscription = host
          .peerEvents
          .listen(hostPeerEvents.add);
      addTearDown(hostSubscription.cancel);
      addTearDown(peerASubscription.cancel);
      addTearDown(peerBSubscription.cancel);
      addTearDown(hostPeerSubscription.cancel);

      final Invitation value = invitation();
      await host.host(value);
      await peerA.join(value);
      await peerB.join(value);
      await peerA.send(envelope(id: 'peer-command', sender: 'peer-a'));
      await host.send(
        envelope(
          id: 'host-activity-1',
          sender: 'host-1',
          kind: SessionMessageKind.activity,
        ),
      );
      await host.send(
        envelope(
          id: 'host-activity-2',
          sender: 'host-1',
          kind: SessionMessageKind.activity,
        ),
      );

      expect(
        hostMessages.map(
          (ReceivedSessionEnvelope value) => value.envelope.messageId,
        ),
        <String>['peer-command'],
      );
      expect(hostMessages.single.peer.role, SessionRole.participant);
      expect(hostMessages.single.peer.connectionId, 'memory-peer:peer-a');
      expect(
        peerAMessages.map(
          (ReceivedSessionEnvelope value) => value.envelope.messageId,
        ),
        <String>['host-activity-1', 'host-activity-2'],
      );
      expect(
        peerBMessages.map(
          (ReceivedSessionEnvelope value) => value.envelope.messageId,
        ),
        <String>['host-activity-1', 'host-activity-2'],
      );
      expect(
        hostPeerEvents.map((SessionPeerEvent event) => event.peer.connectionId),
        <String>['memory-peer:peer-a', 'memory-peer:peer-b'],
      );
      expect(
        hostPeerEvents.map((SessionPeerEvent event) => event.presence),
        everyElement(SessionPeerPresence.connected),
      );

      await peerA.close();
      expect(hostPeerEvents.last.peer.connectionId, 'memory-peer:peer-a');
      expect(hostPeerEvents.last.presence, SessionPeerPresence.disconnected);
    });

    test('binds each registered capability to its granted role', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport host = hub.createTransport(
        deviceId: 'host-1',
        clock: clock,
      );
      final InMemoryTransport display = hub.createTransport(
        deviceId: 'display-1',
        clock: clock,
      );
      final InMemoryTransport controller = hub.createTransport(
        deviceId: 'controller-1',
        clock: clock,
      );
      final InMemoryTransport roleSpoof = hub.createTransport(
        deviceId: 'spoof-1',
        clock: clock,
      );
      addTearDown(host.close);
      addTearDown(display.close);
      addTearDown(controller.close);
      addTearDown(roleSpoof.close);
      final List<SessionPeerEvent> peerEvents = <SessionPeerEvent>[];
      host.peerEvents.listen(peerEvents.add);
      final Invitation participantInvitation = invitation();
      final Invitation displayInvitation = invitation(
        role: SessionRole.display,
        capability: token(2),
      );
      final Invitation controllerInvitation = invitation(
        role: SessionRole.controller,
        capability: token(3),
      );

      await host.host(participantInvitation);
      hub.registerInvitation(displayInvitation);
      hub.registerInvitation(controllerInvitation);
      await display.join(displayInvitation);
      await controller.join(controllerInvitation);

      expect(
        peerEvents.map((SessionPeerEvent event) => event.peer.role),
        <SessionRole>[SessionRole.display, SessionRole.controller],
      );

      await expectLater(
        roleSpoof.join(
          invitation(
            role: SessionRole.participant,
            capability: displayInvitation.capability,
          ),
        ),
        throwsStateError,
      );
    });

    test('marks every peer stale when the host closes', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport host = hub.createTransport(
        deviceId: 'host-1',
        clock: clock,
      );
      final InMemoryTransport peer = hub.createTransport(
        deviceId: 'peer-1',
        clock: clock,
      );
      addTearDown(host.close);
      addTearDown(peer.close);
      final List<SessionConnectionState> states = <SessionConnectionState>[];
      final StreamSubscription<SessionConnectionState> subscription = peer
          .connectionStates
          .listen(states.add);
      addTearDown(subscription.cancel);

      await host.host(invitation());
      await peer.join(invitation());
      await host.close();

      expect(peer.connectionState, SessionConnectionState.stale);
      expect(states, contains(SessionConnectionState.stale));
      await expectLater(
        peer.send(envelope(id: 'late', sender: 'peer-1')),
        throwsStateError,
      );
    });

    test('host can evict one peer without interrupting other peers', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport host = hub.createTransport(
        deviceId: 'host-1',
        clock: clock,
      );
      final InMemoryTransport removed = hub.createTransport(
        deviceId: 'peer-a',
        clock: clock,
      );
      final InMemoryTransport retained = hub.createTransport(
        deviceId: 'peer-b',
        clock: clock,
      );
      addTearDown(host.close);
      addTearDown(removed.close);
      addTearDown(retained.close);
      final List<ReceivedSessionEnvelope> retainedMessages =
          <ReceivedSessionEnvelope>[];
      retained.messages.listen(retainedMessages.add);

      await host.host(invitation());
      await removed.join(invitation());
      await retained.join(invitation());
      await host.disconnectPeer('memory-peer:peer-a');
      await host.send(
        envelope(
          id: 'after-eviction',
          sender: 'host-1',
          kind: SessionMessageKind.snapshot,
        ),
      );

      expect(removed.connectionState, SessionConnectionState.stale);
      expect(retained.connectionState, SessionConnectionState.connected);
      expect(
        retainedMessages.map(
          (ReceivedSessionEnvelope value) => value.envelope.messageId,
        ),
        <String>['after-eviction'],
      );
      await expectLater(
        removed.send(envelope(id: 'removed-command', sender: 'peer-a')),
        throwsStateError,
      );
    });

    test(
      'device revocation closes every matching socket and blocks reconnects',
      () async {
        final InMemoryTransportHub hub = InMemoryTransportHub();
        final _FakeClock clock = _FakeClock(fixtureStart);
        final InMemoryTransport host = hub.createTransport(
          deviceId: 'host-1',
          clock: clock,
        );
        final InMemoryTransport firstSocket = hub.createTransport(
          deviceId: 'peer-a',
          clock: clock,
        );
        final InMemoryTransport secondSocket = hub.createTransport(
          deviceId: 'peer-a',
          clock: clock,
        );
        final InMemoryTransport reconnect = hub.createTransport(
          deviceId: 'peer-a',
          clock: clock,
        );
        addTearDown(host.close);
        addTearDown(firstSocket.close);
        addTearDown(secondSocket.close);
        addTearDown(reconnect.close);

        final Invitation value = invitation();
        await host.host(value);
        await firstSocket.join(value);
        await secondSocket.join(value);
        final String deviceToken = await SessionDeviceToken.derive(
          deviceId: 'peer-a',
          sessionSecret: value.sessionSecret,
        );

        await host.revokeDevice(deviceToken);

        expect(firstSocket.connectionState, SessionConnectionState.stale);
        expect(secondSocket.connectionState, SessionConnectionState.stale);
        await expectLater(reconnect.join(value), throwsStateError);
      },
    );

    test(
      'host role updates authenticate live commands and survive reconnects',
      () async {
        final InMemoryTransportHub hub = InMemoryTransportHub();
        final _FakeClock clock = _FakeClock(fixtureStart);
        final InMemoryTransport host = hub.createTransport(
          deviceId: 'host-1',
          clock: clock,
        );
        final InMemoryTransport firstSocket = hub.createTransport(
          deviceId: 'peer-a',
          clock: clock,
        );
        final InMemoryTransport reconnect = hub.createTransport(
          deviceId: 'peer-a',
          clock: clock,
        );
        addTearDown(host.close);
        addTearDown(firstSocket.close);
        addTearDown(reconnect.close);
        final List<ReceivedSessionEnvelope> received =
            <ReceivedSessionEnvelope>[];
        host.messages.listen(received.add);

        final Invitation value = invitation();
        await host.host(value);
        await firstSocket.join(value);
        final String deviceToken = await SessionDeviceToken.derive(
          deviceId: 'peer-a',
          sessionSecret: value.sessionSecret,
        );

        await host.updatePeerRole(deviceToken, SessionRole.controller);
        await firstSocket.send(
          envelope(id: 'controller-command', sender: 'peer-a'),
        );
        expect(received.single.peer.role, SessionRole.controller);

        await firstSocket.close();
        await reconnect.join(value);
        await reconnect.send(
          envelope(id: 'reconnected-command', sender: 'peer-a'),
        );
        expect(received.last.peer.role, SessionRole.controller);

        await host.updatePeerRole(deviceToken, SessionRole.participant);
        await reconnect.send(envelope(id: 'demoted-command', sender: 'peer-a'));
        expect(received.last.peer.role, SessionRole.participant);
        await expectLater(
          reconnect.updatePeerRole(deviceToken, SessionRole.controller),
          throwsStateError,
        );
      },
    );

    test('allows 50 guests in addition to the authoritative host', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport host = hub.createTransport(
        deviceId: 'host-1',
        clock: clock,
      );
      final List<InMemoryTransport> guests = List<InMemoryTransport>.generate(
        maxSessionTransportPeers + 1,
        (int index) =>
            hub.createTransport(deviceId: 'peer-$index', clock: clock),
      );
      addTearDown(host.close);
      addTearDown(() async {
        for (final InMemoryTransport guest in guests) {
          await guest.close();
        }
      });
      final Invitation value = invitation();
      await host.host(value);

      for (final InMemoryTransport guest in guests.take(
        maxSessionTransportPeers,
      )) {
        await guest.join(value);
      }

      expect(
        guests
            .take(maxSessionTransportPeers)
            .map((InMemoryTransport guest) => guest.connectionState),
        everyElement(SessionConnectionState.connected),
      );
      await expectLater(guests.last.join(value), throwsStateError);
    });

    test('rejects expired invitations and unavailable hosts', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport expiredHost = hub.createTransport(
        deviceId: 'expired-host',
        clock: clock,
      );
      final InMemoryTransport peer = hub.createTransport(
        deviceId: 'peer-1',
        clock: clock,
      );
      addTearDown(expiredHost.close);
      addTearDown(peer.close);

      await expectLater(
        expiredHost.host(invitation(expiresAt: fixtureStart)),
        throwsStateError,
      );
      await expectLater(peer.join(invitation()), throwsStateError);
    });

    test('validates envelope session and sender identity', () async {
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final _FakeClock clock = _FakeClock(fixtureStart);
      final InMemoryTransport host = hub.createTransport(
        deviceId: 'host-1',
        clock: clock,
      );
      addTearDown(host.close);
      await host.host(invitation());

      await expectLater(
        host.send(envelope(id: 'spoof', sender: 'someone-else')),
        throwsStateError,
      );
      final SessionEnvelope wrongSession = SessionEnvelope(
        sessionId: 'another-session',
        messageId: 'wrong-session',
        senderDeviceId: 'host-1',
        baseRevision: 0,
        sentAt: fixtureStart,
        kind: SessionMessageKind.heartbeat,
        encryptedPayload: 'ciphertext',
      );
      await expectLater(host.send(wrongSession), throwsStateError);
    });
  });
}

class _FakeClock implements Clock {
  const _FakeClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
