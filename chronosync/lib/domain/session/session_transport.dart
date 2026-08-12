import 'dart:async';

import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_device_token.dart';
import 'package:chronosync/domain/session/session_protocol.dart';

enum SessionConnectionState { idle, hosting, connected, stale, closed }

/// Maximum non-host device connections in one live-session room.
const int maxSessionTransportPeers = 50;

/// Transport-authenticated context for the socket that supplied an envelope.
///
/// The identifier is opaque and is stable only for one connection. Hosts bind
/// it to a device after validating that device's encrypted join proof.
final class AuthenticatedSessionPeer {
  AuthenticatedSessionPeer({
    required String connectionId,
    required this.role,
    String? deviceToken,
  }) : connectionId = connectionId.trim(),
       deviceToken = deviceToken?.trim() {
    if (this.connectionId.isEmpty) {
      throw ArgumentError.value(
        connectionId,
        'connectionId',
        'An authenticated connection ID cannot be empty.',
      );
    }
    if (this.deviceToken?.isEmpty == true) {
      throw ArgumentError.value(
        deviceToken,
        'deviceToken',
        'An authenticated device token cannot be empty.',
      );
    }
  }

  final String connectionId;
  final SessionRole role;
  final String? deviceToken;
}

final class ReceivedSessionEnvelope {
  const ReceivedSessionEnvelope({required this.envelope, required this.peer});

  final SessionEnvelope envelope;
  final AuthenticatedSessionPeer peer;
}

enum SessionPeerPresence { connected, disconnected }

/// A transport-authenticated peer entering or leaving the active room.
///
/// Presence is deliberately connection-scoped: a reconnect receives a new
/// connection ID and must reauthenticate its device identity at the session
/// layer.
final class SessionPeerEvent {
  const SessionPeerEvent({required this.peer, required this.presence});

  final AuthenticatedSessionPeer peer;
  final SessionPeerPresence presence;
}

/// Common boundary for nearby, relay, and deterministic in-memory transports.
abstract interface class SessionTransport {
  String get deviceId;

  SessionConnectionState get connectionState;

  Stream<SessionConnectionState> get connectionStates;

  /// Ordered envelopes plus identity asserted by the active transport socket.
  Stream<ReceivedSessionEnvelope> get messages;

  /// Transport-authenticated connection presence visible to the local host.
  ///
  /// Client transports may expose an empty stream when their protocol does not
  /// reveal other room members.
  Stream<SessionPeerEvent> get peerEvents;

  Future<void> host(Invitation invitation);

  Future<void> join(Invitation invitation);

  Future<void> send(SessionEnvelope envelope);

  /// Stops one transport-authenticated connection from receiving or sending.
  ///
  /// Only an active host transport may call this method.
  Future<void> disconnectPeer(String connectionId);

  /// Durably blocks a room-scoped device token and closes all matching peers.
  ///
  /// The future completes only after the host transport acknowledges that the
  /// block is installed, including when the device is currently offline.
  Future<void> revokeDevice(String deviceToken);

  /// Changes the transport-attested role for one room-scoped device.
  ///
  /// Only the active host may call this. Implementations must retain the role
  /// for reconnects in the current room and must never grant [SessionRole.host].
  Future<void> updatePeerRole(String deviceToken, SessionRole role);

  Future<void> close();
}

/// Shared router used by [InMemoryTransport] instances in tests and previews.
class InMemoryTransportHub {
  final Map<String, _InMemoryRoom> _rooms = <String, _InMemoryRoom>{};

  InMemoryTransport createTransport({
    required String deviceId,
    Clock clock = const SystemClock(),
  }) {
    return InMemoryTransport._(hub: this, deviceId: deviceId, clock: clock);
  }

  /// Registers an additional role-scoped invitation for an active room.
  ///
  /// Tests must explicitly register Display or private Controller grants so
  /// they exercise the same capability-to-role binding as real transports.
  void registerInvitation(Invitation invitation) {
    final _InMemoryRoom? room = _rooms[invitation.sessionId];
    if (room == null ||
        room.host.connectionState != SessionConnectionState.hosting) {
      throw StateError('The session host is unavailable.');
    }
    if (invitation.sessionSecret != room.hostInvitation.sessionSecret ||
        invitation.transport != room.hostInvitation.transport ||
        invitation.endpoint != room.hostInvitation.endpoint) {
      throw StateError('The invitation does not belong to this room.');
    }
    final Invitation? existing = room.invitations[invitation.capability];
    if (existing != null && existing != invitation) {
      throw StateError('The capability is already bound to another grant.');
    }
    room.invitations[invitation.capability] = invitation;
  }

