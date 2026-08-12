import 'dart:async';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/main.dart';
import 'package:chronosync/presentation/screens/mvp_app_shell.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app follows system brightness changes while mounted', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    final AppDependencies dependencies = AppDependencies(
      database: database,
      identity: const DeviceIdentity(
        deviceId: 'host-1',
        displayName: 'Event lead',
      ),
      identityRepository: DeviceIdentityRepository(database),
      planRepository: const _MemoryPlans(),
      historyRepository: _MemoryHistory(null),
      archiveService: const PlanArchiveService(),
      fileService: const PortabilityFileService(),
      cueService: LiveCueService(audioPlayer: _AudioPlayerFake()),
      onlineRoomService: null,
      recoverableSession: null,
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();

    ThemeData activeTheme() =>
        Theme.of(tester.element(find.byType(MvpAppShell)));

    expect(activeTheme().brightness, Brightness.light);
    expect(activeTheme().extension<ChronoColors>(), ChronoColors.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(activeTheme().brightness, Brightness.dark);
    expect(activeTheme().extension<ChronoColors>(), ChronoColors.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(activeTheme().brightness, Brightness.light);
    expect(activeTheme().extension<ChronoColors>(), ChronoColors.light);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('plan launch identity failures stay safe and recoverable', (
    WidgetTester tester,
  ) async {
    final sqlite.Database sqliteDatabase = sqlite.sqlite3.openInMemory();
    final AppDatabase database = AppDatabase(
      NativeDatabase.opened(sqliteDatabase),
    );
    final Plan plan = _launchablePlan();
    final DeviceIdentityRepository identityRepository =
        DeviceIdentityRepository(database);
    await database.customSelect('SELECT 1').get();
    sqliteDatabase.dispose();
    await expectLater(identityRepository.load(), throwsA(anything));
    final AppDependencies dependencies = AppDependencies(
      database: database,
      identity: const DeviceIdentity(
        deviceId: 'host-1',
        displayName: 'Event lead',
      ),
      identityRepository: identityRepository,
      planRepository: _MemoryPlans(<Plan>[plan]),
      historyRepository: _MemoryHistory(null),
      archiveService: const PlanArchiveService(),
      fileService: const PortabilityFileService(),
      cueService: LiveCueService(audioPlayer: _AudioPlayerFake()),
      onlineRoomService: null,
      recoverableSession: null,
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('Opening night'), findsOneWidget);
    await tester.ensureVisible(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Could not open the live session. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('closed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('startup recovery prompt discards the unfinished session', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    final LiveSession session = _runningSession();
    final _MemoryHistory historyRepository = _MemoryHistory(session);
    final AppDependencies dependencies = AppDependencies(
      database: database,
      identity: const DeviceIdentity(
        deviceId: 'host-1',
        displayName: 'Event lead',
      ),
      identityRepository: DeviceIdentityRepository(database),
      planRepository: const _MemoryPlans(),
      historyRepository: historyRepository,
      archiveService: const PlanArchiveService(),
      fileService: const PortabilityFileService(),
      cueService: LiveCueService(audioPlayer: _AudioPlayerFake()),
      onlineRoomService: null,
      recoverableSession: session,
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Resume solo session?'), findsOneWidget);
    expect(find.text('Opening night'), findsOneWidget);

    await tester.tap(find.text('Discard session'));
    await tester.pumpAndSettle();

    expect(await historyRepository.getSession(session.id), isNull);
    expect(find.text('Resume solo session?'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('startup recovery resumes the solo session in the live view', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    final DeviceIdentityRepository identityRepository =
        DeviceIdentityRepository(database);
    final DeviceIdentity identity = await identityRepository.load();
    final LiveSession session = _runningSession(
      hostDeviceId: identity.deviceId,
      status: LiveSessionStatus.paused,
    );
    final _MemoryHistory historyRepository = _MemoryHistory(session);
    final _AudioPlayerFake audioPlayer = _AudioPlayerFake();
    final AppDependencies dependencies = AppDependencies(
      database: database,
      identity: identity,
      identityRepository: identityRepository,
      planRepository: const _MemoryPlans(),
      historyRepository: historyRepository,
      archiveService: const PlanArchiveService(),
      fileService: const PortabilityFileService(),
      cueService: LiveCueService(audioPlayer: audioPlayer),
      onlineRoomService: null,
      recoverableSession: session,
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resume'));
    for (int frame = 0; frame < 40; frame += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(audioPlayer.assetLoads, 1);
    expect(historyRepository.saveCalls, 1);
    expect(find.textContaining('could not prepare'), findsNothing);
    expect(find.text('Resume solo session?'), findsNothing);
    expect(find.text('Live session'), findsOneWidget);
    expect(find.text('Doors open'), findsWidgets);
    expect(await historyRepository.getSession(session.id), isNotNull);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('End live session?'), findsOneWidget);
    expect(find.text('Live session'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pump();
    expect(find.text('Live session'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });
}

final class _MemoryPlans implements PlanRepository {
  const _MemoryPlans([this.plans = const <Plan>[]]);

  final List<Plan> plans;

  @override
  Future<Plan> createPlan({required String title}) {
    throw UnimplementedError();
  }

  @override
  Future<void> deletePlan(String id) async {}

  @override
  Future<Plan> duplicatePlan(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<Plan>> getAllPlans() async => plans;

  @override
  Future<Plan?> getPlan(String id) async {
    for (final Plan plan in plans) {
      if (plan.id == id) {
        return plan;
      }
    }
    return null;
  }

  @override
  Future<void> savePlan(Plan plan) async {}

  @override
  Future<void> savePlans(Iterable<Plan> plans) async {}

  @override
  Stream<List<Plan>> watchPlans() => Stream<List<Plan>>.value(plans);
}

final class _AudioPlayerFake extends Fake implements AudioPlayer {
  int assetLoads = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async {
    assetLoads += 1;
    return Duration.zero;
  }
}

final class _MemoryHistory implements SessionHistoryRepository {
  _MemoryHistory(this._session);

  LiveSession? _session;
  int saveCalls = 0;

  @override
  Future<void> deleteSession(String id) async {
    if (_session?.id == id) {
      _session = null;
    }
  }

  @override
  Future<LiveSession?> getSession(String id) async {
    return _session?.id == id ? _session : null;
  }

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async =>
      const <LiveSession>[];

  @override
  Future<LiveSession?> prepareStartupRecovery({
    required String hostDeviceId,
  }) async => _session;

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async {
    saveCalls += 1;
    _session = session;
  }

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) =>
      Stream<List<LiveSession>>.value(const <LiveSession>[]);
}

LiveSession _runningSession({
  String hostDeviceId = 'host-1',
  LiveSessionStatus status = LiveSessionStatus.running,
}) {
  final DateTime startedAt = DateTime.utc(2026, 8, 11, 12);
  return LiveSession(
    id: 'recoverable-session',
    planSnapshot: PlanSnapshot(
      sourcePlanId: 'plan-1',
      title: 'Opening night',
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Doors open',
          durationSeconds: 3600,
        ),
      ],
      capturedAt: startedAt.subtract(const Duration(hours: 1)),
    ),
    hostDeviceId: hostDeviceId,
    status: status,
    startedAt: startedAt,
    currentStepStartedAt: startedAt,
    pausedAt: status == LiveSessionStatus.paused
        ? startedAt.add(const Duration(minutes: 1))
        : null,
  );
}

Plan _launchablePlan() {
  final DateTime createdAt = DateTime.utc(2026, 8, 11, 12);
  return Plan(
    id: 'launch-plan',
    title: 'Opening night',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'doors-open',
        planId: 'launch-plan',
        position: 0,
        title: 'Doors open',
        durationSeconds: 300,
      ),
    ],
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
