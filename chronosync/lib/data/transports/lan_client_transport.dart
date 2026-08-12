import 'dart:async';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/data/transports/transport_heartbeat.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef LanWebSocketConnector =
    WebSocketChannel Function(Uri uri, Iterable<String> protocols);

/// Flutter client for an iPhone-hosted same-Wi-Fi session.
final class LanClientTransport implements SessionTransport {
  LanClientTransport({
    required this.deviceId,
    Duration heartbeatInterval = const Duration(seconds: 5),
    Duration heartbeatTimeout = const Duration(seconds: 16),
    Duration reconnectBaseDelay = const Duration(seconds: 1),
    LanWebSocketConnector? connectWebSocket,
    DateTime Function()? now,
  }) : _heartbeatInterval = heartbeatInterval,
       _heartbeatTimeout = heartbeatTimeout,
       _reconnectBaseDelay = reconnectBaseDelay,
       _connectWebSocket = connectWebSocket ?? _defaultConnectWebSocket,
       _now = now ?? DateTime.now {
    if (heartbeatInterval <= Duration.zero ||
        heartbeatTimeout <= heartbeatInterval ||
        reconnectBaseDelay <= Duration.zero) {
      throw ArgumentError(
        'The heartbeat timeout must be longer than its positive interval.',
      );
    }
  }

  @override
  final String deviceId;

  final StreamController<ReceivedSessionEnvelope> _messageController =
      StreamController<ReceivedSessionEnvelope>.broadcast();
  final StreamController<SessionConnectionState> _stateController =
      StreamController<SessionConnectionState>.broadcast();
  final Duration _heartbeatInterval;
  final Duration _heartbeatTimeout;
  final Duration _reconnectBaseDelay;
  final LanWebSocketConnector _connectWebSocket;
  final DateTime Function() _now;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Invitation? _invitation;
  SessionConnectionState _connectionState = SessionConnectionState.idle;
  bool _closed = false;
  bool _terminallyClosed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeatResponseAt;

  @override
  SessionConnectionState get connectionState => _connectionState;

  @override
  Stream<SessionConnectionState> get connectionStates =>
      _stateController.stream;

  @override
  Stream<ReceivedSessionEnvelope> get messages => _messageController.stream;

  @override
  Stream<SessionPeerEvent> get peerEvents =>
      const Stream<SessionPeerEvent>.empty();

  @override
  Future<void> join(Invitation invitation) async {
    if (_connectionState != SessionConnectionState.idle) {
      throw StateError('This nearby client has already been used.');
    }
    if (invitation.transport != SessionTransportKind.nearbyLan) {
      throw ArgumentError.value(
        invitation.transport,
        'invitation',
        'LanClientTransport requires a nearby invitation.',
      );
    }
    if (invitation.isExpiredAt(_now())) {
      throw StateError('The nearby invitation has expired.');
    }
    _invitation = invitation;
    await _connect(throwOnFailure: true);
  }

  Future<void> _connect({required bool throwOnFailure}) async {
    final Invitation? invitation = _invitation;
    if (_closed || _terminallyClosed || invitation == null) {
      return;
    }
    if (invitation.isExpiredAt(_now())) {
      _setState(SessionConnectionState.stale);
      return;
    }
    final Uri endpoint = webSocketUriFor(invitation);
    try {
      final WebSocketChannel channel = _connectWebSocket(
        endpoint,
        await webSocketProtocolsFor(invitation: invitation, deviceId: deviceId),
      );
      await channel.ready;
      if (_closed) {
        await channel.sink.close();
        return;
      }
      await _subscription?.cancel();
      _channel = channel;
      _reconnectAttempt = 0;
      _subscription = channel.stream.listen(
        _handleFrame,
        onDone: () => _markStale(channel),
        onError: (Object error, StackTrace stackTrace) => _markStale(channel),
        cancelOnError: true,
      );
      _lastHeartbeatResponseAt = _now().toUtc();
      _startHeartbeat(channel);
      _setState(SessionConnectionState.connected);
    } on Object {
      _setState(SessionConnectionState.stale);
      if (throwOnFailure) {
        rethrow;
      }
      _scheduleReconnect();
    }
  }

  static Uri webSocketUriFor(Invitation invitation) {
    final Uri endpoint = invitation.endpoint;
    return Uri(
      scheme: invitation.endpoint.scheme == 'https' ? 'wss' : 'ws',
      userInfo: endpoint.userInfo,
      host: endpoint.host,
      port: endpoint.hasPort ? endpoint.port : null,
      path: '/ws',
    );
  }

