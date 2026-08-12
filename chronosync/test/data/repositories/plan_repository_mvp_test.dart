import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftPlanRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPlanRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('round-trips a plan and ordered steps through Drift', () async {
    final Plan plan = _plan();

    await repository.savePlan(plan);

    expect(await repository.getPlan(plan.id), plan);
    expect(await repository.watchPlans().first, <Plan>[plan]);
  });

  test('saving replaces stale steps transactionally', () async {
    final Plan original = _plan();
    await repository.savePlan(original);
    final Plan updated = original.copyWith(
      steps: <Step>[
        original.steps.last.copyWith(position: 0, title: 'Only step'),
      ],
      updatedAt: original.updatedAt.add(const Duration(minutes: 1)),
    );

    await repository.savePlan(updated);

    final Plan stored = (await repository.getPlan(original.id))!;
    expect(stored.steps, hasLength(1));
    expect(stored.steps.single.title, 'Only step');
  });

  test('duplicates with new plan and step identities', () async {
    final Plan original = _plan();
    await repository.savePlan(original);

    final Plan duplicate = await repository.duplicatePlan(original.id);

    expect(duplicate.id, isNot(original.id));
    expect(duplicate.title, '${original.title} copy');
    expect(
      duplicate.steps.map((Step step) => step.id).toSet(),
      isNot(equals(original.steps.map((Step step) => step.id).toSet())),
    );
    expect(
      duplicate.steps.every((Step step) => step.planId == duplicate.id),
      isTrue,
    );
  });

  test(
    'duplicates a maximum-length title without exceeding storage limits',
    () async {
      final Plan original = _plan().copyWith(title: 'x' * maxPlanTitleLength);
      await repository.savePlan(original);

      final Plan duplicate = await repository.duplicatePlan(original.id);

      expect(duplicate.title, hasLength(maxPlanTitleLength));
      expect(duplicate.title, endsWith(' copy'));
    },
  );

  test('bulk save rolls back every plan when one insert fails', () async {
    final Plan first = _plan();
    final Plan second = first.copyWith(
      id: 'plan-2',
      title: 'Second plan',
      steps: first.steps
          .map((Step step) => step.copyWith(planId: 'plan-2'))
          .toList(growable: false),
    );

    await expectLater(
      repository.savePlans(<Plan>[first, second]),
      throwsA(isA<Object>()),
    );

    expect(await repository.getAllPlans(), isEmpty);
  });

  test('loads steps for multiple plans without mixing ownership', () async {
    final Plan first = _plan();
    final Plan second = first.copyWith(
      id: 'plan-2',
      title: 'Second plan',
      steps: first.steps
          .map(
            (Step step) => step.copyWith(id: '${step.id}-2', planId: 'plan-2'),
          )
          .toList(growable: false),
      updatedAt: first.updatedAt.add(const Duration(minutes: 1)),
    );
    await repository.savePlan(first);
    await repository.savePlan(second);

    final List<Plan> plans = await repository.getAllPlans();

    expect(plans.map((Plan plan) => plan.id), <String>['plan-2', 'plan-1']);
    expect(
      plans.every(
        (Plan plan) => plan.steps.every((Step step) => step.planId == plan.id),
      ),
      isTrue,
    );
  });

  test('rejects blank identifiers at repository boundaries', () async {
    await expectLater(repository.getPlan('  '), throwsArgumentError);
    await expectLater(repository.deletePlan('\n'), throwsArgumentError);
    await expectLater(repository.duplicatePlan('\t'), throwsArgumentError);
  });

  test('deleting a plan cascades its steps', () async {
    final Plan plan = _plan();
    await repository.savePlan(plan);

    await repository.deletePlan(plan.id);

    expect(await repository.getPlan(plan.id), isNull);
    expect(await database.select(database.stepRecords).get(), isEmpty);
  });
}

Plan _plan() {
  final DateTime createdAt = DateTime.utc(2026, 7, 28, 12);
  return Plan(
    id: 'plan-1',
    title: 'Opening night',
    plannedStartTime: DateTime.utc(2026, 7, 28, 19),
    defaultCueProfile: CueProfile(approachingSeconds: 90, overdueSeconds: 30),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Doors',
        durationSeconds: 300,
      ),
      Step(
        id: 'step-2',
        planId: 'plan-1',
        position: 1,
        title: 'Welcome',
        durationSeconds: 120,
        autoAdvance: true,
        cueOverride: CueProfile(
          approachingSeconds: 20,
          overdueSeconds: 15,
          hapticEnabled: false,
        ),
      ),
    ],
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