  void _host(InMemoryTransport transport, Invitation invitation) {
    if (_rooms.containsKey(invitation.sessionId)) {
      throw StateError('A host already exists for this session.');
    }
    _rooms[invitation.sessionId] = _InMemoryRoom(
      hostInvitation: invitation,
      host: transport,
    );
  }

  void _join(InMemoryTransport transport, Invitation invitation) {
    final _InMemoryRoom? room = _rooms[invitation.sessionId];
    if (room == null ||
        room.host.connectionState != SessionConnectionState.hosting) {
      throw StateError('The session host is unavailable.');
    }
    final Invitation? authorized = room.invitations[invitation.capability];
    if (authorized == null || authorized != invitation) {
      throw StateError('The invitation capability is not valid for this room.');
    }
    final String? deviceToken = transport._deviceToken;
    if (deviceToken == null || room.blockedDeviceTokens.contains(deviceToken)) {
      throw StateError('This device was removed from the session.');
    }
    if (room.peers.length >= maxSessionTransportPeers) {
      throw StateError('The session has reached its connected-device limit.');
    }
    room.peers.add(transport);
    final AuthenticatedSessionPeer guestPeer = AuthenticatedSessionPeer(
      connectionId: 'memory-peer:${transport.deviceId}',
      role: _effectiveRole(
        room,
        requestedRole: invitation.requestedRole,
        deviceToken: deviceToken,
      ),
      deviceToken: deviceToken,
    );
    room.host._receivePeerEvent(
      SessionPeerEvent(
        peer: guestPeer,
        presence: SessionPeerPresence.connected,
      ),
    );
    final SessionEnvelope? latestSnapshot = room.latestSnapshot;
    if (latestSnapshot != null) {
      scheduleMicrotask(
        () => transport._receive(
          latestSnapshot,
          peer: AuthenticatedSessionPeer(
            connectionId: 'memory-host:${room.host.deviceId}',
            role: SessionRole.host,
            deviceToken: room.host._deviceToken,
          ),
        ),
      );
    }
  }

  void _route(InMemoryTransport sender, SessionEnvelope envelope) {
    final _InMemoryRoom? room = _rooms[envelope.sessionId];
    if (room == null) {
      throw StateError('The session room no longer exists.');
    }
    if (identical(room.host, sender)) {
      if (envelope.kind == SessionMessageKind.snapshot) {
        room.latestSnapshot = envelope;
      }
      for (final InMemoryTransport peer in List<InMemoryTransport>.of(
        room.peers,
      )) {
        peer._receive(
          envelope,
          peer: AuthenticatedSessionPeer(
            connectionId: 'memory-host:${sender.deviceId}',
            role: SessionRole.host,
            deviceToken: sender._deviceToken,
          ),
        );
      }
      return;
    }
    if (!room.peers.contains(sender)) {
      throw StateError('The sender is not connected to this session.');
    }
    room.host._receive(
      envelope,
      peer: AuthenticatedSessionPeer(
        connectionId: 'memory-peer:${sender.deviceId}',
        role: _effectiveRole(
          room,
          requestedRole: sender._requestedRole ?? SessionRole.participant,
          deviceToken: sender._deviceToken,
        ),
        deviceToken: sender._deviceToken,
      ),
    );
  }

  void _leave(InMemoryTransport transport, String sessionId) {
    final _InMemoryRoom? room = _rooms[sessionId];
    if (room == null) {
      return;
    }
    if (identical(room.host, transport)) {
      _rooms.remove(sessionId);
      for (final InMemoryTransport peer in List<InMemoryTransport>.of(
        room.peers,
      )) {
        peer._receivePeerEvent(
          SessionPeerEvent(
            peer: AuthenticatedSessionPeer(
              connectionId: 'memory-host:${transport.deviceId}',
              role: SessionRole.host,
              deviceToken: transport._deviceToken,
            ),
            presence: SessionPeerPresence.disconnected,
          ),
        );
        peer._markStale();
      }
    } else {
      if (room.peers.remove(transport)) {
        room.host._receivePeerEvent(
          SessionPeerEvent(
            peer: AuthenticatedSessionPeer(
              connectionId: 'memory-peer:${transport.deviceId}',
              role: _effectiveRole(
                room,
                requestedRole:
                    transport._requestedRole ?? SessionRole.participant,
                deviceToken: transport._deviceToken,
              ),
              deviceToken: transport._deviceToken,
            ),
            presence: SessionPeerPresence.disconnected,
          ),
        );
      }
    }
  }

