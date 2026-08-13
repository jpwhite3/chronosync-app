import 'dart:async';

import 'package:chronosync/core/platform/display_fullscreen.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/live/live_view_models.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Role-aware live sequence. All state and actions remain owned by the caller.
class LiveSessionScreen extends StatelessWidget {
  const LiveSessionScreen({
    required this.data,
    this.onClose,
    this.onShowPeople,
    this.onStart,
    this.onPauseResume,
    this.onAdvance,
    this.onAdjustRemaining,
    this.onCustomAdjustmentRequested,
    this.onJumpRequested,
    this.onAcknowledge,
    this.onEndRequested,
    super.key,
  });

  final LiveSessionViewData data;
  final VoidCallback? onClose;
  final VoidCallback? onShowPeople;
  final VoidCallback? onStart;
  final VoidCallback? onPauseResume;
  final VoidCallback? onAdvance;
  final ValueChanged<int>? onAdjustRemaining;
  final VoidCallback? onCustomAdjustmentRequested;
  final VoidCallback? onJumpRequested;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onEndRequested;

  @override
  Widget build(BuildContext context) {
    if (data.role == SessionRole.display) {
      return _DisplaySessionView(data: data, onClose: onClose);
    }

    return Scaffold(
      appBar: AppBar(
        leading: onClose == null
            ? null
            : IconButton(
                onPressed: onClose,
                tooltip: 'Leave live session',
                icon: const Icon(Icons.close_rounded),
              ),
        title: const Text('Live session'),
        actions: <Widget>[
          if (onShowPeople != null)
            Tooltip(
              message: _peopleActionLabel(data.participantCount),
              excludeFromSemantics: true,
              child: Semantics(
                label: _peopleActionLabel(data.participantCount),
                button: true,
                child: ExcludeSemantics(
                  child: TextButton.icon(
                    onPressed: onShowPeople,
                    icon: const Icon(Icons.group_outlined),
                    label: Text('${data.participantCount}'),
                  ),
                ),
              ),
            ),
          const SizedBox(width: ChronoSpacing.xs),
        ],
      ),
      body: ChronoResponsiveBuilder(
        builder:
            (
              BuildContext context,
              ChronoWindowClass windowClass,
              BoxConstraints constraints,
            ) {
              final EdgeInsets padding = ChronoBreakpoints.pagePaddingFor(
                constraints.maxWidth,
              );
              return SingleChildScrollView(
                padding: padding.copyWith(
                  bottom: padding.bottom + ChronoSpacing.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ChronoBreakpoints.maximumContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _LiveUpdateAnnouncement(data: data),
                        _LiveHeader(data: data),
                        if (data.isStale) ...<Widget>[
                          const SizedBox(height: ChronoSpacing.sm),
                          _StaleBanner(
                            message:
                                data.staleMessage ??
                                'The host connection is stale. Timers and '
                                    'controls are frozen until reconnection.',
                          ),
                        ],
                        if (!data.hasCompleteActivityHistory) ...<Widget>[
                          const SizedBox(height: ChronoSpacing.sm),
                          const _IncompleteActivityHistoryBanner(),
                        ],
                        const SizedBox(height: ChronoSpacing.md),
                        _LiveComposition(
                          data: data,
                          windowClass: windowClass,
                          onStart: onStart,
                          onPauseResume: onPauseResume,
                          onAdvance: onAdvance,
                          onAdjustRemaining: onAdjustRemaining,
                          onCustomAdjustmentRequested:
                              onCustomAdjustmentRequested,
                          onJumpRequested: onJumpRequested,
                          onAcknowledge: onAcknowledge,
                          onEndRequested: onEndRequested,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
      ),
    );
  }
}

class _LiveUpdateAnnouncement extends StatelessWidget {
  const _LiveUpdateAnnouncement({required this.data});

  final LiveSessionViewData data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: _liveUpdateLabel(data),
      child: const SizedBox.shrink(),
    );
  }
}

class _IncompleteActivityHistoryBanner extends StatelessWidget {
  const _IncompleteActivityHistoryBanner();

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      ChronoStatus.approaching,
    );
    const String message =
        'Earlier session activity isn’t available on this device. '
        'Live timing still reflects the host’s current state.';
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Incomplete activity history. $message',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: visual.background,
            border: Border.all(color: visual.border),
            borderRadius: ChronoRadii.controlBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.all(ChronoSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.history_toggle_off_rounded,
                  color: visual.foreground,
                ),
                const SizedBox(width: ChronoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Incomplete activity history',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: visual.foreground,
                        ),
                      ),
                      const SizedBox(height: ChronoSpacing.xxs),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: visual.foreground,
                        ),
                      ),
                    ],
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

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({required this.data});

  final LiveSessionViewData data;

  @override
  Widget build(BuildContext context) {
    final ChronoStatus status = _statusFor(data);
    return Semantics(
      container: true,
      label:
          '${data.planTitle}. ${_roleLabel(data.role)} view. '
          'Interval ${data.currentStepIndex + 1} of ${data.stepCount}. '
          '${status.label}.',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.planTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: ChronoSpacing.xxs),
                  Text(
                    '${_roleLabel(data.role)} · '
                    'Interval ${data.currentStepIndex + 1} of ${data.stepCount}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: ChronoSpacing.sm),
            ChronoStatusPill(status: status),
          ],
        ),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      ChronoStatus.disconnected,
    );
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Connection stale. $message',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: visual.background,
            border: Border.all(color: visual.border),
            borderRadius: ChronoRadii.controlBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.all(ChronoSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.sync_problem_rounded, color: visual.foreground),
                const SizedBox(width: ChronoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Connection stale',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: visual.foreground,
                        ),
                      ),
                      const SizedBox(height: ChronoSpacing.xxs),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: visual.foreground,
                        ),
                      ),
                    ],
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

