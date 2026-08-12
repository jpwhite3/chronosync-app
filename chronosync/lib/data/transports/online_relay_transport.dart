import 'dart:async';
import 'dart:convert';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/data/transports/transport_heartbeat.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SessionWebSocketConnector =
    WebSocketChannel Function(Uri uri, Iterable<String> protocols);

typedef RelayPayloadOpener =
    Future<SessionEnvelope> Function({
      required RelayPayloadCrypto crypto,
      required String sessionId,
      required String messageId,
      required int revision,
      required DateTime sentAt,
      required SessionMessageKind kind,
      required String nonce,
      required String ciphertext,
    });

final class OnlineRelayTransport implements SessionTransport {
  OnlineRelayTransport({
    required this.deviceId,
    Duration heartbeatInterval = const Duration(seconds: 10),
    Duration heartbeatTimeout = const Duration(seconds: 26),
    Duration hostPresenceTimeout = const Duration(seconds: 35),
    Duration reconnectBaseDelay = const Duration(seconds: 1),
    Duration peerDisconnectTimeout = const Duration(seconds: 5),
    Duration connectionTimeout = const Duration(seconds: 15),
    SessionWebSocketConnector? connectWebSocket,
    RelayPayloadOpener? openRelayPayload,
    DateTime Function()? now,
    Uuid uuid = const Uuid(),
  }) : _heartbeatInterval = heartbeatInterval,
       _heartbeatTimeout = heartbeatTimeout,
       _hostPresence = RelayHostPresenceTracker(timeout: hostPresenceTimeout),
       _reconnectBaseDelay = reconnectBaseDelay,
       _peerDisconnectTimeout = peerDisconnectTimeout,
       _connectionTimeout = connectionTimeout,
       _connectWebSocket = connectWebSocket ?? _defaultConnectWebSocket,
       _openRelayPayload = openRelayPayload ?? _defaultOpenRelayPayload,
       _now = now ?? DateTime.now,
       _uuid = uuid {
    if (heartbeatInterval <= Duration.zero ||
        heartbeatTimeout <= heartbeatInterval ||
        hostPresenceTimeout <= heartbeatInterval ||
        reconnectBaseDelay <= Duration.zero ||
        peerDisconnectTimeout <= Duration.zero ||
        connectionTimeout <= Duration.zero) {
      throw ArgumentError(
        'Relay and host-presence timeouts must be longer than the positive '
        'heartbeat interval.',
      );
    }
  }

  @override
  final String deviceId;

