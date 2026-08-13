import 'dart:async';

import 'package:chronosync/core/platform/mac_live_activity.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/portability/session_csv_exporter.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/data/transports/lan_client_transport.dart';
import 'package:chronosync/data/transports/online_relay_transport.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:chronosync/logic/live_session/live_session_controller.dart';
import 'package:chronosync/logic/live_session/live_session_view_mapper.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/live/live.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart' hide Step;

class JoinSessionScreen extends StatefulWidget {
  const JoinSessionScreen({
    required this.invitation,
    required this.localIdentity,
    required this.identityRepository,
    required this.historyRepository,
    required this.cueService,
    required this.fileService,
    this.initialController,
    this.joinControllerFactory,
    this.acquireActivity,
    this.releaseActivity,
    this.authenticationSecretLoader,
    super.key,
  });

  final Invitation invitation;
  final DeviceIdentity localIdentity;
  final DeviceIdentityRepository identityRepository;
  final SessionHistoryRepository historyRepository;
  final LiveCueDelivery cueService;
  final PortabilityFileService fileService;
  final LiveSessionController? initialController;

  @visibleForTesting
  final Future<LiveSessionController> Function()? joinControllerFactory;

  @visibleForTesting
  final Future<void> Function()? acquireActivity;

  @visibleForTesting
  final Future<void> Function()? releaseActivity;

