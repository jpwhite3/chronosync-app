import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/session_recovery_dialog.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('running recovery explains downtime and prepares Resume', (
    WidgetTester tester,
  ) async {
    SessionRecoveryChoice? choice;
    bool prepared = false;

    await tester.pumpWidget(
      _RecoveryHarness(
        session: _session(LiveSessionStatus.running),
        onPrepareResume: () async => prepared = true,
        onChoice: (SessionRecoveryChoice? value) => choice = value,
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Resume solo session?'), findsOneWidget);
    expect(find.text('Opening night'), findsOneWidget);
    expect(find.text('Doors open'), findsOneWidget);
    expect(find.textContaining('Time continued'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Discard session'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(prepared, isTrue);
    expect(choice, SessionRecoveryChoice.resume);
  });

  testWidgets('paused recovery stays paused and can be discarded', (
    WidgetTester tester,
  ) async {
    SessionRecoveryChoice? choice;

    await tester.pumpWidget(
      _RecoveryHarness(
        session: _session(LiveSessionStatus.paused),
        onPrepareResume: () async {},
        onChoice: (SessionRecoveryChoice? value) => choice = value,
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();

    expect(find.textContaining('reopen paused'), findsOneWidget);

    await tester.tap(find.text('Discard session'));
    await tester.pumpAndSettle();

    expect(choice, SessionRecoveryChoice.discard);
  });

  testWidgets('recovery remains usable on a compact screen at 200 percent', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _RecoveryHarness(
        session: _session(LiveSessionStatus.running),
        onPrepareResume: () async {},
        onChoice: (SessionRecoveryChoice? _) {},
        textScale: 2,
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Discard session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecoveryHarness extends StatelessWidget {
  const _RecoveryHarness({
    required this.session,
    required this.onPrepareResume,
    required this.onChoice,
    this.textScale = 1,
  });

  final LiveSession session;
  final Future<void> Function() onPrepareResume;
  final ValueChanged<SessionRecoveryChoice?> onChoice;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                onChoice(
                  await showSessionRecoveryDialog(
                    context,
                    session: session,
                    onPrepareResume: onPrepareResume,
                  ),
                );
              },
              child: const Text('Open recovery'),
            ),
          ),
        ),
      ),
    );
  }
}

LiveSession _session(LiveSessionStatus status) {
  final DateTime startedAt = DateTime.utc(2026, 8, 11, 12);
  return LiveSession(
    id: 'session-1',
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
          durationSeconds: 300,
        ),
      ],
      capturedAt: startedAt.subtract(const Duration(hours: 1)),
    ),
    hostDeviceId: 'host-1',
    status: status,
    startedAt: startedAt,
    currentStepStartedAt: startedAt,
    pausedAt: status == LiveSessionStatus.paused
        ? startedAt.add(const Duration(minutes: 1))
        : null,
  );
}