  final StreamController<ReceivedSessionEnvelope> _messageController =
      StreamController<ReceivedSessionEnvelope>.broadcast();
  final StreamController<SessionConnectionState> _stateController =
      StreamController<SessionConnectionState>.broadcast();
  final StreamController<SessionPeerEvent> _peerEventController =
      StreamController<SessionPeerEvent>.broadcast();
  final Duration _heartbeatInterval;
  final Duration _heartbeatTimeout;
  final Duration _reconnectBaseDelay;
  final Duration _peerDisconnectTimeout;
  final Duration _connectionTimeout;
  final RelayHostPresenceTracker _hostPresence;
  final SessionWebSocketConnector _connectWebSocket;
  final RelayPayloadOpener _openRelayPayload;
  final DateTime Function() _now;
  final Uuid _uuid;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _channelSubscription;
  Invitation? _invitation;
  RelayPayloadCrypto? _relayCrypto;
  bool _isHost = false;
  bool _closed = false;
  bool _terminallyClosed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeatResponseAt;
  String? _ownConnectionId;
  Map<String, AuthenticatedSessionPeer> _knownPeers =
      <String, AuthenticatedSessionPeer>{};
  final Map<String, _PendingPeerDisconnect> _pendingPeerDisconnects =
      <String, _PendingPeerDisconnect>{};
  final Map<String, _PendingPeerRoleUpdate> _pendingPeerRoleUpdates =
      <String, _PendingPeerRoleUpdate>{};
  final Set<String> _unconfirmedDeviceRevocations = <String>{};
  SessionConnectionState _connectionState = SessionConnectionState.idle;

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
    await _begin(invitation, isHost: true);
  }

  @override
  Future<void> join(Invitation invitation) async {
    await _begin(invitation, isHost: false);
  }

  Future<void> _begin(Invitation invitation, {required bool isHost}) async {
    if (_connectionState != SessionConnectionState.idle) {
      throw StateError('This transport has already been used.');
    }
    if (invitation.transport != SessionTransportKind.onlineRelay) {
      throw ArgumentError.value(
        invitation.transport,
        'invitation',
        'OnlineRelayTransport requires an online relay invitation.',
      );
    }
    if (invitation.isExpiredAt(_now())) {
      throw StateError('The invitation has expired.');
    }
    _invitation = invitation;
    _relayCrypto = RelayPayloadCrypto(invitation.sessionSecret);
    _isHost = isHost;
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

    try {
      final WebSocketChannel channel = _connectWebSocket(
        webSocketUriFor(invitation),
        await webSocketProtocolsFor(
          invitation: invitation,
          deviceId: deviceId,
          isHost: _isHost,
        ),
      );
      try {
        await channel.ready.timeout(_connectionTimeout);
      } on TimeoutException {
        unawaited(channel.sink.close(4000, 'Connection timed out'));
        throw TimeoutException(
          'The online relay did not connect in time.',
          _connectionTimeout,
        );
      }
      if (_closed) {
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _reconnectAttempt = 0;
      _ownConnectionId = null;
      _hostPresence.markAbsent();
      _setState(
        _isHost ? SessionConnectionState.hosting : SessionConnectionState.stale,
      );
      await _channelSubscription?.cancel();
      _channelSubscription = channel.stream
          .asyncMap<void>((Object? frame) => _handleFrame(frame, channel))
          .listen(
            (void _) {},
            onError: (Object error, StackTrace stackTrace) =>
                _handleDisconnect(channel),
            onDone: () => _handleDisconnect(channel),
            cancelOnError: true,
          );
      _lastHeartbeatResponseAt = _now().toUtc();
      _startHeartbeat(channel);
      _resendPeerDisconnects(channel);
      _resendPeerRoleUpdates(channel);
    } on Object {
      _setState(SessionConnectionState.stale);
      if (throwOnFailure) {
        rethrow;
      }
      _scheduleReconnect();
    }
  }

  @override
  Future<void> send(SessionEnvelope envelope) async {
    final WebSocketChannel? channel = _channel;
    if (channel == null ||
        (_connectionState != SessionConnectionState.hosting &&
            _connectionState != SessionConnectionState.connected)) {
      throw StateError('The relay is not connected.');
    }
    if (envelope.senderDeviceId != deviceId) {
      throw StateError('The envelope sender does not match this device.');
    }
    if (envelope.sessionId != _invitation?.sessionId) {
      throw StateError('The envelope belongs to a different session.');
    }
    final RelayPayloadCrypto? relayCrypto = _relayCrypto;
    if (relayCrypto == null) {
      throw StateError('The relay encryption context is unavailable.');
    }
    final RelayCiphertext encrypted = await relayCrypto.seal(envelope);
    if (_isHost && envelope.kind != SessionMessageKind.snapshot) {
      throw StateError('A relay host can publish snapshots only.');
    }
    if (!_isHost && envelope.kind != SessionMessageKind.command) {
      throw StateError('A relay guest can submit commands only.');
    }
    channel.sink.add(
      jsonEncode(<String, Object>{
        'type': _isHost ? 'snapshot' : 'command',
        'messageId': envelope.messageId,
        if (_isHost)
          'revision': envelope.baseRevision
        else
          'baseRevision': envelope.baseRevision,
        'sentAt': envelope.sentAt.toUtc().toIso8601String(),
        'nonce': encrypted.nonce,
        'ciphertext': encrypted.ciphertext,
      }),
    );
  }

  @override
  Future<void> disconnectPeer(String connectionId) async {
    final String normalizedConnectionId = connectionId.trim();
    if (normalizedConnectionId.isEmpty) {
      throw ArgumentError.value(
        connectionId,
        'connectionId',
        'A peer connection ID cannot be empty.',
      );
    }
    await _requestPeerDisconnect(
      type: 'disconnect_connection',
      targetField: 'connectionId',
      targetValue: normalizedConnectionId,
      durableRevocation: false,
    );
  }

  @override
  Future<void> revokeDevice(String deviceToken) async {
    final String normalizedDeviceToken = deviceToken.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(normalizedDeviceToken)) {
      throw ArgumentError.value(
        deviceToken,
        'deviceToken',
        'A device token must be a 43-character base64url value.',
      );
    }
    final Future<void> request = _requestPeerDisconnect(
      type: 'disconnect_peer',
      targetField: 'deviceToken',
      targetValue: normalizedDeviceToken,
      durableRevocation: true,
    );
    _unconfirmedDeviceRevocations.add(normalizedDeviceToken);
    await request;
  }

  @override
  Future<void> updatePeerRole(String deviceToken, SessionRole role) async {
    final String normalizedDeviceToken = deviceToken.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(normalizedDeviceToken)) {
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
    final WebSocketChannel? channel = _channel;
    if (!_isHost ||
        channel == null ||
        _connectionState != SessionConnectionState.hosting) {
      throw StateError('Only the connected relay host can update a peer role.');
    }
    for (final _PendingPeerRoleUpdate pending
        in _pendingPeerRoleUpdates.values) {
      if (pending.deviceToken == normalizedDeviceToken &&
          pending.role == role) {
        return pending.completer.future;
      }
    }
    final Completer<void> completer = Completer<void>();
    final _PendingPeerRoleUpdate pending = _PendingPeerRoleUpdate(
      requestId: _uuid.v4(),
      deviceToken: normalizedDeviceToken,
      role: role,
      completer: completer,
    );
    _pendingPeerRoleUpdates[pending.requestId] = pending;
    pending.timer = Timer(_peerDisconnectTimeout, () {
      if (_pendingPeerRoleUpdates.remove(pending.requestId) == null) {
        return;
      }
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'The relay did not acknowledge the peer role update.',
            _peerDisconnectTimeout,
          ),
        );
      }
    });
    _sendPeerRoleUpdate(channel, pending);
    return completer.future;
  }

  void _sendPeerRoleUpdate(
    WebSocketChannel channel,
    _PendingPeerRoleUpdate pending,
  ) {
    channel.sink.add(
      jsonEncode(<String, Object>{
        'type': 'set_peer_role',
        'requestId': pending.requestId,
        'deviceToken': pending.deviceToken,
        'role': pending.role.name,
      }),
    );
  }

  void _resendPeerRoleUpdates(WebSocketChannel channel) {
    for (final _PendingPeerRoleUpdate pending
        in _pendingPeerRoleUpdates.values) {
      _sendPeerRoleUpdate(channel, pending);
    }
  }

  Future<void> _requestPeerDisconnect({
    required String type,
    required String targetField,
    required String targetValue,
    required bool durableRevocation,
  }) {
    final WebSocketChannel? channel = _channel;
    if (!_isHost ||
        channel == null ||
        _connectionState != SessionConnectionState.hosting) {
      throw StateError('Only the connected relay host can disconnect a peer.');
    }
    for (final _PendingPeerDisconnect pending
        in _pendingPeerDisconnects.values) {
      if (pending.type == type && pending.targetValue == targetValue) {
        final Completer<void>? completer = pending.completer;
        if (completer != null) {
          return completer.future;
        }
      }
    }
    final Completer<void> completer = Completer<void>();
    final _PendingPeerDisconnect pending = _PendingPeerDisconnect(
      requestId: _uuid.v4(),
      type: type,
      targetField: targetField,
      targetValue: targetValue,
      durableRevocation: durableRevocation,
      completer: completer,
    );
    _pendingPeerDisconnects[pending.requestId] = pending;
    pending.timer = Timer(_peerDisconnectTimeout, () {
      if (_pendingPeerDisconnects.remove(pending.requestId) == null) {
        return;
      }
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'The relay did not acknowledge the peer disconnection.',
            _peerDisconnectTimeout,
          ),
        );
      }
    });
    _sendPeerDisconnect(channel, pending);
    return completer.future;
  }

  void _sendPeerDisconnect(
    WebSocketChannel channel,
    _PendingPeerDisconnect pending,
  ) {
    channel.sink.add(
      jsonEncode(<String, Object>{
        'type': pending.type,
        'requestId': pending.requestId,
        pending.targetField: pending.targetValue,
      }),
    );
  }

  void _resendPeerDisconnects(WebSocketChannel channel) {
    for (final _PendingPeerDisconnect pending
        in _pendingPeerDisconnects.values) {
      _sendPeerDisconnect(channel, pending);
    }
    final Set<String> pendingTokens = _pendingPeerDisconnects.values
        .where((_PendingPeerDisconnect pending) => pending.durableRevocation)
        .map((_PendingPeerDisconnect pending) => pending.targetValue)
        .toSet();
    for (final String token in _unconfirmedDeviceRevocations.difference(
      pendingTokens,
    )) {
      final _PendingPeerDisconnect retry = _PendingPeerDisconnect(
        requestId: _uuid.v4(),
        type: 'disconnect_peer',
        targetField: 'deviceToken',
        targetValue: token,
        durableRevocation: true,
        completer: null,
      );
      _pendingPeerDisconnects[retry.requestId] = retry;
      _sendPeerDisconnect(channel, retry);
    }
  }

  Future<void> _handleFrame(Object? frame, WebSocketChannel channel) async {
    if (!identical(_channel, channel) ||
        _closed ||
        _terminallyClosed ||
        frame is! String) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(frame);
      if (decoded is! Map<Object?, Object?>) {
        return;
      }
      final Map<String, Object?> message = Map<String, Object?>.from(decoded);
      final String? type = message['type'] as String?;
      _applyAuthoritativeHostStatus(message);
      if (type == 'pong') {
        _touchHeartbeat();
        return;
      }
      if (type == 'peer_disconnect_result') {
        _handlePeerDisconnectResult(message);
        return;
      }
      if (type == 'peer_role_result') {
        _handlePeerRoleResult(message);
        return;
      }
      if (type == 'snapshot' || type == 'command') {
        final Object? revisionValue = type == 'snapshot'
            ? message['revision']
            : message['baseRevision'];
        final Object? messageIdValue = message['messageId'];
        final Object? sentAtValue = message['sentAt'];
        final Object? nonceValue = message['nonce'];
        final Object? ciphertextValue = message['ciphertext'];
        if (revisionValue is! int ||
            messageIdValue is! String ||
            sentAtValue is! String ||
            nonceValue is! String ||
            ciphertextValue is! String) {
          return;
        }
        final DateTime? sentAt = DateTime.tryParse(sentAtValue);
        final RelayPayloadCrypto? relayCrypto = _relayCrypto;
        final Invitation? invitation = _invitation;
        if (sentAt == null || relayCrypto == null || invitation == null) {
          return;
        }
        final SessionEnvelope envelope = await _openRelayPayload(
          crypto: relayCrypto,
          sessionId: invitation.sessionId,
          messageId: messageIdValue,
          revision: revisionValue,
          sentAt: sentAt.toUtc(),
          kind: type == 'snapshot'
              ? SessionMessageKind.snapshot
              : SessionMessageKind.command,
          nonce: nonceValue,
          ciphertext: ciphertextValue,
        );
        if (!identical(_channel, channel) || _closed || _terminallyClosed) {
          return;
        }
        final AuthenticatedSessionPeer? peer = type == 'snapshot'
            ? AuthenticatedSessionPeer(
                connectionId: 'relay-host',
                role: SessionRole.host,
              )
            : authenticatedCommandPeer(message);
        if (peer == null) {
          return;
        }
        _messageController.add(
          ReceivedSessionEnvelope(envelope: envelope, peer: peer),
        );
        return;
      }

      if (type == 'welcome') {
        final Object? ownConnectionId = message['connectionId'];
        if (ownConnectionId is String && ownConnectionId.trim().isNotEmpty) {
          _ownConnectionId = ownConnectionId;
        }
        _touchHeartbeat();
        return;
      }
      if (type == 'presence') {
        _touchHeartbeat();
        _applyPresence(message['connections']);
        return;
      }
      if (type == 'room_closed') {
        _terminallyClosed = true;
        _reconnectTimer?.cancel();
        _hostPresence.markAbsent();
        _setState(SessionConnectionState.closed);
        return;
      }
      if (type == 'error' &&
          (message['code'] == 'host_replaced' ||
              message['code'] == 'host_unavailable' ||
              message['code'] == 'host_heartbeat_timeout')) {
        _hostPresence.markAbsent();
        _setState(SessionConnectionState.stale);
        return;
      }
    } on Object {
      // Malformed, unauthenticated, or unknown relay frames are ignored.
    }
  }

  void _handlePeerDisconnectResult(Map<String, Object?> message) {
    final Object? requestIdValue = message['requestId'];
    final Object? statusValue = message['status'];
    if (requestIdValue is! String || statusValue is! String) {
      return;
    }
    final _PendingPeerDisconnect? pending =
        _pendingPeerDisconnects[requestIdValue];
    if (pending == null ||
        message[pending.targetField] != pending.targetValue ||
        (statusValue != 'disconnected' &&
            statusValue != 'not_found' &&
            statusValue != 'failed')) {
      return;
    }
    _pendingPeerDisconnects.remove(requestIdValue);
    pending.timer?.cancel();
    final Completer<void>? completer = pending.completer;
    if (statusValue == 'failed') {
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StateError(
            'The relay could not disconnect the peer'
            '${message['errorCode'] is String ? ': ${message['errorCode']}.' : '.'}',
          ),
        );
      }
      return;
    }
    if (pending.durableRevocation) {
      _unconfirmedDeviceRevocations.remove(pending.targetValue);
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _handlePeerRoleResult(Map<String, Object?> message) {
    final Object? requestIdValue = message['requestId'];
    final Object? deviceTokenValue = message['deviceToken'];
    final Object? roleValue = message['role'];
    final Object? statusValue = message['status'];
    if (requestIdValue is! String ||
        deviceTokenValue is! String ||
        roleValue is! String ||
        statusValue is! String) {
      return;
    }
    final _PendingPeerRoleUpdate? pending =
        _pendingPeerRoleUpdates[requestIdValue];
    if (pending == null ||
        pending.deviceToken != deviceTokenValue ||
        pending.role.name != roleValue ||
        (statusValue != 'updated' &&
            statusValue != 'not_found' &&
            statusValue != 'failed')) {
      return;
    }
    _pendingPeerRoleUpdates.remove(requestIdValue);
    pending.timer?.cancel();
    if (statusValue == 'failed') {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          StateError(
            'The relay could not update the peer role'
            '${message['errorCode'] is String ? ': ${message['errorCode']}.' : '.'}',
          ),
        );
      }
      return;
    }
    if (!pending.completer.isCompleted) {
      pending.completer.complete();
    }
  }

  /// Reads only the sender identity attached by the relay after capability
  /// authentication. Encrypted client payloads cannot supply this field.
  static AuthenticatedSessionPeer? authenticatedCommandPeer(
    Map<String, Object?> message,
  ) {
    final Object? senderValue = message['sender'];
    if (senderValue is! Map<Object?, Object?>) {
      return null;
    }
    final Map<String, Object?> sender = Map<String, Object?>.from(senderValue);
    final Object? connectionIdValue = sender['connectionId'];
    final Object? deviceTokenValue = sender['deviceToken'];
    final SessionRole? role = _sessionRole(sender['role']);
    if (connectionIdValue is! String ||
        connectionIdValue.trim().isEmpty ||
        deviceTokenValue is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(deviceTokenValue) ||
        role == null ||
        (role != SessionRole.controller && role != SessionRole.participant)) {
      return null;
    }
    return AuthenticatedSessionPeer(
      connectionId: connectionIdValue,
      role: role,
      deviceToken: deviceTokenValue,
    );
  }

  static SessionRole? _sessionRole(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final SessionRole role in SessionRole.values) {
      if (role.name == value) {
        return role;
      }
    }
    return null;
  }

  /// Parses only relay-attested room presence entries.
  static Map<String, AuthenticatedSessionPeer> authenticatedPresencePeers(
    Object? connectionsValue,
  ) {
    final Map<String, AuthenticatedSessionPeer> peers =
        <String, AuthenticatedSessionPeer>{};
    if (connectionsValue is! List<Object?>) {
      return peers;
    }
    for (final Object? value in connectionsValue) {
      if (value is! Map<Object?, Object?>) {
        continue;
      }
      final Object? connectionIdValue = value['connectionId'];
      final Object? deviceTokenValue = value['deviceToken'];
      final SessionRole? role = _sessionRole(value['role']);
      if (connectionIdValue is! String ||
          connectionIdValue.trim().isEmpty ||
          role == null ||
          (role != SessionRole.host &&
              (deviceTokenValue is! String ||
                  !RegExp(
                    r'^[A-Za-z0-9_-]{43}$',
                  ).hasMatch(deviceTokenValue)))) {
        continue;
      }
      peers[connectionIdValue] = AuthenticatedSessionPeer(
        connectionId: connectionIdValue,
        role: role,
        deviceToken: deviceTokenValue is String ? deviceTokenValue : null,
      );
    }
    return peers;
  }

  /// Extracts the relay's authoritative host-presence assertion.
  ///
  /// New relays include `hostConnected` on welcome, presence, and pong frames.
  /// Presence-list derivation preserves compatibility with an older relay
  /// while pong frames without an explicit assertion do not prove host life.
  static bool? authoritativeHostConnected(Map<String, Object?> message) {
    final Object? type = message['type'];
    if (type != 'welcome' && type != 'presence' && type != 'pong') {
      return null;
    }
    final Object? explicit = message['hostConnected'];
    if (explicit is bool) {
      return explicit;
    }
    if (type != 'presence') {
      return null;
    }
    return authenticatedPresencePeers(message['connections']).values.any(
      (AuthenticatedSessionPeer peer) => peer.role == SessionRole.host,
    );
  }

  /// Returns true once no relay-attested host proof has arrived in [timeout].
  static bool isAuthoritativeHostStale({
    required DateTime? lastConfirmedAt,
    required DateTime now,
    required Duration timeout,
  }) {
    if (lastConfirmedAt == null) {
      return true;
    }
    return !now.toUtc().isBefore(lastConfirmedAt.toUtc().add(timeout));
  }

  void _applyPresence(Object? connectionsValue) {
    final Map<String, AuthenticatedSessionPeer> present =
        authenticatedPresencePeers(connectionsValue);
    if (!_isHost) {
      return;
    }

    final Map<String, AuthenticatedSessionPeer> visible =
        <String, AuthenticatedSessionPeer>{
          for (final MapEntry<String, AuthenticatedSessionPeer> entry
              in present.entries)
            if (entry.key != _ownConnectionId &&
                entry.value.role != SessionRole.host)
              entry.key: entry.value,
        };
    for (final MapEntry<String, AuthenticatedSessionPeer> previous
        in _knownPeers.entries) {
      final AuthenticatedSessionPeer? current = visible[previous.key];
      if (current == null) {
        _emitPeerEvent(previous.value, SessionPeerPresence.disconnected);
      }
    }
    for (final MapEntry<String, AuthenticatedSessionPeer> current
        in visible.entries) {
      final AuthenticatedSessionPeer? previous = _knownPeers[current.key];
      if (previous == null || previous.role != current.value.role) {
        _emitPeerEvent(current.value, SessionPeerPresence.connected);
      }
    }
    _knownPeers = visible;
  }

  void _applyAuthoritativeHostStatus(Map<String, Object?> message) {
    if (_isHost || _closed) {
      return;
    }
    final bool? hostConnected = _hostPresence.observeRelayFrame(
      message,
      now: _now(),
    );
    if (hostConnected == null) {
      return;
    }
    _setState(
      hostConnected
          ? SessionConnectionState.connected
          : SessionConnectionState.stale,
    );
  }

  void _touchHeartbeat() {
    _lastHeartbeatResponseAt = _now().toUtc();
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
        _handleDisconnect(channel);
        unawaited(channel.sink.close(4000, 'Heartbeat timeout'));
        return;
      }
      if (!_isHost && _hostPresence.isStaleAt(_now())) {
        _hostPresence.markAbsent();
        _setState(SessionConnectionState.stale);
      }
      channel.sink.add(TransportHeartbeat.pingFrame);
    });
  }

  void _handleDisconnect(WebSocketChannel channel) {
    if (!identical(_channel, channel)) {
      return;
    }
    final bool shouldReconnect = shouldReconnectAfterClose(
      closeCode: channel.closeCode,
      isHost: _isHost,
    );
    _channel = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastHeartbeatResponseAt = null;
    _hostPresence.markAbsent();
    _ownConnectionId = null;
    _disconnectKnownPeers();
    if (_closed) {
      return;
    }
    if (_terminallyClosed || !shouldReconnect) {
      _terminallyClosed = true;
      _reconnectTimer?.cancel();
      _setState(SessionConnectionState.closed);
      return;
    }
    _setState(SessionConnectionState.stale);
    _scheduleReconnect();
  }

  void _disconnectKnownPeers() {
    for (final AuthenticatedSessionPeer peer in _knownPeers.values) {
      _emitPeerEvent(peer, SessionPeerPresence.disconnected);
    }
    _knownPeers = <String, AuthenticatedSessionPeer>{};
  }

  void _emitPeerEvent(
    AuthenticatedSessionPeer peer,
    SessionPeerPresence presence,
  ) {
    if (!_peerEventController.isClosed) {
      _peerEventController.add(
        SessionPeerEvent(peer: peer, presence: presence),
      );
    }
  }

  void _scheduleReconnect() {
    if (_closed || _terminallyClosed || _reconnectTimer?.isActive == true) {
      return;
    }
    final int exponent = _reconnectAttempt.clamp(0, 3);
    final Duration delay = _reconnectBaseDelay * (1 << exponent);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, () {
      _connect(throwOnFailure: false);
    });
  }

  /// Resolves the relay connection independently from the PWA join URL.
  ///
  /// This is public to make the security-sensitive URL split directly
  /// testable without opening a socket.
  static Uri webSocketUriFor(Invitation invitation) {
    final Uri endpoint = invitation.endpoint;
    final List<String> segments = <String>[
      ...endpoint.pathSegments.where((String segment) => segment.isNotEmpty),
    ];
    final bool alreadyConnectPath =
        segments.length >= 4 &&
        segments[segments.length - 4] == 'v1' &&
        segments[segments.length - 3] == 'rooms' &&
        segments[segments.length - 2] == invitation.sessionId &&
        segments.last == 'connect';
    if (!alreadyConnectPath) {
      segments
        ..add('v1')
        ..add('rooms')
        ..add(invitation.sessionId)
        ..add('connect');
    }
    return Uri(
      scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
      userInfo: endpoint.userInfo,
      host: endpoint.host,
      port: endpoint.hasPort ? endpoint.port : null,
      pathSegments: segments,
      query: endpoint.hasQuery ? endpoint.query : null,
    );
  }

  static Future<List<String>> webSocketProtocolsFor({
    required Invitation invitation,
    required String deviceId,
    required bool isHost,
  }) async {
    final String deviceToken = await SessionDeviceToken.derive(
      deviceId: deviceId,
      sessionSecret: invitation.sessionSecret,
    );
    return <String>[
      'chronosync.v$sessionProtocolVersion',
      'role.${isHost ? 'host' : invitation.requestedRole.name}',
      'cap.${invitation.capability.replaceAll(RegExp(r'=+$'), '')}',
      'device.$deviceToken',
    ];
  }

  static bool shouldReconnectAfterClose({
    required int? closeCode,
    required bool isHost,
  }) {
    return closeCode != 4003 && !(isHost && closeCode == 4001);
  }

  static WebSocketChannel _defaultConnectWebSocket(
    Uri uri,
    Iterable<String> protocols,
  ) {
    return WebSocketChannel.connect(uri, protocols: protocols);
  }

  static Future<SessionEnvelope> _defaultOpenRelayPayload({
    required RelayPayloadCrypto crypto,
    required String sessionId,
    required String messageId,
    required int revision,
    required DateTime sentAt,
    required SessionMessageKind kind,
    required String nonce,
    required String ciphertext,
  }) {
    return crypto.open(
      sessionId: sessionId,
      messageId: messageId,
      revision: revision,
      sentAt: sentAt,
      kind: kind,
      nonce: nonce,
      ciphertext: ciphertext,
    );
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
    await _channelSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    for (final _PendingPeerDisconnect pending
        in _pendingPeerDisconnects.values) {
      pending.timer?.cancel();
      final Completer<void>? completer = pending.completer;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StateError('The relay closed before disconnecting the peer.'),
        );
      }
    }
    _pendingPeerDisconnects.clear();
    for (final _PendingPeerRoleUpdate pending
        in _pendingPeerRoleUpdates.values) {
      pending.timer?.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          StateError('The relay closed before updating the peer role.'),
        );
      }
    }
    _pendingPeerRoleUpdates.clear();
    _unconfirmedDeviceRevocations.clear();
    _disconnectKnownPeers();
    _setState(SessionConnectionState.closed);
    await _messageController.close();
    await _peerEventController.close();
    await _stateController.close();
  }
}