  static Future<List<String>> webSocketProtocolsFor({
    required Invitation invitation,
    required String deviceId,
  }) async {
    final String deviceToken = await SessionDeviceToken.derive(
      deviceId: deviceId,
      sessionSecret: invitation.sessionSecret,
    );
    return <String>[
      'chronosync.v$sessionProtocolVersion',
      'role.${invitation.requestedRole.name}',
      'cap.${invitation.capability.replaceAll(RegExp(r'=+$'), '')}',
      'device.$deviceToken',
    ];
  }

  static bool shouldReconnectAfterClose(int? closeCode) => closeCode != 4003;

  static WebSocketChannel _defaultConnectWebSocket(
    Uri uri,
    Iterable<String> protocols,
  ) {
    return WebSocketChannel.connect(uri, protocols: protocols);
  }

  @override
  Future<void> host(Invitation invitation) {
    throw UnsupportedError('LanClientTransport cannot host a session.');
  }

  @override
  Future<void> send(SessionEnvelope envelope) async {
    final WebSocketChannel? channel = _channel;
    if (channel == null ||
        _connectionState != SessionConnectionState.connected) {
      throw StateError('The nearby host is not connected.');
    }
    if (envelope.sessionId != _invitation?.sessionId ||
        envelope.senderDeviceId != deviceId) {
      throw StateError('The session envelope does not match this client.');
    }
    channel.sink.add(envelope.encode());
  }

  @override
  Future<void> disconnectPeer(String connectionId) {
    throw UnsupportedError('A nearby client cannot disconnect another peer.');
  }

  @override
  Future<void> revokeDevice(String deviceToken) {
    throw UnsupportedError('A nearby client cannot revoke another device.');
  }

  @override
  Future<void> updatePeerRole(String deviceToken, SessionRole role) {
    throw UnsupportedError('A nearby client cannot update another peer role.');
  }

  void _handleFrame(Object? frame) {
    if (TransportHeartbeat.isPong(frame)) {
      _lastHeartbeatResponseAt = _now().toUtc();
      return;
    }
    if (frame is! String) {
      return;
    }
    try {
      final SessionEnvelope envelope = SessionEnvelope.decode(frame);
      if (envelope.sessionId != _invitation?.sessionId ||
          envelope.kind != SessionMessageKind.snapshot) {
        return;
      }
      _messageController.add(
        ReceivedSessionEnvelope(
          envelope: envelope,
          peer: AuthenticatedSessionPeer(
            connectionId: 'nearby-host',
            role: SessionRole.host,
          ),
        ),
      );
    } on Object {
      return;
    }
  }

  void _startHeartbeat(WebSocketChannel channel) {
    _heartbeatTimer?.cancel();
    channel.sink.add(TransportHeartbeat.pingFrame);
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (Timer _) {
      if (!identical(_channel, channel) || _closed) {
        return;
      }
      final DateTime? lastResponseAt = _lastHeartbeatResponseAt;
      if (lastResponseAt == null ||
          TransportHeartbeat.isTimedOut(
            lastResponseAt: lastResponseAt,
            now: _now(),
            timeout: _heartbeatTimeout,
          )) {
        _markStale(channel);
        unawaited(channel.sink.close(4000, 'Heartbeat timeout'));
        return;
      }
      channel.sink.add(TransportHeartbeat.pingFrame);
    });
  }

  void _markStale([WebSocketChannel? disconnectedChannel]) {
    if (disconnectedChannel != null &&
        !identical(_channel, disconnectedChannel)) {
      return;
    }
    _channel = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastHeartbeatResponseAt = null;
    if (!_closed) {
      if (!shouldReconnectAfterClose(disconnectedChannel?.closeCode)) {
        _terminallyClosed = true;
        _reconnectTimer?.cancel();
        _setState(SessionConnectionState.closed);
        return;
      }
      _setState(SessionConnectionState.stale);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed || _terminallyClosed || _reconnectTimer?.isActive == true) {
      return;
    }
    final int exponent = _reconnectAttempt.clamp(0, 4);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(_reconnectBaseDelay * (1 << exponent), () {
      _connect(throwOnFailure: false);
    });
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
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(SessionConnectionState.closed);
    await _messageController.close();
    await _stateController.close();
  }
}