class _LiveComposition extends StatelessWidget {
  const _LiveComposition({
    required this.data,
    required this.windowClass,
    required this.onStart,
    required this.onPauseResume,
    required this.onAdvance,
    required this.onAdjustRemaining,
    required this.onCustomAdjustmentRequested,
    required this.onJumpRequested,
    required this.onAcknowledge,
    required this.onEndRequested,
  });

  final LiveSessionViewData data;
  final ChronoWindowClass windowClass;
  final VoidCallback? onStart;
  final VoidCallback? onPauseResume;
  final VoidCallback? onAdvance;
  final ValueChanged<int>? onAdjustRemaining;
  final VoidCallback? onCustomAdjustmentRequested;
  final VoidCallback? onJumpRequested;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onEndRequested;

  bool get _isParticipant => data.role == SessionRole.participant;

  @override
  Widget build(BuildContext context) {
    final Widget current = _CurrentStepCard(
      data: data,
      participantMode: _isParticipant,
    );
    final Widget metrics = _TimingMetrics(data: data);
    final Widget next = _NextStepCard(data: data);
    final Widget? acknowledgements =
        data.role == SessionRole.host || data.role == SessionRole.controller
        ? _AcknowledgementsCard(
            acknowledgements: data.currentStepAcknowledgements,
          )
        : null;
    final Widget actions = _RoleActions(
      data: data,
      onStart: onStart,
      onPauseResume: onPauseResume,
      onAdvance: onAdvance,
      onAdjustRemaining: onAdjustRemaining,
      onCustomAdjustmentRequested: onCustomAdjustmentRequested,
      onJumpRequested: onJumpRequested,
      onAcknowledge: onAcknowledge,
      onEndRequested: onEndRequested,
    );

    if (windowClass == ChronoWindowClass.expanded) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                current,
                const SizedBox(height: ChronoSpacing.md),
                metrics,
              ],
            ),
          ),
          const SizedBox(width: ChronoSpacing.md),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                next,
                if (acknowledgements != null) ...<Widget>[
                  const SizedBox(height: ChronoSpacing.md),
                  acknowledgements,
                ],
                const SizedBox(height: ChronoSpacing.md),
                actions,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        current,
        const SizedBox(height: ChronoSpacing.sm),
        metrics,
        const SizedBox(height: ChronoSpacing.sm),
        next,
        if (acknowledgements != null) ...<Widget>[
          const SizedBox(height: ChronoSpacing.sm),
          acknowledgements,
        ],
        const SizedBox(height: ChronoSpacing.md),
        actions,
      ],
    );
  }
}

class _CurrentStepCard extends StatelessWidget {
  const _CurrentStepCard({required this.data, required this.participantMode});

  final LiveSessionViewData data;
  final bool participantMode;

