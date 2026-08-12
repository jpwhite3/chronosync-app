import 'dart:async';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:flutter/services.dart';

final class LanHostingResult {
  const LanHostingResult({
    required this.invitation,
    required this.displayInvitation,
  });

  final Invitation invitation;
  final Invitation displayInvitation;
}

/// Deduplicates native connection events and can atomically clear a LAN room.
///
/// Native lifecycle callbacks may race individual socket-close callbacks. This
/// tracker ensures a suspension produces exactly one disconnect per peer while
/// still providing a safety clear if iOS stops delivering socket events.
final class LanPeerPresenceTracker {
  final Map<String, AuthenticatedSessionPeer> _peers =
      <String, AuthenticatedSessionPeer>{};

  List<SessionPeerEvent> apply(SessionPeerEvent event) {
    final String connectionId = event.peer.connectionId;
    final AuthenticatedSessionPeer? previous = _peers[connectionId];
    if (event.presence == SessionPeerPresence.disconnected) {
      if (previous == null) {
        return const <SessionPeerEvent>[];
      }
      _peers.remove(connectionId);
      return <SessionPeerEvent>[
        SessionPeerEvent(
          peer: previous,
          presence: SessionPeerPresence.disconnected,
        ),
      ];
    }

    if (previous?.role == event.peer.role &&
        previous?.deviceToken == event.peer.deviceToken) {
      return const <SessionPeerEvent>[];
    }
    _peers[connectionId] = event.peer;
    return <SessionPeerEvent>[event];
  }

  List<SessionPeerEvent> disconnectAll() {
    final List<SessionPeerEvent> events = _peers.values
        .map(
          (AuthenticatedSessionPeer peer) => SessionPeerEvent(
            peer: peer,
            presence: SessionPeerPresence.disconnected,
          ),
        )
        .toList(growable: false);
    _peers.clear();
    return events;
  }
}