  void _disconnectPeer(InMemoryTransport host, String connectionId) {
    final String? sessionId = host._sessionId;
    final _InMemoryRoom? room = sessionId == null ? null : _rooms[sessionId];
    if (room == null || !identical(room.host, host)) {
      throw StateError('Only the active host can disconnect a peer.');
    }
    InMemoryTransport? target;
    for (final InMemoryTransport peer in room.peers) {
      if ('memory-peer:${peer.deviceId}' == connectionId) {
        target = peer;
        break;
      }
    }
    if (target == null) {
      return;
    }
    room.peers.remove(target);
    room.host._receivePeerEvent(
      SessionPeerEvent(
        peer: AuthenticatedSessionPeer(
          connectionId: connectionId,
          role: _effectiveRole(
            room,
            requestedRole: target._requestedRole ?? SessionRole.participant,
            deviceToken: target._deviceToken,
          ),
          deviceToken: target._deviceToken,
        ),
        presence: SessionPeerPresence.disconnected,
      ),
    );
    target._markStale();
  }

  void _revokeDevice(InMemoryTransport host, String deviceToken) {
    final String? sessionId = host._sessionId;
    final _InMemoryRoom? room = sessionId == null ? null : _rooms[sessionId];
    if (room == null || !identical(room.host, host)) {
      throw StateError('Only the active host can revoke a device.');
    }
    final String normalizedToken = deviceToken.trim();
    if (normalizedToken.isEmpty) {
      throw ArgumentError.value(
        deviceToken,
        'deviceToken',
        'A device token cannot be empty.',
      );
    }
    room.blockedDeviceTokens.add(normalizedToken);
    final List<InMemoryTransport> targets = room.peers
        .where((InMemoryTransport peer) => peer._deviceToken == normalizedToken)
        .toList(growable: false);
    for (final InMemoryTransport target in targets) {
      room.peers.remove(target);
      room.host._receivePeerEvent(
        SessionPeerEvent(
          peer: AuthenticatedSessionPeer(
            connectionId: 'memory-peer:${target.deviceId}',
            role: _effectiveRole(
              room,
              requestedRole: target._requestedRole ?? SessionRole.participant,
              deviceToken: target._deviceToken,
            ),
            deviceToken: target._deviceToken,
          ),
          presence: SessionPeerPresence.disconnected,
        ),
      );
      target._markStale();
    }
    room.roleOverrides.remove(normalizedToken);
  }

  void _updatePeerRole(
    InMemoryTransport host,
    String deviceToken,
    SessionRole role,
  ) {
    final String? sessionId = host._sessionId;
    final _InMemoryRoom? room = sessionId == null ? null : _rooms[sessionId];
    if (room == null || !identical(room.host, host)) {
      throw StateError('Only the active host can update a peer role.');
    }
    final String normalizedToken = deviceToken.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(normalizedToken)) {
      throw ArgumentError.value(
        deviceToken,
        'deviceToken',
        'A device token must be a 43-character base64url value.',
      );
    }
    if (role == SessionRole.host) {
      throw ArgumentError.value(
        role,
        'role',
        'A peer cannot be promoted to host.',
      );
    }
    if (normalizedToken == host._deviceToken) {
      throw StateError('The host role cannot be changed through a peer grant.');
    }
    room.roleOverrides[normalizedToken] = role;
    for (final InMemoryTransport peer in room.peers.where(
      (InMemoryTransport peer) => peer._deviceToken == normalizedToken,
    )) {
      room.host._receivePeerEvent(
        SessionPeerEvent(
          peer: AuthenticatedSessionPeer(
            connectionId: 'memory-peer:${peer.deviceId}',
            role: role,
            deviceToken: normalizedToken,
          ),
          presence: SessionPeerPresence.connected,
        ),
      );
    }
  }

  SessionRole _effectiveRole(
    _InMemoryRoom room, {
    required SessionRole requestedRole,
    required String? deviceToken,
  }) {
    if (requestedRole == SessionRole.host || deviceToken == null) {
      return requestedRole;
    }
    return room.roleOverrides[deviceToken] ?? requestedRole;
  }
}

