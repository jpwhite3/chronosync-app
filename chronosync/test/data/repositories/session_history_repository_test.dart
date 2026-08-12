import 'dart:convert';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/portability/session_csv_exporter.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSessionHistoryRepository repository;
  late _RecordingQueryInterceptor queryInterceptor;

  setUp(() {
    queryInterceptor = _RecordingQueryInterceptor();
    database = AppDatabase(
      NativeDatabase.memory().interceptWith(queryInterceptor),
    );
    repository = DriftSessionHistoryRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'history lists ended sessions while retaining active snapshots',
    () async {
      final LiveSession waiting = _session(
        id: 'waiting',
        status: LiveSessionStatus.waiting,
      );
      final LiveSession running = _session(
        id: 'running',
        status: LiveSessionStatus.running,
      );
      final LiveSession paused = _session(
        id: 'paused',
        status: LiveSessionStatus.paused,
      );
      final LiveSession ended = _session(
        id: 'ended',
        status: LiveSessionStatus.ended,
      );

      for (final LiveSession session in <LiveSession>[
        waiting,
        running,
        paused,
        ended,
      ]) {
        await repository.saveSession(
          session,
          hostDisplayName: 'Morgan',
          recoveryKind: SessionRecoveryKind.solo,
        );
      }

      expect(await repository.getSessions(), <LiveSession>[ended]);
      expect(await repository.watchSessions().first, <LiveSession>[ended]);
      expect(await repository.getSession(running.id), running);
    },
  );

  test(
    'recovery returns only the newest active solo session for this host',
    () async {
      final LiveSession olderSolo = _session(
        id: 'older-solo',
        status: LiveSessionStatus.running,
        capturedAt: DateTime.utc(2026, 7, 28, 10),
      );
      final LiveSession newerSolo = _session(
        id: 'newer-solo',
        status: LiveSessionStatus.paused,
        capturedAt: DateTime.utc(2026, 7, 28, 11),
      );
      final LiveSession newestShared = _session(
        id: 'newest-shared',
        status: LiveSessionStatus.running,
        capturedAt: DateTime.utc(2026, 7, 28, 12),
      );
      final LiveSession otherHostSolo = _session(
        id: 'other-host',
        status: LiveSessionStatus.running,
        capturedAt: DateTime.utc(2026, 7, 28, 13),
        hostDeviceId: 'host-2',
      );
      final LiveSession endedSolo = _session(
        id: 'ended-solo',
        status: LiveSessionStatus.ended,
        capturedAt: DateTime.utc(2026, 7, 28, 14),
      );

      await repository.saveSession(
        olderSolo,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );
      await repository.saveSession(
        newerSolo,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );
      await repository.saveSession(
        newestShared,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.sharedHost,
      );
      await repository.saveSession(
        otherHostSolo,
        hostDisplayName: 'Taylor',
        recoveryKind: SessionRecoveryKind.solo,
      );
      await repository.saveSession(
        endedSolo,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );

      queryInterceptor.selects.clear();
      final LiveSession? recovered = await repository.prepareStartupRecovery(
        hostDeviceId: 'host-1',
      );
      final List<_RecordedSelect> recoveryActivityQueries = queryInterceptor
          .selects
          .where(
            (_RecordedSelect query) =>
                query.statement.contains('activity_records'),
          )
          .toList(growable: false);

      expect(recovered, newerSolo);
      expect(recoveryActivityQueries, isNotEmpty);
      expect(
        recoveryActivityQueries.expand(
          (_RecordedSelect query) => query.arguments,
        ),
        isNot(contains(endedSolo.id)),
        reason: 'Startup recovery must not load ended-session activities.',
      );
      expect(await repository.getSession(olderSolo.id), isNull);
      expect(await repository.getSession(newestShared.id), isNull);
      expect(await repository.getSession(otherHostSolo.id), isNull);
      expect(await repository.getSession(endedSolo.id), endedSolo);

      await repository.deleteSession(newerSolo.id);

      expect(
        await repository.prepareStartupRecovery(hostDeviceId: 'host-1'),
        isNull,
      );
    },
  );

  test('appends activity rows without rewriting persisted history', () async {
    LiveSession session = _startedSession('incremental');
    await repository.saveSession(
      session,
      hostDisplayName: 'Morgan',
      recoveryKind: SessionRecoveryKind.solo,
    );
    await database.customStatement('''
      CREATE TRIGGER reject_activity_delete
      BEFORE DELETE ON activity_records
      BEGIN
        SELECT RAISE(ABORT, 'activity history must be append-only');
      END
      ''');
    session = SessionReducer.applyCommand(
      session: session,
      command: SessionCommand.pause(
        id: 'pause-incremental',
        sessionId: session.id,
        actorDeviceId: session.hostDeviceId,
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: DateTime.utc(2026, 7, 28, 19, 1),
      ),
      occurredAt: DateTime.utc(2026, 7, 28, 19, 1),
    ).session;

    await repository.saveSession(
      session,
      hostDisplayName: 'Morgan',
      recoveryKind: SessionRecoveryKind.solo,
    );

    final List<ActivityRecord> rows = await database
        .select(database.activityRecords)
        .get();
    expect(rows.map((ActivityRecord row) => row.revision), <int>[1, 2]);
  });

  test(
    'incremental save indexes directly into a long authoritative history',
    () async {
      final LiveSession session = _largeHistorySession(12500);
      final Activity previous = session.activities[12498];
      await _seedStoredTail(
        database,
        session,
        recordRevision: 12499,
        activity: previous,
      );
      final int readsBeforeSave = session.debugActivityReadCount;

      await repository.saveSession(
        session,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );

      final int activityReads =
          session.debugActivityReadCount - readsBeforeSave;
      final List<ActivityRecord> rows =
          await (database.select(database.activityRecords)
                ..orderBy(<OrderClauseGenerator<$ActivityRecordsTable>>[
                  ($ActivityRecordsTable table) =>
                      OrderingTerm.asc(table.revision),
                ]))
              .get();
      expect(
        activityReads,
        lessThan(256),
        reason: 'Persisting one new revision must not scan 12,500 activities.',
      );
      expect(rows.map((ActivityRecord row) => row.revision), <int>[
        12499,
        12500,
      ]);

      final int readsBeforeEqualSave = session.debugActivityReadCount;
      await repository.saveSession(
        session,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );
      expect(
        session.debugActivityReadCount - readsBeforeEqualSave,
        lessThan(128),
        reason: 'An equal-revision save must not scan completed history.',
      );
      expect(
        await database.select(database.activityRecords).get(),
        hasLength(2),
      );
    },
  );

  test(
    'compact activity windows append from their exact revision offset',
    () async {
      final LiveSession full = _largeHistorySession(100);
      final LiveSession compact = full.copyWith(
        activityRevisionOffset: 90,
        activities: full.activities.skip(90),
      );
      await _seedStoredTail(
        database,
        compact,
        recordRevision: 90,
        activity: full.activities[89],
      );

      await repository.saveSession(
        compact,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );

      final List<ActivityRecord> rows =
          await (database.select(database.activityRecords)
                ..orderBy(<OrderClauseGenerator<$ActivityRecordsTable>>[
                  ($ActivityRecordsTable table) =>
                      OrderingTerm.asc(table.revision),
                ]))
              .get();
      expect(rows.map((ActivityRecord row) => row.revision), <int>[
        90,
        ...List<int>.generate(10, (int index) => index + 91),
      ]);
    },
  );

  test(
    'an empty compact window supports equal save and its next revision',
    () async {
      final LiveSession full = _largeHistorySession(100);
      final LiveSession emptyWindow = full.copyWith(
        activityRevisionOffset: 100,
        activities: const <Activity>[],
      );
      await repository.saveSession(
        emptyWindow,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.sharedParticipant,
      );

      await repository.saveSession(
        emptyWindow,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.sharedParticipant,
      );
      final LiveSession next = SessionReducer.applyActivity(
        session: emptyWindow,
        activity: Activity(
          id: 'activity-101',
          commandId: 'command-101',
          sessionId: emptyWindow.id,
          revision: 101,
          type: ActivityType.remainingAdjusted,
          stepIndex: emptyWindow.currentStepIndex,
          stepId: emptyWindow.currentStep.id,
          actorDeviceId: emptyWindow.hostDeviceId,
          actorRole: SessionRole.host,
          occurredAt: DateTime.utc(2026, 7, 28, 21),
          payload: const <String, Object?>{'adjustmentSeconds': 1},
        ),
      );
      await repository.saveSession(
        next,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.sharedParticipant,
      );

      final LiveSession restored = (await repository.getSession(next.id))!;
      expect(restored.activityRevisionOffset, 100);
      expect(restored.activities.single.revision, 101);
      expect(restored.hasCompleteActivityHistory, isFalse);
    },
  );

  test(
    'rejects a persisted tail that a compact window cannot bridge',
    () async {
      final LiveSession full = _largeHistorySession(100);
      final LiveSession compact = full.copyWith(
        activityRevisionOffset: 90,
        activities: full.activities.skip(90),
      );
      await _seedStoredTail(
        database,
        compact,
        recordRevision: 89,
        activity: full.activities[88],
      );

      await expectLater(
        repository.saveSession(
          compact,
          hostDisplayName: 'Morgan',
          recoveryKind: SessionRecoveryKind.solo,
        ),
        throwsStateError,
      );

      expect(
        (await database.select(database.sessionRecords).getSingle())
            .lastRevision,
        89,
      );
      expect(
        await database.select(database.activityRecords).get(),
        hasLength(1),
      );
    },
  );

  test(
    'rejects session metadata that disagrees with its activity tail',
    () async {
      final LiveSession full = _largeHistorySession(100);
      await _seedStoredTail(
        database,
        full,
        recordRevision: 90,
        activity: full.activities[88],
      );

      await expectLater(
        repository.saveSession(
          full,
          hostDisplayName: 'Morgan',
          recoveryKind: SessionRecoveryKind.solo,
        ),
        throwsStateError,
      );

      expect(
        (await database.select(database.sessionRecords).getSingle())
            .lastRevision,
        90,
      );
    },
  );

  test(
    'stores a bounded state snapshot and reconstructs full history',
    () async {
      final LiveSession session = _largeHistorySession(100);

      await repository.saveSession(
        session,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );

      final SessionRecord row = await database
          .select(database.sessionRecords)
          .getSingle();
      final Map<String, Object?> state = Map<String, Object?>.from(
        jsonDecode(row.sessionStateJson) as Map<Object?, Object?>,
      );
      final List<Object?> storedActivities =
          state['activities']! as List<Object?>;
      final LiveSession restored = (await repository.getSession(session.id))!;

      expect(storedActivities.length, lessThanOrEqualTo(64));
      expect(restored.activities, hasLength(100));
      expect(restored.activities.first.commandId, 'command-1');
      expect(restored.hasCompleteActivityHistory, isTrue);
    },
  );

  test('preserves actor names captured when activities were saved', () async {
    final LiveSession session = _startedSession('historical-name');
    await repository.saveSession(
      session,
      hostDisplayName: 'Original Host',
      recoveryKind: SessionRecoveryKind.solo,
    );

    final LiveSession restored = (await repository.getSession(session.id))!;
    final String csv = const SessionCsvExporter().export(
      restored,
      hostDisplayName: 'Renamed Host',
    );

    expect(restored.activities.single.actorDisplayName, 'Original Host');
    expect(csv, contains('Original Host'));
    expect(csv, isNot(contains('Renamed Host')));
  });

  test(
    'rejects stale rewrites, blank IDs, and invalid history limits',
    () async {
      final LiveSession current = _startedSession('monotonic');
      await repository.saveSession(
        current,
        hostDisplayName: 'Morgan',
        recoveryKind: SessionRecoveryKind.solo,
      );

      await expectLater(
        repository.saveSession(
          _session(id: current.id, status: LiveSessionStatus.waiting),
          hostDisplayName: 'Morgan',
          recoveryKind: SessionRecoveryKind.solo,
        ),
        throwsStateError,
      );
      await expectLater(repository.getSession('  '), throwsArgumentError);
      await expectLater(repository.deleteSession('\n'), throwsArgumentError);
      await expectLater(repository.getSessions(limit: 0), throwsArgumentError);
      expect(() => repository.watchSessions(limit: 501), throwsArgumentError);
      expect((await repository.getSession(current.id))!.revision, 1);
    },
  );
}

