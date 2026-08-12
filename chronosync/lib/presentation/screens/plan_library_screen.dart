import 'dart:typed_data';

import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/plan_editor_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:intl/intl.dart';

class PlanLibraryScreen extends StatelessWidget {
  const PlanLibraryScreen({
    required this.repository,
    required this.archiveService,
    required this.fileService,
    required this.onStartPlan,
    required this.onJoinSession,
    super.key,
  });

  final PlanRepository repository;
  final PlanArchiveService archiveService;
  final PortabilityFileService fileService;
  final PlanStartCallback onStartPlan;
  final VoidCallback onJoinSession;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Plan>>(
      stream: repository.watchPlans(),
      builder: (BuildContext context, AsyncSnapshot<List<Plan>> snapshot) {
        if (snapshot.hasError) {
          return const _LibraryError();
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Plan> plans = snapshot.data!;
        final ChronoWindowClass windowClass = ChronoBreakpoints.forWidth(
          MediaQuery.sizeOf(context).width,
        );
        return Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _LibraryHeader(
                  planCount: plans.length,
                  onCreate: () => _createPlan(context),
                  onJoin: onJoinSession,
                  onImport: () => _importPlans(context),
                  onExportAll: plans.isEmpty
                      ? null
                      : () => _exportPlans(context, plans),
                ),
              ),
              if (plans.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: _EmptyLibrary(
                    onCreate: () => _createPlan(context),
                    onCreateExample: () => _createExample(context),
                    onJoin: onJoinSession,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    ChronoBreakpoints.pagePaddingFor(
                      MediaQuery.sizeOf(context).width,
                    ).left,
                    0,
                    ChronoBreakpoints.pagePaddingFor(
                      MediaQuery.sizeOf(context).width,
                    ).right,
                    ChronoSpacing.xl,
                  ),
                  sliver: SliverLayoutBuilder(
                    builder:
                        (BuildContext context, SliverConstraints constraints) {
                          final int columns =
                              switch (ChronoBreakpoints.forWidth(
                                constraints.crossAxisExtent,
                              )) {
                                ChronoWindowClass.compact => 1,
                                ChronoWindowClass.medium => 2,
                                ChronoWindowClass.expanded =>
                                  (constraints.crossAxisExtent / 340)
                                      .floor()
                                      .clamp(2, 4)
                                      .toInt(),
                              };
                          return SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: ChronoSpacing.sm,
                                  crossAxisSpacing: ChronoSpacing.sm,
                                  mainAxisExtent:
                                      226 +
                                      ((MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(1) -
                                                  1)
                                              .clamp(0, 2) *
                                          260),
                                ),
                            itemCount: plans.length,
                            itemBuilder: (BuildContext context, int index) {
                              final Plan plan = plans[index];
                              return _PlanCard(
                                plan: plan,
                                onOpen: () => _openEditor(context, plan),
                                onStart: plan.steps.isEmpty
                                    ? null
                                    : () => onStartPlan(plan),
                                onDuplicate: () => _duplicate(context, plan),
                                onExport: () =>
                                    _exportPlans(context, <Plan>[plan]),
                                onDelete: () => _delete(context, plan),
                              );
                            },
                          );
                        },
                  ),
                ),
            ],
          ),
          floatingActionButton:
              plans.isEmpty || windowClass == ChronoWindowClass.expanded
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _createPlan(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New plan'),
                ),
        );
      },
    );
  }

  Future<void> _createPlan(BuildContext context) async {
    final String? title = await _askForPlanTitle(context);
    if (title == null || !context.mounted) {
      return;
    }
    try {
      final Plan plan = await repository.createPlan(title: title);
      if (context.mounted) {
        await _openEditor(context, plan);
      }
    } on Object {
      if (context.mounted) {
        _showMessage(context, 'Could not create the plan. Try again.');
      }
    }
  }

  Future<void> _createExample(BuildContext context) async {
    Plan? base;
    bool savedExample = false;
    try {
      base = await repository.createPlan(title: 'Event run of show');
      final DateTime now = DateTime.now().toUtc();
      final Plan example = base.copyWith(
        steps: <Step>[
          Step(
            id: '${base.id}-welcome',
            planId: base.id,
            position: 0,
            title: 'Welcome and doors open',
            durationSeconds: 300,
          ),
          Step(
            id: '${base.id}-keynote',
            planId: base.id,
            position: 1,
            title: 'Opening keynote',
            durationSeconds: 1800,
          ),
          Step(
            id: '${base.id}-questions',
            planId: base.id,
            position: 2,
            title: 'Audience questions',
            durationSeconds: 600,
          ),
          Step(
            id: '${base.id}-close',
            planId: base.id,
            position: 3,
            title: 'Closing notes',
            durationSeconds: 300,
          ),
        ],
        updatedAt: now,
      );
      await repository.savePlan(example);
      savedExample = true;
      if (context.mounted) {
        await _openEditor(context, example);
      }
    } on Object {
      if (base != null && !savedExample) {
        try {
          await repository.deletePlan(base.id);
        } on Object {
          // The original creation failure is more useful to the user. A
          // future library load can still expose a draft that could not be
          // removed so it is not silently lost.
        }
      }
      if (context.mounted) {
        _showMessage(context, 'Could not create the example plan. Try again.');
      }
    }
  }

  Future<String?> _askForPlanTitle(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _PlanTitleDialog(),
    );
  }

  Future<void> _openEditor(BuildContext context, Plan plan) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PlanEditorScreen(
          plan: plan,
          repository: repository,
          onStart: onStartPlan,
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, Plan plan) async {
    try {
      final Plan duplicate = await repository.duplicatePlan(plan.id);
      if (context.mounted) {
        _showMessage(context, 'Created “${duplicate.title}”');
      }
    } on Object {
      if (context.mounted) {
        _showMessage(context, 'Could not duplicate the plan. Try again.');
      }
    }
  }

  Future<void> _delete(BuildContext context, Plan plan) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete plan?'),
        content: Text(
          '“${plan.title}” will be removed from this device. '
          'Past session history stays available.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await repository.deletePlan(plan.id);
        if (context.mounted) {
          _showMessage(context, 'Plan deleted');
        }
      } on Object {
        if (context.mounted) {
          _showMessage(context, 'Could not delete the plan. Try again.');
        }
      }
    }
  }

  Future<void> _exportPlans(BuildContext context, List<Plan> plans) async {
    try {
      final Uint8List bytes = archiveService.exportPlans(plans);
      final String stem = plans.length == 1
          ? safeFileStem(plans.single.title)
          : 'chronosync-plans';
      await fileService.shareArchive(
        bytes: bytes,
        fileName: '$stem.chronosync',
      );
    } on Object {
      if (context.mounted) {
        _showMessage(context, 'Could not export plans. Try again.');
      }
    }
  }

  Future<void> _importPlans(BuildContext context) async {
    try {
      final Uint8List? bytes = await fileService.pickChronoSyncArchive();
      if (bytes == null || !context.mounted) {
        return;
      }
      final PlanImportPreview preview = archiveService.inspect(bytes);
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Import plans?'),
          content: Text(
            '${preview.plans.length} plans and ${preview.stepCount} steps '
            'were exported by ChronoSync ${preview.sourceAppVersion}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      final List<Plan> existing = await repository.getAllPlans();
      final List<Plan> imports = archiveService.resolveIdCollisions(
        importedPlans: preview.plans,
        existingPlanIds: existing.map<String>((Plan plan) => plan.id).toSet(),
        existingStepIds: existing
            .expand<Step>((Plan plan) => plan.steps)
            .map<String>((Step step) => step.id)
            .toSet(),
      );
      await repository.savePlans(imports);
      if (context.mounted) {
        _showMessage(context, 'Imported ${imports.length} plans');
      }
    } on Object {
      if (context.mounted) {
        _showMessage(
          context,
          'Could not import that ChronoSync file. Check the file and try '
          'again.',
        );
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PlanTitleDialog extends StatefulWidget {
  const _PlanTitleDialog();

  @override
  State<_PlanTitleDialog> createState() => _PlanTitleDialogState();
}

class _PlanTitleDialogState extends State<_PlanTitleDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New plan'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 160,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Plan name',
          hintText: 'Saturday conference',
        ),
        onSubmitted: (String value) => _submit(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _submit(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _submit(String value) {
    final String title = value.trim();
    if (title.isNotEmpty) {
      Navigator.pop(context, title);
    }
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.planCount,
    required this.onCreate,
    required this.onJoin,
    required this.onImport,
    required this.onExportAll,
  });

  final int planCount;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onImport;
  final VoidCallback? onExportAll;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final ChronoWindowClass windowClass = ChronoBreakpoints.forWidth(width);
    final Widget title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Your plans', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ChronoSpacing.xxs),
        Text(
          planCount == 1
              ? '1 plan ready on this device'
              : '$planCount plans ready on this device',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
    final Widget actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: ChronoSpacing.xs,
      runSpacing: ChronoSpacing.xs,
      children: <Widget>[
        PopupMenuButton<String>(
          tooltip: 'Plan library actions',
          onSelected: (String value) {
            if (value == 'import') {
              onImport();
            } else if (value == 'export') {
              onExportAll?.call();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'import',
              child: ListTile(
                leading: Icon(Icons.file_open_outlined),
                title: Text('Import .chronosync'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'export',
              enabled: onExportAll != null,
              child: const ListTile(
                leading: Icon(Icons.ios_share_rounded),
                title: Text('Export all plans'),
              ),
            ),
          ],
          icon: const Icon(Icons.more_horiz_rounded),
        ),
        OutlinedButton.icon(
          onPressed: onJoin,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Join session'),
        ),
        if (windowClass == ChronoWindowClass.expanded && planCount > 0)
          ChronoPrimaryButton(
            label: 'New plan',
            icon: Icons.add_rounded,
            onPressed: onCreate,
          ),
      ],
    );
    return Padding(
      padding: ChronoBreakpoints.pagePaddingFor(width),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ChronoBreakpoints.maximumContentWidth,
          ),
          child: windowClass == ChronoWindowClass.compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    title,
                    const SizedBox(height: ChronoSpacing.sm),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: title),
                    const SizedBox(width: ChronoSpacing.md),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: actions,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onOpen,
    required this.onStart,
    required this.onDuplicate,
    required this.onExport,
    required this.onDelete,
  });

  final Plan plan;
  final VoidCallback onOpen;
  final VoidCallback? onStart;
  final VoidCallback onDuplicate;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String schedule = plan.plannedStartTime == null
        ? 'Starts when you’re ready'
        : DateFormat.MMMd().add_jm().format(plan.plannedStartTime!.toLocal());
    return ChronoCard(
      semanticLabel:
          '${plan.title}, ${plan.steps.length} '
          '${plan.steps.length == 1 ? 'step' : 'steps'}',
      padding: const EdgeInsets.all(ChronoSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  plan.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Plan actions',
                onSelected: (String value) {
                  switch (value) {
                    case 'duplicate':
                      onDuplicate();
                    case 'export':
                      onExport();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'duplicate',
                        child: Text('Duplicate'),
                      ),
                      PopupMenuItem<String>(
                        value: 'export',
                        child: Text('Export'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
              ),
            ],
          ),
          const SizedBox(height: ChronoSpacing.xs),
          Text(
            '${plan.steps.length} steps · '
            '${formatFriendlyDuration(plan.totalDuration)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: ChronoSpacing.xs),
          Row(
            children: <Widget>[
              const Icon(Icons.schedule_rounded, size: 18),
              const SizedBox(width: ChronoSpacing.xxs),
              Expanded(
                child: Text(
                  schedule,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: ChronoSpacing.xs),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(onStart == null ? 'Add steps' : 'Start'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.onCreate,
    required this.onCreateExample,
    required this.onJoin,
  });

  final VoidCallback onCreate;
  final VoidCallback onCreateExample;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(ChronoSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.chronoColors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(ChronoSpacing.md),
                          child: Icon(
                            Icons.view_timeline_outlined,
                            size: 48,
                            color: context.chronoColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: ChronoSpacing.md),
                      Text(
                        'Keep the whole team on the same step',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: ChronoSpacing.xs),
                      Text(
                        'Build a timed plan, run it live, and share the current '
                        'moment with anyone nearby or online.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: ChronoSpacing.md),
                      ChronoPrimaryButton(
                        label: 'Create a plan',
                        icon: Icons.add_rounded,
                        onPressed: onCreate,
                      ),
                      const SizedBox(height: ChronoSpacing.xs),
                      TextButton(
                        onPressed: onCreateExample,
                        child: const Text('Start with an event example'),
                      ),
                      TextButton.icon(
                        onPressed: onJoin,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Join someone else’s session'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(ChronoSpacing.md),
        child: Text(
          'ChronoSync could not open your plans.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
