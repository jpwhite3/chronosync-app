// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/data/transports/transport_heartbeat.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:uuid/uuid.dart';

import 'session_presentation.dart';

const Uuid _uuid = Uuid();

Future<void> main() async {
  final NearbyClientApp app = NearbyClientApp();
  await app.start();
}

final class NearbyClientApp {
  final html.BodyElement _body = html.document.body!;
  final html.Element _entryPanel = _element('entry-panel');
  final html.Element _livePanel = _element('live-panel');
  final html.Element _fatalPanel = _element('fatal-panel');
  final html.Element _fatalMessage = _element('fatal-message');
  final html.Element _connectionBanner = _element('connection-banner');
  final html.Element _connectionLabel = _element('connection-label');
  final html.Element _planTitle = _element('plan-title');
  final html.Element _roleLabel = _element('role-label');
  final html.Element _statusLabel = _element('session-status');
  final html.Element _stepPosition = _element('step-position');
  final html.Element _currentStep = _element('current-step');
  final html.Element _stepAnnouncement = _element('step-announcement');
  final html.Element _nextStep = _element('next-step');
  final html.Element _elapsed = _element('elapsed');
  final html.Element _remaining = _element('remaining');
  final html.Element _remainingCaption = _element('remaining-caption');
  final html.Element _progress = _element('progress-fill');
  final html.InputElement _displayName =
      _element('display-name') as html.InputElement;
  final html.ButtonElement _connectButton =
      _element('connect-button') as html.ButtonElement;
  final html.ButtonElement _reconnectButton =
      _element('reconnect-button') as html.ButtonElement;
  final html.ButtonElement _acknowledgeButton =
      _element('acknowledge-button') as html.ButtonElement;
  final html.ButtonElement _pauseResumeButton =
      _element('pause-resume-button') as html.ButtonElement;
  final html.ButtonElement _advanceButton =
      _element('advance-button') as html.ButtonElement;
  final html.ButtonElement _subtractMinuteButton =
      _element('subtract-minute-button') as html.ButtonElement;
  final html.ButtonElement _addMinuteButton =
      _element('add-minute-button') as html.ButtonElement;
  final html.Element _nameField = _element('name-field');
  final html.Element _entryRole = _element('entry-role');
  final html.Element _actionPanel = _element('action-panel');
  final html.Element _acknowledgementControls = _element(
    'acknowledgement-controls',
  );
  final html.Element _controllerControls = _element('controller-controls');

  Invitation? _invitation;
  SessionEnvelopeCrypto? _crypto;
  LiveSession? _session;
  html.WebSocket? _socket;
  Timer? _clockTimer;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeatResponseAt;
  DateTime? _frozenAt;
  Duration? _hostClockOffset;
  NearbySessionPresentation? _lastRenderedView;
  String? _authenticationSecret;
  late final String _deviceId;
  late final String _deviceToken;
  bool _connected = false;
  bool _synchronized = false;
  bool _joinSentForConnection = false;
  bool _joinConfirmed = false;
  int? _joinBaseRevision;
  int _reconnectAttempt = 0;
  bool _removed = false;

