import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

abstract interface class PlanRepository {
  Stream<List<Plan>> watchPlans();

  Future<List<Plan>> getAllPlans();

  Future<Plan?> getPlan(String id);

  Future<void> savePlan(Plan plan);

  /// Saves an imported collection as one transaction.
  Future<void> savePlans(Iterable<Plan> plans);

  Future<void> deletePlan(String id);

  Future<Plan> duplicatePlan(String id);

  Future<Plan> createPlan({required String title});
}

final class DriftPlanRepository implements PlanRepository {
  DriftPlanRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  @override
  Stream<List<Plan>> watchPlans() {
    final Selectable<QueryRow> invalidationQuery = _database.customSelect(
      '''
      SELECT plans.id
      FROM plan_records AS plans
      LEFT JOIN step_records AS steps ON steps.plan_id = plans.id
      ORDER BY plans.updated_at_millis DESC, steps.position ASC
      ''',
      readsFrom: <ResultSetImplementation<Table, DataClass>>{
        _database.planRecords,
        _database.stepRecords,
      },
    );
    return invalidationQuery.watch().asyncMap(
      (List<QueryRow> _) => getAllPlans(),
    );
  }

  @override
  Future<List<Plan>> getAllPlans() async {
    final List<PlanRecord> planRows =
        await (_database.select(_database.planRecords)
              ..orderBy(<OrderClauseGenerator<$PlanRecordsTable>>[
                ($PlanRecordsTable table) =>
                    OrderingTerm.desc(table.updatedAtMillis),
              ]))
            .get();
    if (planRows.isEmpty) {
      return const <Plan>[];
    }
    final List<String> planIds = planRows
        .map((PlanRecord row) => row.id)
        .toList(growable: false);
    final List<StepRecord> stepRows =
        await (_database.select(_database.stepRecords)
              ..where(($StepRecordsTable table) => table.planId.isIn(planIds))
              ..orderBy(<OrderClauseGenerator<$StepRecordsTable>>[
                ($StepRecordsTable table) => OrderingTerm.asc(table.planId),
                ($StepRecordsTable table) => OrderingTerm.asc(table.position),
              ]))
            .get();
    final Map<String, List<StepRecord>> stepsByPlan =
        <String, List<StepRecord>>{};
    for (final StepRecord step in stepRows) {
      stepsByPlan.putIfAbsent(step.planId, () => <StepRecord>[]).add(step);
    }
    return List<Plan>.unmodifiable(
      planRows.map(
        (PlanRecord row) =>
            _mapPlan(row, stepsByPlan[row.id] ?? const <StepRecord>[]),
      ),
    );
  }

  @override
  Future<Plan?> getPlan(String id) async {
    final String normalizedId = _requirePlanId(id);
    final PlanRecord? record =
        await (_database.select(_database.planRecords)..where(
              ($PlanRecordsTable table) => table.id.equals(normalizedId),
            ))
            .getSingleOrNull();
    if (record == null) {
      return null;
    }
    final List<StepRecord> stepRows = await _stepsForPlan(record.id);
    return _mapPlan(record, stepRows);
  }

  @override
  Future<Plan> createPlan({required String title}) async {
    final DateTime now = DateTime.now().toUtc();
    final Plan plan = Plan(
      id: _uuid.v4(),
      title: title,
      defaultCueProfile: CueProfile(),
      steps: const <Step>[],
      createdAt: now,
      updatedAt: now,
    );
    await savePlan(plan);
    return plan;
  }

  @override
  Future<void> savePlan(Plan plan) async {
    await savePlans(<Plan>[plan]);
  }

  @override
  Future<void> savePlans(Iterable<Plan> plans) async {
    final List<Plan> values = List<Plan>.of(plans, growable: false);
    final Set<String> ids = <String>{};
    for (final Plan plan in values) {
      if (!ids.add(plan.id)) {
        throw ArgumentError.value(
          plan.id,
          'plans',
          'A bulk save cannot contain the same plan more than once.',
        );
      }
    }
    if (values.isEmpty) {
      return;
    }
    await _database.transaction(() async {
      for (final Plan plan in values) {
        await _savePlanWithinTransaction(plan);
      }
    });
  }

  @override
  Future<void> deletePlan(String id) async {
    final String normalizedId = _requirePlanId(id);
    await (_database.delete(
      _database.planRecords,
    )..where(($PlanRecordsTable table) => table.id.equals(normalizedId))).go();
  }

  @override
  Future<Plan> duplicatePlan(String id) async {
    final Plan? source = await getPlan(_requirePlanId(id));
    if (source == null) {
      throw StateError('The plan to duplicate no longer exists.');
    }
    final DateTime now = DateTime.now().toUtc();
    final String duplicateId = _uuid.v4();
    final Plan duplicate = Plan(
      id: duplicateId,
      title: _duplicateTitle(source.title),
      plannedStartTime: source.plannedStartTime,
      defaultCueProfile: source.defaultCueProfile,
      steps: source.steps
          .map<Step>(
            (Step step) => step.copyWith(id: _uuid.v4(), planId: duplicateId),
          )
          .toList(growable: false),
      createdAt: now,
      updatedAt: now,
    );
    await savePlan(duplicate);
    return duplicate;
  }