typedef _RecordedSelect = ({String statement, List<Object?> arguments});

final class _RecordingQueryInterceptor extends QueryInterceptor {
  final List<_RecordedSelect> selects = <_RecordedSelect>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add((statement: statement, arguments: List<Object?>.of(args)));
    return super.runSelect(executor, statement, args);
  }
}

LiveSession _startedSession(String id) {
  final LiveSession waiting = _session(
    id: id,
    status: LiveSessionStatus.waiting,
  );
  return SessionReducer.applyCommand(
    session: waiting,
    command: SessionCommand.start(
      id: 'start-$id',
      sessionId: waiting.id,
      actorDeviceId: waiting.hostDeviceId,
      actorRole: SessionRole.host,
      baseRevision: waiting.revision,
      issuedAt: DateTime.utc(2026, 7, 28, 19),
    ),
    occurredAt: DateTime.utc(2026, 7, 28, 19),
  ).session;
}

ActivityRecordsCompanion _activityCompanion(Activity activity) {
  return ActivityRecordsCompanion.insert(
    id: activity.id,
    sessionId: activity.sessionId,
    revision: activity.revision,
    commandId: Value<String?>(activity.commandId),
    type: activity.type.name,
    stepId: Value<String?>(activity.stepId),
    stepIndex: Value<int?>(activity.stepIndex),
    actorDeviceId: activity.actorDeviceId,
    actorDisplayName: activity.actorDisplayName ?? 'Morgan',
    actorRole: activity.actorRole.name,
    occurredAtMillis: activity.occurredAt.millisecondsSinceEpoch,
    payloadJson: jsonEncode(activity.payload),
  );
}