  Future<void> start() async {
    _connectButton.onClick.listen((html.MouseEvent _) => _beginFromEntry());
    _reconnectButton.onClick.listen(
      (html.MouseEvent _) => _connect(manual: true),
    );
    _acknowledgeButton.onClick.listen((html.MouseEvent _) => _acknowledge());
    _pauseResumeButton.onClick.listen((html.MouseEvent _) => _pauseOrResume());
    _advanceButton.onClick.listen((html.MouseEvent _) => _advance());
    _subtractMinuteButton.onClick.listen(
      (html.MouseEvent _) => _adjustRemaining(-60),
    );
    _addMinuteButton.onClick.listen(
      (html.MouseEvent _) => _adjustRemaining(60),
    );
    _displayName.onKeyDown.listen((html.KeyboardEvent event) {
      if (event.key == 'Enter') {
        _beginFromEntry();
      }
    });
    html.window.onBeforeUnload.listen((html.Event _) {
      _reconnectTimer?.cancel();
      _clockTimer?.cancel();
      _heartbeatTimer?.cancel();
      _socket?.close();
    });

    try {
      final Uri invitationUri = Uri.parse(html.window.location.href);
      try {
        html.window.history.replaceState(
          null,
          html.document.title,
          fragmentFreeNearbyUrl(invitationUri).toString(),
        );
      } on Object {
        // History can be unavailable in restricted browser contexts. Keep the
        // join flow usable; the fragment is never sent in the HTTP request.
      }
      final Invitation invitation = Invitation.fromQrPayload(
        invitationUri.toString(),
      );
      if (invitation.transport != SessionTransportKind.nearbyLan) {
        throw const FormatException('This is not a nearby invitation.');
      }
      if (invitation.isExpiredAt(DateTime.now())) {
        throw const FormatException('This invitation has expired.');
      }
      _invitation = invitation;
      _crypto = SessionEnvelopeCrypto(invitation.sessionSecret);
      await _restoreOrCreateDeviceIdentity();
      _deviceToken = await SessionDeviceToken.derive(
        deviceId: _deviceId,
        sessionSecret: invitation.sessionSecret,
      );
      _configureEntry(invitation);
      _clockTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (Timer _) => _renderSession(),
      );
    } on Object catch (error) {
      _showFatal(_friendlyError(error));
    }
  }

  Future<void> _restoreOrCreateDeviceIdentity() async {
    final Invitation invitation = _invitation!;
    // Local storage intentionally keeps anonymous identity stable across
    // ordinary tabs. Clearing site data still creates a new anonymous device.
    final html.Storage storage = html.window.localStorage;
    final NearbyResolvedIdentity identity = await restoreOrCreateNearbyIdentity(
      sessionId: invitation.sessionId,
      read: (String key) => storage[key],
      write: (String key, String value) => storage[key] = value,
      createDeviceId: _uuid.v4,
      createAuthenticationSecret: () async =>
          (await SessionSecrets.generate()).capability,
    );
    _deviceId = identity.deviceId;
    _authenticationSecret = identity.authenticationSecret;
  }

  void _configureEntry(Invitation invitation) {
    final bool isDisplay = invitation.requestedRole == SessionRole.display;
    _body.classes.toggle('display-mode', isDisplay);
    _entryRole.text = isDisplay ? 'Fullscreen display' : 'Team participant';
    _nameField.hidden = isDisplay;
    _connectButton.text = isDisplay ? 'Open display' : 'Join live session';
    _roleLabel.text = isDisplay ? 'Display' : 'Participant';
    _actionPanel.hidden = isDisplay;
    _entryPanel.hidden = false;
    _fatalPanel.hidden = true;

    if (!isDisplay) {
      final String? savedName =
          html.window.localStorage['chronosync.nearby.display_name'];
      final String? normalizedName = normalizeNearbyDisplayName(savedName);
      if (normalizedName != null) {
        _displayName.value = normalizedName;
      }
      _displayName.focus();
    }
  }

  void _beginFromEntry() {
    final Invitation? invitation = _invitation;
    if (invitation == null) {
      return;
    }
    if (invitation.requestedRole == SessionRole.participant) {
      final String? displayName = normalizeNearbyDisplayName(
        _displayName.value,
      );
      if (displayName == null) {
        _displayName
          ..setCustomValidity('Enter the name your team will see.')
          ..reportValidity();
        return;
      }
      _displayName.setCustomValidity('');
      _displayName.value = displayName;
      html.window.localStorage['chronosync.nearby.display_name'] = displayName;
    }
    _entryPanel.hidden = true;
    _livePanel.hidden = false;
    _connect(manual: true);
  }

  void _connect({required bool manual}) {
    final Invitation? invitation = _invitation;
    if (invitation == null ||
        _removed ||
        invitation.isExpiredAt(DateTime.now()) ||
        _socket?.readyState == html.WebSocket.CONNECTING ||
        _socket?.readyState == html.WebSocket.OPEN) {
      if (invitation?.isExpiredAt(DateTime.now()) ?? false) {
        _showConnection(
          'Invitation expired',
          state: ConnectionVisualState.error,
        );
      }
      return;
    }
    _reconnectTimer?.cancel();
    if (manual) {
      _reconnectAttempt = 0;
    }
    _connected = false;
    _synchronized = false;
    _joinSentForConnection = false;
    _joinConfirmed = false;
    _joinBaseRevision = null;
    _showConnection(
      _session == null ? 'Connecting to host…' : 'Reconnecting · timing frozen',
      state: ConnectionVisualState.connecting,
    );

    final Uri invitationEndpoint = invitation.endpoint;
    final Uri socketEndpoint = Uri(
      scheme: invitationEndpoint.scheme == 'https' ? 'wss' : 'ws',
      userInfo: invitationEndpoint.userInfo,
      host: invitationEndpoint.host,
      port: invitationEndpoint.hasPort ? invitationEndpoint.port : null,
      path: '/ws',
    );
    final html.WebSocket socket =
        html.WebSocket(socketEndpoint.toString(), <String>[
          'chronosync.v$sessionProtocolVersion',
          'role.${invitation.requestedRole.name}',
          'cap.${invitation.capability.replaceAll(RegExp(r'=+$'), '')}',
          'device.$_deviceToken',
        ]);
    _socket = socket;
    socket.onOpen.listen((html.Event _) {
      if (!identical(_socket, socket)) {
        return;
      }
      _connected = true;
      _lastHeartbeatResponseAt = DateTime.now().toUtc();
      _startHeartbeat(socket);
      _showConnection(
        'Connected · verifying session…',
        state: ConnectionVisualState.connecting,
      );
    });
    socket.onMessage.listen((html.MessageEvent event) {
      if (!identical(_socket, socket) || event.data is! String) {
        return;
      }
      unawaited(_handleMessage(event.data! as String));
    });
    socket.onClose.listen((html.CloseEvent event) {
      if (!identical(_socket, socket)) {
        return;
      }
      _socket = null;
      if (event.code == 4003) {
        _removed = true;
        _heartbeatTimer?.cancel();
        _reconnectTimer?.cancel();
        _connected = false;
        _synchronized = false;
        _joinConfirmed = false;
        _frozenAt ??= _hostNow();
        _showConnection(
          'Removed from this session',
          state: ConnectionVisualState.error,
        );
        _reconnectButton.hidden = true;
        _renderSession();
        return;
      }
      _connectionLost();
    });
    socket.onError.listen((html.Event _) {
      if (!identical(_socket, socket)) {
        return;
      }
      _showConnection(
        'Can’t reach host · retrying',
        state: ConnectionVisualState.error,
      );
      socket.close();
    });
  }

  Future<void> _handleMessage(String encoded) async {
    if (TransportHeartbeat.isPong(encoded)) {
      _lastHeartbeatResponseAt = DateTime.now().toUtc();
      return;
    }
    final Invitation invitation = _invitation!;
    final DateTime localReceivedAt = DateTime.now().toUtc();
    try {
      final SessionEnvelope envelope = SessionEnvelope.decode(encoded);
      if (envelope.sessionId != invitation.sessionId ||
          envelope.kind != SessionMessageKind.snapshot) {
        return;
      }
      final Map<String, Object?> payload = await _crypto!.open(envelope);
      final Object? rawSession = payload['session'];
      if (payload['type'] != 'snapshot' ||
          rawSession is! Map<Object?, Object?>) {
        throw const FormatException('The host sent an invalid snapshot.');
      }
      final LiveSession incoming = LiveSession.fromJson(
        Map<String, Object?>.from(rawSession),
      );
      final LiveSession? current = _session;
      if (current != null && incoming.revision < current.revision) {
        return;
      }
      _session = incoming;
      _hostClockOffset = calculateHostClockOffset(
        localReceivedAt: localReceivedAt,
        authenticatedHostSentAt: envelope.sentAt,
      );
      _synchronized = true;
      _frozenAt = null;
      _reconnectAttempt = 0;

      if (invitation.requestedRole == SessionRole.participant) {
        final NearbyJoinSnapshotAction joinAction = decideNearbyJoinOnSnapshot(
          joinSent: _joinSentForConnection,
          joinConfirmed: _joinConfirmed,
          joinBaseRevision: _joinBaseRevision,
          incomingRevision: incoming.revision,
          participantConnected:
              incoming.participantFor(_deviceId)?.connectionState ==
              ParticipantConnectionState.connected,
        );
        switch (joinAction) {
          case NearbyJoinSnapshotAction.wait:
            break;
          case NearbyJoinSnapshotAction.confirm:
            _joinConfirmed = true;
          case NearbyJoinSnapshotAction.send:
            await _sendJoin(incoming);
          case NearbyJoinSnapshotAction.retry:
            _joinSentForConnection = false;
            _joinBaseRevision = null;
            await _sendJoin(incoming);
        }
      }
      _showConnection(
        _joinConfirmed || invitation.requestedRole == SessionRole.display
            ? 'Live with host'
            : 'Connected · joining team…',
        state: ConnectionVisualState.live,
      );
      _renderSession();
    } on Object {
      _showConnection(
        'Update could not be verified',
        state: ConnectionVisualState.error,
      );
    }
  }

  Future<void> _sendJoin(LiveSession session) async {
    _joinSentForConnection = true;
    _joinBaseRevision = session.revision;
    final String displayName =
        html.window.localStorage['chronosync.nearby.display_name'] ??
        'Participant';
    final DateTime issuedAt = DateTime.now().toUtc();
    final SessionCommand command = SessionCommand.join(
      id: _uuid.v4(),
      sessionId: session.id,
      actorDeviceId: _deviceId,
      baseRevision: session.revision,
      issuedAt: issuedAt,
      displayName: displayName,
      requestedRole: SessionRole.participant,
      authenticationSecret: _authenticationSecret!,
    );
    try {
      await _sendCommand(command, issuedAt: issuedAt);
    } on Object {
      _joinSentForConnection = false;
      _joinBaseRevision = null;
      rethrow;
    }
  }

  Future<void> _acknowledge() async {
    final LiveSession? session = _session;
    if (session == null || !_connected || !_synchronized || !_joinConfirmed) {
      return;
    }
    final Participant? participant = session.participantFor(_deviceId);
    if (participant == null) {
      return;
    }
    _acknowledgeButton.disabled = true;
    final DateTime issuedAt = DateTime.now().toUtc();
    final SessionCommand command = SessionCommand.acknowledge(
      id: _uuid.v4(),
      sessionId: session.id,
      actorDeviceId: _deviceId,
      actorRole: participant.role,
      baseRevision: session.revision,
      issuedAt: issuedAt,
      stepIndex: session.currentStepIndex,
    );
    try {
      await _sendCommand(command, issuedAt: issuedAt);
      _acknowledgeButton.text = 'Sending…';
    } on Object {
      _acknowledgeButton
        ..disabled = false
        ..text = 'Got it';
      _showConnection(
        'Couldn’t send · reconnect and try again',
        state: ConnectionVisualState.error,
      );
    }
  }

  Future<void> _pauseOrResume() async {
    final LiveSession? session = _controllerSession();
    if (session == null ||
        (session.status != LiveSessionStatus.running &&
            session.status != LiveSessionStatus.paused)) {
      return;
    }
    final Participant participant = session.participantFor(_deviceId)!;
    final DateTime issuedAt = DateTime.now().toUtc();
    final SessionCommand command = session.status == LiveSessionStatus.paused
        ? SessionCommand.resume(
            id: _uuid.v4(),
            sessionId: session.id,
            actorDeviceId: _deviceId,
            actorRole: participant.role,
            baseRevision: session.revision,
            issuedAt: issuedAt,
          )
        : SessionCommand.pause(
            id: _uuid.v4(),
            sessionId: session.id,
            actorDeviceId: _deviceId,
            actorRole: participant.role,
            baseRevision: session.revision,
            issuedAt: issuedAt,
          );
    await _sendControllerCommand(command, issuedAt: issuedAt);
  }

  Future<void> _advance() async {
    final LiveSession? session = _controllerSession();
    if (session == null || session.status != LiveSessionStatus.running) {
      return;
    }
    final Participant participant = session.participantFor(_deviceId)!;
    final DateTime issuedAt = DateTime.now().toUtc();
    await _sendControllerCommand(
      SessionCommand.advance(
        id: _uuid.v4(),
        sessionId: session.id,
        actorDeviceId: _deviceId,
        actorRole: participant.role,
        baseRevision: session.revision,
        issuedAt: issuedAt,
      ),
      issuedAt: issuedAt,
    );
  }

  Future<void> _adjustRemaining(int adjustmentSeconds) async {
    final LiveSession? session = _controllerSession();
    if (session == null ||
        !session.isActive ||
        session.adjustedCurrentStepDuration.inSeconds + adjustmentSeconds <=
            0) {
      return;
    }
    final Participant participant = session.participantFor(_deviceId)!;
    final DateTime issuedAt = DateTime.now().toUtc();
    await _sendControllerCommand(
      SessionCommand.adjustRemaining(
        id: _uuid.v4(),
        sessionId: session.id,
        actorDeviceId: _deviceId,
        actorRole: participant.role,
        baseRevision: session.revision,
        issuedAt: issuedAt,
        adjustmentSeconds: adjustmentSeconds,
      ),
      issuedAt: issuedAt,
    );
  }

  LiveSession? _controllerSession() {
    final LiveSession? session = _session;
    if (session == null ||
        !_connected ||
        !_synchronized ||
        !_joinConfirmed ||
        session.participantFor(_deviceId)?.role != SessionRole.controller) {
      return null;
    }
    return session;
  }

  Future<void> _sendControllerCommand(
    SessionCommand command, {
    required DateTime issuedAt,
  }) async {
    try {
      await _sendCommand(command, issuedAt: issuedAt);
    } on Object {
      _showConnection(
        'Couldn’t send · reconnect and try again',
        state: ConnectionVisualState.error,
      );
    }
  }

  Future<void> _sendCommand(
    SessionCommand command, {
    required DateTime issuedAt,
  }) async {
    final html.WebSocket? socket = _socket;
    if (socket == null || socket.readyState != html.WebSocket.OPEN) {
      throw StateError('The host connection is not open.');
    }
    final SessionEnvelope envelope = await _crypto!.seal(
      sessionId: command.sessionId,
      messageId: command.id,
      senderDeviceId: _deviceId,
      baseRevision: command.baseRevision,
      sentAt: issuedAt,
      kind: SessionMessageKind.command,
      payload: <String, Object?>{
        'type': 'command',
        'command': command.toJson(),
      },
    );
    socket.send(envelope.encode());
  }

  void _connectionLost() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastHeartbeatResponseAt = null;
    _connected = false;
    _synchronized = false;
    _joinConfirmed = false;
    _frozenAt ??= _hostNow();
    _showConnection(
      'Connection paused · timing frozen',
      state: ConnectionVisualState.error,
    );
    _renderSession();
    _scheduleReconnect();
  }

  void _startHeartbeat(html.WebSocket socket) {
    _heartbeatTimer?.cancel();
    socket.send(TransportHeartbeat.pingFrame);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (Timer _) {
      if (!identical(_socket, socket) ||
          socket.readyState != html.WebSocket.OPEN) {
        return;
      }
      final DateTime? lastResponseAt = _lastHeartbeatResponseAt;
      if (lastResponseAt == null ||
          TransportHeartbeat.isTimedOut(
            lastResponseAt: lastResponseAt,
            now: DateTime.now(),
            timeout: const Duration(seconds: 16),
          )) {
        _socket = null;
        socket.close(4000, 'Heartbeat timeout');
        _connectionLost();
        return;
      }
      // Display sockets remain application-level receive-only; this frame is
      // transport liveness and can never carry a session command.
      socket.send(TransportHeartbeat.pingFrame);
    });
  }

  void _scheduleReconnect() {
    final Invitation? invitation = _invitation;
    if (_removed ||
        invitation == null ||
        invitation.isExpiredAt(DateTime.now())) {
      return;
    }
    _reconnectAttempt += 1;
    final int delaySeconds = switch (_reconnectAttempt) {
      1 => 1,
      2 => 2,
      3 => 4,
      _ => 6,
    };
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: delaySeconds),
      () => _connect(manual: false),
    );
  }

  void _renderSession() {
    final LiveSession? session = _session;
    if (session == null) {
      return;
    }
    final DateTime displayNow =
        (_connected && _synchronized ? null : _frozenAt) ?? _hostNow();
    final Participant? participant = session.participantFor(_deviceId);
    final NearbySessionPresentation view =
        NearbySessionPresentation.fromSession(
          session: session,
          now: displayNow,
          deviceId: _deviceId,
          canSendCommands:
              _connected &&
              _synchronized &&
              _joinConfirmed &&
              participant != null,
          invitedRole: _invitation?.requestedRole ?? SessionRole.participant,
        );
    final NearbySessionPresentation? previous = _lastRenderedView;
    if (previous != null && previous.hasSameDomState(view)) {
      return;
    }
    final bool announceStep = shouldAnnounceNearbyStep(previous, view);
    _lastRenderedView = view;
    _planTitle.text = view.planTitle;
    _statusLabel.text = view.statusLabel;
    _stepPosition.text = view.stepPositionLabel;
    _currentStep.text = view.currentStepTitle;
    if (announceStep) {
      _stepAnnouncement.text = nearbyStepAnnouncement(view);
    }
    _nextStep.text = view.nextStepTitle;
    _elapsed.text = view.elapsedLabel;
    _remaining.text = view.remainingLabel;
    _remainingCaption.text = view.isOvertime ? 'Overtime' : 'Remaining';
    _progress.style.width = view.progressWidth;
    _body.classes.toggle('overtime', view.isOvertime);

    _roleLabel.text = view.roleLabel;
    _body.classes.toggle('display-mode', view.role == SessionRole.display);
    _actionPanel.hidden = !view.showsActionPanel;
    _acknowledgementControls.hidden = !view.showsAcknowledgementControl;
    _controllerControls.hidden = !view.showsControllerControls;
    _acknowledgeButton
      ..disabled = !view.canAcknowledge
      ..text = view.hasAcknowledged ? 'Got it ✓' : 'Got it';
    _pauseResumeButton
      ..disabled = !view.canPauseResume
      ..text = view.pauseResumeLabel;
    _advanceButton.disabled = !view.canAdvance;
    _subtractMinuteButton.disabled = !view.canSubtractMinute;
    _addMinuteButton.disabled = !view.canAddMinute;
  }

  DateTime _hostNow() {
    return applyHostClockOffset(DateTime.now().toUtc(), _hostClockOffset);
  }

  void _showConnection(String label, {required ConnectionVisualState state}) {
    _connectionLabel.text = label;
    _connectionBanner.className = 'connection ${state.name}';
    _reconnectButton.hidden =
        state != ConnectionVisualState.error ||
        (_invitation?.isExpiredAt(DateTime.now()) ?? true);
  }

  void _showFatal(String message) {
    _entryPanel.hidden = true;
    _livePanel.hidden = true;
    _fatalPanel.hidden = false;
    _fatalMessage.text = message;
  }

  String _friendlyError(Object error) {
    if (error is FormatException && error.message.isNotEmpty) {
      return error.message;
    }
    return 'This invitation could not be opened. Ask the host for a new QR code.';
  }
}

enum ConnectionVisualState { connecting, live, error }

html.Element _element(String id) {
  final html.Element? element = html.document.getElementById(id);
  if (element == null) {
    throw StateError('Nearby client element #$id is missing.');
  }
  return element;
}