/// A deterministic host-routed transport implementing the production contract.
///
/// A peer can send only to the host; the host can broadcast to all peers. This
/// mirrors the host-authoritative topology without simulating encryption.
class InMemoryTransport implements SessionTransport {
  InMemoryTransport._({
    required InMemoryTransportHub hub,
    required this.deviceId,
    required Clock clock,
  }) : _hub = hub,
       _clock = clock {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'A transport device ID cannot be empty.',
      );
    }
  }

  final InMemoryTransportHub _hub;
  final Clock _clock;
  final StreamController<ReceivedSessionEnvelope> _messageController =
      StreamController<ReceivedSessionEnvelope>.broadcast(sync: true);
  final StreamController<SessionConnectionState> _stateController =
      StreamController<SessionConnectionState>.broadcast(sync: true);
  final StreamController<SessionPeerEvent> _peerEventController =
      StreamController<SessionPeerEvent>.broadcast(sync: true);

  @override
  final String deviceId;

  SessionConnectionState _connectionState = SessionConnectionState.idle;
  String? _sessionId;
  SessionRole? _requestedRole;
  String? _deviceToken;

  @override
  SessionConnectionState get connectionState => _connectionState;

  @override
  Stream<SessionConnectionState> get connectionStates =>
      _stateController.stream;

  @override
  Stream<ReceivedSessionEnvelope> get messages => _messageController.stream;

  @override
  Stream<SessionPeerEvent> get peerEvents => _peerEventController.stream;

  @override
  Future<void> host(Invitation invitation) async {
    _requireIdle();
    _requireCurrent(invitation);
    _deviceToken = await SessionDeviceToken.derive(
      deviceId: deviceId,
      sessionSecret: invitation.sessionSecret,
    );
    _hub._host(this, invitation);
    _sessionId = invitation.sessionId;
    _setState(SessionConnectionState.hosting);
  }

  @override
  Future<void> join(Invitation invitation) async {
    _requireIdle();
    _requireCurrent(invitation);
    _deviceToken = await SessionDeviceToken.derive(
      deviceId: deviceId,
      sessionSecret: invitation.sessionSecret,
    );
    _hub._join(this, invitation);
    _sessionId = invitation.sessionId;
    _requestedRole = invitation.requestedRole;
    _setState(SessionConnectionState.connected);
  }

  @override
  Future<void> send(SessionEnvelope envelope) async {
    if (_connectionState != SessionConnectionState.hosting &&
        _connectionState != SessionConnectionState.connected) {
      throw StateError('The transport is not connected.');
    }
    if (envelope.sessionId != _sessionId) {
      throw StateError('The envelope belongs to a different session.');
    }
    if (envelope.senderDeviceId != deviceId) {
      throw StateError('The envelope sender does not match this transport.');
    }
    _hub._route(this, envelope);
  }

  @override
  Future<void> disconnectPeer(String connectionId) async {
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('Only an active host can disconnect a peer.');
    }
    _hub._disconnectPeer(this, connectionId);
  }

  @override
  Future<void> revokeDevice(String deviceToken) async {
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('Only an active host can revoke a device.');
    }
    _hub._revokeDevice(this, deviceToken);
  }

  @override
  Future<void> updatePeerRole(String deviceToken, SessionRole role) async {
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('Only an active host can update a peer role.');
    }
    _hub._updatePeerRole(this, deviceToken, role);
  }

  @override
  Future<void> close() async {
    if (_connectionState == SessionConnectionState.closed) {
      return;
    }
    final String? sessionId = _sessionId;
    if (sessionId != null) {
      _hub._leave(this, sessionId);
    }
    _sessionId = null;
    _requestedRole = null;
    _setState(SessionConnectionState.closed);
    await _messageController.close();
    await _peerEventController.close();
    await _stateController.close();
  }

  void _receive(
    SessionEnvelope envelope, {
    required AuthenticatedSessionPeer peer,
  }) {
    if (_connectionState == SessionConnectionState.hosting ||
        _connectionState == SessionConnectionState.connected) {
      _messageController.add(
        ReceivedSessionEnvelope(envelope: envelope, peer: peer),
      );
    }
  }

  void _markStale() {
    if (_connectionState == SessionConnectionState.connected) {
      _setState(SessionConnectionState.stale);
    }
  }

  void _receivePeerEvent(SessionPeerEvent event) {
    if ((_connectionState == SessionConnectionState.hosting ||
            _connectionState == SessionConnectionState.connected) &&
        !_peerEventController.isClosed) {
      _peerEventController.add(event);
    }
  }

  void _setState(SessionConnectionState value) {
    _connectionState = value;
    if (!_stateController.isClosed) {
      _stateController.add(value);
    }
  }

  void _requireIdle() {
    if (_connectionState != SessionConnectionState.idle) {
      throw StateError('A transport can connect only once.');
    }
  }

  void _requireCurrent(Invitation invitation) {
    if (invitation.isExpiredAt(_clock.now())) {
      throw StateError('The invitation has expired.');
    }
  }
}

class _InMemoryRoom {
  _InMemoryRoom({required this.hostInvitation, required this.host})
    : invitations = <String, Invitation>{
        hostInvitation.capability: hostInvitation,
      };

  final Invitation hostInvitation;
  final Map<String, Invitation> invitations;
  final InMemoryTransport host;
  final Set<InMemoryTransport> peers = <InMemoryTransport>{};
  final Set<String> blockedDeviceTokens = <String>{};
  final Map<String, SessionRole> roleOverrides = <String, SessionRole>{};
  SessionEnvelope? latestSnapshot;
}