  @visibleForTesting
  final Future<String> Function(String sessionId)? authenticationSecretLoader;

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  late final TextEditingController _nameController;
  final MacLiveActivityLease _activityLease = MacLiveActivityLease();
  LiveSessionController? _controller;
  bool _connecting = false;
  bool _exporting = false;
  bool _disconnectPromptOpen = false;
  bool _allowDisconnectPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.invitation.requestedRole == SessionRole.display
          ? 'Display'
          : widget.localIdentity.displayName,
    );
    _controller = widget.initialController;
    if (_controller != null) {
      unawaited(_acquireActivity());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    final LiveSessionController? controller = _controller;
    if (controller != null) {
      unawaited(controller.shutdown());
      controller.dispose();
    }
    unawaited(_releaseActivity());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LiveSessionController? controller = _controller;
    if (controller == null) {
      return _buildJoinForm();
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final LiveSession? session = controller.session;
        if (session == null) {
          return PopScope<Object?>(
            canPop: _allowDisconnectPop,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (!didPop) {
                unawaited(_requestDisconnect());
              }
            },
            child: Scaffold(
              appBar: AppBar(title: const Text('Joining session')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(ChronoSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: ChronoSpacing.md),
                      const Text('Waiting for the host’s encrypted snapshot…'),
                      if (controller.lastError != null) ...<Widget>[
                        const SizedBox(height: ChronoSpacing.sm),
                        Text(
                          'The host has not sent the session yet. Check your '
                          'connection and keep this page open.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: ChronoSpacing.md),
                      TextButton(
                        onPressed: () => unawaited(_requestDisconnect()),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (session.status == LiveSessionStatus.ended) {
          unawaited(_releaseActivity());
          return PopScope<Object?>(
            canPop: true,
            child: SessionSummaryScreen(
              data: mapSessionSummaryView(
                session: session,
                now: controller.now,
                currentDeviceId: controller.identity.deviceId,
                currentDeviceDisplayName: controller.identity.displayName,
              ),
              isExporting: _exporting,
              onDone: () => Navigator.pop(context),
              onExportCsv: () => unawaited(_exportCsv(session)),
            ),
          );
        }
        return PopScope<Object?>(
          canPop: _allowDisconnectPop,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) {
              unawaited(_requestDisconnect());
            }
          },
          child: _buildLive(controller, session),
        );
      },
    );
  }

  Widget _buildJoinForm() {
    final bool expired = widget.invitation.isExpiredAt(DateTime.now());
    final String roleLabel = switch (widget.invitation.requestedRole) {
      SessionRole.participant => 'Participant',
      SessionRole.display => 'Display',
      SessionRole.controller => 'Timekeeper',
      SessionRole.host => 'Host',
    };
    final bool isDisplay =
        widget.invitation.requestedRole == SessionRole.display;
    return Scaffold(
      appBar: AppBar(title: const Text('Join ChronoSync')),
      body: SingleChildScrollView(
        padding: ChronoBreakpoints.pagePaddingFor(
          MediaQuery.sizeOf(context).width,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ChronoStatusPill(
                  status: expired
                      ? ChronoStatus.disconnected
                      : ChronoStatus.live,
                  label: expired ? 'Invitation expired' : 'Invitation ready',
                ),
                const SizedBox(height: ChronoSpacing.md),
                Text(
                  'Join as $roleLabel',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: ChronoSpacing.xs),
                Text(
                  widget.invitation.transport == SessionTransportKind.nearbyLan
                      ? 'Connect to the same Wi‑Fi network as the host. The '
                            'session works without Internet.'
                      : 'This anonymous room uses an expiring capability and '
                            'end-to-end encrypted session messages.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: ChronoSpacing.lg),
                ChronoCard(
                  padding: const EdgeInsets.all(ChronoSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (isDisplay)
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(Icons.tv_outlined),
                            SizedBox(width: ChronoSpacing.sm),
                            Expanded(
                              child: Text(
                                'Displays join without a name and cannot '
                                'control the session.',
                              ),
                            ),
                          ],
                        )
                      else
                        TextField(
                          controller: _nameController,
                          enabled: !_connecting && !expired,
                          maxLength: 48,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Name for this session',
                            helperText:
                                'No account is created. This name is stored '
                                'only in the session history.',
                          ),
                        ),
                      const SizedBox(height: ChronoSpacing.sm),
                      ChronoPrimaryButton(
                        label: _connecting ? 'Connecting…' : 'Join session',
                        icon: Icons.login_rounded,
                        isLoading: _connecting,
                        expand: true,
                        onPressed: expired || _connecting ? null : _connect,
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: ChronoSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final String displayName = _nameController.text.trim();
    if (displayName.isEmpty) {
      setState(() => _error = 'Enter a name for this session.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    LiveSessionController? pendingController;
    SessionTransport? pendingTransport;
    bool activityMayBeHeld = false;
    try {
      await widget.cueService.unlockAudio();
      final DeviceIdentity sessionIdentity = DeviceIdentity(
        deviceId: widget.localIdentity.deviceId,
        displayName: displayName,
      );
      final Future<String> Function(String sessionId) secretLoader =
          widget.authenticationSecretLoader ??
          widget.identityRepository.loadOrCreateSessionAuthenticationSecret;
      final String deviceAuthenticationSecret = await secretLoader(
        widget.invitation.sessionId,
      );
      final Future<LiveSessionController> Function()? controllerFactory =
          widget.joinControllerFactory;
      if (controllerFactory != null) {
        pendingController = await controllerFactory();
      } else {
        final SessionTransport transport =
            switch (widget.invitation.transport) {
              SessionTransportKind.nearbyLan => LanClientTransport(
                deviceId: sessionIdentity.deviceId,
              ),
              SessionTransportKind.onlineRelay => OnlineRelayTransport(
                deviceId: sessionIdentity.deviceId,
              ),
            };
        pendingTransport = transport;
        pendingController = await LiveSessionController.joinShared(
          identity: sessionIdentity,
          invitation: widget.invitation,
          transport: transport,
          historyRepository: widget.historyRepository,
          deviceAuthenticationSecret: deviceAuthenticationSecret,
          cueService: widget.cueService,
        );
      }
      final LiveSessionController controller = pendingController;
      if (!mounted) {
        await _cleanupFailedConnection(
          controller: controller,
          transport: pendingTransport,
          releaseActivity: false,
        );
        return;
      }
      activityMayBeHeld = true;
      await _acquireActivity();
      if (!mounted) {
        await _cleanupFailedConnection(
          controller: controller,
          transport: pendingTransport,
          releaseActivity: activityMayBeHeld,
        );
        return;
      }
      if (mounted) {
        setState(() {
          _controller = controller;
          _connecting = false;
        });
      }
    } on Object {
      await _cleanupFailedConnection(
        controller: pendingController,
        transport: pendingTransport,
        releaseActivity: activityMayBeHeld,
      );
      if (mounted) {
        setState(() {
          _connecting = false;
          _error =
              'Could not join the session. Check the invitation and your '
              'connection, then try again.';
        });
      }
    }
  }

  Future<void> _cleanupFailedConnection({
    required LiveSessionController? controller,
    required SessionTransport? transport,
    required bool releaseActivity,
  }) async {
    if (releaseActivity) {
      try {
        await _releaseActivity();
      } on Object {
        // Preserve the connection failure while cleanup remains best effort.
      }
    }
    if (controller != null) {
      try {
        await controller.shutdown();
      } on Object {
        // Disposing below retries the same idempotent cleanup path.
      } finally {
        controller.dispose();
      }
      return;
    }
    if (transport != null) {
      try {
        await transport.close();
      } on Object {
        // Preserve the original connection failure.
      }
    }
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
          : 'The host connection was interrupted. Controls will return after '
                'reconnection.',
      currentDeviceDisplayName: controller.identity.displayName,
    );
    final bool isController =
        controller.role == SessionRole.controller && !controller.isStale;
    final bool canAcknowledge =
        !controller.isStale &&
        controller.role != SessionRole.display &&
        session.isActive &&
        !data.hasAcknowledged;
    return LiveSessionScreen(
      data: data,
      onClose: () => unawaited(_requestDisconnect()),
      onShowPeople: _showPeople,
      onPauseResume:
          isController &&
              (session.status == LiveSessionStatus.running ||
                  session.status == LiveSessionStatus.paused)
          ? () => unawaited(
              _run(
                session.status == LiveSessionStatus.paused
                    ? controller.resume
                    : controller.pause,
              ),
            )
          : null,
      onAdvance: isController && session.isActive
          ? () => unawaited(_run(controller.advance))
          : null,
      onAdjustRemaining: isController && session.isActive
          ? (int seconds) =>
                unawaited(_run(() => controller.adjustRemaining(seconds)))
          : null,
      onCustomAdjustmentRequested: isController && session.isActive
          ? () => unawaited(_customAdjustment(controller))
          : null,
      onJumpRequested: isController && session.isActive
          ? () => unawaited(_jump(controller, session))
          : null,
      onAcknowledge: canAcknowledge
          ? () => unawaited(_run(controller.acknowledge))
          : null,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The action could not be completed. Check the connection and '
              'try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _customAdjustment(LiveSessionController controller) async {
    String input = '';
    final int? minutes = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Adjust remaining time'),
        content: TextField(
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(labelText: 'Minutes'),
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
      await _run(() => controller.adjustRemaining(minutes * 60));
    }
  }

  Future<void> _jump(
    LiveSessionController controller,
    LiveSession session,
  ) async {
    final int? target = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Jump to interval'),
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
      ),
    );
    if (target != null) {
      await _run(() => controller.jumpTo(target, confirmed: true));
    }
  }

  void _showPeople() {
    final LiveSession? session = _controller?.session;
    if (session == null) {
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
            Text('People', style: Theme.of(context).textTheme.headlineSmall),
            const ListTile(
              leading: CircleAvatar(child: Icon(Icons.star_rounded)),
              title: Text('Host'),
              subtitle: Text('Host · session owner'),
            ),
            for (final Participant participant in session.participants)
              ListTile(
                title: Text(participant.displayName),
                subtitle: Text(
                  '${_roleLabel(participant.role)} · '
                  '${participant.connectionState.name}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(LiveSession session) async {
    setState(() => _exporting = true);
    try {
      final String csv = const SessionCsvExporter().export(
        session,
        hostDisplayName: 'Host',
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

  Future<void> _requestDisconnect() async {
    if (_disconnectPromptOpen || !mounted) {
      return;
    }
    _disconnectPromptOpen = true;
    try {
      final bool disconnect =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Disconnect from session?'),
              content: const Text(
                'You can rejoin while the invitation remains valid.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay connected'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ) ??
          false;
      if (disconnect && mounted) {
        setState(() => _allowDisconnectPop = true);
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    } finally {
      _disconnectPromptOpen = false;
    }
  }

  Future<void> _acquireActivity() {
    return widget.acquireActivity?.call() ??
        _activityLease.acquire(
          reason: 'Participating in a ChronoSync live session',
          keepDisplayAwake:
              widget.invitation.requestedRole == SessionRole.display,
        );
  }

  Future<void> _releaseActivity() {
    return widget.releaseActivity?.call() ?? _activityLease.release();
  }
}

String _roleLabel(SessionRole role) {
  return switch (role) {
    SessionRole.host => 'Host',
    SessionRole.controller => 'Timekeeper',
    SessionRole.participant => 'Participant',
    SessionRole.display => 'Display',
  };
}
