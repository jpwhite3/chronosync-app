import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/presentation/screens/plan_editor_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add, save, and start follows the edited plan journey', (
    WidgetTester tester,
  ) async {
    final _MemoryPlanRepository repository = _MemoryPlanRepository();
    Plan? launchedPlan;

    await _pumpEditor(
      tester,
      plan: _plan(steps: const <Step>[]),
      repository: repository,
      onStart: (Plan plan) async {
        launchedPlan = plan;
      },
    );

    await tester.ensureVisible(find.text('Add interval').first);
    await tester.tap(find.text('Add interval').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Interval title'),
      'Sound check',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add interval').last);
    await tester.pumpAndSettle();

    expect(find.text('Sound check'), findsOneWidget);
    await tester.tap(find.text('Start live session'));
    await tester.pumpAndSettle();

    expect(repository.savedPlans, hasLength(1));
    expect(repository.savedPlans.single.steps.single.title, 'Sound check');
    expect(launchedPlan, repository.savedPlans.single);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back asks before discarding unsaved plan edits', (
    WidgetTester tester,
  ) async {
    final _MemoryPlanRepository repository = _MemoryPlanRepository();

    await _pumpEditorFromLauncher(
      tester,
      plan: _plan(),
      repository: repository,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Sequence name'),
      'Changed run of show',
    );
    await tester.pump();
    final PopScope<Object?> popScope = tester.widget<PopScope<Object?>>(
      find.byType(PopScope<Object?>),
    );
    expect(popScope.canPop, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('Changed run of show'), findsOneWidget);
    expect(find.text('Launcher'), findsNothing);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit sequence'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Launcher'), findsOneWidget);
  });

  testWidgets('save failures do not expose raw exception details', (
    WidgetTester tester,
  ) async {
    final _MemoryPlanRepository repository = _MemoryPlanRepository(
      saveError: StateError('sqlite path=/private/secret.db token=abc123'),
    );

    await _pumpEditor(tester, plan: _plan(), repository: repository);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save the sequence. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret.db'), findsNothing);
    expect(find.textContaining('abc123'), findsNothing);
  });

  testWidgets('step menu supports keyboard-accessible reordering', (
    WidgetTester tester,
  ) async {
    final _MemoryPlanRepository repository = _MemoryPlanRepository();
    await _pumpEditor(
      tester,
      plan: _plan(
        steps: <Step>[
          _step(id: 'step-1', position: 0, title: 'Doors open'),
          _step(id: 'step-2', position: 1, title: 'Welcome'),
          _step(id: 'step-3', position: 2, title: 'Questions'),
        ],
      ),
      repository: repository,
    );

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Interval actions').first);
    await tester.tap(find.byTooltip('Interval actions').first);
    await tester.pumpAndSettle();

    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      repository.savedPlans.single.steps.map((Step step) => step.title),
      <String>['Welcome', 'Doors open', 'Questions'],
    );
  });

  testWidgets('editor remains usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await _setViewport(tester, size: const Size(320, 568), textScale: 2);
    await _pumpEditor(
      tester,
      plan: _plan(),
      repository: _MemoryPlanRepository(),
      textScale: 2,
    );

    expect(find.text('Sequence details', skipOffstage: false), findsOneWidget);
    expect(find.text('Intervals', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact editor paints its app bar and content on screen', (
    WidgetTester tester,
  ) async {
    await _setViewport(tester, size: const Size(390, 844), textScale: 1);
    await _pumpEditor(
      tester,
      plan: _plan(steps: const <Step>[]),
      repository: _MemoryPlanRepository(),
    );

    expect(find.text('Edit sequence').hitTestable(), findsOneWidget);
    expect(find.text('Sequence details').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Add the first interval'));
    await tester.pumpAndSettle();
    expect(find.text('Add the first interval').hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Edit sequence')).dy,
      greaterThanOrEqualTo(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule picker clamps an out-of-range imported date', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(
      tester,
      plan: _plan(plannedStartTime: DateTime.utc(1900)),
      repository: _MemoryPlanRepository(),
    );

    await tester.tap(find.text('Scheduled start'));
    await tester.pumpAndSettle();

    expect(find.text('Sequence start date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('250-step plan renders lazily and disables further additions', (
    WidgetTester tester,
  ) async {
    final List<Step> steps = List<Step>.generate(
      maxPlanSteps,
      (int index) => _step(
        id: 'step-${index + 1}',
        position: index,
        title: 'Step ${index + 1}',
      ),
    );
    await _pumpEditor(
      tester,
      plan: _plan(steps: steps),
      repository: _MemoryPlanRepository(),
    );

    expect(find.text('250-interval limit reached'), findsOneWidget);
    expect(find.text('Add interval', skipOffstage: false), findsOneWidget);
    final TextButton addButton = tester.widget<TextButton>(
      find.byWidgetPredicate(
        (Widget widget) => widget is TextButton && widget.onPressed == null,
        description: 'disabled Add interval button',
      ),
    );
    expect(addButton.onPressed, isNull);

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Step 250'),
      800,
      scrollable: find
          .descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.text('Step 250'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required Plan plan,
  required PlanRepository repository,
  PlanStartCallback? onStart,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: PlanEditorScreen(
        plan: plan,
        repository: repository,
        onStart: onStart ?? (Plan _) async {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpEditorFromLauncher(
  WidgetTester tester, {
  required Plan plan,
  required PlanRepository repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => PlanEditorScreen(
                      plan: plan,
                      repository: repository,
                      onStart: (Plan _) async {},
                    ),
                  ),
                );
              },
              child: const Text('Launcher'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launcher'));
  await tester.pumpAndSettle();
}

Future<void> _setViewport(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Plan _plan({List<Step>? steps, DateTime? plannedStartTime}) {
  final DateTime timestamp = DateTime.utc(2026, 1, 1);
  return Plan(
    id: 'plan-1',
    title: 'Opening night',
    plannedStartTime: plannedStartTime,
    defaultCueProfile: CueProfile(),
    steps:
        steps ??
        <Step>[
          Step(
            id: 'step-1',
            planId: 'plan-1',
            position: 0,
            title: 'Doors open',
            durationSeconds: 300,
          ),
        ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Step _step({required String id, required int position, required String title}) {
  return Step(
    id: id,
    planId: 'plan-1',
    position: position,
    title: title,
    durationSeconds: 300,
  );
}

final class _MemoryPlanRepository implements PlanRepository {
  _MemoryPlanRepository({this.saveError});

  final Object? saveError;
  final List<Plan> savedPlans = <Plan>[];

  @override
  Future<Plan> createPlan({required String title}) async => _plan();

  @override
  Future<void> deletePlan(String id) async {}

  @override
  Future<Plan> duplicatePlan(String id) async => _plan();

  @override
  Future<List<Plan>> getAllPlans() async => List<Plan>.of(savedPlans);

  @override
  Future<Plan?> getPlan(String id) async => null;

  @override
  Future<void> savePlan(Plan plan) async {
    if (saveError case final Object error) {
      throw error;
    }
    savedPlans.add(plan);
  }

  @override
  Future<void> savePlans(Iterable<Plan> plans) async {
    for (final Plan plan in plans) {
      await savePlan(plan);
    }
  }

  @override
  Stream<List<Plan>> watchPlans() => Stream<List<Plan>>.value(savedPlans);
}
