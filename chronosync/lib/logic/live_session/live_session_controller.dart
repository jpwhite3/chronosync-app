import 'dart:async';

import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

/// Coordinates timestamp-derived presentation state with the authoritative
/// reducer, local history, cue delivery, and an optional shared transport.
final class LiveSessionController extends ChangeNotifier
    with WidgetsBindingObserver {
  LiveSessionController._({
    required LiveSession? session,
    required DeviceIdentity identity,
    required SessionRole role,
    required bool isHost,
    required SessionHistoryRepository historyRepository,
    required Clock clock,
    required Uuid uuid,
    required LiveCueDelivery? cueService,
    required SessionTransport? transport,
    required SessionEnvelopeCrypto? crypto,
    required String? sessionSecret,
    required String? deviceAuthenticationSecret,
    required bool requiresForegroundHosting,
    required SessionTransportKind? transportKind,
    required SessionRecoveryKind recoveryKind,
  }) : _session = session,
       _identity = identity,
       _role = role,
       _isHost = isHost,
       _historyRepository = historyRepository,
       _clock = clock,
       _uuid = uuid,
       _cueService = cueService,
       _transport = transport,
       _crypto = crypto,
       _sessionSecret = sessionSecret,
       _deviceAuthenticationSecret = deviceAuthenticationSecret,
       _requiresForegroundHosting = requiresForegroundHosting,
       _transportKind = transportKind,
       _recoveryKind = recoveryKind {
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (Timer timer) => unawaited(refresh()),
    );
    _cueSubscription = cueService?.cues.listen((LiveCue cue) {
      if (_shutdown) {
        return;
      }
      _lastCue = cue;
      _notifyListenersIfActive();
    });
    _messageSubscription = transport?.messages.listen(
      (ReceivedSessionEnvelope message) => unawaited(_handleEnvelope(message)),
      onError: (Object error, StackTrace stackTrace) {
        _setError('Live session messages were interrupted.');
      },
    );
    _connectionSubscription = transport?.connectionStates.listen(
      _handleConnectionState,
    );
    _peerEventSubscription = transport?.peerEvents.listen(
      _handlePeerEvent,
      onError: (Object error, StackTrace stackTrace) {
        _setError('Connected-device presence was interrupted.');
      },
    );
  }

  static Future<LiveSessionController> createSolo({
    required Plan plan,
    required DeviceIdentity identity,
    required SessionHistoryRepository historyRepository,
    Clock clock = const SystemClock(),
    Uuid uuid = const Uuid(),
    LiveCueDelivery? cueService,
  }) async {
    final DateTime now = clock.now().toUtc();
    final LiveSessionController controller = LiveSessionController._(
      session: LiveSession(
        id: uuid.v4(),
        planSnapshot: plan.snapshot(capturedAt: now),
        hostDeviceId: identity.deviceId,
      ),
      identity: identity,
      role: SessionRole.host,
      isHost: true,
      historyRepository: historyRepository,
      clock: clock,
      uuid: uuid,
      cueService: cueService,
      transport: null,
      crypto: null,
      sessionSecret: null,
      deviceAuthenticationSecret: null,
      requiresForegroundHosting: false,
      transportKind: null,
      recoveryKind: SessionRecoveryKind.solo,
    );
    await controller._persist();
    await controller.refresh();
    return controller;
  }

  /// Restores an authoritative local-only session after process termination.
  ///
  /// Shared sessions cannot use this path because their transport capability,
  /// encryption context, and connected-device authority are not persisted.
  static Future<LiveSessionController> recoverSolo({
    required LiveSession session,
    required DeviceIdentity identity,
    required SessionHistoryRepository historyRepository,
    Clock clock = const SystemClock(),
    Uuid uuid = const Uuid(),
    LiveCueDelivery? cueService,
  }) async {
    if (session.status == LiveSessionStatus.ended) {
      throw ArgumentError.value(
        session.status,
        'session',
        'An ended session cannot be recovered.',
      );
    }
    if (session.hostDeviceId != identity.deviceId) {
      throw ArgumentError.value(
        session.hostDeviceId,
        'session',
        'Only the original host device can recover a solo session.',
      );
    }
    if (session.participants.isNotEmpty ||
        !session.hasCompleteActivityHistory) {
      throw ArgumentError.value(
        session.id,
        'session',
        'A recoverable solo session must retain complete local authority.',
      );
    }
    final LiveSessionController controller = LiveSessionController._(
      session: session,
      identity: identity,
      role: SessionRole.host,
      isHost: true,
      historyRepository: historyRepository,
      clock: clock,
      uuid: uuid,
      cueService: cueService,
      transport: null,
      crypto: null,
      sessionSecret: null,
      deviceAuthenticationSecret: null,
      requiresForegroundHosting: false,
      transportKind: null,
      recoveryKind: SessionRecoveryKind.solo,
    );
    try {
      await controller._persist();
      await controller.refresh();
      return controller;
    } on Object catch (error, stackTrace) {
      await controller._cleanupAfterFailedInitialization();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<LiveSessionController> hostShared({
    required Plan plan,
    required DeviceIdentity identity,
    required Invitation invitation,
    required SessionTransport transport,
    required SessionHistoryRepository historyRepository,
    bool transportAlreadyHosting = false,
    Clock clock = const SystemClock(),
    Uuid uuid = const Uuid(),
    LiveCueDelivery? cueService,
    bool? requiresForegroundHosting,
  }) async {
    final LiveSessionController controller = LiveSessionController._(
      session: LiveSession(
        id: invitation.sessionId,
        planSnapshot: plan.snapshot(capturedAt: clock.now()),
        hostDeviceId: identity.deviceId,
      ),
      identity: identity,
      role: SessionRole.host,
      isHost: true,
      historyRepository: historyRepository,
      clock: clock,
      uuid: uuid,
      cueService: cueService,
      transport: transport,
      crypto: SessionEnvelopeCrypto(invitation.sessionSecret),
      sessionSecret: invitation.sessionSecret,
      deviceAuthenticationSecret: null,
      requiresForegroundHosting:
          requiresForegroundHosting ??
          (invitation.transport == SessionTransportKind.nearbyLan ||
              _platformRequiresForegroundHosting()),
      transportKind: invitation.transport,
      recoveryKind: SessionRecoveryKind.sharedHost,
    );
    try {
      if (!transportAlreadyHosting) {
        await transport.host(invitation);
      }
      await controller._persist();
      await controller._publishSnapshot();
      await controller.refresh();
      return controller;
    } on Object catch (error, stackTrace) {
      await controller._cleanupAfterFailedInitialization();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<LiveSessionController> joinShared({
    required DeviceIdentity identity,
    required Invitation invitation,
    required SessionTransport transport,
    required SessionHistoryRepository historyRepository,
    String? deviceAuthenticationSecret,
    Clock clock = const SystemClock(),
    Uuid uuid = const Uuid(),
    LiveCueDelivery? cueService,
  }) async {
    final String resolvedAuthenticationSecret =
        deviceAuthenticationSecret ??
        (await SessionSecrets.generate()).capability;
    final LiveSessionController controller = LiveSessionController._(
      session: null,
      identity: identity,
      role: invitation.requestedRole,
      isHost: false,
      historyRepository: historyRepository,
      clock: clock,
      uuid: uuid,
      cueService: cueService,
      transport: transport,
      crypto: SessionEnvelopeCrypto(invitation.sessionSecret),
      sessionSecret: invitation.sessionSecret,
      deviceAuthenticationSecret: resolvedAuthenticationSecret,
      requiresForegroundHosting: false,
      transportKind: invitation.transport,
      recoveryKind: SessionRecoveryKind.sharedParticipant,
    );
    controller._expectedSessionId = invitation.sessionId;
    try {
      await transport.join(invitation);
      return controller;
    } on Object catch (error, stackTrace) {
      await controller._cleanupAfterFailedInitialization();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  final SessionHistoryRepository _historyRepository;
  final Clock _clock;
  final Uuid _uuid;
  final LiveCueDelivery? _cueService;
  final SessionTransport? _transport;
  final SessionEnvelopeCrypto? _crypto;
  final String? _sessionSecret;
  final String? _deviceAuthenticationSecret;
  final bool _isHost;
  final bool _requiresForegroundHosting;
  final SessionTransportKind? _transportKind;
  final SessionRecoveryKind _recoveryKind;

  LiveSession? _session;
  final DeviceIdentity _identity;
  SessionRole _role;
  LiveCue? _lastCue;
  String? _lastError;
  String? _expectedSessionId;
  bool _autoAdvanceInProgress = false;
  bool _scheduledStartSubmitted = false;
  bool _hostForeground = true;
  bool _shutdown = false;
  Future<void>? _shutdownFuture;
  bool _joinSubmittedForConnection = false;
  int? _joinSubmittedAtRevision;
  bool _hasHostClockSample = false;
  Duration _hostClockOffset = Duration.zero;
  DateTime? _staleAt;
  Future<void> _hostQueue = Future<void>.value();
  final Map<String, String> _peerDeviceByConnection = <String, String>{};
  final Map<String, String> _deviceAuthenticationSecrets = <String, String>{};
  final Map<String, String> _deviceTransportTokens = <String, String>{};
  final Map<String, ParticipantConnectionState> _participantPresenceByDevice =
      <String, ParticipantConnectionState>{};
  final Map<String, SessionRole> _connectedPeerRolesByConnection =
      <String, SessionRole>{};
  final Set<String> _revokedDeviceIds = <String>{};
  final Set<String> _revokedConnectionIds = <String>{};
  Object? _lastRefreshPresentationKey;
  Timer? _ticker;
  StreamSubscription<LiveCue>? _cueSubscription;
  StreamSubscription<ReceivedSessionEnvelope>? _messageSubscription;
  StreamSubscription<SessionConnectionState>? _connectionSubscription;
  StreamSubscription<SessionPeerEvent>? _peerEventSubscription;

  LiveSession? get session => _session;

  DeviceIdentity get identity => _identity;

  SessionRole get role => _role;

  bool get isHost => _isHost;

  bool get isReady => _session != null;

  bool get isShared => _transport != null;

  LiveCue? get lastCue => _lastCue;

  String? get lastError => _lastError;

  DateTime get now => _staleAt ?? _synchronizedNow;

  DateTime get _synchronizedNow {
    final DateTime local = _clock.now().toUtc();
    return _isHost ? local : local.add(_hostClockOffset);
  }

  SessionConnectionState get connectionState =>
      _transport?.connectionState ??
      (_shutdown
          ? SessionConnectionState.closed
          : SessionConnectionState.hosting);

  bool get isStale =>
      !_hostForeground ||
      _staleAt != null ||
      connectionState == SessionConnectionState.stale ||
      connectionState == SessionConnectionState.closed;

  Duration get elapsed => _session?.elapsedAt(now) ?? Duration.zero;

  Duration get remaining => _session?.remainingAt(now) ?? Duration.zero;

  Duration get variance => _session?.scheduleVarianceAt(now) ?? Duration.zero;

  ParticipantConnectionState participantConnectionState(String deviceId) {
    return _participantPresenceByDevice[deviceId] ??
        _session?.participantFor(deviceId)?.connectionState ??
        ParticipantConnectionState.disconnected;
  }

  int get connectedParticipantCount {
    final LiveSession? current = _session;
    if (current == null) {
      return 0;
    }
    return current.participants
        .where(
          (Participant participant) =>
              participantConnectionState(participant.deviceId) ==
              ParticipantConnectionState.connected,
        )
        .length;
  }

  int get connectedDisplayCount => _connectedPeerRolesByConnection.values
      .where((SessionRole role) => role == SessionRole.display)
      .length;

  Future<void> unlockCues() async {
    await _cueService?.unlockAudio();
  }

  Future<void> refresh() async {
    if (_shutdown) {
      return;
    }
    final LiveSession? current = _session;
    final DateTime refreshNow = now;
    if (current == null) {
      _notifyForRefreshIfChanged(null, refreshNow);
      return;
    }

    if (_isHost &&
        !isStale &&
        current.status == LiveSessionStatus.waiting &&
        current.planSnapshot.plannedStartTime != null &&
        !refreshNow.isBefore(current.planSnapshot.plannedStartTime!) &&
        !_scheduledStartSubmitted) {
      _scheduledStartSubmitted = true;
      unawaited(
        start().onError((Object error, StackTrace stackTrace) {
          _scheduledStartSubmitted = false;
        }),
      );
    }

    if (_isHost && !isStale && current.status == LiveSessionStatus.running) {
      await _cueService?.evaluate(current, refreshNow);
      await _catchUpAutomaticSteps(refreshNow);
    } else if (!_isHost &&
        !isStale &&
        current.status == LiveSessionStatus.running) {
      await _cueService?.evaluate(current, refreshNow);
    }
    _notifyForRefreshIfChanged(_session, refreshNow);
  }

  Future<void> _catchUpAutomaticSteps(DateTime refreshNow) async {
    if (_autoAdvanceInProgress) {
      return;
    }
    _autoAdvanceInProgress = true;
    try {
      while (!_shutdown) {
        final LiveSession? current = _session;
        if (current == null ||
            current.status != LiveSessionStatus.running ||
            !current.currentStep.autoAdvance) {
          return;
        }
        final DateTime dueAt = current.currentStepStartedAt!
            .add(current.currentStepPausedDuration)
            .add(current.adjustedCurrentStepDuration);
        if (refreshNow.isBefore(dueAt)) {
          return;
        }
        final SessionCommand command = SessionCommand.advance(
          id: _uuid.v4(),
          sessionId: current.id,
          actorDeviceId: _identity.deviceId,
          actorRole: _role,
          baseRevision: current.revision,
          issuedAt: dueAt,
          automatically: true,
        );
        try {
          await _submit(command, occurredAt: dueAt);
        } on Object {
          return;
        }
      }
    } finally {
      _autoAdvanceInProgress = false;
    }
  }

  void _notifyForRefreshIfChanged(LiveSession? current, DateTime refreshNow) {
    final Object key = _refreshPresentationKey(current, refreshNow);
    if (key == _lastRefreshPresentationKey) {
      return;
    }
    _lastRefreshPresentationKey = key;
    _notifyListenersIfActive();
  }

  Object _refreshPresentationKey(LiveSession? current, DateTime refreshNow) {
    if (current == null) {
      return const ('waiting-for-snapshot',);
    }
    if (current.status == LiveSessionStatus.running) {
      final Duration elapsed = current.elapsedAt(refreshNow);
      final Duration remaining = current.remainingAt(refreshNow);
      final Duration variance = current.scheduleVarianceAt(refreshNow);
      final CueProfile profile =
          current.currentStep.cueOverride ??
          current.planSnapshot.defaultCueProfile;
      return (
        current.revision,
        current.currentStepIndex,
        elapsed.inSeconds,
        _displayedRemainingSeconds(remaining),
        variance.isNegative,
        variance.abs().inSeconds,
        remaining <= Duration(seconds: profile.approachingSeconds),
        remaining <= Duration.zero,
        remaining <= Duration(seconds: -profile.overdueSeconds),
        isStale,
      );
    }
    if (current.status == LiveSessionStatus.waiting &&
        current.planSnapshot.plannedStartTime != null) {
      final Duration untilStart = current.planSnapshot.plannedStartTime!
          .difference(refreshNow);
      return (
        current.revision,
        current.status,
        _displayedRemainingSeconds(untilStart),
        isStale,
      );
    }
    return (current.revision, current.status, isStale);
  }

  Future<void> start() {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.start(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
      ),
    );
  }

  Future<void> pause() {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.pause(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
      ),
    );
  }

  Future<void> resume() {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.resume(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
      ),
    );
  }

  Future<void> advance({bool automatically = false}) {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.advance(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        automatically: automatically,
      ),
    );
  }

  Future<void> adjustRemaining(int seconds) {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.adjustRemaining(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        adjustmentSeconds: seconds,
      ),
    );
  }

  Future<void> jumpTo(int stepIndex, {required bool confirmed}) {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.jump(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        targetStepIndex: stepIndex,
        confirmed: confirmed,
      ),
    );
  }

  Future<void> acknowledge() {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.acknowledge(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        stepIndex: current.currentStepIndex,
      ),
    );
  }

  Future<void> end({required bool confirmed}) {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.end(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        confirmed: confirmed,
      ),
    );
  }

  Future<void> changeParticipantRole(String deviceId, SessionRole role) {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.changeRole(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        targetDeviceId: deviceId,
        targetRole: role,
      ),
    );
  }

  Future<void> removeParticipant(String deviceId) {
    final LiveSession current = _requireSession();
    return _submit(
      SessionCommand.disconnectParticipant(
        id: _uuid.v4(),
        sessionId: current.id,
        actorDeviceId: _identity.deviceId,
        actorRole: _role,
        baseRevision: current.revision,
        issuedAt: now,
        targetDeviceId: deviceId,
      ),
    );
  }

  Future<void> _submit(SessionCommand command, {DateTime? occurredAt}) async {
    if (_shutdown) {
      throw StateError('The live session controller has been shut down.');
    }
    _lastError = null;
    if (_isHost) {
      if (isShared && isStale) {
        final StateError error = StateError(
          'The host must reconnect before the session can change.',
        );
        _setError('Reconnect before changing the live session.');
        throw error;
      }
      final Completer<void> completer = Completer<void>();
      _hostQueue = _hostQueue.then((_) async {
        try {
          await _applyHostCommandAndEvictParticipant(
            command,
            occurredAt: occurredAt,
          );
          completer.complete();
        } on Object catch (error, stackTrace) {
          _setError(_friendlyCommandError(error));
          completer.completeError(error, stackTrace);
        }
      });
      return completer.future;
    }

    final SessionEnvelopeCrypto crypto = _requireCrypto();
    final SessionTransport transport = _requireTransport();
    final SessionEnvelope envelope = await crypto.seal(
      sessionId: command.sessionId,
      messageId: command.id,
      senderDeviceId: _identity.deviceId,
      baseRevision: command.baseRevision,
      sentAt: now,
      kind: SessionMessageKind.command,
      payload: <String, Object?>{
        'type': 'command',
        'command': command.toJson(),
      },
    );
    try {
      await transport.send(envelope);
    } on Object {
      _setError('The command could not reach the host.');
      rethrow;
    }
  }

  Future<void> _sendJoinIfNeeded() async {
    final LiveSession? current = _session;
    if (_isHost ||
        current == null ||
        _role == SessionRole.display ||
        connectionState != SessionConnectionState.connected ||
        _joinSubmittedForConnection) {
      return;
    }
    final String? authenticationSecret = _deviceAuthenticationSecret;
    if (authenticationSecret == null) {
      throw StateError('This participant has no device authentication secret.');
    }
    _joinSubmittedForConnection = true;
    _joinSubmittedAtRevision = current.revision;
    final SessionCommand command = SessionCommand.join(
      id: _uuid.v4(),
      sessionId: current.id,
      actorDeviceId: _identity.deviceId,
      baseRevision: current.revision,
      issuedAt: now,
      displayName: _identity.displayName,
      requestedRole: SessionRole.participant,
      authenticationSecret: authenticationSecret,
    );
    try {
      await _submit(command);
    } on Object {
      _joinSubmittedForConnection = false;
      _joinSubmittedAtRevision = null;
      rethrow;
    }
  }

  Future<void> _applyHostCommand(
    SessionCommand command, {
    void Function()? onTransitionApplied,
    DateTime? occurredAt,
  }) async {
    final LiveSession current = _requireSession();
    final SessionTransition transition = SessionReducer.applyCommand(
      session: current,
      command: command,
      occurredAt: occurredAt ?? now,
      activityId: _uuid.v4(),
    );
    if (transition.wasDuplicate) {
      return;
    }
    if (isShared && command.type == SessionCommandType.changeRole) {
      await _applySharedRoleChange(
        current: current,
        command: command,
        transition: transition,
        onTransitionApplied: onTransitionApplied,
      );
      return;
    }
    _session = transition.session;
    onTransitionApplied?.call();
    _syncLocalRole();
    _notifyListenersIfActive();
    await _persist();
    await _publishCommittedSnapshot();
  }

  Future<void> _applySharedRoleChange({
    required LiveSession current,
    required SessionCommand command,
    required SessionTransition transition,
    required void Function()? onTransitionApplied,
  }) async {
    final String targetDeviceId = command.targetDeviceId!;
    final Participant? existing = current.participantFor(targetDeviceId);
    final SessionRole targetRole = command.targetRole!;
    final String? deviceToken = _deviceTransportTokens[targetDeviceId];
    final SessionTransport? transport = _transport;
    if (existing == null || deviceToken == null || transport == null) {
      throw StateError(
        'This participant has no authenticated transport identity to update.',
      );
    }

    await transport.updatePeerRole(deviceToken, targetRole);
    try {
      _session = transition.session;
      onTransitionApplied?.call();
      _syncLocalRole();
      _notifyListenersIfActive();
      await _persist(propagateFailure: true);
    } on Object catch (error, stackTrace) {
      _session = current;
      _syncLocalRole();
      _notifyListenersIfActive();
      try {
        await transport.updatePeerRole(deviceToken, existing.role);
      } on Object {
        _setError(
          'The participant role could not be rolled back. Commands from that '
          'device remain blocked until the role is reconciled.',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _publishCommittedSnapshot();
  }

  Future<void> _applyHostCommandAndEvictParticipant(
    SessionCommand command, {
    DateTime? occurredAt,
  }) async {
    if (command.type == SessionCommandType.disconnectParticipant) {
      final String deviceId = command.targetDeviceId!;
      final SessionTransition transition = SessionReducer.applyCommand(
        session: _requireSession(),
        command: command,
        occurredAt: occurredAt ?? now,
        activityId: _uuid.v4(),
      );
      if (transition.wasDuplicate) {
        return;
      }
      await _evictDevice(deviceId);
      _session = transition.session;
      _revokeDevice(deviceId);
      _syncLocalRole();
      _notifyListenersIfActive();
      await _persist();
      await _publishCommittedSnapshot();
      return;
    }

    await _applyHostCommand(command, occurredAt: occurredAt);
  }

  Future<void> _submitAuthenticatedCommand(
    ReceivedSessionEnvelope received,
    SessionCommand command,
  ) {
    final Completer<void> completer = Completer<void>();
    _hostQueue = _hostQueue.then((_) async {
      try {
        final LiveSession current = _requireSession();
        final SessionEnvelope envelope = received.envelope;
        _validateCommandEnvelope(envelope, command);

        if (command.type == SessionCommandType.join) {
          try {
            await _validatePeerDeviceToken(
              received.peer,
              command.actorDeviceId,
            );
            if (_revokedDeviceIds.contains(command.actorDeviceId)) {
              throw const SessionCommandException(
                SessionCommandError.unauthorized,
                'This device was removed from the live session.',
              );
            }
            final Participant? existing = current.participantFor(
              command.actorDeviceId,
            );
            if (existing == null) {
              _validateNewPeerJoin(received.peer, command, current);
              List<String> supersededConnections = const <String>[];
              await _applyHostCommand(
                command,
                onTransitionApplied: () {
                  _deviceAuthenticationSecrets[command.actorDeviceId] =
                      command.authenticationSecret!;
                  _deviceTransportTokens[command.actorDeviceId] =
                      received.peer.deviceToken!;
                  supersededConnections = _bindPeerConnection(
                    received.peer.connectionId,
                    command.actorDeviceId,
                  );
                },
              );
              await _disconnectConnections(supersededConnections);
            } else {
              _validatePeerReconnect(received.peer, command, existing);
              final List<String> supersededConnections = _bindPeerConnection(
                received.peer.connectionId,
                command.actorDeviceId,
              );
              await _disconnectConnections(supersededConnections);
              await _publishSnapshot();
            }
          } on SessionCommandException catch (error) {
            if (error.code == SessionCommandError.unauthorized) {
              await _disconnectConnections(<String>[
                received.peer.connectionId,
              ]);
            }
            rethrow;
          }
        } else {
          final String? boundDevice =
              _peerDeviceByConnection[received.peer.connectionId];
          final String? boundToken = boundDevice == null
              ? null
              : _deviceTransportTokens[boundDevice];
          final Participant? authenticatedParticipant = boundDevice == null
              ? null
              : current.participantFor(boundDevice);
          if (_revokedConnectionIds.contains(received.peer.connectionId) ||
              boundDevice == null ||
              boundDevice != command.actorDeviceId ||
              boundToken == null ||
              authenticatedParticipant == null ||
              received.peer.role != command.actorRole ||
              authenticatedParticipant.role != command.actorRole ||
              !_constantTimeEqual(
                boundToken,
                received.peer.deviceToken ?? '',
              ) ||
              command.actorDeviceId == current.hostDeviceId) {
            throw const SessionCommandException(
              SessionCommandError.unauthorized,
              'This command is not bound to its authenticated connection.',
            );
          }
          await _applyHostCommandAndEvictParticipant(command);
        }
        completer.complete();
      } on Object catch (error, stackTrace) {
        _setError(_friendlyCommandError(error));
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _validateCommandEnvelope(
    SessionEnvelope envelope,
    SessionCommand command,
  ) {
    if (envelope.kind != SessionMessageKind.command ||
        envelope.messageId != command.id ||
        envelope.sessionId != command.sessionId ||
        envelope.senderDeviceId != command.actorDeviceId ||
        envelope.baseRevision != command.baseRevision) {
      throw const SessionCommandException(
        SessionCommandError.unauthorized,
        'The encrypted command does not match its transport envelope.',
      );
    }
  }

  void _validateNewPeerJoin(
    AuthenticatedSessionPeer peer,
    SessionCommand command,
    LiveSession current,
  ) {
    if (peer.role != SessionRole.participant ||
        command.requestedRole != SessionRole.participant ||
        command.actorDeviceId == current.hostDeviceId) {
      throw const SessionCommandException(
        SessionCommandError.unauthorized,
        'This connection cannot claim the requested session role.',
      );
    }
  }

  Future<void> _validatePeerDeviceToken(
    AuthenticatedSessionPeer peer,
    String deviceId,
  ) async {
    final String? sessionSecret = _sessionSecret;
    final String? suppliedToken = peer.deviceToken;
    if (sessionSecret == null || suppliedToken == null) {
      throw const SessionCommandException(
        SessionCommandError.unauthorized,
        'This connection has no authenticated device identity.',
      );
    }
    final String expectedToken = await SessionDeviceToken.derive(
      deviceId: deviceId,
      sessionSecret: sessionSecret,
    );
    final String? retainedToken = _deviceTransportTokens[deviceId];
    if (!_constantTimeEqual(expectedToken, suppliedToken) ||
        (retainedToken != null &&
            !_constantTimeEqual(retainedToken, suppliedToken))) {
      throw const SessionCommandException(
        SessionCommandError.unauthorized,
        'The transport identity does not match the encrypted device identity.',
      );
    }
  }

  void _validatePeerReconnect(
    AuthenticatedSessionPeer peer,
    SessionCommand command,
    Participant existing,
  ) {
    final String? expectedSecret =
        _deviceAuthenticationSecrets[existing.deviceId];
    if (peer.role != existing.role ||
        existing.connectionState != ParticipantConnectionState.connected ||
        expectedSecret == null ||
        !_constantTimeEqual(
          expectedSecret,
          command.authenticationSecret ?? '',
        )) {
      throw const SessionCommandException(
        SessionCommandError.unauthorized,
        'This device could not re-authenticate its session connection.',
      );
    }
  }

  void _revokeDevice(String deviceId) {
    _revokedDeviceIds.add(deviceId);
    _deviceAuthenticationSecrets.remove(deviceId);
    _deviceTransportTokens.remove(deviceId);
    _participantPresenceByDevice.remove(deviceId);
    final Set<String> revokedConnections = _peerDeviceByConnection.entries
        .where((MapEntry<String, String> entry) => entry.value == deviceId)
        .map((MapEntry<String, String> entry) => entry.key)
        .toSet();
    _peerDeviceByConnection.removeWhere((
      String connectionId,
      String boundDeviceId,
    ) {
      return boundDeviceId == deviceId;
    });
    for (final String connectionId in revokedConnections) {
      _connectedPeerRolesByConnection.remove(connectionId);
      _revokedConnectionIds.add(connectionId);
    }
    _notifyListenersIfActive();
  }

  Future<void> _evictDevice(String deviceId) async {
    final SessionTransport? transport = _transport;
    final String? deviceToken = _deviceTransportTokens[deviceId];
    if (transport == null || deviceToken == null) {
      throw StateError(
        'This participant has no authenticated transport identity to revoke.',
      );
    }
    await transport.revokeDevice(deviceToken);
  }

  Future<void> _disconnectConnections(Iterable<String> connectionIds) async {
    final SessionTransport? transport = _transport;
    final List<String> uniqueConnectionIds = connectionIds.toSet().toList(
      growable: false,
    );
    _revokedConnectionIds.addAll(uniqueConnectionIds);
    for (final String connectionId in uniqueConnectionIds) {
      _connectedPeerRolesByConnection.remove(connectionId);
    }
    if (transport != null) {
      await Future.wait(
        uniqueConnectionIds.map(transport.disconnectPeer),
        eagerError: false,
      );
    }
  }

  List<String> _bindPeerConnection(String connectionId, String deviceId) {
    final List<String> supersededConnections = _peerDeviceByConnection.entries
        .where(
          (MapEntry<String, String> entry) =>
              entry.value == deviceId && entry.key != connectionId,
        )
        .map((MapEntry<String, String> entry) => entry.key)
        .toList(growable: false);
    _peerDeviceByConnection[connectionId] = deviceId;
    _revokedConnectionIds.remove(connectionId);
    _participantPresenceByDevice[deviceId] =
        ParticipantConnectionState.connected;
    _notifyListenersIfActive();
    return supersededConnections;
  }

  bool _constantTimeEqual(String left, String right) {
    if (left.length != right.length) {
      return false;
    }
    int difference = 0;
    for (int index = 0; index < left.length; index += 1) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  Future<void> _handleEnvelope(ReceivedSessionEnvelope received) async {
    final SessionEnvelope envelope = received.envelope;
    if (_shutdown ||
        envelope.sessionId != (_session?.id ?? _expectedSessionId)) {
      return;
    }
    try {
      final Map<String, Object?> payload = await _requireCrypto().open(
        envelope,
      );
      if (_isHost && envelope.kind == SessionMessageKind.command) {
        final Object? commandValue = payload['command'];
        if (payload['type'] != 'command' ||
            commandValue is! Map<Object?, Object?>) {
          return;
        }
        final SessionCommand command = SessionCommand.fromJson(
          Map<String, Object?>.from(commandValue),
        );
        await _submitAuthenticatedCommand(received, command);
        return;
      }
      if (!_isHost &&
          envelope.kind == SessionMessageKind.snapshot &&
          received.peer.role == SessionRole.host) {
        final Object? sessionValue = payload['session'];
        if (payload['type'] != 'snapshot' ||
            sessionValue is! Map<Object?, Object?>) {
          return;
        }
        final LiveSession? current = _session;
        final LiveSession incoming = LiveSessionSnapshot.fromJson(
          Map<String, Object?>.from(sessionValue),
        ).mergeOnto(current);
        if (current == null || incoming.revision >= current.revision) {
          final Participant? localParticipant = incoming.participantFor(
            _identity.deviceId,
          );
          final bool isJoined =
              localParticipant != null &&
              localParticipant.connectionState ==
                  ParticipantConnectionState.connected;
          if (_joinSubmittedForConnection &&
              _joinSubmittedAtRevision != null &&
              incoming.revision > _joinSubmittedAtRevision!) {
            _joinSubmittedForConnection = false;
            _joinSubmittedAtRevision = null;
          } else if (_joinSubmittedForConnection && isJoined) {
            _joinSubmittedAtRevision = null;
          }
          _updateHostClock(envelope.sentAt);
          _session = incoming;
          _expectedSessionId = incoming.id;
          if (connectionState == SessionConnectionState.connected) {
            _staleAt = null;
          }
          _syncLocalRole();
          if (_staleAt == null) {
            _lastError = null;
          }
          _notifyListenersIfActive();
          await _persist();
          unawaited(_sendJoinIfNeeded());
        }
      }
    } on SessionCommandException catch (error) {
      _setError(_friendlyCommandError(error));
      if (_isHost) {
        await _publishSnapshot();
      }
    } on Object {
      _setError('A live session update could not be verified.');
    }
  }

  void _updateHostClock(DateTime hostSentAt) {
    if (_isHost) {
      return;
    }
    final Duration sample = hostSentAt.toUtc().difference(_clock.now().toUtc());
    if (!_hasHostClockSample) {
      _hostClockOffset = sample;
      _hasHostClockSample = true;
      return;
    }
    _hostClockOffset = Duration(
      microseconds:
          ((_hostClockOffset.inMicroseconds * 3) + sample.inMicroseconds) ~/ 4,
    );
  }

  Future<void> _publishSnapshot() async {
    final SessionTransport? transport = _transport;
    final SessionEnvelopeCrypto? crypto = _crypto;
    final LiveSession? current = _session;
    if (!_isHost ||
        transport == null ||
        crypto == null ||
        current == null ||
        transport.connectionState != SessionConnectionState.hosting) {
      return;
    }
    final SessionEnvelope envelope = await crypto.seal(
      sessionId: current.id,
      messageId: _uuid.v4(),
      senderDeviceId: _identity.deviceId,
      baseRevision: current.revision,
      sentAt: now,
      kind: SessionMessageKind.snapshot,
      payload: <String, Object?>{
        'type': 'snapshot',
        'session': LiveSessionSnapshot.fromSession(current).toJson(),
      },
    );
    await transport.send(envelope);
  }

  Future<void> _publishCommittedSnapshot() async {
    try {
      await _publishSnapshot();
    } on Object {
      _setError(
        'The session update was saved but could not reach connected devices.',
      );
    }
  }

  Future<void> _persist({bool propagateFailure = false}) async {
    final LiveSession? current = _session;
    if (current == null) {
      return;
    }
    try {
      await _historyRepository.saveSession(
        current,
        hostDisplayName: _isHost
            ? _identity.displayName
            : current.participantFor(current.hostDeviceId)?.displayName ??
                  'Host',
        recoveryKind: _recoveryKind,
      );
    } on Object {
      _setError('Session history could not be saved on this device.');
      if (propagateFailure) {
        rethrow;
      }
    }
  }

  void _syncLocalRole() {
    if (_isHost) {
      _role = SessionRole.host;
      return;
    }
    final Participant? participant = _session?.participantFor(
      _identity.deviceId,
    );
    if (participant != null) {
      _role = participant.role;
    }
  }

  void _handleConnectionState(SessionConnectionState state) {
    if (_shutdown) {
      return;
    }
    if (state == SessionConnectionState.stale) {
      if (!_isHost) {
        _staleAt ??= _synchronizedNow;
        _joinSubmittedForConnection = false;
        _joinSubmittedAtRevision = null;
      }
      _setError(
        _isHost
            ? 'Keep this app open so everyone stays synchronized.'
            : 'The host connection was lost. Live timing is frozen.',
      );
    } else if (state == SessionConnectionState.connected ||
        state == SessionConnectionState.hosting) {
      if (_isHost) {
        _lastError = null;
        unawaited(_republishAfterReconnect());
      } else if (_staleAt == null) {
        _lastError = null;
      }
      _notifyListenersIfActive();
    }
  }

  void _handlePeerEvent(SessionPeerEvent event) {
    if (!_isHost || _shutdown) {
      return;
    }
    final String connectionId = event.peer.connectionId;
    if (event.presence == SessionPeerPresence.connected) {
      _connectedPeerRolesByConnection[connectionId] = event.peer.role;
      _notifyListenersIfActive();
      return;
    }

    _connectedPeerRolesByConnection.remove(connectionId);
    final String? deviceId = _peerDeviceByConnection.remove(connectionId);
    _revokedConnectionIds.remove(connectionId);
    if (deviceId != null &&
        !_peerDeviceByConnection.entries.any(
          (MapEntry<String, String> entry) =>
              entry.value == deviceId &&
              !_revokedConnectionIds.contains(entry.key),
        ) &&
        _session?.participantFor(deviceId) != null) {
      _participantPresenceByDevice[deviceId] = ParticipantConnectionState.stale;
    }
    _notifyListenersIfActive();
  }

  Future<void> _republishAfterReconnect() async {
    try {
      final SessionTransport? transport = _transport;
      final LiveSession? current = _session;
      if (transport != null && current != null) {
        for (final Participant participant in current.participants) {
          final String? deviceToken =
              _deviceTransportTokens[participant.deviceId];
          if (deviceToken != null) {
            await transport.updatePeerRole(deviceToken, participant.role);
          }
        }
      }
      await _publishSnapshot();
    } on Object {
      _setError('The latest session state could not be republished.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isHost || !isShared || !_requiresForegroundHosting) {
      return;
    }
    _hostForeground = state == AppLifecycleState.resumed;
    if (!_hostForeground) {
      _setError(
        _transportKind == SessionTransportKind.nearbyLan
            ? 'Return to ChronoSync and keep it open while hosting nearby.'
            : 'Return to ChronoSync and keep it open while hosting this '
                  'shared session.',
      );
    } else {
      _notifyListenersIfActive();
    }
  }

  void clearCue() {
    _lastCue = null;
    _notifyListenersIfActive();
  }

  void clearError() {
    _lastError = null;
    _notifyListenersIfActive();
  }

  LiveSession _requireSession() {
    final LiveSession? current = _session;
    if (current == null) {
      throw StateError('The initial host snapshot has not arrived.');
    }
    return current;
  }

  SessionEnvelopeCrypto _requireCrypto() {
    final SessionEnvelopeCrypto? crypto = _crypto;
    if (crypto == null) {
      throw StateError('This session has no encryption context.');
    }
    return crypto;
  }

  SessionTransport _requireTransport() {
    final SessionTransport? transport = _transport;
    if (transport == null) {
      throw StateError('This is a local-only session.');
    }
    return transport;
  }

  String _friendlyCommandError(Object error) {
    if (error is SessionCommandException) {
      return switch (error.code) {
        SessionCommandError.staleRevision =>
          'The session changed first. Your view is being refreshed.',
        SessionCommandError.unauthorized =>
          'Your current role cannot use that control.',
        SessionCommandError.confirmationRequired =>
          'Confirm this action before continuing.',
        SessionCommandError.invalidAdjustment =>
          'That adjustment would make the step duration invalid.',
        SessionCommandError.invalidState =>
          'That control is not available in the current session state.',
        SessionCommandError.invalidStep => 'That step is no longer available.',
        SessionCommandError.wrongSession =>
          'That command belongs to another session.',
      };
    }
    return 'ChronoSync could not apply that action.';
  }

  void _setError(String message) {
    if (_shutdown) {
      return;
    }
    _lastError = message;
    _notifyListenersIfActive();
  }

  void _notifyListenersIfActive() {
    if (!_shutdown) {
      notifyListeners();
    }
  }

  Future<void> shutdown() {
    _beginShutdown();
    return _shutdownFuture!;
  }

  void _beginShutdown() {
    if (!_shutdown) {
      _shutdown = true;
      _ticker?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    }
    _shutdownFuture ??= _releaseResources();
  }

  Future<void> _releaseResources() async {
    await _cueSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _peerEventSubscription?.cancel();
    await _transport?.close();
  }

  Future<void> _cleanupAfterFailedInitialization() async {
    try {
      await shutdown();
    } on Object {
      // Preserve the initialization error while still releasing local state.
    } finally {
      dispose();
    }
  }

  @override
  void dispose() {
    _beginShutdown();
    unawaited(_ignoreCleanupErrors(_shutdownFuture!));
    super.dispose();
  }
}

bool _platformRequiresForegroundHosting() {
  if (kIsWeb) {
    return true;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

int _displayedRemainingSeconds(Duration duration) {
  if (duration <= Duration.zero) {
    return -duration.abs().inSeconds;
  }
  return (duration.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
}

Future<void> _ignoreCleanupErrors(Future<void> cleanup) async {
  try {
    await cleanup;
  } on Object {
    // dispose cannot report asynchronous cleanup failures to its caller.
  }
}
