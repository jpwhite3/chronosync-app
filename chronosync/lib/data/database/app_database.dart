import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// Keep these synchronized with the literal `withLength` values below.
// drift_dev does not emit maximum-length checks for referenced constants.
const int maximumPlanTitleLength = 160;
const int maximumStepTitleLength = 240;

@DataClassName('PlanRecord')
class PlanRecords extends Table {
  TextColumn get id => text()();

  TextColumn get title => text().withLength(min: 1, max: 160)();

  IntColumn get plannedStartMillis => integer().nullable()();

  IntColumn get approachingCueSeconds =>
      integer().withDefault(const Constant<int>(60))();

  IntColumn get overdueCueSeconds =>
      integer().withDefault(const Constant<int>(60))();

  BoolColumn get visualCuesEnabled =>
      boolean().withDefault(const Constant<bool>(true))();

  BoolColumn get soundCuesEnabled =>
      boolean().withDefault(const Constant<bool>(true))();

  BoolColumn get hapticCuesEnabled =>
      boolean().withDefault(const Constant<bool>(true))();

  IntColumn get createdAtMillis => integer()();

  IntColumn get updatedAtMillis => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('StepRecord')
class StepRecords extends Table {
  TextColumn get id => text()();

  TextColumn get planId =>
      text().references(PlanRecords, #id, onDelete: KeyAction.cascade)();

  IntColumn get position => integer()();

  TextColumn get title => text().withLength(min: 1, max: 240)();

  IntColumn get durationSeconds => integer()();

  BoolColumn get autoAdvance =>
      boolean().withDefault(const Constant<bool>(false))();

  IntColumn get approachingCueSeconds => integer().nullable()();

  IntColumn get overdueCueSeconds => integer().nullable()();

  BoolColumn get visualCuesEnabled => boolean().nullable()();

  BoolColumn get soundCuesEnabled => boolean().nullable()();

  BoolColumn get hapticCuesEnabled => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{planId, position},
  ];
}

@DataClassName('SessionRecord')
class SessionRecords extends Table {
  TextColumn get id => text()();

  TextColumn get planId => text().nullable()();

  TextColumn get planTitle => text()();

  TextColumn get planSnapshotJson => text()();

  TextColumn get sessionStateJson => text()();

  TextColumn get status => text()();

  IntColumn get startedAtMillis => integer().nullable()();

  IntColumn get endedAtMillis => integer().nullable()();

  IntColumn get lastRevision => integer().withDefault(const Constant<int>(0))();

  IntColumn get createdAtMillis => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ActivityRecord')
class ActivityRecords extends Table {
  TextColumn get id => text()();

  TextColumn get sessionId =>
      text().references(SessionRecords, #id, onDelete: KeyAction.cascade)();

  IntColumn get revision => integer()();

  /// Added in schema v2. Nullable only so existing v1 rows can migrate;
  /// every newly persisted activity supplies this value.
  TextColumn get commandId => text().nullable()();

  TextColumn get type => text()();

  TextColumn get stepId => text().nullable()();

  IntColumn get stepIndex => integer().nullable()();

  TextColumn get actorDeviceId => text()();

  TextColumn get actorDisplayName => text()();

  TextColumn get actorRole => text()();

  IntColumn get occurredAtMillis => integer()();

  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{sessionId, revision},
  ];
}

@DataClassName('AppMetadataRecord')
class AppMetadataRecords extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

@DriftDatabase(
  tables: <Type>[
    PlanRecords,
    StepRecords,
    SessionRecords,
    ActivityRecords,
    AppMetadataRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults()
    : super(
        driftDatabase(
          name: 'chronosync',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
      await _createPerformanceIndexes();
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.addColumn(activityRecords, activityRecords.commandId);
        await _createPerformanceIndexes();
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createPerformanceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS '
      'idx_session_records_status_created '
      'ON session_records(status, created_at_millis DESC)',
    );
  }
}