Future<void> _seedStoredTail(
  AppDatabase database,
  LiveSession session, {
  required int recordRevision,
  required Activity activity,
}) async {
  await database
      .into(database.sessionRecords)
      .insert(
        SessionRecordsCompanion.insert(
          id: session.id,
          planTitle: session.planSnapshot.title,
          planSnapshotJson: jsonEncode(session.planSnapshot.toJson()),
          sessionStateJson: '{}',
          status: session.status.name,
          lastRevision: Value<int>(recordRevision),
          createdAtMillis:
              session.planSnapshot.capturedAt.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.activityRecords)
      .insert(_activityCompanion(activity));
}

LiveSession _largeHistorySession(int activityCount) {
  final DateTime startedAt = DateTime.utc(2026, 7, 28, 19);
  final LiveSession base = _session(
    id: 'large-history',
    status: LiveSessionStatus.running,
  );
  return LiveSession(
    id: base.id,
    planSnapshot: base.planSnapshot,
    hostDeviceId: base.hostDeviceId,
    status: LiveSessionStatus.running,
    revision: activityCount,
    startedAt: startedAt,
    currentStepStartedAt: startedAt,
    activities: List<Activity>.generate(
      activityCount,
      (int index) => Activity(
        id: 'activity-${index + 1}',
        commandId: 'command-${index + 1}',
        sessionId: base.id,
        revision: index + 1,
        type: ActivityType.acknowledged,
        stepIndex: 0,
        stepId: base.planSnapshot.steps.single.id,
        actorDeviceId: base.hostDeviceId,
        actorRole: SessionRole.host,
        occurredAt: startedAt.add(Duration(seconds: index)),
      ),
      growable: false,
    ),
  );
}

LiveSession _session({
  required String id,
  required LiveSessionStatus status,
  DateTime? capturedAt,
  String hostDeviceId = 'host-1',
}) {
  final DateTime startedAt = DateTime.utc(2026, 7, 28, 19);
  final PlanSnapshot snapshot = PlanSnapshot(
    sourcePlanId: 'plan-1',
    title: 'Opening night',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Doors',
        durationSeconds: 300,
      ),
    ],
    capturedAt: capturedAt ?? startedAt.subtract(const Duration(hours: 1)),
  );

  return switch (status) {
    LiveSessionStatus.waiting => LiveSession(
      id: id,
      planSnapshot: snapshot,
      hostDeviceId: hostDeviceId,
    ),
    LiveSessionStatus.running => LiveSession(
      id: id,
      planSnapshot: snapshot,
      hostDeviceId: hostDeviceId,
      status: status,
      startedAt: startedAt,
      currentStepStartedAt: startedAt,
    ),
    LiveSessionStatus.paused => LiveSession(
      id: id,
      planSnapshot: snapshot,
      hostDeviceId: hostDeviceId,
      status: status,
      startedAt: startedAt,
      currentStepStartedAt: startedAt,
      pausedAt: startedAt.add(const Duration(minutes: 1)),
    ),
    LiveSessionStatus.ended => LiveSession(
      id: id,
      planSnapshot: snapshot,
      hostDeviceId: hostDeviceId,
      status: status,
      startedAt: startedAt,
      currentStepStartedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 2)),
      endReason: SessionEndReason.endedByHost,
    ),
  };
}
