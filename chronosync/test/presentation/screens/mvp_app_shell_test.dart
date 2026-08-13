import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/mvp_app_shell.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact navigation preserves in-progress settings state', (
    WidgetTester tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _pumpShell(tester, database: database);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Unsaved stage lead',
    );
    await tester.tap(find.text('History'));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pump();

    final TextField field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Display name'),
    );
    expect(field.controller?.text, 'Unsaved stage lead');
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded layout uses a navigation rail', (
    WidgetTester tester,
  ) async {
    await _setViewport(tester, const Size(1280, 900));
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _pumpShell(tester, database: database);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Your sequences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact navigation is overflow-free at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _pumpShell(tester, database: database, textScale: 2);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDatabase database,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MvpAppShell(
        planRepository: const _EmptyPlans(),
        historyRepository: const _EmptyHistory(),
        identityRepository: DeviceIdentityRepository(database),
        initialIdentity: const DeviceIdentity(
          deviceId: 'device-1',
          displayName: 'This device',
        ),
        archiveService: const PlanArchiveService(),
        fileService: const PortabilityFileService(),
        onLaunchPlan: (BuildContext _, Plan _) async {},
        onOpenSession: (BuildContext _, LiveSession _) async {},
        onJoinSession: (BuildContext _) async {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

final class _EmptyPlans implements PlanRepository {
  const _EmptyPlans();

  @override
  Future<Plan> createPlan({required String title}) =>
      throw UnimplementedError();

  @override
  Future<void> deletePlan(String id) async {}

  @override
  Future<Plan> duplicatePlan(String id) => throw UnimplementedError();

  @override
  Future<List<Plan>> getAllPlans() async => const <Plan>[];

  @override
  Future<Plan?> getPlan(String id) async => null;

  @override
  Future<void> savePlan(Plan plan) async {}

  @override
  Future<void> savePlans(Iterable<Plan> plans) async {}

  @override
  Stream<List<Plan>> watchPlans() => Stream<List<Plan>>.value(const <Plan>[]);
}

final class _EmptyHistory implements SessionHistoryRepository {
  const _EmptyHistory();

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<LiveSession?> getSession(String id) async => null;

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async =>
      const <LiveSession>[];

  @override
  Future<LiveSession?> prepareStartupRecovery({required String hostDeviceId}) =>
      Future<LiveSession?>.value();

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async {}

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) =>
      Stream<List<LiveSession>>.value(const <LiveSession>[]);
}
