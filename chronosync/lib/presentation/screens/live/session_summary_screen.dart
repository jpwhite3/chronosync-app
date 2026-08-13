import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/live/live_view_models.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Scheduled-versus-actual review shown after a live session ends.
class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({
    required this.data,
    this.onDone,
    this.onExportCsv,
    this.isExporting = false,
    super.key,
  });

  final SessionSummaryViewData data;
  final VoidCallback? onDone;
  final VoidCallback? onExportCsv;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    final bool useCompactExportAction =
        ChronoBreakpoints.forWidth(MediaQuery.sizeOf(context).width) ==
            ChronoWindowClass.compact ||
        MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return Scaffold(
      appBar: AppBar(
        leading: onDone == null
            ? null
            : IconButton(
                onPressed: onDone,
                tooltip: 'Back to sequences',
                icon: const Icon(Icons.close_rounded),
              ),
        title: const Text('Session summary'),
        actions: <Widget>[
          if (onExportCsv != null)
            Tooltip(
              message: data.hasCompleteActivityHistory
                  ? 'Export complete session activity as CSV'
                  : 'CSV export is unavailable because this device has only '
                        'part of the activity history.',
              child: useCompactExportAction
                  ? IconButton(
                      onPressed: data.hasCompleteActivityHistory && !isExporting
                          ? onExportCsv
                          : null,
                      icon: isExporting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                    )
                  : TextButton.icon(
                      onPressed: data.hasCompleteActivityHistory && !isExporting
                          ? onExportCsv
                          : null,
                      icon: isExporting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: const Text('Export CSV'),
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
              final Widget overview = _SummaryOverview(data: data);
              final Widget steps = _StepSummaryList(steps: data.steps);

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
                        _SummaryHeader(data: data),
                        if (!data.hasCompleteActivityHistory) ...<Widget>[
                          const SizedBox(height: ChronoSpacing.sm),
                          const _IncompleteActivityHistoryBanner(),
                        ],
                        const SizedBox(height: ChronoSpacing.md),
                        if (windowClass == ChronoWindowClass.expanded)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(width: 360, child: overview),
                              const SizedBox(width: ChronoSpacing.md),
                              Expanded(child: steps),
                            ],
                          )
                        else ...<Widget>[
                          overview,
                          const SizedBox(height: ChronoSpacing.md),
                          steps,
                        ],
                        if (onExportCsv != null) ...<Widget>[
                          const SizedBox(height: ChronoSpacing.md),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ChronoPrimaryButton(
                              label: 'Export activity as CSV',
                              semanticLabel:
                                  'Export complete session activity as CSV',
                              icon: Icons.table_view_outlined,
                              isLoading: isExporting,
                              onPressed: data.hasCompleteActivityHistory
                                  ? onExportCsv
                                  : null,
                            ),
                          ),
                        ],
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

class _IncompleteActivityHistoryBanner extends StatelessWidget {
  const _IncompleteActivityHistoryBanner();

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      ChronoStatus.approaching,
    );
    const String message =
        'This device only received recent activity. Earlier timing, '
        'acknowledgements, and actions may be missing. Export CSV from the '
        'host device for a complete record.';
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

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.data});

  final SessionSummaryViewData data;

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFormat = DateFormat.yMMMd().add_jm();
    final bool completed = data.endReason == SessionEndReason.completed;
    final String stateLabel = completed ? 'Session complete' : 'Session ended';
    final String timingLabel;
    if (data.startedAt == null) {
      timingLabel = data.endedAt == null
          ? 'Ended before start'
          : 'Ended before start · ${dateFormat.format(data.endedAt!.toLocal())}';
    } else {
      timingLabel =
          'Started ${dateFormat.format(data.startedAt!.toLocal())}'
          '${data.endedAt == null ? '' : ' · '
                    'Ended ${DateFormat.jm().format(data.endedAt!.toLocal())}'}';
    }
    return Semantics(
      container: true,
      label:
          '${data.planTitle} ${completed ? 'complete' : 'ended'}. '
          '${_varianceSemantic(data.variance)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChronoStatusPill(
              status: completed ? ChronoStatus.complete : ChronoStatus.ended,
              label: stateLabel,
            ),
            const SizedBox(height: ChronoSpacing.sm),
            Text(
              data.planTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: ChronoSpacing.xs),
            Text(
              timingLabel,
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

class _SummaryOverview extends StatelessWidget {
  const _SummaryOverview({required this.data});

  final SessionSummaryViewData data;

  @override
  Widget build(BuildContext context) {
    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('At a glance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: ChronoSpacing.md),
          _SummaryMetric(
            label: 'Scheduled',
            value: formatFriendlyDuration(data.plannedDuration),
            icon: Icons.event_available_outlined,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          _SummaryMetric(
            label: 'Actual',
            value: formatFriendlyDuration(data.actualDuration),
            icon: Icons.timer_outlined,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          _SummaryMetric(
            label: _varianceLabel(data.variance),
            value: data.variance.abs() < const Duration(seconds: 1)
                ? 'On time'
                : formatClock(data.variance.abs()),
            icon: _varianceIcon(data.variance),
            status: _varianceStatus(data.variance),
          ),
          const Divider(height: ChronoSpacing.lg),
          _SummaryMetric(
            label: data.hasCompleteActivityHistory
                ? 'Activity entries'
                : 'Available activity entries',
            value: '${data.activityCount}',
            icon: Icons.history_rounded,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          _SummaryMetric(
            label: 'Intervals reviewed',
            value: '${data.steps.length}',
            icon: Icons.checklist_rounded,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.status = ChronoStatus.neutral,
  });

  final String label;
  final String value;
  final IconData icon;
  final ChronoStatus status;

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      status,
    );
    return Semantics(
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: visual.background,
                borderRadius: ChronoRadii.controlBorder,
              ),
              child: SizedBox.square(
                dimension: ChronoSpacing.minimumTouchTarget,
                child: Icon(icon, color: visual.foreground),
              ),
            ),
            const SizedBox(width: ChronoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: ChronoSpacing.xxs),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
    );
  }
}

class _StepSummaryList extends StatelessWidget {
  const _StepSummaryList({required this.steps});

  final List<StepSummaryViewData> steps;

  @override
  Widget build(BuildContext context) {
    return ChronoCard(
      padding: const EdgeInsets.all(ChronoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Scheduled vs. actual',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: ChronoSpacing.xxs),
          Text(
            'Positive drift means the interval ran longer than scheduled.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: ChronoSpacing.md),
          if (steps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ChronoSpacing.lg),
              child: Text(
                'No interval timing was recorded.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          else
            for (int index = 0; index < steps.length; index++) ...<Widget>[
              _StepSummaryRow(index: index, step: steps[index]),
              if (index < steps.length - 1)
                const Divider(height: ChronoSpacing.lg),
            ],
        ],
      ),
    );
  }
}

class _StepSummaryRow extends StatelessWidget {
  const _StepSummaryRow({required this.index, required this.step});

  final int index;
  final StepSummaryViewData step;

  @override
  Widget build(BuildContext context) {
    final ChronoStatus varianceStatus = step.wasCompleted
        ? _varianceStatus(step.variance)
        : ChronoStatus.neutral;
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      varianceStatus,
    );
    final String varianceText = !step.wasCompleted
        ? 'Not reached'
        : step.variance.abs() < const Duration(seconds: 1)
        ? 'On time'
        : '${step.variance.isNegative ? '−' : '+'}'
              '${formatClock(step.variance.abs())}';

    return Semantics(
      container: true,
      label:
          'Interval ${index + 1}, ${step.title}. '
          'Scheduled ${_durationSemantic(step.plannedDuration)}. '
          'Actual ${_durationSemantic(step.actualDuration)}. '
          '${step.wasCompleted ? _varianceSemantic(step.variance) : 'Not reached'}.'
          '${_acknowledgementSemantic(step)}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 18,
              backgroundColor: visual.background,
              foregroundColor: visual.foreground,
              child: step.wasCompleted
                  ? Text('${index + 1}')
                  : const Icon(Icons.remove_rounded, size: 18),
            ),
            const SizedBox(width: ChronoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          step.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (step.hasAcknowledgements)
                        Tooltip(
                          message:
                              '${step.acknowledgements.length} '
                              '${step.acknowledgements.length == 1 ? 'acknowledgement' : 'acknowledgements'}',
                          child: Icon(
                            Icons.done_all_rounded,
                            size: 20,
                            color: context.chronoColors.success,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: ChronoSpacing.sm),
                  Wrap(
                    spacing: ChronoSpacing.md,
                    runSpacing: ChronoSpacing.xs,
                    children: <Widget>[
                      _InlineMetric(
                        label: 'Scheduled',
                        value: formatClock(step.plannedDuration),
                      ),
                      _InlineMetric(
                        label: 'Actual',
                        value: formatClock(step.actualDuration),
                      ),
                      _InlineMetric(
                        label: 'Timing drift',
                        value: varianceText,
                        valueColor: visual.foreground,
                      ),
                    ],
                  ),
                  if (step.acknowledgements.isNotEmpty) ...<Widget>[
                    const SizedBox(height: ChronoSpacing.sm),
                    _StepAcknowledgements(
                      acknowledgements: step.acknowledgements,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepAcknowledgements extends StatelessWidget {
  const _StepAcknowledgements({required this.acknowledgements});

  final List<AcknowledgementViewData> acknowledgements;

  @override
  Widget build(BuildContext context) {
    final DateFormat timestampFormat = DateFormat.MMMd().add_jm();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.chronoColors.successContainer,
        borderRadius: ChronoRadii.controlBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ChronoSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Got it',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.chronoColors.success,
              ),
            ),
            const SizedBox(height: ChronoSpacing.xxs),
            for (
              int index = 0;
              index < acknowledgements.length;
              index += 1
            ) ...<Widget>[
              _AcknowledgementSummaryRow(
                acknowledgement: acknowledgements[index],
                timestampFormat: timestampFormat,
              ),
              if (index < acknowledgements.length - 1)
                const SizedBox(height: ChronoSpacing.xxs),
            ],
          ],
        ),
      ),
    );
  }
}

class _AcknowledgementSummaryRow extends StatelessWidget {
  const _AcknowledgementSummaryRow({
    required this.acknowledgement,
    required this.timestampFormat,
  });

  final AcknowledgementViewData acknowledgement;
  final DateFormat timestampFormat;

  @override
  Widget build(BuildContext context) {
    final Widget identity = Row(
      children: <Widget>[
        Icon(
          Icons.check_rounded,
          size: 16,
          color: context.chronoColors.success,
        ),
        const SizedBox(width: ChronoSpacing.xxs),
        Expanded(
          child: Text(
            acknowledgement.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
    final Widget timestamp = Text(
      timestampFormat.format(acknowledgement.acknowledgedAt.toLocal()),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.chronoColors.textSecondary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stack =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              identity,
              Padding(
                padding: const EdgeInsets.only(left: 16 + ChronoSpacing.xxs),
                child: timestamp,
              ),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: identity),
            const SizedBox(width: ChronoSpacing.xs),
            timestamp,
          ],
        );
      },
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: ChronoSpacing.xxs),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: valueColor,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _acknowledgementSemantic(StepSummaryViewData step) {
  if (step.acknowledgements.isEmpty) {
    return step.wasAcknowledged ? ' Acknowledged.' : '';
  }
  final DateFormat timestampFormat = DateFormat.MMMd().add_jm();
  final String details = step.acknowledgements
      .map<String>(
        (AcknowledgementViewData acknowledgement) =>
            '${acknowledgement.displayName} at '
            '${timestampFormat.format(acknowledgement.acknowledgedAt.toLocal())}',
      )
      .join(', ');
  return ' Got it acknowledgements: $details.';
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
    return 'Behind schedule';
  }
  if (variance < const Duration(seconds: -30)) {
    return 'Ahead of schedule';
  }
  return 'Timing drift';
}

String _varianceSemantic(Duration variance) {
  if (variance.abs() < const Duration(seconds: 1)) {
    return 'On schedule';
  }
  final String direction = variance.isNegative ? 'Ahead' : 'Behind';
  return '$direction by ${_durationSemantic(variance.abs())}';
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