final class _PendingPeerDisconnect {
  _PendingPeerDisconnect({
    required this.requestId,
    required this.type,
    required this.targetField,
    required this.targetValue,
    required this.durableRevocation,
    required this.completer,
  });

  final String requestId;
  final String type;
  final String targetField;
  final String targetValue;
  final bool durableRevocation;
  final Completer<void>? completer;
  Timer? timer;
}

final class _PendingPeerRoleUpdate {
  _PendingPeerRoleUpdate({
    required this.requestId,
    required this.deviceToken,
    required this.role,
    required this.completer,
  });

  final String requestId;
  final String deviceToken;
  final SessionRole role;
  final Completer<void> completer;
  Timer? timer;
}

/// Stateful, relay-attested proof of current authoritative host presence.
///
/// Every relay frame passes through this tracker. Frames without an explicit
/// host assertion—including retained snapshots—leave the current state
/// unchanged.
final class RelayHostPresenceTracker {
  RelayHostPresenceTracker({required this.timeout}) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  final Duration timeout;
  DateTime? _lastConfirmedAt;
  bool _hostConnected = false;

  bool get hostConnected => _hostConnected;

  bool? observeRelayFrame(
    Map<String, Object?> message, {
    required DateTime now,
  }) {
    final bool? assertion = OnlineRelayTransport.authoritativeHostConnected(
      message,
    );
    if (assertion == null) {
      return null;
    }
    _hostConnected = assertion;
    _lastConfirmedAt = assertion ? now.toUtc() : null;
    return assertion;
  }

  bool isStaleAt(DateTime now) {
    return OnlineRelayTransport.isAuthoritativeHostStale(
      lastConfirmedAt: _lastConfirmedAt,
      now: now,
      timeout: timeout,
    );
  }

  void markAbsent() {
    _hostConnected = false;
    _lastConfirmedAt = null;
  }
}