  @override
  Widget build(BuildContext context) {
    final ChronoStatus status = _statusFor(data);
    final double progress = data.stepCount <= 0
        ? 0
        : (data.currentStepIndex + 1) / data.stepCount;

    return ChronoCard(
      padding: EdgeInsets.all(
        participantMode ? ChronoSpacing.md : ChronoSpacing.lg,
      ),
      backgroundColor: _surfaceForStatus(context, status),
      borderColor: ChronoStatusVisual.resolve(context, status).border,
      child: Semantics(
        container: true,
        label:
            'Current interval, ${data.currentStepTitle}. '
            '${_timerSemantic(data)}.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'CURRENT INTERVAL',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Text(
                    '${data.currentStepIndex + 1} / ${data.stepCount}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: ChronoSpacing.sm),
              Text(
                data.currentStepTitle,
                maxLines: participantMode ? 4 : 3,
                overflow: TextOverflow.ellipsis,
                style: participantMode
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: ChronoSpacing.lg),
              ChronoTimerDisplay(
                label: _timerLabel(data),
                value: _remainingClock(data.remaining),
                status: status,
                size: participantMode
                    ? ChronoTimerSize.standard
                    : ChronoTimerSize.hero,
                showStatus: true,
                semanticLabel: _timerSemantic(data),
              ),
              const SizedBox(height: ChronoSpacing.md),
              Semantics(
                label:
                    'Sequence progress, interval ${data.currentStepIndex + 1} '
                    'of ${data.stepCount}',
                value: '${(progress * 100).round()} percent',
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 8,
                  borderRadius: ChronoRadii.controlBorder,
                  backgroundColor: context.chronoColors.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimingMetrics extends StatelessWidget {
  const _TimingMetrics({required this.data});

  final LiveSessionViewData data;

  @override
  Widget build(BuildContext context) {
    final Widget elapsed = _MetricCard(
      label: 'Elapsed',
      value: formatClock(data.elapsed),
      semanticValue: 'Elapsed, ${_durationSemantic(data.elapsed)}',
      icon: Icons.timelapse_rounded,
    );
    final Widget variance = _MetricCard(
      label: _varianceLabel(data.variance),
      value: formatClock(data.variance.abs()),
      semanticValue: _varianceSemantic(data.variance),
      icon: _varianceIcon(data.variance),
      status: _varianceStatus(data.variance),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              elapsed,
              const SizedBox(height: ChronoSpacing.xs),
              variance,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: elapsed),
            const SizedBox(width: ChronoSpacing.sm),
            Expanded(child: variance),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.semanticValue,
    required this.icon,
    this.status = ChronoStatus.neutral,
  });

  final String label;
  final String value;
  final String semanticValue;
  final IconData icon;
  final ChronoStatus status;

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      status,
    );
    return ChronoCard(
      backgroundColor: status == ChronoStatus.neutral
          ? null
          : visual.background,
      child: Semantics(
        label: semanticValue,
        child: ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Icon(icon, color: visual.foreground),
              const SizedBox(width: ChronoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: ChronoSpacing.xxs),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: visual.foreground,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.data});

  final LiveSessionViewData data;

  @override
  Widget build(BuildContext context) {
    final bool hasNext = data.nextStepTitle != null;
    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Semantics(
        container: true,
        label: hasNext
            ? 'Next interval, ${data.nextStepTitle}, '
                  '${_durationSemantic(data.nextStepDuration!)}'
            : 'This is the final interval',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    hasNext ? Icons.skip_next_rounded : Icons.flag_rounded,
                    color: context.chronoColors.textSecondary,
                  ),
                  const SizedBox(width: ChronoSpacing.xs),
                  Text(
                    hasNext ? 'UP NEXT' : 'FINAL INTERVAL',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: ChronoSpacing.sm),
              Text(
                data.nextStepTitle ?? 'Finish the session when ready',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.nextStepDuration != null) ...<Widget>[
                const SizedBox(height: ChronoSpacing.xs),
                Text(
                  formatFriendlyDuration(data.nextStepDuration!),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AcknowledgementsCard extends StatelessWidget {
  const _AcknowledgementsCard({required this.acknowledgements});

  final List<AcknowledgementViewData> acknowledgements;

  @override
  Widget build(BuildContext context) {
    final DateFormat timeFormat = DateFormat.jm();
    final String semanticDetails = acknowledgements.isEmpty
        ? 'No one has acknowledged this interval yet.'
        : acknowledgements
              .map<String>(
                (AcknowledgementViewData acknowledgement) =>
                    '${acknowledgement.displayName} at '
                    '${timeFormat.format(acknowledgement.acknowledgedAt.toLocal())}',
              )
              .join('. ');
    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Semantics(
        container: true,
        label: 'Got it acknowledgements. $semanticDetails',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.done_all_rounded,
                    color: context.chronoColors.success,
                  ),
                  const SizedBox(width: ChronoSpacing.xs),
                  Expanded(
                    child: Text(
                      'Acknowledgements',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.chronoColors.successContainer,
                      borderRadius: BorderRadius.circular(ChronoRadii.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ChronoSpacing.xs,
                        vertical: ChronoSpacing.xxs,
                      ),
                      child: Text(
                        '${acknowledgements.length}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: context.chronoColors.success),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ChronoSpacing.sm),
              if (acknowledgements.isEmpty)
                Text(
                  'No acknowledgements yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.chronoColors.textSecondary,
                  ),
                )
              else
                for (
                  int index = 0;
                  index < acknowledgements.length;
                  index += 1
                ) ...<Widget>[
                  _AcknowledgementRow(
                    acknowledgement: acknowledgements[index],
                    timeFormat: timeFormat,
                  ),
                  if (index < acknowledgements.length - 1)
                    const Divider(height: ChronoSpacing.sm),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AcknowledgementRow extends StatelessWidget {
  const _AcknowledgementRow({
    required this.acknowledgement,
    required this.timeFormat,
  });

  final AcknowledgementViewData acknowledgement;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ChronoSpacing.xxs),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: context.chronoColors.successContainer,
            foregroundColor: context.chronoColors.success,
            child: const Icon(Icons.check_rounded, size: 18),
          ),
          const SizedBox(width: ChronoSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  acknowledgement.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  acknowledgement.isCurrentDevice
                      ? '${_roleLabel(acknowledgement.role)} · this device'
                      : _roleLabel(acknowledgement.role),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.chronoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ChronoSpacing.xs),
          Text(
            timeFormat.format(acknowledgement.acknowledgedAt.toLocal()),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.chronoColors.textSecondary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleActions extends StatelessWidget {
  const _RoleActions({
    required this.data,
    required this.onStart,
    required this.onPauseResume,
    required this.onAdvance,
    required this.onAdjustRemaining,
    required this.onCustomAdjustmentRequested,
    required this.onJumpRequested,
    required this.onAcknowledge,
    required this.onEndRequested,
  });

  final LiveSessionViewData data;
  final VoidCallback? onStart;
  final VoidCallback? onPauseResume;
  final VoidCallback? onAdvance;
  final ValueChanged<int>? onAdjustRemaining;
  final VoidCallback? onCustomAdjustmentRequested;
  final VoidCallback? onJumpRequested;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onEndRequested;

  @override
  Widget build(BuildContext context) {
    if (data.status == LiveSessionStatus.ended) {
      return _EndedMessage(endReason: data.endReason);
    }
    if (data.role == SessionRole.participant) {
      return _ParticipantAction(
        acknowledged: data.hasAcknowledged,
        enabled:
            !data.isStale &&
            data.status != LiveSessionStatus.waiting &&
            onAcknowledge != null,
        onAcknowledge: onAcknowledge,
      );
    }
    if (data.status == LiveSessionStatus.waiting) {
      if (data.role != SessionRole.host || onStart == null) {
        return const _WaitingMessage();
      }
      return ChronoPrimaryButton(
        label: 'Start session',
        icon: Icons.play_arrow_rounded,
        expand: true,
        autofocus: true,
        onPressed: data.isStale ? null : onStart,
      );
    }
    return _ControllerActions(
      isHost: data.role == SessionRole.host,
      isPaused: data.status == LiveSessionStatus.paused,
      isFinalStep: data.currentStepIndex >= data.stepCount - 1,
      acknowledged: data.hasAcknowledged,
      enabled: !data.isStale,
      onPauseResume: onPauseResume,
      onAdvance: onAdvance,
      onAdjustRemaining: onAdjustRemaining,
      onCustomAdjustmentRequested: onCustomAdjustmentRequested,
      onJumpRequested: onJumpRequested,
      onAcknowledge: onAcknowledge,
      onEndRequested: onEndRequested,
    );
  }
}

class _ParticipantAction extends StatelessWidget {
  const _ParticipantAction({
    required this.acknowledged,
    required this.enabled,
    required this.onAcknowledge,
  });

  final bool acknowledged;
  final bool enabled;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    if (acknowledged) {
      return ChronoCard(
        backgroundColor: context.chronoColors.successContainer,
        borderColor: context.chronoColors.success,
        child: Semantics(
          label: 'You acknowledged the current interval',
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.check_circle_rounded,
                  color: context.chronoColors.success,
                ),
                const SizedBox(width: ChronoSpacing.xs),
                Text(
                  'Got it',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.chronoColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ChronoPrimaryButton(
      label: 'Got it',
      semanticLabel: 'Acknowledge the current interval',
      icon: Icons.check_rounded,
      expand: true,
      autofocus: true,
      onPressed: enabled ? onAcknowledge : null,
    );
  }
}

class _ControllerActions extends StatelessWidget {
  const _ControllerActions({
    required this.isHost,
    required this.isPaused,
    required this.isFinalStep,
    required this.acknowledged,
    required this.enabled,
    required this.onPauseResume,
    required this.onAdvance,
    required this.onAdjustRemaining,
    required this.onCustomAdjustmentRequested,
    required this.onJumpRequested,
    required this.onAcknowledge,
    required this.onEndRequested,
  });

  final bool isHost;
  final bool isPaused;
  final bool isFinalStep;
  final bool acknowledged;
  final bool enabled;
  final VoidCallback? onPauseResume;
  final VoidCallback? onAdvance;
  final ValueChanged<int>? onAdjustRemaining;
  final VoidCallback? onCustomAdjustmentRequested;
  final VoidCallback? onJumpRequested;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onEndRequested;

  @override
  Widget build(BuildContext context) {
    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ChronoPrimaryButton(
            label: isFinalStep ? 'Finish session' : 'Advance',
            semanticLabel: isFinalStep
                ? 'Finish the live session'
                : 'Advance to the next interval',
            icon: isFinalStep ? Icons.flag_rounded : Icons.skip_next_rounded,
            expand: true,
            autofocus: true,
            onPressed: enabled ? onAdvance : null,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          _ControllerAcknowledgementAction(
            acknowledged: acknowledged,
            enabled: enabled && onAcknowledge != null,
            onAcknowledge: onAcknowledge,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          OutlinedButton.icon(
            onPressed: enabled ? onPauseResume : null,
            icon: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            label: Text(isPaused ? 'Resume' : 'Pause'),
          ),
          const SizedBox(height: ChronoSpacing.md),
          Text(
            'Adjust remaining',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: ChronoSpacing.xs),
          Wrap(
            spacing: ChronoSpacing.xs,
            runSpacing: ChronoSpacing.xs,
            children: <Widget>[
              OutlinedButton(
                onPressed: enabled && onAdjustRemaining != null
                    ? () => onAdjustRemaining!(-60)
                    : null,
                child: const Text('−1 min'),
              ),
              OutlinedButton(
                onPressed: enabled && onAdjustRemaining != null
                    ? () => onAdjustRemaining!(60)
                    : null,
                child: const Text('+1 min'),
              ),
              OutlinedButton(
                onPressed: enabled ? onCustomAdjustmentRequested : null,
                child: const Text('Custom'),
              ),
            ],
          ),
          if (onJumpRequested != null ||
              (isHost && onEndRequested != null)) ...<Widget>[
            const SizedBox(height: ChronoSpacing.md),
            const Divider(),
            const SizedBox(height: ChronoSpacing.sm),
            Wrap(
              spacing: ChronoSpacing.xs,
              runSpacing: ChronoSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              children: <Widget>[
                if (onJumpRequested != null)
                  TextButton.icon(
                    onPressed: enabled ? onJumpRequested : null,
                    icon: const Icon(Icons.alt_route_rounded),
                    label: const Text('Jump to interval'),
                  ),
                if (isHost && onEndRequested != null)
                  TextButton.icon(
                    onPressed: enabled ? onEndRequested : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End session'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.chronoColors.overtime,
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

class _ControllerAcknowledgementAction extends StatelessWidget {
  const _ControllerAcknowledgementAction({
    required this.acknowledged,
    required this.enabled,
    required this.onAcknowledge,
  });

  final bool acknowledged;
  final bool enabled;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    if (!acknowledged) {
      return Semantics(
        label: 'Acknowledge the current interval',
        button: true,
        enabled: enabled,
        child: ExcludeSemantics(
          child: OutlinedButton.icon(
            onPressed: enabled ? onAcknowledge : null,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Got it'),
          ),
        ),
      );
    }

    return Semantics(
      label: 'You acknowledged the current interval',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(
            minHeight: ChronoSpacing.minimumTouchTarget,
          ),
          decoration: BoxDecoration(
            color: context.chronoColors.successContainer,
            borderRadius: ChronoRadii.controlBorder,
            border: Border.all(color: context.chronoColors.success),
          ),
          padding: const EdgeInsets.symmetric(horizontal: ChronoSpacing.sm),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.check_circle_rounded,
                color: context.chronoColors.success,
              ),
              const SizedBox(width: ChronoSpacing.xs),
              Text(
                'Got it',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: context.chronoColors.success,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingMessage extends StatelessWidget {
  const _WaitingMessage();

  @override
  Widget build(BuildContext context) {
    return ChronoCard(
      backgroundColor: context.chronoColors.surfaceMuted,
      child: const Row(
        children: <Widget>[
          Icon(Icons.hourglass_top_rounded),
          SizedBox(width: ChronoSpacing.sm),
          Expanded(child: Text('Waiting for the host to start')),
        ],
      ),
    );
  }
}

class _EndedMessage extends StatelessWidget {
  const _EndedMessage({required this.endReason});

  final SessionEndReason? endReason;

  @override
  Widget build(BuildContext context) {
    final bool completed = endReason == SessionEndReason.completed;
    final Color background = completed
        ? context.chronoColors.successContainer
        : context.chronoColors.surfaceMuted;
    final Color foreground = completed
        ? context.chronoColors.success
        : context.chronoColors.textPrimary;
    final String label = completed ? 'Session complete' : 'Session ended';
    return ChronoCard(
      backgroundColor: background,
      borderColor: completed
          ? context.chronoColors.success
          : context.chronoColors.outlineStrong,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Icon(
                completed
                    ? Icons.check_circle_rounded
                    : Icons.stop_circle_outlined,
                color: foreground,
              ),
              const SizedBox(width: ChronoSpacing.sm),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplaySessionView extends StatefulWidget {
  const _DisplaySessionView({required this.data, required this.onClose});

  final LiveSessionViewData data;
  final VoidCallback? onClose;

  @override
  State<_DisplaySessionView> createState() => _DisplaySessionViewState();
}

class _DisplaySessionViewState extends State<_DisplaySessionView> {
  StreamSubscription<bool>? _fullscreenSubscription;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    if (DisplayFullscreen.isSupported) {
      _fullscreenSubscription = DisplayFullscreen.changes.listen((
        bool isFullscreen,
      ) {
        if (mounted) {
          setState(() => _isFullscreen = isFullscreen);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        unawaited(_enterFullscreen());
      });
    }
  }

  @override
  void dispose() {
    unawaited(_fullscreenSubscription?.cancel());
    if (DisplayFullscreen.isSupported) {
      unawaited(DisplayFullscreen.exit());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LiveSessionViewData data = widget.data;
    final VoidCallback? onClose = widget.onClose;
    const ChronoColors displayColors = ChronoColors.dark;
    final Color background = displayColors.canvas;
    final Color foreground = displayColors.textPrimary;
    final Color secondary = displayColors.textSecondary;
    final ChronoStatus status = _statusFor(data);
    final Color accent = switch (status) {
      ChronoStatus.disconnected => displayColors.disconnected,
      ChronoStatus.approaching => displayColors.approaching,
      ChronoStatus.due => displayColors.due,
      ChronoStatus.overtime => displayColors.overtime,
      ChronoStatus.paused => const Color(0xFFC792EA),
      ChronoStatus.ended => secondary,
      _ => displayColors.live,
    };
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: ChronoResponsiveBuilder(
          builder:
              (
                BuildContext context,
                ChronoWindowClass windowClass,
                BoxConstraints constraints,
              ) {
                final bool expanded = windowClass == ChronoWindowClass.expanded;
                final EdgeInsets padding = EdgeInsets.all(
                  expanded ? ChronoSpacing.xl : ChronoSpacing.md,
                );
                final bool supportsFullscreen = DisplayFullscreen.isSupported;
                final bool hasDisplayActions =
                    supportsFullscreen || onClose != null;
                final double actionWidth =
                    (supportsFullscreen ? 48 : 0) +
                    (onClose != null ? 48 : 0) +
                    (supportsFullscreen && onClose != null
                        ? ChronoSpacing.xs
                        : 0);
                final double minimumContentHeight =
                    constraints.maxHeight > padding.vertical
                    ? constraints.maxHeight - padding.vertical
                    : 0;
                return Stack(
                  children: <Widget>[
                    _LiveUpdateAnnouncement(data: data),
                    Semantics(
                      container: true,
                      label:
                          'Display view. Current interval '
                          '${data.currentStepTitle}. ${_timerSemantic(data)}.'
                          '${data.isStale ? ' Connection stale.' : ''}',
                      child: ExcludeSemantics(
                        child: SingleChildScrollView(
                          padding: padding,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: minimumContentHeight,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          data.planTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(color: secondary),
                                        ),
                                      ),
                                      if (data.isStale)
                                        _DisplayBadge(
                                          icon: Icons.sync_problem_rounded,
                                          label: 'CONNECTION STALE',
                                          color: accent,
                                        )
                                      else
                                        _DisplayBadge(
                                          icon: status.icon,
                                          label: status.label.toUpperCase(),
                                          color: accent,
                                        ),
                                      if (hasDisplayActions) ...<Widget>[
                                        const SizedBox(width: ChronoSpacing.xs),
                                        SizedBox(width: actionWidth),
                                      ],
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(
                                    'CURRENT · ${data.currentStepIndex + 1} OF '
                                    '${data.stepCount}',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: secondary,
                                          letterSpacing: 1.5,
                                        ),
                                  ),
                                  const SizedBox(height: ChronoSpacing.md),
                                  Text(
                                    data.currentStepTitle,
                                    maxLines: expanded ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style:
                                        (expanded
                                                ? Theme.of(
                                                    context,
                                                  ).textTheme.displayLarge
                                                : Theme.of(
                                                    context,
                                                  ).textTheme.displaySmall)
                                            ?.copyWith(color: foreground),
                                  ),
                                  const SizedBox(height: ChronoSpacing.xl),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _remainingClock(data.remaining),
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: expanded ? 144 : 96,
                                        height: 0.9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -4,
                                        fontFeatures: const <FontFeature>[
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: ChronoSpacing.sm),
                                  Text(
                                    _timerLabel(data).toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: accent,
                                          letterSpacing: 1.5,
                                        ),
                                  ),
                                  const Spacer(),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: displayColors.outline,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        top: ChronoSpacing.md,
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          Text(
                                            _varianceDisplay(data.variance),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(color: secondary),
                                          ),
                                          const Spacer(),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              data.nextStepTitle == null
                                                  ? 'Final interval'
                                                  : 'Next: ${data.nextStepTitle}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.end,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(color: foreground),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasDisplayActions)
                      Positioned(
                        top: padding.top,
                        right: padding.right,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (supportsFullscreen)
                              IconButton(
                                onPressed: () => unawaited(_toggleFullscreen()),
                                tooltip: _isFullscreen
                                    ? 'Exit full screen'
                                    : 'Enter full screen',
                                color: foreground,
                                icon: Icon(
                                  _isFullscreen
                                      ? Icons.fullscreen_exit_rounded
                                      : Icons.fullscreen_rounded,
                                ),
                              ),
                            if (supportsFullscreen && onClose != null)
                              const SizedBox(width: ChronoSpacing.xs),
                            if (onClose != null)
                              IconButton(
                                onPressed: onClose,
                                tooltip: 'Leave display',
                                color: foreground,
                                icon: const Icon(Icons.close_rounded),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
        ),
      ),
    );
  }

  Future<void> _enterFullscreen() async {
    final bool isFullscreen = await DisplayFullscreen.enter();
    if (mounted) {
      setState(() => _isFullscreen = isFullscreen);
    }
  }

  Future<void> _toggleFullscreen() async {
    final bool isFullscreen = await DisplayFullscreen.toggle();
    if (mounted) {
      setState(() => _isFullscreen = isFullscreen);
    }
  }
}

class _DisplayBadge extends StatelessWidget {
  const _DisplayBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        const SizedBox(width: ChronoSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color, letterSpacing: 1),
        ),
      ],
    );
  }
}

ChronoStatus _statusFor(LiveSessionViewData data) {
  if (data.isStale) {
    return ChronoStatus.disconnected;
  }
  return switch (data.status) {
    LiveSessionStatus.waiting => ChronoStatus.neutral,
    LiveSessionStatus.paused => ChronoStatus.paused,
    LiveSessionStatus.ended =>
      data.endReason == SessionEndReason.completed
          ? ChronoStatus.complete
          : ChronoStatus.ended,
    LiveSessionStatus.running => switch (data.timingPhase) {
      LiveTimingPhase.normal => ChronoStatus.live,
      LiveTimingPhase.approaching => ChronoStatus.approaching,
      LiveTimingPhase.due => ChronoStatus.due,
      LiveTimingPhase.overtime => ChronoStatus.overtime,
    },
  };
}

String _timerLabel(LiveSessionViewData data) {
  return switch (data.timingPhase) {
    LiveTimingPhase.due => 'Due',
    LiveTimingPhase.overtime => 'Overtime',
    _ => 'Remaining',
  };
}

Color _surfaceForStatus(BuildContext context, ChronoStatus status) {
  return switch (status) {
    ChronoStatus.approaching ||
    ChronoStatus.due ||
    ChronoStatus.overtime ||
    ChronoStatus.disconnected => ChronoStatusVisual.resolve(
      context,
      status,
    ).background,
    _ => context.chronoColors.surface,
  };
}

ChronoStatus _varianceStatus(Duration variance) {
  if (variance > const Duration(seconds: 30)) {
    return ChronoStatus.overtime;
  }
  if (variance < const Duration(seconds: -30)) {
    return ChronoStatus.live;
  }
  return ChronoStatus.complete;
}

String _varianceLabel(Duration variance) {
  if (variance > const Duration(seconds: 30)) {
    return 'Behind';
  }
  if (variance < const Duration(seconds: -30)) {
    return 'Ahead';
  }
  return 'On schedule';
}

String _varianceSemantic(Duration variance) {
  final String label = _varianceLabel(variance);
  if (label == 'On schedule') {
    return label;
  }
  return '$label by ${_durationSemantic(variance.abs())}';
}

String _varianceDisplay(Duration variance) {
  final String label = _varianceLabel(variance);
  if (label == 'On schedule') {
    return label;
  }
  return '$label ${formatClock(variance.abs())}';
}

IconData _varianceIcon(Duration variance) {
  if (variance > const Duration(seconds: 30)) {
    return Icons.trending_down_rounded;
  }
  if (variance < const Duration(seconds: -30)) {
    return Icons.trending_up_rounded;
  }
  return Icons.check_circle_outline_rounded;
}

String _remainingClock(Duration remaining) {
  if (remaining.isNegative) {
    return '+${formatClock(remaining.abs())}';
  }
  return formatClock(_ceilPositiveRemaining(remaining));
}

String _timerSemantic(LiveSessionViewData data) {
  if (data.timingPhase == LiveTimingPhase.due) {
    return data.remaining.isNegative
        ? 'Due by ${_durationSemantic(data.remaining.abs())}'
        : 'Due now';
  }
  if (data.timingPhase == LiveTimingPhase.overtime ||
      data.remaining.isNegative) {
    return 'Overtime by ${_durationSemantic(data.remaining.abs())}';
  }
  return '${_durationSemantic(_ceilPositiveRemaining(data.remaining))} '
      'remaining';
}

Duration _ceilPositiveRemaining(Duration duration) {
  if (duration <= Duration.zero) {
    return duration;
  }
  final int seconds =
      (duration.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
  return Duration(seconds: seconds);
}

String _durationSemantic(Duration duration) {
  final int seconds = duration.inSeconds.abs();
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  final int remainder = seconds % 60;
  return <String>[
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    if (remainder > 0 || seconds == 0)
      '$remainder ${remainder == 1 ? 'second' : 'seconds'}',
  ].join(', ');
}

String _peopleActionLabel(int participantCount) {
  return 'Show people, $participantCount connected';
}

String _liveUpdateLabel(LiveSessionViewData data) {
  final String state;
  if (data.isStale) {
    state = 'Connection stale';
  } else {
    state = switch (data.status) {
      LiveSessionStatus.waiting => 'Session waiting to start',
      LiveSessionStatus.running => 'Session running',
      LiveSessionStatus.paused => 'Session paused',
      LiveSessionStatus.ended =>
        data.endReason == SessionEndReason.completed
            ? 'Session complete'
            : 'Session ended',
    };
  }
  return 'Current interval ${data.currentStepTitle}. $state.';
}

String _roleLabel(SessionRole role) {
  return switch (role) {
    SessionRole.host => 'Host',
    SessionRole.controller => 'Timekeeper',
    SessionRole.participant => 'Participant',
    SessionRole.display => 'Display',
  };
}