/// iOS bridge for the foreground-only Bonjour and local HTTP/WebSocket host.
final class LanHostTransport implements SessionTransport {
  LanHostTransport({required this.deviceId}) {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object _) {
        _disconnectAllKnownPeers();
        _setState(SessionConnectionState.stale);
      },
    );
  }

  static const MethodChannel _methodChannel = MethodChannel(
    'com.chronosync/nearby_host',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.chronosync/nearby_host/events',
  );

  @override
  final String deviceId;

  final StreamController<ReceivedSessionEnvelope> _messageController =
      StreamController<ReceivedSessionEnvelope>.broadcast();
  final StreamController<SessionConnectionState> _stateController =
      StreamController<SessionConnectionState>.broadcast();
  final StreamController<SessionPeerEvent> _peerEventController =
      StreamController<SessionPeerEvent>.broadcast();
  final LanPeerPresenceTracker _peerPresence = LanPeerPresenceTracker();

  StreamSubscription<Object?>? _eventSubscription;
  SessionConnectionState _connectionState = SessionConnectionState.idle;
  Invitation? _invitation;
  bool _closed = false;

  @override
  SessionConnectionState get connectionState => _connectionState;

  @override
  Stream<SessionConnectionState> get connectionStates =>
      _stateController.stream;

  @override
  Stream<ReceivedSessionEnvelope> get messages => _messageController.stream;

  @override
  Stream<SessionPeerEvent> get peerEvents => _peerEventController.stream;

  Future<LanHostingResult> startHosting({
    required String sessionId,
    required DateTime expiresAt,
  }) async {
    final SessionSecrets participantSecrets = await SessionSecrets.generate();
    final SessionSecrets displaySecrets = await SessionSecrets.generate();
    final Map<Object?, Object?>? response = await _methodChannel
        .invokeMapMethod<Object?, Object?>('startHost', <String, Object>{
          'sessionId': sessionId,
          'participantCapability': participantSecrets.capability,
          'displayCapability': displaySecrets.capability,
          'sessionSecret': participantSecrets.sessionSecret,
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        });
    final Object? endpointValue = response?['endpoint'];
    if (endpointValue is! String) {
      throw StateError('The iPhone could not create a nearby session URL.');
    }
    final Uri endpoint = Uri.parse(endpointValue);
    final Invitation participantInvitation = Invitation(
      sessionId: sessionId,
      transport: SessionTransportKind.nearbyLan,
      endpoint: endpoint,
      capability: participantSecrets.capability,
      sessionSecret: participantSecrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: expiresAt,
    );
    final Invitation displayInvitation = Invitation(
      sessionId: sessionId,
      transport: SessionTransportKind.nearbyLan,
      endpoint: endpoint,
      capability: displaySecrets.capability,
      sessionSecret: participantSecrets.sessionSecret,
      requestedRole: SessionRole.display,
      expiresAt: expiresAt,
    );
    _invitation = participantInvitation;
    _setState(SessionConnectionState.hosting);
    return LanHostingResult(
      invitation: participantInvitation,
      displayInvitation: displayInvitation,
    );
  }

  @override
  Future<void> host(Invitation invitation) async {
    if (_connectionState != SessionConnectionState.idle) {
      throw StateError('This nearby transport has already been used.');
    }
    if (invitation.transport != SessionTransportKind.nearbyLan) {
      throw ArgumentError.value(
        invitation.transport,
        'invitation',
        'LanHostTransport requires a nearby invitation.',
      );
    }
    await _methodChannel.invokeMethod<void>(
      'startHostWithInvitation',
      <String, Object>{'invitation': invitation.toJson()},
    );
    _invitation = invitation;
    _setState(SessionConnectionState.hosting);
  }

  @override
  Future<void> join(Invitation invitation) {
    throw UnsupportedError('LanHostTransport cannot join another host.');
  }

  @override
  Future<void> send(SessionEnvelope envelope) async {
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('The nearby host is not running.');
    }
    if (envelope.sessionId != _invitation?.sessionId ||
        envelope.senderDeviceId != deviceId) {
      throw StateError('The session envelope does not match this host.');
    }
    await _methodChannel.invokeMethod<void>('broadcast', <String, Object>{
      'envelope': envelope.encode(),
    });
  }

  @override
  Future<void> disconnectPeer(String connectionId) async {
    final String normalizedConnectionId = connectionId.trim();
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('The nearby host is not running.');
    }
    if (normalizedConnectionId.isEmpty) {
      throw ArgumentError.value(
        connectionId,
        'connectionId',
        'A peer connection ID cannot be empty.',
      );
    }
    await _methodChannel.invokeMethod<void>(
      'disconnectClient',
      <String, Object>{'connectionId': normalizedConnectionId},
    );
  }

  @override
  Future<void> revokeDevice(String deviceToken) async {
    final String normalizedDeviceToken = deviceToken.trim();
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('The nearby host is not running.');
    }
    if (normalizedDeviceToken.isEmpty) {
      throw ArgumentError.value(
        deviceToken,
        'deviceToken',
        'A device token cannot be empty.',
      );
    }
    await _methodChannel.invokeMethod<void>('revokeDevice', <String, Object>{
      'deviceToken': normalizedDeviceToken,
    });
  }

  @override
  Future<void> updatePeerRole(String deviceToken, SessionRole role) async {
    final String normalizedDeviceToken = deviceToken.trim();
    if (_connectionState != SessionConnectionState.hosting) {
      throw StateError('The nearby host is not running.');
    }
    if (!_isDeviceToken(normalizedDeviceToken)) {
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
    await _methodChannel.invokeMethod<void>('setPeerRole', <String, Object>{
      'deviceToken': normalizedDeviceToken,
      'role': role.name,
    });
  }

  void _handleNativeEvent(Object? event) {
    if (event is! Map<Object?, Object?>) {
      return;
    }
    final Object? type = event['type'];
    if (type == 'message' &&
        event['envelope'] is String &&
        event['clientId'] is String &&
        event['role'] is String &&
        _isDeviceToken(event['deviceToken'])) {
      try {
        final SessionRole authenticatedRole = SessionRole.values.firstWhere(
          (SessionRole role) => role.name == event['role'],
        );
        final AuthenticatedSessionPeer peer = AuthenticatedSessionPeer(
          connectionId: event['clientId']! as String,
          role: authenticatedRole,
          deviceToken: event['deviceToken']! as String,
        );
        _emitPeerEvents(
          _peerPresence.apply(
            SessionPeerEvent(
              peer: peer,
              presence: SessionPeerPresence.connected,
            ),
          ),
        );
        _messageController.add(
          ReceivedSessionEnvelope(
            envelope: SessionEnvelope.decode(event['envelope']! as String),
            peer: peer,
          ),
        );
      } on Object {
        return;
      }
    } else if (type == 'client_connected' || type == 'client_disconnected') {
      final SessionPeerEvent? peerEvent = peerEventFromNative(event);
      if (peerEvent != null) {
        _emitPeerEvents(_peerPresence.apply(peerEvent));
      }
    } else if (type == 'backgrounded' || type == 'listener_failed') {
      _disconnectAllKnownPeers();
      _setState(SessionConnectionState.stale);
    } else if (type == 'foregrounded' && _invitation != null) {
      _disconnectAllKnownPeers();
      _setState(SessionConnectionState.hosting);
    }
  }

  void _disconnectAllKnownPeers() {
    _emitPeerEvents(_peerPresence.disconnectAll());
  }

  void _emitPeerEvents(Iterable<SessionPeerEvent> events) {
    if (_peerEventController.isClosed) {
      return;
    }
    for (final SessionPeerEvent event in events) {
      _peerEventController.add(event);
    }
  }

  /// Converts identity metadata asserted by the native WebSocket listener.
  static SessionPeerEvent? peerEventFromNative(Map<Object?, Object?> event) {
    final Object? type = event['type'];
    final Object? clientId = event['clientId'];
    final Object? roleValue = event['role'];
    final Object? deviceToken = event['deviceToken'];
    if ((type != 'client_connected' && type != 'client_disconnected') ||
        clientId is! String ||
        clientId.trim().isEmpty ||
        roleValue is! String ||
        !_isDeviceToken(deviceToken)) {
      return null;
    }
    try {
      final SessionRole role = SessionRole.values.firstWhere(
        (SessionRole candidate) => candidate.name == roleValue,
      );
      if (role != SessionRole.participant &&
          role != SessionRole.controller &&
          role != SessionRole.display) {
        return null;
      }
      return SessionPeerEvent(
        peer: AuthenticatedSessionPeer(
          connectionId: clientId,
          role: role,
          deviceToken: deviceToken! as String,
        ),
        presence: type == 'client_connected'
            ? SessionPeerPresence.connected
            : SessionPeerPresence.disconnected,
      );
    } on StateError {
      return null;
    }
  }

  static bool _isDeviceToken(Object? value) {
    return value is String && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);
  }

  void _setState(SessionConnectionState state) {
    if (_connectionState == state) {
      return;
    }
    _connectionState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _methodChannel.invokeMethod<void>('stopHost');
    await _eventSubscription?.cancel();
    _disconnectAllKnownPeers();
    _setState(SessionConnectionState.closed);
    await _messageController.close();
    await _peerEventController.close();
    await _stateController.close();
  }
}
