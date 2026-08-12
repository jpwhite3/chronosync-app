import 'dart:async';

import 'package:chronosync/core/platform/mac_live_activity.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/portability/session_csv_exporter.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/data/transports/lan_host_transport.dart';
import 'package:chronosync/data/transports/online_relay_transport.dart';
import 'package:chronosync/data/transports/online_room_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:chronosync/logic/live_session/live_session_controller.dart';
import 'package:chronosync/logic/live_session/live_session_view_mapper.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/live/live.dart';
import 'package:chronosync/presentation/screens/session_setup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

enum _SessionFlowPhase { setup, lobby, live, summary }

class SessionFlowScreen extends StatefulWidget {
  const SessionFlowScreen({
    required this.plan,
    required this.identity,
    required this.historyRepository,
    required this.cueService,
    required this.fileService,
    this.onlineRoomService,
    this.initialController,
    this.initialTransportLabel = 'Shared session',
    this.soloControllerFactory,
    this.acquireActivity,
    this.releaseActivity,
    super.key,
  });

  final Plan plan;
  final DeviceIdentity identity;
  final SessionHistoryRepository historyRepository;
  final LiveCueDelivery cueService;
  final PortabilityFileService fileService;
  final OnlineRoomService? onlineRoomService;
  final LiveSessionController? initialController;
  final String initialTransportLabel;

  @visibleForTesting
  final Future<LiveSessionController> Function()? soloControllerFactory;

  @visibleForTesting
  final Future<void> Function()? acquireActivity;

  @visibleForTesting
  final Future<void> Function()? releaseActivity;

  @override
  State<SessionFlowScreen> createState() => _SessionFlowScreenState();
}

class _SessionFlowScreenState extends State<SessionFlowScreen> {
  final Uuid _uuid = const Uuid();
  final SessionCsvExporter _csvExporter = const SessionCsvExporter();
  final MacLiveActivityLease _activityLease = MacLiveActivityLease();
  _SessionFlowPhase _phase = _SessionFlowPhase.setup;
  LiveSessionController? _controller;
  Invitation? _participantInvitation;
  Invitation? _displayInvitation;
  String _transportLabel = 'On this device';
  bool _hostReady = true;
  bool _launching = false;
  bool _exporting = false;
  bool _closePromptOpen = false;
  String? _launchError;

