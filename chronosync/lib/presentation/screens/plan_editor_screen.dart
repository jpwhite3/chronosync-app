import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

typedef PlanStartCallback = Future<void> Function(Plan plan);

class PlanEditorScreen extends StatefulWidget {
  const PlanEditorScreen({
    required this.plan,
    required this.repository,
    required this.onStart,
    super.key,
  });

  final Plan plan;
  final PlanRepository repository;
  final PlanStartCallback onStart;

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  final Uuid _uuid = const Uuid();
  late final TextEditingController _titleController;
  late Plan _draft;
  bool _saving = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _discardPromptOpen = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.plan;
    _titleController = TextEditingController(text: _draft.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_dirty || _allowPop,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit plan'),
          actions: <Widget>[
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save'),
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
                final Widget details = _PlanDetails(
                  titleController: _titleController,
                  draft: _draft,
                  onTitleChanged: _updateTitle,
                  onSchedulePressed: _chooseSchedule,
                  onClearSchedule: _draft.plannedStartTime == null
                      ? null
                      : () => _update(
                          _draft.copyWith(
                            plannedStartTime: null,
                            updatedAt: DateTime.now(),
                          ),
                        ),
                  onCuePressed: _editDefaultCues,
                );
                final Widget steps = _StepsEditor(
                  plan: _draft,
                  onReorder: _reorderSteps,
                  onMove: _moveStep,
                  onEdit: _editStep,
                  onDuplicate: _duplicateStep,
                  onDelete: _deleteStep,
                  onAdd: _addStep,
                );

                if (windowClass == ChronoWindowClass.expanded) {
                  return Padding(
                    padding: padding,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: ChronoBreakpoints.maximumContentWidth,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 360,
                              child: SingleChildScrollView(child: details),
                            ),
                            const SizedBox(width: ChronoSpacing.md),
                            Expanded(child: steps),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return NestedScrollView(
                  headerSliverBuilder:
                      (BuildContext context, bool innerBoxIsScrolled) =>
                          <Widget>[
                            SliverPadding(
                              padding: padding.copyWith(bottom: 0),
                              sliver: SliverToBoxAdapter(child: details),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: ChronoSpacing.sm),
                            ),
                          ],
                  body: Padding(
                    padding: EdgeInsets.only(
                      left: padding.left,
                      right: padding.right,
                      bottom: padding.bottom,
                    ),
                    child: steps,
                  ),
                );
              },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.chronoColors.surface,
              border: Border(
                top: BorderSide(color: context.chronoColors.outline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(ChronoSpacing.sm),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget summary = Text(
                    '${_draft.steps.length} steps · '
                    '${formatFriendlyDuration(_draft.totalDuration)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                  final bool stackActions =
                      constraints.maxWidth < ChronoBreakpoints.medium ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3;
                  final Widget startButton = ChronoPrimaryButton(
                    label: 'Start live session',
                    icon: Icons.play_arrow_rounded,
                    expand: stackActions,
                    onPressed: _draft.steps.isEmpty || _saving
                        ? null
                        : _saveAndStart,
                  );
                  if (stackActions) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        summary,
                        const SizedBox(height: ChronoSpacing.xs),
                        startButton,
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: summary),
                      const SizedBox(width: ChronoSpacing.sm),
                      startButton,
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

  void _update(Plan value) {
    setState(() {
      _draft = value;
      _dirty = true;
    });
  }

  void _updateTitle(String value) {
    if (value.trim().isEmpty) {
      if (!_dirty) {
        setState(() => _dirty = true);
      }
      return;
    }
    _update(_draft.copyWith(title: value, updatedAt: DateTime.now()));
  }

  Future<bool> _save() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Give this plan a name.');
      return false;
    }
    setState(() {
      _saving = true;
    });
    try {
      final Plan saved = _draft.copyWith(
        title: title,
        updatedAt: DateTime.now(),
      );
      await widget.repository.savePlan(saved);
      if (!mounted) {
        return true;
      }
      setState(() {
        _draft = saved;
        _dirty = false;
      });
      _showMessage('Plan saved');
      return true;
    } on Object {
      if (mounted) {
        _showMessage('Could not save the plan. Try again.');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _confirmDiscard() async {
    if (_discardPromptOpen || !_dirty) {
      return;
    }
    _discardPromptOpen = true;
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Changes to this plan have not been saved. You can keep editing '
          'or discard them.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    _discardPromptOpen = false;
    if (discard != true || !mounted) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _saveAndStart() async {
    if (await _save() && mounted) {
      await widget.onStart(_draft);
    }
  }

  Future<void> _chooseSchedule() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = now.subtract(const Duration(days: 1));
    final DateTime lastDate = now.add(const Duration(days: 3650));
    final DateTime requestedInitial = _draft.plannedStartTime?.toLocal() ?? now;
    final DateTime initial = requestedInitial.isBefore(firstDate)
        ? firstDate
        : requestedInitial.isAfter(lastDate)
        ? lastDate
        : requestedInitial;
    final DateTime? date = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initial,
      helpText: 'Plan start date',
    );
    if (date == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Plan start time',
    );
    if (time == null) {
      return;
    }
    final DateTime selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    _update(
      _draft.copyWith(plannedStartTime: selected, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editDefaultCues() async {
    final CueProfile? cue = await showDialog<CueProfile>(
      context: context,
      builder: (BuildContext context) =>
          _CueProfileDialog(initial: _draft.defaultCueProfile),
    );
    if (cue != null) {
      _update(
        _draft.copyWith(defaultCueProfile: cue, updatedAt: DateTime.now()),
      );
    }
  }

  Future<void> _addStep() async {
    if (_draft.steps.length >= maxPlanSteps) {
      _showMessage('A plan can contain up to $maxPlanSteps steps.');
      return;
    }
    final _StepDraft? result = await showDialog<_StepDraft>(
      context: context,
      builder: (BuildContext context) => const _StepDialog(),
    );
    if (result == null) {
      return;
    }
    final List<Step> steps = <Step>[
      ..._draft.steps,
      Step(
        id: _uuid.v4(),
        planId: _draft.id,
        position: _draft.steps.length,
        title: result.title,
        durationSeconds: result.durationSeconds,
        autoAdvance: result.autoAdvance,
        cueOverride: result.cueOverride,
      ),
    ];
    _update(_draft.copyWith(steps: steps, updatedAt: DateTime.now()));
  }

  Future<void> _editStep(Step step) async {
    final _StepDraft? result = await showDialog<_StepDraft>(
      context: context,
      builder: (BuildContext context) => _StepDialog(
        initial: _StepDraft(
          title: step.title,
          durationSeconds: step.durationSeconds,
          autoAdvance: step.autoAdvance,
          cueOverride: step.cueOverride,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    final List<Step> steps = _draft.steps
        .map<Step>((Step candidate) {
          return candidate.id == step.id
              ? candidate.copyWith(
                  title: result.title,
                  durationSeconds: result.durationSeconds,
                  autoAdvance: result.autoAdvance,
                  cueOverride: result.cueOverride,
                )
              : candidate;
        })
        .toList(growable: false);
    _update(_draft.copyWith(steps: steps, updatedAt: DateTime.now()));
  }

  void _duplicateStep(Step step) {
    if (_draft.steps.length >= maxPlanSteps) {
      _showMessage('A plan can contain up to $maxPlanSteps steps.');
      return;
    }
    final List<Step> steps = List<Step>.of(_draft.steps);
    final int insertionIndex = step.position + 1;
    steps.insert(
      insertionIndex,
      step.copyWith(id: _uuid.v4(), position: insertionIndex),
    );
    _update(
      _draft.copyWith(
        steps: _normalizePositions(steps),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _deleteStep(Step step) {
    final List<Step> steps = _draft.steps
        .where((Step candidate) => candidate.id != step.id)
        .toList(growable: false);
    _update(
      _draft.copyWith(
        steps: _normalizePositions(steps),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _reorderSteps(int oldIndex, int newIndex) {
    final List<Step> steps = List<Step>.of(_draft.steps);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final Step moved = steps.removeAt(oldIndex);
    steps.insert(newIndex, moved);
    _update(
      _draft.copyWith(
        steps: _normalizePositions(steps),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _moveStep(int index, int offset) {
    final int targetIndex = index + offset;
    if (targetIndex < 0 || targetIndex >= _draft.steps.length) {
      return;
    }
    final List<Step> steps = List<Step>.of(_draft.steps);
    final Step moved = steps.removeAt(index);
    steps.insert(targetIndex, moved);
    _update(
      _draft.copyWith(
        steps: _normalizePositions(steps),
        updatedAt: DateTime.now(),
      ),
    );
  }

  List<Step> _normalizePositions(List<Step> steps) {
    return List<Step>.generate(
      steps.length,
      (int index) => steps[index].copyWith(position: index),
      growable: false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PlanDetails extends StatelessWidget {
  const _PlanDetails({
    required this.titleController,
    required this.draft,
    required this.onTitleChanged,
    required this.onSchedulePressed,
    required this.onClearSchedule,
    required this.onCuePressed,
  });

  final TextEditingController titleController;
  final Plan draft;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onSchedulePressed;
  final VoidCallback? onClearSchedule;
  final VoidCallback onCuePressed;

  @override
  Widget build(BuildContext context) {
    final String schedule = draft.plannedStartTime == null
        ? 'Start whenever you’re ready'
        : DateFormat.yMMMd().add_jm().format(draft.plannedStartTime!.toLocal());
    return ChronoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Plan details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: ChronoSpacing.sm),
          TextField(
            controller: titleController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Plan name',
              hintText: 'Opening night run of show',
              counterText: '',
            ),
            onChanged: onTitleChanged,
          ),
          const SizedBox(height: ChronoSpacing.sm),
          _DetailAction(
            icon: Icons.calendar_today_outlined,
            title: 'Scheduled start',
            subtitle: schedule,
            onTap: onSchedulePressed,
            trailing: onClearSchedule == null
                ? null
                : IconButton(
                    tooltip: 'Clear scheduled start',
                    onPressed: onClearSchedule,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          const SizedBox(height: ChronoSpacing.xs),
          _DetailAction(
            icon: Icons.notifications_active_outlined,
            title: 'Timing cues',
            subtitle:
                '${draft.defaultCueProfile.approachingSeconds}s before, '
                '${draft.defaultCueProfile.overdueSeconds}s overtime',
            onTap: onCuePressed,
          ),
        ],
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: ChronoSpacing.minimumTouchTarget,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _StepsEditor extends StatelessWidget {
  const _StepsEditor({
    required this.plan,
    required this.onReorder,
    required this.onMove,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onAdd,
  });

  final Plan plan;
  final ReorderCallback onReorder;
  final void Function(int index, int offset) onMove;
  final ValueChanged<Step> onEdit;
  final ValueChanged<Step> onDuplicate;
  final ValueChanged<Step> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bool atStepLimit = plan.steps.length >= maxPlanSteps;
    return ChronoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ChronoSpacing.sm,
              ChronoSpacing.sm,
              ChronoSpacing.xs,
              ChronoSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Steps',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        atStepLimit
                            ? '$maxPlanSteps-step limit reached'
                            : 'Drag to reorder. The live session uses this '
                                  'sequence.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: atStepLimit ? null : onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add step'),
                ),
              ],
            ),
          ),
          const Divider(),
          if (plan.steps.isEmpty)
            Expanded(child: _EmptySteps(onAdd: onAdd))
          else
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(
                  left: ChronoSpacing.xs,
                  right: ChronoSpacing.xs,
                  bottom: ChronoSpacing.sm,
                ),
                itemCount: plan.steps.length,
                onReorder: onReorder,
                itemBuilder: (BuildContext context, int index) {
                  final Step step = plan.steps[index];
                  return _StepTile(
                    key: ValueKey<String>(step.id),
                    step: step,
                    index: index,
                    onMoveUp: index == 0 ? null : () => onMove(index, -1),
                    onMoveDown: index == plan.steps.length - 1
                        ? null
                        : () => onMove(index, 1),
                    onEdit: () => onEdit(step),
                    onDuplicate: atStepLimit ? null : () => onDuplicate(step),
                    onDelete: () => onDelete(step),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.index,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    super.key,
  });

  final Step step;
  final int index;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ChronoSpacing.xs),
      child: Material(
        color: context.chronoColors.surfaceMuted,
        borderRadius: ChronoRadii.controlBorder,
        child: ListTile(
          minTileHeight: 68,
          leading: ReorderableDragStartListener(
            index: index,
            child: const Tooltip(
              message: 'Drag to reorder',
              child: SizedBox(
                width: ChronoSpacing.minimumTouchTarget,
                height: ChronoSpacing.minimumTouchTarget,
                child: Icon(Icons.drag_indicator_rounded),
              ),
            ),
          ),
          title: Text(step.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Wrap(
            spacing: ChronoSpacing.xs,
            runSpacing: ChronoSpacing.xxs,
            children: <Widget>[
              Text(formatFriendlyDuration(step.duration)),
              if (step.autoAdvance) const Text('• Auto-advance'),
              if (step.cueOverride != null) const Text('• Custom cues'),
            ],
          ),
          onTap: onEdit,
          trailing: PopupMenuButton<String>(
            tooltip: 'Step actions',
            onSelected: (String value) {
              switch (value) {
                case 'moveUp':
                  onMoveUp?.call();
                case 'moveDown':
                  onMoveDown?.call();
                case 'edit':
                  onEdit();
                case 'duplicate':
                  onDuplicate?.call();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'moveUp',
                enabled: onMoveUp != null,
                child: const Text('Move up'),
              ),
              PopupMenuItem<String>(
                value: 'moveDown',
                enabled: onMoveDown != null,
                child: const Text('Move down'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
              PopupMenuItem<String>(
                value: 'duplicate',
                enabled: onDuplicate != null,
                child: const Text('Duplicate'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySteps extends StatelessWidget {
  const _EmptySteps({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minimumHeight =
            (constraints.maxHeight - (ChronoSpacing.lg * 2))
                .clamp(0, double.infinity)
                .toDouble();
        return ListView(
          padding: const EdgeInsets.all(ChronoSpacing.lg),
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minimumHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.format_list_numbered_rounded,
                      size: 48,
                      color: context.chronoColors.primary,
                    ),
                    const SizedBox(height: ChronoSpacing.sm),
                    Text(
                      'Add the first step',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: ChronoSpacing.xs),
                    Text(
                      'Each step gets a title, duration, and optional '
                      'auto-advance.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: ChronoSpacing.md),
                    ChronoPrimaryButton(
                      label: 'Add step',
                      icon: Icons.add_rounded,
                      onPressed: onAdd,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StepDraft {
  const _StepDraft({
    required this.title,
    required this.durationSeconds,
    required this.autoAdvance,
    required this.cueOverride,
  });

  final String title;
  final int durationSeconds;
  final bool autoAdvance;
  final CueProfile? cueOverride;
}

class _StepDialog extends StatefulWidget {
  const _StepDialog({this.initial});

  final _StepDraft? initial;

  @override
  State<_StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<_StepDialog> {
  late final TextEditingController _title;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  late bool _autoAdvance;
  late bool _customCues;
  CueProfile _cueOverride = CueProfile();

  @override
  void initState() {
    super.initState();
    final _StepDraft? initial = widget.initial;
    final int duration = initial?.durationSeconds ?? 300;
    _title = TextEditingController(text: initial?.title ?? '');
    _minutes = TextEditingController(text: (duration ~/ 60).toString());
    _seconds = TextEditingController(text: (duration % 60).toString());
    _autoAdvance = initial?.autoAdvance ?? false;
    _customCues = initial?.cueOverride != null;
    _cueOverride = initial?.cueOverride ?? CueProfile();
  }

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add step' : 'Edit step'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 240,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Step title',
                  hintText: 'Doors open',
                ),
              ),
              const SizedBox(height: ChronoSpacing.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                    ),
                  ),
                  const SizedBox(width: ChronoSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _seconds,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Seconds'),
                    ),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-advance'),
                subtitle: const Text('Move on when the timer reaches zero'),
                value: _autoAdvance,
                onChanged: (bool value) {
                  setState(() {
                    _autoAdvance = value;
                  });
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Custom timing cues'),
                subtitle: const Text('Override the plan defaults'),
                value: _customCues,
                onChanged: (bool value) {
                  setState(() {
                    _customCues = value;
                  });
                },
              ),
              if (_customCues)
                OutlinedButton.icon(
                  onPressed: _editCues,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(
                    '${_cueOverride.approachingSeconds}s before, '
                    '${_cueOverride.overdueSeconds}s late',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Add step' : 'Save step'),
        ),
      ],
    );
  }

  Future<void> _editCues() async {
    final CueProfile? result = await showDialog<CueProfile>(
      context: context,
      builder: (BuildContext context) =>
          _CueProfileDialog(initial: _cueOverride),
    );
    if (result != null) {
      setState(() {
        _cueOverride = result;
      });
    }
  }

  void _submit() {
    final String title = _title.text.trim();
    final int minutes = int.tryParse(_minutes.text) ?? 0;
    final int seconds = int.tryParse(_seconds.text) ?? 0;
    final int totalSeconds = (minutes * 60) + seconds;
    if (title.isEmpty || totalSeconds < 1 || totalSeconds > 359999) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a title and a duration between 1s and 99h.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _StepDraft(
        title: title,
        durationSeconds: totalSeconds,
        autoAdvance: _autoAdvance,
        cueOverride: _customCues ? _cueOverride : null,
      ),
    );
  }
}

class _CueProfileDialog extends StatefulWidget {
  const _CueProfileDialog({required this.initial});

  final CueProfile initial;

  @override
  State<_CueProfileDialog> createState() => _CueProfileDialogState();
}

class _CueProfileDialogState extends State<_CueProfileDialog> {
  late final TextEditingController _approaching;
  late final TextEditingController _overdue;
  late bool _visual;
  late bool _sound;
  late bool _haptic;

  @override
  void initState() {
    super.initState();
    _approaching = TextEditingController(
      text: widget.initial.approachingSeconds.toString(),
    );
    _overdue = TextEditingController(
      text: widget.initial.overdueSeconds.toString(),
    );
    _visual = widget.initial.visualEnabled;
    _sound = widget.initial.soundEnabled;
    _haptic = widget.initial.hapticEnabled;
  }

  @override
  void dispose() {
    _approaching.dispose();
    _overdue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Timing cues'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _approaching,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Approaching cue (seconds before)',
                ),
              ),
              const SizedBox(height: ChronoSpacing.xs),
              TextField(
                controller: _overdue,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Overtime cue (seconds late)',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _visual,
                onChanged: (bool value) => setState(() => _visual = value),
                title: const Text('Visual cue'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _sound,
                onChanged: (bool value) => setState(() => _sound = value),
                title: const Text('Sound'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _haptic,
                onChanged: (bool value) => setState(() => _haptic = value),
                title: const Text('Haptic'),
                subtitle: const Text(
                  'Plays on supported mobile devices; saved with this plan.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save cues')),
      ],
    );
  }

  void _submit() {
    final int approaching = int.tryParse(_approaching.text) ?? 0;
    final int overdue = int.tryParse(_overdue.text) ?? 0;
    if (approaching < 1 ||
        approaching > 86400 ||
        overdue < 1 ||
        overdue > 86400) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cue thresholds must be 1–86,400s.')),
      );
      return;
    }
    Navigator.pop(
      context,
      CueProfile(
        approachingSeconds: approaching,
        overdueSeconds: overdue,
        visualEnabled: _visual,
        soundEnabled: _sound,
        hapticEnabled: _haptic,
      ),
    );
  }
}
