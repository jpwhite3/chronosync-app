import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/history_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history labels saved sessions with incomplete activity', (
    WidgetTester tester,
  ) async {
    final LiveSession session = _incompleteEndedSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: ChronoTheme.light(),
        home: Scaffold(
          body: HistoryScreen(
            repository: _MemoryHistory(session),
            onOpenSession: (LiveSession session) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Incomplete activity history'), findsOneWidget);
    expect(find.text('Ended'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'complete-history card semantics do not contain an empty clause',
    (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpHistory(tester, _endedSession(completeHistory: true));

      expect(
        find.bySemanticsLabel('Open Event run of show session summary.'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('history card is overflow-free at 300 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpHistory(tester, _incompleteEndedSession(), textScale: 3);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();

    expect(find.text('Event run of show'), findsOneWidget);
    expect(find.text('Ended'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHistory(
  WidgetTester tester,
  LiveSession session, {
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
      home: Scaffold(
        body: HistoryScreen(
          repository: _MemoryHistory(session),
          onOpenSession: (LiveSession session) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

LiveSession _incompleteEndedSession() {
  return _endedSession(completeHistory: false);
}

LiveSession _endedSession({required bool completeHistory}) {
  final DateTime startedAt = DateTime.utc(2026, 7, 29, 12);
  return LiveSession(
    id: 'session-1',
    planSnapshot: PlanSnapshot(
      sourcePlanId: 'plan-1',
      title: 'Event run of show',
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Opening keynote',
          durationSeconds: 60,
        ),
      ],
      capturedAt: startedAt.subtract(const Duration(hours: 1)),
    ),
    hostDeviceId: 'host-1',
    status: LiveSessionStatus.ended,
    revision: completeHistory ? 0 : 4,
    activityRevisionOffset: completeHistory ? 0 : 4,
    startedAt: startedAt,
    currentStepStartedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 1)),
    endReason: SessionEndReason.completed,
  );
}

final class _MemoryHistory implements SessionHistoryRepository {
  const _MemoryHistory(this.session);

  final LiveSession session;

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<LiveSession?> getSession(String id) async => session;

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async =>
      <LiveSession>[session];

  @override
  Future<LiveSession?> prepareStartupRecovery({
    required String hostDeviceId,
  }) async => null;

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async {}

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) =>
      Stream<List<LiveSession>>.value(<LiveSession>[session]);
}