  bool get _nearbyAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    final LiveSessionController? initialController = widget.initialController;
    if (initialController != null) {
      _controller = initialController;
      _transportLabel = widget.initialTransportLabel;
      _phase =
          !initialController.isShared ||
              _sessionHasStarted(initialController.session)
          ? _SessionFlowPhase.live
          : _SessionFlowPhase.lobby;
      initialController.addListener(_controllerChanged);
      unawaited(_acquireActivity());
    }
  }

  @override
  void dispose() {
    final LiveSessionController? controller = _controller;
    if (controller != null) {
      controller.removeListener(_controllerChanged);
      unawaited(controller.shutdown());
      controller.dispose();
    }
    unawaited(_releaseActivity());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LiveSessionController? controller = _controller;
    if (_phase == _SessionFlowPhase.setup || controller == null) {
      return SessionSetupScreen(
        plan: widget.plan,
        nearbyAvailable: _nearbyAvailable,
        onlineAvailable: widget.onlineRoomService != null,
        isLaunching: _launching,
        errorMessage: _launchError,
        onLaunch: (SessionLaunchMode mode) => unawaited(_launch(mode)),
      );
    }

    return PopScope<Object?>(
      canPop: controller.session?.status == LiveSessionStatus.ended,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_requestClose(controller));
        }
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final LiveSession? session = controller.session;
          if (session == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return switch (_phase) {
            _SessionFlowPhase.setup => const SizedBox.shrink(),
            _SessionFlowPhase.lobby => _buildLobby(controller, session),
            _SessionFlowPhase.live => _buildLive(controller, session),
            _SessionFlowPhase.summary => _buildSummary(session),
          };
        },
      ),
    );
  }

  Future<void> _launch(SessionLaunchMode mode) async {
    setState(() {
      _launching = true;
      _launchError = null;
    });
    LiveSessionController? pendingController;
    SessionTransport? pendingTransport;
    bool activityMayBeHeld = false;
    try {
      await widget.cueService.unlockAudio();
      switch (mode) {
        case SessionLaunchMode.solo:
          pendingController =
              await widget.soloControllerFactory?.call() ??
              await LiveSessionController.createSolo(
                plan: widget.plan,
                identity: widget.identity,
                historyRepository: widget.historyRepository,
                cueService: widget.cueService,
              );
          _transportLabel = 'Solo session';
          _phase = _SessionFlowPhase.live;
        case SessionLaunchMode.nearby:
          if (!_nearbyAvailable) {
            throw StateError('Nearby hosting is available from iPhone.');
          }
          final String sessionId = _uuid.v4();
          final LanHostTransport transport = LanHostTransport(
            deviceId: widget.identity.deviceId,
          );
          pendingTransport = transport;
          final LanHostingResult hosted = await transport.startHosting(
            sessionId: sessionId,
            expiresAt: DateTime.now().add(const Duration(hours: 8)),
          );
          pendingController = await LiveSessionController.hostShared(
            plan: widget.plan,
            identity: widget.identity,
            invitation: hosted.invitation,
            transport: transport,
            transportAlreadyHosting: true,
            historyRepository: widget.historyRepository,
            cueService: widget.cueService,
          );
          _participantInvitation = hosted.invitation;
          _displayInvitation = hosted.displayInvitation;
          _transportLabel = 'Nearby · Wi‑Fi';
          _phase = _SessionFlowPhase.lobby;
        case SessionLaunchMode.online:
          final OnlineRoomService? roomService = widget.onlineRoomService;
          if (roomService == null) {
            throw StateError('Online rooms are not configured in this build.');
          }
          final OnlineRoom room = await roomService.createRoom();
          final OnlineRelayTransport transport = OnlineRelayTransport(
            deviceId: widget.identity.deviceId,
          );
          pendingTransport = transport;
          pendingController = await LiveSessionController.hostShared(
            plan: widget.plan,
            identity: widget.identity,
            invitation: room.hostInvitation(),
            transport: transport,
            historyRepository: widget.historyRepository,
            cueService: widget.cueService,
          );
          _participantInvitation = room.participantInvitation();
          _displayInvitation = room.displayInvitation();
          _transportLabel = 'Online · encrypted';
          _phase = _SessionFlowPhase.lobby;
      }
      final LiveSessionController controller = pendingController;
      activityMayBeHeld = true;
      await _acquireActivity();
      if (!mounted) {
        await _cleanupFailedLaunch(
          controller: controller,
          transport: pendingTransport,
          releaseActivity: activityMayBeHeld,
        );
        return;
      }
      _controller = controller;
      controller.addListener(_controllerChanged);
      if (_phase == _SessionFlowPhase.lobby &&
          _sessionHasStarted(controller.session)) {
        _phase = _SessionFlowPhase.live;
      }
      if (mounted) {
        setState(() => _launching = false);
      }
    } on Object {
      await _cleanupFailedLaunch(
        controller: pendingController,
        transport: pendingTransport,
        releaseActivity: activityMayBeHeld,
      );
      if (mounted) {
        setState(() {
          _launching = false;
          _launchError = 'Could not start the session. Try again.';
        });
      }
    }
  }

  Future<void> _cleanupFailedLaunch({
    required LiveSessionController? controller,
    required SessionTransport? transport,
    required bool releaseActivity,
  }) async {
    if (releaseActivity) {
      try {
        await _releaseActivity();
      } on Object {
        // Preserve the launch failure while making cleanup best effort.
      }
    }
    if (controller != null) {
      try {
        await controller.shutdown();
      } on Object {
        // Disposing below starts the same idempotent cleanup path again.
      } finally {
        controller.dispose();
      }
      return;
    }
    if (transport != null) {
      try {
        await transport.close();
      } on Object {
        // Preserve the original launch failure.
      }
    }
  }

  Widget _buildLobby(LiveSessionController controller, LiveSession session) {
    return SessionLobbyScreen(
      data: LobbyViewData(
        planTitle: session.planSnapshot.title,
        transportLabel: _transportLabel,
        stepCount: session.planSnapshot.steps.length,
        totalDuration: session.planSnapshot.totalDuration,
        participants: <LobbyParticipantViewData>[
          LobbyParticipantViewData(
            deviceId: widget.identity.deviceId,
            displayName: widget.identity.displayName,
            role: SessionRole.host,
            connectionState: ParticipantConnectionState.connected,
            isReady: _hostReady,
            isCurrentDevice: true,
          ),
          ...session.participants.map<LobbyParticipantViewData>(
            (Participant participant) => LobbyParticipantViewData(
              deviceId: participant.deviceId,
              displayName: participant.displayName,
              role: participant.role,
              connectionState: controller.participantConnectionState(
                participant.deviceId,
              ),
            ),
          ),
          for (
            int displayIndex = 0;
            displayIndex < controller.connectedDisplayCount;
            displayIndex += 1
          )
            LobbyParticipantViewData(
              deviceId: 'connected-display-$displayIndex',
              displayName: controller.connectedDisplayCount == 1
                  ? 'Display'
                  : 'Display ${displayIndex + 1}',
              role: SessionRole.display,
              connectionState: ParticipantConnectionState.connected,
              isManageable: false,
            ),
        ],
        isHostReady: _hostReady,
        participantInvitation: _mapInvitation(
          _participantInvitation,
          label: 'Join as participant',
          detail: 'See the current and next steps, then tap Got it.',
        ),
        displayInvitation: _mapInvitation(
          _displayInvitation,
          label: 'Open display',
          detail: 'Fullscreen timing with no controls.',
        ),
        sessionCode: _shortSessionCode(session.id),
        connectionNote: controller.lastError != null
            ? 'The connection needs attention. Check the network and try '
                  'again.'
            : (_transportLabel.startsWith('Nearby')
                  ? 'Keep this iPhone awake, open, and on the same Wi‑Fi '
                        'network as the team.'
                  : 'The host device remains authoritative and must stay '
                        'open.'),
      ),
      onBack: () => unawaited(_requestClose(controller)),
      onHostReadyChanged: (bool ready) => setState(() => _hostReady = ready),
      onStart: _hostReady ? () => unawaited(_startFromLobby(controller)) : null,
      onCopyInvitation: (LobbyInvitationViewData invitation) =>
          unawaited(_copyInvitation(invitation)),
      onShareInvitation: (LobbyInvitationViewData invitation) =>
          unawaited(_shareInvitation(invitation)),
      onRoleChanged: (String deviceId, SessionRole role) => unawaited(
        _runCommand(() => controller.changeParticipantRole(deviceId, role)),
      ),
      onRemoveParticipant: (String deviceId) =>
          unawaited(_runCommand(() => controller.removeParticipant(deviceId))),
    );
  }

  Widget _buildLive(LiveSessionController controller, LiveSession session) {
    final LiveSessionViewData data = mapLiveSessionView(
      session: session,
      role: controller.role,
      deviceId: controller.identity.deviceId,
      now: controller.now,
      isStale: controller.isStale,
      staleMessage: controller.lastError == null
          ? null
          : 'Updates are paused while ChronoSync reconnects.',
      currentDeviceDisplayName: controller.identity.displayName,
      hostDisplayName: widget.identity.displayName,
      connectedParticipantCount: controller.connectedParticipantCount,
      connectedDisplayCount: controller.connectedDisplayCount,
    );
    final bool canControl =
        !controller.isStale &&
        (controller.role == SessionRole.host ||
            controller.role == SessionRole.controller);
    final bool canAcknowledge =
        !controller.isStale &&
        (controller.role == SessionRole.host ||
            controller.role == SessionRole.controller ||
            controller.role == SessionRole.participant);
    return LiveSessionScreen(
      data: data,
      onClose: () => unawaited(_requestClose(controller)),
      onShowPeople: controller.isShared ? _showPeople : null,
      onStart: canControl && session.status == LiveSessionStatus.waiting
          ? () => unawaited(_runCommand(controller.start))
          : null,
      onPauseResume:
          canControl &&
              (session.status == LiveSessionStatus.running ||
                  session.status == LiveSessionStatus.paused)
          ? () => unawaited(
              _runCommand(
                session.status == LiveSessionStatus.paused
                    ? controller.resume
                    : controller.pause,
              ),
            )
          : null,
      onAdvance: canControl && session.isActive
          ? () => unawaited(_requestAdvance(controller, session))
          : null,
      onAdjustRemaining: canControl && session.isActive
          ? (int seconds) => unawaited(
              _runCommand(() => controller.adjustRemaining(seconds)),
            )
          : null,
      onCustomAdjustmentRequested: canControl && session.isActive
          ? () => unawaited(_requestCustomAdjustment(controller))
          : null,
      onJumpRequested: canControl && session.isActive
          ? () => unawaited(_requestJump(controller, session))
          : null,
      onAcknowledge: canAcknowledge && session.isActive && !data.hasAcknowledged
          ? () => unawaited(_runCommand(controller.acknowledge))
          : null,
      onEndRequested: controller.role == SessionRole.host && session.isActive
          ? () => unawaited(_requestEnd(controller))
          : null,
    );
  }

  Widget _buildSummary(LiveSession session) {
    return SessionSummaryScreen(
      data: mapSessionSummaryView(
        session: session,
        now: DateTime.now(),
        hostDisplayName: widget.identity.displayName,
        currentDeviceId: widget.identity.deviceId,
        currentDeviceDisplayName: widget.identity.displayName,
      ),
      isExporting: _exporting,
      onDone: () => Navigator.pop(context),
      onExportCsv: () => unawaited(_exportCsv(session)),
    );
  }

  Future<void> _startFromLobby(LiveSessionController controller) async {
    await _runCommand(controller.start);
    if (mounted && controller.session?.status == LiveSessionStatus.running) {
      setState(() => _phase = _SessionFlowPhase.live);
    }
  }

  Future<void> _runCommand(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The action could not be completed. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _requestAdvance(
    LiveSessionController controller,
    LiveSession session,
  ) async {
    final bool isFinalStep =
        session.currentStepIndex >= session.planSnapshot.steps.length - 1;
    if (!isFinalStep) {
      await _runCommand(controller.advance);
      return;
    }

    final int expectedRevision = session.revision;
    final int expectedStepIndex = session.currentStepIndex;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Finish live session?'),
            content: const Text(
              'This completes the final step and opens the session summary '
              'for everyone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep running'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Finish session'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    final LiveSession? latest = controller.session;
    if (latest == null ||
        latest.revision != expectedRevision ||
        latest.currentStepIndex != expectedStepIndex ||
        !latest.isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The session changed while confirmation was open. Review the '
              'current step and try again.',
            ),
          ),
        );
      }
      return;
    }
    await _runCommand(controller.advance);
  }

  Future<void> _requestCustomAdjustment(
    LiveSessionController controller,
  ) async {
    String input = '';
    final int? minutes = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Adjust remaining time'),
        content: TextField(
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Minutes',
            helperText: 'Use a negative number to remove time.',
            hintText: '5',
          ),
          onChanged: (String value) => input = value,
          onSubmitted: (String value) {
            Navigator.pop(context, int.tryParse(value.trim()));
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(input.trim())),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (minutes != null && minutes != 0) {
      await _runCommand(() => controller.adjustRemaining(minutes * 60));
    }
  }

  Future<void> _requestJump(
    LiveSessionController controller,
    LiveSession session,
  ) async {
    final int? target = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Jump to another step?'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: session.planSnapshot.steps.length,
            itemBuilder: (BuildContext context, int index) {
              final Step step = session.planSnapshot.steps[index];
              return ListTile(
                enabled: index != session.currentStepIndex,
                title: Text('${index + 1}. ${step.title}'),
                subtitle: Text(formatFriendlyDuration(step.duration)),
                onTap: index == session.currentStepIndex
                    ? null
                    : () => Navigator.pop(context, index),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (target != null) {
      await _runCommand(() => controller.jumpTo(target, confirmed: true));
    }
  }

  Future<void> _requestEnd(LiveSessionController controller) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('End live session?'),
            content: const Text(
              'Everyone will see the final state. The activity history and '
              'timing summary will remain on this device.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep running'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('End session'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await _runCommand(() => controller.end(confirmed: true));
    }
  }

  Future<void> _requestClose(LiveSessionController controller) async {
    if (_closePromptOpen) {
      return;
    }
    if (controller.session?.status == LiveSessionStatus.ended) {
      setState(() => _phase = _SessionFlowPhase.summary);
      return;
    }
    _closePromptOpen = true;
    try {
      final bool shouldClose =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: Text(
                controller.isHost
                    ? _phase == _SessionFlowPhase.lobby
                          ? 'End shared session?'
                          : 'End live session?'
                    : 'Disconnect?',
              ),
              content: Text(
                controller.isHost
                    ? 'Everyone receives the final state. ChronoSync will '
                          'show the timing summary and save it to history.'
                    : 'You can rejoin while the invitation remains valid.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(controller.isHost ? 'End session' : 'Disconnect'),
                ),
              ],
            ),
          ) ??
          false;
      if (!shouldClose) {
        return;
      }
      if (controller.isHost) {
        await _runCommand(() => controller.end(confirmed: true));
        return;
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  void _showPeople() {
    final LiveSessionController? controller = _controller;
    final LiveSession? session = controller?.session;
    if (controller == null || session == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            Text(
              'Connected people',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.star_rounded)),
              title: Text(widget.identity.displayName),
              subtitle: const Text('Host · this device'),
            ),
            for (final Participant participant in session.participants)
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline_rounded),
                ),
                title: Text(participant.displayName),
                subtitle: Text(
                  '${participant.role.name} · '
                  '${controller.participantConnectionState(participant.deviceId).name}',
                ),
              ),
            for (
              int displayIndex = 0;
              displayIndex < controller.connectedDisplayCount;
              displayIndex += 1
            )
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.monitor_outlined),
                ),
                title: Text(
                  controller.connectedDisplayCount == 1
                      ? 'Display'
                      : 'Display ${displayIndex + 1}',
                ),
                subtitle: const Text('display · connected'),
              ),
          ],
        ),
      ),
    );
  }

  LobbyInvitationViewData? _mapInvitation(
    Invitation? invitation, {
    required String label,
    required String detail,
  }) {
    if (invitation == null) {
      return null;
    }
    return LobbyInvitationViewData(
      label: label,
      role: invitation.requestedRole,
      link: invitation.toQrPayload(),
      detail: detail,
      expiresAt: invitation.expiresAt,
    );
  }

  Future<void> _copyInvitation(LobbyInvitationViewData invitation) async {
    try {
      await Clipboard.setData(ClipboardData(text: invitation.link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${invitation.label} link copied')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not copy the invitation. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _shareInvitation(LobbyInvitationViewData invitation) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: 'Join ${widget.plan.title} in ChronoSync',
          text: '${invitation.label}\n${invitation.link}',
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share the invitation. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _exportCsv(LiveSession session) async {
    setState(() => _exporting = true);
    try {
      final String csv = _csvExporter.export(
        session,
        hostDisplayName: widget.identity.displayName,
      );
      await widget.fileService.shareCsv(
        csv: csv,
        fileName: '${safeFileStem(session.planSnapshot.title)}-session.csv',
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not export the activity. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  String _shortSessionCode(String sessionId) {
    final String compact = sessionId.replaceAll('-', '').toUpperCase();
    return compact.length <= 6
        ? compact
        : compact.substring(compact.length - 6);
  }

  void _controllerChanged() {
    final LiveSession? session = _controller?.session;
    if (!mounted || session == null) {
      return;
    }
    if (session.status == LiveSessionStatus.ended &&
        _phase != _SessionFlowPhase.summary) {
      unawaited(_releaseActivity());
      setState(() => _phase = _SessionFlowPhase.summary);
    } else if (_phase == _SessionFlowPhase.lobby &&
        _sessionHasStarted(session)) {
      setState(() => _phase = _SessionFlowPhase.live);
    }
  }

  bool _sessionHasStarted(LiveSession? session) {
    return session?.status == LiveSessionStatus.running ||
        session?.status == LiveSessionStatus.paused;
  }

  Future<void> _acquireActivity() {
    return widget.acquireActivity?.call() ??
        _activityLease.acquire(reason: 'Running a ChronoSync live session');
  }

  Future<void> _releaseActivity() {
    return widget.releaseActivity?.call() ?? _activityLease.release();
  }
}
