import 'dart:async';

import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/live/live_view_models.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

typedef LobbyInvitationCallback =
    void Function(LobbyInvitationViewData invitation);
typedef LobbyRoleChanged = void Function(String deviceId, SessionRole role);

/// Responsive pre-session lobby for sharing invitations and managing roles.
class SessionLobbyScreen extends StatelessWidget {
  const SessionLobbyScreen({
    required this.data,
    this.onBack,
    this.onHostReadyChanged,
    this.onStart,
    this.onCopyInvitation,
    this.onShareInvitation,
    this.onRoleChanged,
    this.onRemoveParticipant,
    super.key,
  });

  final LobbyViewData data;
  final VoidCallback? onBack;
  final ValueChanged<bool>? onHostReadyChanged;
  final VoidCallback? onStart;
  final LobbyInvitationCallback? onCopyInvitation;
  final LobbyInvitationCallback? onShareInvitation;
  final LobbyRoleChanged? onRoleChanged;
  final ValueChanged<String>? onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(
                onPressed: onBack,
                tooltip: 'Back to plans',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: const Text('Session lobby'),
      ),
      body: ChronoResponsiveBuilder(
        builder:
            (
              BuildContext context,
              ChronoWindowClass windowClass,
              BoxConstraints constraints,
            ) {
              final EdgeInsets pagePadding = ChronoBreakpoints.pagePaddingFor(
                constraints.maxWidth,
              );
              final Widget invitations = _InvitationsPanel(
                participantInvitation: data.participantInvitation,
                displayInvitation: data.displayInvitation,
                sessionCode: data.sessionCode,
                connectionNote: data.connectionNote,
                onCopy: onCopyInvitation,
                onShare: onShareInvitation,
              );
              final Widget people = _PeoplePanel(
                participants: data.participants,
                onRoleChanged: onRoleChanged,
                onRemoveParticipant: onRemoveParticipant,
              );

              return SingleChildScrollView(
                padding: pagePadding.copyWith(
                  bottom: pagePadding.bottom + ChronoSpacing.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ChronoBreakpoints.maximumContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _LobbyHeader(data: data),
                        const SizedBox(height: ChronoSpacing.md),
                        if (windowClass ==
                            ChronoWindowClass.compact) ...<Widget>[
                          invitations,
                          const SizedBox(height: ChronoSpacing.sm),
                          people,
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(flex: 6, child: invitations),
                              const SizedBox(width: ChronoSpacing.md),
                              Expanded(flex: 5, child: people),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
      ),
      bottomNavigationBar: _LobbyBottomBar(
        isReady: data.isHostReady,
        isStarting: data.isStarting,
        onReadyChanged: onHostReadyChanged,
        onStart: onStart,
      ),
    );
  }
}

class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({required this.data});

  final LobbyViewData data;

  @override
  Widget build(BuildContext context) {
    final int connectedCount = data.participants
        .where(
          (LobbyParticipantViewData person) =>
              person.connectionState == ParticipantConnectionState.connected,
        )
        .length;

    return Semantics(
      container: true,
      label:
          '${data.planTitle}, ${data.stepCount} steps, '
          '$connectedCount connected',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChronoStatusPill(
              status: ChronoStatus.neutral,
              label: data.transportLabel,
            ),
            const SizedBox(height: ChronoSpacing.sm),
            Text(
              data.planTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: ChronoSpacing.xs),
            Text(
              '${data.stepCount} ${data.stepCount == 1 ? 'step' : 'steps'}'
              ' · ${formatFriendlyDuration(data.totalDuration)}'
              ' · $connectedCount connected',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.chronoColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationsPanel extends StatelessWidget {
  const _InvitationsPanel({
    required this.participantInvitation,
    required this.displayInvitation,
    required this.sessionCode,
    required this.connectionNote,
    required this.onCopy,
    required this.onShare,
  });

  final LobbyInvitationViewData? participantInvitation;
  final LobbyInvitationViewData? displayInvitation;
  final String? sessionCode;
  final String? connectionNote;
  final LobbyInvitationCallback? onCopy;
  final LobbyInvitationCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final List<LobbyInvitationViewData> invitations = <LobbyInvitationViewData>[
      if (participantInvitation != null) participantInvitation!,
      if (displayInvitation != null) displayInvitation!,
    ];

    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Invite people', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: ChronoSpacing.xs),
          Text(
            'Scan a QR code or share its link. Invitations only grant the '
            'role shown.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (sessionCode != null) ...<Widget>[
            const SizedBox(height: ChronoSpacing.sm),
            _SessionCode(code: sessionCode!),
          ],
          const SizedBox(height: ChronoSpacing.md),
          if (invitations.isEmpty)
            _UnavailableInvitation(note: connectionNote)
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool sideBySide =
                    constraints.maxWidth >= ChronoBreakpoints.medium;
                if (!sideBySide || invitations.length == 1) {
                  return Column(
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < invitations.length;
                        index++
                      ) ...<Widget>[
                        _InvitationCard(
                          invitation: invitations[index],
                          onCopy: onCopy,
                          onShare: onShare,
                        ),
                        if (index < invitations.length - 1)
                          const SizedBox(height: ChronoSpacing.sm),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (
                      int index = 0;
                      index < invitations.length;
                      index++
                    ) ...<Widget>[
                      Expanded(
                        child: _InvitationCard(
                          invitation: invitations[index],
                          onCopy: onCopy,
                          onShare: onShare,
                        ),
                      ),
                      if (index < invitations.length - 1)
                        const SizedBox(width: ChronoSpacing.sm),
                    ],
                  ],
                );
              },
            ),
          if (connectionNote != null && invitations.isNotEmpty) ...<Widget>[
            const SizedBox(height: ChronoSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: context.chronoColors.textSecondary,
                ),
                const SizedBox(width: ChronoSpacing.xs),
                Expanded(
                  child: Text(
                    connectionNote!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionCode extends StatelessWidget {
  const _SessionCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Session code, $code',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.chronoColors.surfaceMuted,
            borderRadius: ChronoRadii.controlBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ChronoSpacing.sm,
              vertical: 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.tag_rounded,
                  color: context.chronoColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: ChronoSpacing.xs),
                Flexible(
                  child: Text(
                    code,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableInvitation extends StatelessWidget {
  const _UnavailableInvitation({required this.note});

  final String? note;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.chronoColors.surfaceMuted,
        borderRadius: ChronoRadii.controlBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ChronoSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.qr_code_2_rounded),
            const SizedBox(width: ChronoSpacing.sm),
            Expanded(
              child: Text(
                note ?? 'Invitations will appear when hosting is ready.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.onCopy,
    required this.onShare,
  });

  final LobbyInvitationViewData invitation;
  final LobbyInvitationCallback? onCopy;
  final LobbyInvitationCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final String? expiry = invitation.expiresAt == null
        ? null
        : DateFormat.jm().format(invitation.expiresAt!.toLocal());

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.chronoColors.surfaceMuted,
        borderRadius: ChronoRadii.surfaceBorder,
        border: Border.all(color: context.chronoColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ChronoSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              invitation.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ChronoSpacing.sm),
            Center(
              child: Semantics(
                image: true,
                label: 'QR code for ${invitation.label.toLowerCase()}',
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: ChronoRadii.controlBorder,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(ChronoSpacing.xs),
                      child: QrImageView(
                        data: invitation.link,
                        version: QrVersions.auto,
                        size: 168,
                        gapless: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (invitation.detail != null || expiry != null) ...<Widget>[
              const SizedBox(height: ChronoSpacing.sm),
              Text(
                <String>[
                  if (invitation.detail != null) invitation.detail!,
                  if (expiry != null) 'Expires $expiry',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: ChronoSpacing.sm),
            Semantics(
              label: '${invitation.label} invitation link',
              child: SelectableText(
                invitation.link,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onCopy != null || onShare != null) ...<Widget>[
              const SizedBox(height: ChronoSpacing.xs),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: ChronoSpacing.xs,
                runSpacing: ChronoSpacing.xs,
                children: <Widget>[
                  if (onCopy != null)
                    TextButton.icon(
                      onPressed: () => onCopy!(invitation),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy link'),
                    ),
                  if (onShare != null)
                    TextButton.icon(
                      onPressed: () => onShare!(invitation),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({
    required this.participants,
    required this.onRoleChanged,
    required this.onRemoveParticipant,
  });

  final List<LobbyParticipantViewData> participants;
  final LobbyRoleChanged? onRoleChanged;
  final ValueChanged<String>? onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'People',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${participants.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: ChronoSpacing.xs),
          Text(
            'Only the host can change roles or remove a device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          if (participants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ChronoSpacing.md),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.group_add_outlined,
                    size: 36,
                    color: context.chronoColors.textSecondary,
                  ),
                  const SizedBox(height: ChronoSpacing.xs),
                  Text(
                    'Waiting for people to join',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          else
            for (
              int index = 0;
              index < participants.length;
              index++
            ) ...<Widget>[
              _ParticipantRow(
                participant: participants[index],
                onRoleChanged: onRoleChanged,
                onRemoveParticipant: onRemoveParticipant,
              ),
              if (index < participants.length - 1)
                const Divider(height: ChronoSpacing.md),
            ],
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.onRoleChanged,
    required this.onRemoveParticipant,
  });

  final LobbyParticipantViewData participant;
  final LobbyRoleChanged? onRoleChanged;
  final ValueChanged<String>? onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    final bool canManage =
        participant.isManageable &&
        participant.role != SessionRole.host &&
        !participant.isCurrentDevice;
    final ChronoStatus connectionStatus = switch (participant.connectionState) {
      ParticipantConnectionState.connected =>
        participant.isReady ? ChronoStatus.complete : ChronoStatus.neutral,
      ParticipantConnectionState.stale ||
      ParticipantConnectionState.disconnected => ChronoStatus.disconnected,
    };
    final String statusLabel = switch (participant.connectionState) {
      ParticipantConnectionState.connected =>
        participant.isReady ? 'Ready' : 'Not ready',
      ParticipantConnectionState.stale => 'Connection stale',
      ParticipantConnectionState.disconnected => 'Disconnected',
    };

    final Widget identity = Semantics(
      container: true,
      label:
          '${participant.displayName}, '
          '${_roleLabel(participant.role)}, $statusLabel',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: context.chronoColors.primaryContainer,
              foregroundColor: context.chronoColors.onPrimaryContainer,
              child: Icon(_roleIcon(participant.role), size: 20),
            ),
            const SizedBox(width: ChronoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    participant.isCurrentDevice
                        ? '${participant.displayName} (you)'
                        : participant.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: ChronoSpacing.xxs),
                  ChronoStatusPill(
                    status: connectionStatus,
                    label: statusLabel,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final Widget roleControl = canManage && onRoleChanged != null
        ? Semantics(
            label: 'Role for ${participant.displayName}',
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ChronoSpacing.minimumTouchTarget,
                maxWidth: 168,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SessionRole>(
                  value: participant.role,
                  isExpanded: true,
                  borderRadius: ChronoRadii.controlBorder,
                  items: const <DropdownMenuItem<SessionRole>>[
                    DropdownMenuItem<SessionRole>(
                      value: SessionRole.controller,
                      child: Text('Controller'),
                    ),
                    DropdownMenuItem<SessionRole>(
                      value: SessionRole.participant,
                      child: Text('Participant'),
                    ),
                    DropdownMenuItem<SessionRole>(
                      value: SessionRole.display,
                      child: Text('Display'),
                    ),
                  ],
                  onChanged: (SessionRole? role) {
                    if (role != null) {
                      onRoleChanged!(participant.deviceId, role);
                    }
                  },
                ),
              ),
            ),
          )
        : Text(
            _roleLabel(participant.role),
            style: Theme.of(context).textTheme.labelMedium,
          );
    final Widget? removeControl = canManage && onRemoveParticipant != null
        ? Semantics(
            container: true,
            button: true,
            label: 'Remove ${participant.displayName}',
            onTap: () => unawaited(_confirmRemoval(context)),
            child: ExcludeSemantics(
              child: IconButton(
                onPressed: () => unawaited(_confirmRemoval(context)),
                tooltip: 'Remove ${participant.displayName}',
                icon: const Icon(Icons.person_remove_outlined),
              ),
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ChronoSpacing.xxs),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stackControls =
              constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (stackControls) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                identity,
                const SizedBox(height: ChronoSpacing.xs),
                Row(
                  children: <Widget>[
                    Expanded(child: roleControl),
                    if (removeControl != null) removeControl,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: identity),
              const SizedBox(width: ChronoSpacing.xs),
              roleControl,
              if (removeControl != null) removeControl,
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRemoval(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Remove ${participant.displayName}?'),
        content: Text(
          '${participant.displayName} will lose access to this session. '
          'They will need a new invitation to rejoin.',
        ),
        actions: <Widget>[
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      onRemoveParticipant?.call(participant.deviceId);
    }
  }
}

class _LobbyBottomBar extends StatelessWidget {
  const _LobbyBottomBar({
    required this.isReady,
    required this.isStarting,
    required this.onReadyChanged,
    required this.onStart,
  });

  final bool isReady;
  final bool isStarting;
  final ValueChanged<bool>? onReadyChanged;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.chronoColors.surface,
          border: Border(top: BorderSide(color: context.chronoColors.outline)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ChronoSpacing.sm),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ChronoBreakpoints.maximumContentWidth,
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool stackActions =
                      constraints.maxWidth < ChronoBreakpoints.medium ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3;
                  final Widget readiness = CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: isReady,
                    onChanged: onReadyChanged == null
                        ? null
                        : (bool? value) => onReadyChanged!(value ?? false),
                    title: const Text('I’m ready'),
                    subtitle: const Text('Everyone sees the first step'),
                  );
                  final Widget start = ChronoPrimaryButton(
                    label: 'Start session',
                    semanticLabel: isReady
                        ? 'Start live session'
                        : 'Start live session, mark yourself ready first',
                    icon: Icons.play_arrow_rounded,
                    isLoading: isStarting,
                    expand: stackActions,
                    onPressed: isReady ? onStart : null,
                  );
                  if (stackActions) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        readiness,
                        const SizedBox(height: ChronoSpacing.xs),
                        start,
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: readiness),
                      const SizedBox(width: ChronoSpacing.sm),
                      start,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _roleLabel(SessionRole role) {
  return switch (role) {
    SessionRole.host => 'Host',
    SessionRole.controller => 'Controller',
    SessionRole.participant => 'Participant',
    SessionRole.display => 'Display',
  };
}

IconData _roleIcon(SessionRole role) {
  return switch (role) {
    SessionRole.host => Icons.star_rounded,
    SessionRole.controller => Icons.tune_rounded,
    SessionRole.participant => Icons.person_rounded,
    SessionRole.display => Icons.tv_rounded,
  };
}
