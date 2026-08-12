import 'package:chronosync/data/transports/lan_host_transport.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses native authenticated peer presence', () {
    final SessionPeerEvent? connected =
        LanHostTransport.peerEventFromNative(<String, Object?>{
          'type': 'client_connected',
          'clientId': 'native-socket-1',
          'role': 'display',
          'deviceToken': _token('a'),
        });

    expect(connected?.peer.connectionId, 'native-socket-1');
    expect(connected?.peer.role, SessionRole.display);
    expect(connected?.peer.deviceToken, _token('a'));
    expect(connected?.presence, SessionPeerPresence.connected);
    expect(
      LanHostTransport.peerEventFromNative(<String, Object?>{
        'type': 'client_connected',
        'clientId': 'native-controller-1',
        'role': 'controller',
        'deviceToken': _token('c'),
      })?.peer.role,
      SessionRole.controller,
    );
    expect(
      LanHostTransport.peerEventFromNative(<String, Object?>{
        'type': 'client_disconnected',
        'clientId': 'native-socket-1',
        'role': 'host',
        'deviceToken': _token('a'),
      }),
      isNull,
    );
    expect(
      LanHostTransport.peerEventFromNative(<String, Object?>{
        'type': 'client_connected',
        'role': 'participant',
        'deviceToken': _token('a'),
      }),
      isNull,
    );
  });

  test('lifecycle clear disconnects every known peer exactly once', () {
    final LanPeerPresenceTracker tracker = LanPeerPresenceTracker();
    final AuthenticatedSessionPeer participant = AuthenticatedSessionPeer(
      connectionId: 'participant-socket',
      role: SessionRole.participant,
      deviceToken: _token('p'),
    );
    final AuthenticatedSessionPeer display = AuthenticatedSessionPeer(
      connectionId: 'display-socket',
      role: SessionRole.display,
      deviceToken: _token('d'),
    );

    expect(
      tracker.apply(
        SessionPeerEvent(
          peer: participant,
          presence: SessionPeerPresence.connected,
        ),
      ),
      hasLength(1),
    );
    expect(
      tracker.apply(
        SessionPeerEvent(
          peer: participant,
          presence: SessionPeerPresence.connected,
        ),
      ),
      isEmpty,
    );
    tracker.apply(
      SessionPeerEvent(peer: display, presence: SessionPeerPresence.connected),
    );

    final List<SessionPeerEvent> disconnected = tracker.disconnectAll();
    expect(
      disconnected.map((SessionPeerEvent event) => event.peer.connectionId),
      <String>['participant-socket', 'display-socket'],
    );
    expect(
      disconnected.map((SessionPeerEvent event) => event.presence),
      everyElement(SessionPeerPresence.disconnected),
    );
    expect(tracker.disconnectAll(), isEmpty);
    expect(
      tracker.apply(
        SessionPeerEvent(
          peer: participant,
          presence: SessionPeerPresence.disconnected,
        ),
      ),
      isEmpty,
    );
  });

  test('role changes update a live connection without disconnecting it', () {
    final LanPeerPresenceTracker tracker = LanPeerPresenceTracker();
    final AuthenticatedSessionPeer participant = AuthenticatedSessionPeer(
      connectionId: 'participant-socket',
      role: SessionRole.participant,
      deviceToken: _token('p'),
    );
    final AuthenticatedSessionPeer controller = AuthenticatedSessionPeer(
      connectionId: 'participant-socket',
      role: SessionRole.controller,
      deviceToken: _token('p'),
    );
    tracker.apply(
      SessionPeerEvent(
        peer: participant,
        presence: SessionPeerPresence.connected,
      ),
    );

    final List<SessionPeerEvent> changed = tracker.apply(
      SessionPeerEvent(
        peer: controller,
        presence: SessionPeerPresence.connected,
      ),
    );

    expect(changed, hasLength(1));
    expect(changed.single.presence, SessionPeerPresence.connected);
    expect(changed.single.peer.role, SessionRole.controller);
  });
}

String _token(String character) => List<String>.filled(43, character).join();