  Future<void> _savePlanWithinTransaction(Plan plan) async {
    await _database
        .into(_database.planRecords)
        .insertOnConflictUpdate(_planCompanion(plan));

    await (_database.delete(
      _database.stepRecords,
    )..where(($StepRecordsTable table) => table.planId.equals(plan.id))).go();

    if (plan.steps.isNotEmpty) {
      await _database.batch((Batch batch) {
        batch.insertAll(
          _database.stepRecords,
          plan.steps.map<StepRecordsCompanion>(_stepCompanion).toList(),
        );
      });
    }
  }

  Future<List<StepRecord>> _stepsForPlan(String planId) {
    return (_database.select(_database.stepRecords)
          ..where(($StepRecordsTable table) => table.planId.equals(planId))
          ..orderBy(<OrderClauseGenerator<$StepRecordsTable>>[
            ($StepRecordsTable table) => OrderingTerm.asc(table.position),
          ]))
        .get();
  }

  Plan _mapPlan(PlanRecord record, List<StepRecord> stepRows) {
    return Plan(
      id: record.id,
      title: record.title,
      plannedStartTime: record.plannedStartMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              record.plannedStartMillis!,
              isUtc: true,
            ),
      defaultCueProfile: CueProfile(
        approachingSeconds: record.approachingCueSeconds,
        overdueSeconds: record.overdueCueSeconds,
        visualEnabled: record.visualCuesEnabled,
        soundEnabled: record.soundCuesEnabled,
        hapticEnabled: record.hapticCuesEnabled,
      ),
      steps: stepRows.map<Step>(_mapStep).toList(growable: false),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        record.createdAtMillis,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        record.updatedAtMillis,
        isUtc: true,
      ),
    );
  }

  Step _mapStep(StepRecord record) {
    final bool hasCueOverride =
        record.approachingCueSeconds != null &&
        record.overdueCueSeconds != null &&
        record.visualCuesEnabled != null &&
        record.soundCuesEnabled != null &&
        record.hapticCuesEnabled != null;
    return Step(
      id: record.id,
      planId: record.planId,
      position: record.position,
      title: record.title,
      durationSeconds: record.durationSeconds,
      autoAdvance: record.autoAdvance,
      cueOverride: hasCueOverride
          ? CueProfile(
              approachingSeconds: record.approachingCueSeconds!,
              overdueSeconds: record.overdueCueSeconds!,
              visualEnabled: record.visualCuesEnabled!,
              soundEnabled: record.soundCuesEnabled!,
              hapticEnabled: record.hapticCuesEnabled!,
            )
          : null,
    );
  }

  PlanRecordsCompanion _planCompanion(Plan plan) {
    return PlanRecordsCompanion.insert(
      id: plan.id,
      title: plan.title,
      plannedStartMillis: Value<int?>(
        plan.plannedStartTime?.millisecondsSinceEpoch,
      ),
      approachingCueSeconds: Value<int>(
        plan.defaultCueProfile.approachingSeconds,
      ),
      overdueCueSeconds: Value<int>(plan.defaultCueProfile.overdueSeconds),
      visualCuesEnabled: Value<bool>(plan.defaultCueProfile.visualEnabled),
      soundCuesEnabled: Value<bool>(plan.defaultCueProfile.soundEnabled),
      hapticCuesEnabled: Value<bool>(plan.defaultCueProfile.hapticEnabled),
      createdAtMillis: plan.createdAt.millisecondsSinceEpoch,
      updatedAtMillis: plan.updatedAt.millisecondsSinceEpoch,
    );
  }

  StepRecordsCompanion _stepCompanion(Step step) {
    final CueProfile? cue = step.cueOverride;
    return StepRecordsCompanion.insert(
      id: step.id,
      planId: step.planId,
      position: step.position,
      title: step.title,
      durationSeconds: step.durationSeconds,
      autoAdvance: Value<bool>(step.autoAdvance),
      approachingCueSeconds: Value<int?>(cue?.approachingSeconds),
      overdueCueSeconds: Value<int?>(cue?.overdueSeconds),
      visualCuesEnabled: Value<bool?>(cue?.visualEnabled),
      soundCuesEnabled: Value<bool?>(cue?.soundEnabled),
      hapticCuesEnabled: Value<bool?>(cue?.hapticEnabled),
    );
  }
}

String _requirePlanId(String id) {
  final String normalized = id.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(id, 'id', 'A plan ID cannot be empty.');
  }
  return normalized;
}

String _duplicateTitle(String sourceTitle) {
  const String suffix = ' copy';
  final int availableSourceLength = maxPlanTitleLength - suffix.length;
  final String base = sourceTitle.length <= availableSourceLength
      ? sourceTitle
      : sourceTitle.substring(0, availableSourceLength).trimRight();
  return '$base$suffix';
}
