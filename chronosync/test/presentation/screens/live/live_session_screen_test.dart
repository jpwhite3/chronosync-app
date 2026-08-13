import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/live/live.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host view makes live controls actionable', (
    WidgetTester tester,
  ) async {
    int advanceCount = 0;
    int? adjustment;
    bool paused = false;
    bool ended = false;

    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(role: SessionRole.host),
      onAdvance: () {
        advanceCount += 1;
      },
      onPauseResume: () {
        paused = true;
      },
      onAdjustRemaining: (int value) {
        adjustment = value;
      },
      onEndRequested: () {
        ended = true;
      },
    );

    expect(find.text('Opening keynote'), findsOneWidget);
    expect(find.text('Advance'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Advance'));
    await tester.tap(find.text('Advance'));
    await tester.tap(find.text('Pause'));
    await tester.tap(find.text('+1 min'));
    await tester.tap(find.text('End session'));

    expect(advanceCount, 1);
    expect(paused, isTrue);
    expect(adjustment, 60);
    expect(ended, isTrue);
  });

  testWidgets('participant gets one Got it action and no controls', (
    WidgetTester tester,
  ) async {
    bool acknowledged = false;
    await _pumpLive(
      tester,
      size: const Size(430, 850),
      data: _liveData(role: SessionRole.participant),
      onAcknowledge: () {
        acknowledged = true;
      },
    );

    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Advance'), findsNothing);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('End session'), findsNothing);
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    expect(acknowledged, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller view omits host-only end action', (
    WidgetTester tester,
  ) async {
    bool acknowledged = false;
    await _pumpLive(
      tester,
      size: const Size(800, 900),
      data: _liveData(role: SessionRole.controller),
      onAdvance: () {},
      onPauseResume: () {},
      onAdjustRemaining: (int value) {},
      onJumpRequested: () {},
      onAcknowledge: () {
        acknowledged = true;
      },
      onEndRequested: () {},
    );

    expect(find.text('Advance'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Acknowledge the current interval'),
      findsOneWidget,
    );
    expect(find.text('Jump to interval'), findsOneWidget);
    expect(find.text('End session'), findsNothing);

    await tester.ensureVisible(
      find.bySemanticsLabel('Acknowledge the current interval'),
    );
    await tester.tap(find.bySemanticsLabel('Acknowledge the current interval'));

    expect(acknowledged, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manually ended sessions are not reported as complete', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(
        role: SessionRole.host,
        status: LiveSessionStatus.ended,
        endReason: SessionEndReason.endedByHost,
      ),
    );

    expect(find.text('Session ended'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
  });

  testWidgets('people action names its purpose and connected count', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(role: SessionRole.host),
      onShowPeople: () {},
    );

    expect(find.bySemanticsLabel('Show people, 8 connected'), findsOneWidget);
    semantics.dispose();
  });

  for (final SessionRole role in <SessionRole>[
    SessionRole.participant,
    SessionRole.display,
  ]) {
    testWidgets('${role.name} receives a non-ticking live step announcement', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpLive(
        tester,
        size: const Size(800, 900),
        data: _liveData(role: role),
      );

      final Finder announcement = find.bySemanticsLabel(
        'Current interval Opening keynote. Session running.',
      );
      expect(announcement, findsOneWidget);
      expect(
        tester.getSemantics(announcement).flagsCollection.isLiveRegion,
        isTrue,
      );
      semantics.dispose();
    });
  }

  testWidgets('host sees who acknowledged the current step and when', (
    WidgetTester tester,
  ) async {
    final DateTime acknowledgedAt = DateTime(2026, 7, 28, 14, 5);
    await _pumpLive(
      tester,
      size: const Size(800, 900),
      data: _liveData(
        role: SessionRole.host,
        acknowledgements: <AcknowledgementViewData>[
          AcknowledgementViewData(
            actorDeviceId: 'participant-1',
            displayName: 'Sam Rivera',
            role: SessionRole.participant,
            acknowledgedAt: acknowledgedAt,
          ),
        ],
      ),
      onAdvance: () {},
      onPauseResume: () {},
    );

    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Sam Rivera'), findsOneWidget);
    expect(find.textContaining('2:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('participant view keeps team acknowledgements out of the way', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(
        role: SessionRole.participant,
        acknowledgements: <AcknowledgementViewData>[
          AcknowledgementViewData(
            actorDeviceId: 'participant-2',
            displayName: 'Sam Rivera',
            role: SessionRole.participant,
            acknowledgedAt: DateTime(2026, 7, 28, 14, 5),
          ),
        ],
      ),
      onAcknowledge: () {},
    );

    expect(find.text('Sam Rivera'), findsNothing);
    expect(find.text('Got it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('due state remains visible after the timer passes zero', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(
        role: SessionRole.participant,
        remaining: const Duration(seconds: -12),
        timingPhase: LiveTimingPhase.due,
      ),
    );

    expect(find.text('Due'), findsAtLeastNWidgets(1));
    expect(find.text('+00:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('positive fractional remaining time rounds up until due', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(
        role: SessionRole.participant,
        remaining: const Duration(milliseconds: 900),
      ),
    );

    expect(find.text('00:01'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('1 second remaining')),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('00:00'), findsNothing);
    semantics.dispose();
  });

  testWidgets('positive fractional minute does not lose a second', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(
        role: SessionRole.participant,
        remaining: const Duration(seconds: 60, milliseconds: 900),
      ),
    );

    expect(find.text('01:01'), findsOneWidget);
    expect(find.text('01:00'), findsNothing);
  });

  testWidgets('stale state is announced and disables commands', (
    WidgetTester tester,
  ) async {
    int advanceCount = 0;
    final LiveSessionViewData stale = _liveData(
      role: SessionRole.controller,
    ).copyWithForTest(isStale: true);
    await _pumpLive(
      tester,
      size: const Size(1280, 850),
      data: stale,
      onAdvance: () {
        advanceCount += 1;
      },
      onPauseResume: () {},
    );

    expect(find.text('Connection stale'), findsOneWidget);
    final FilledButton advanceButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Advance'),
    );
    expect(advanceButton.onPressed, isNull);
    expect(advanceCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late joiners see that earlier activity is unavailable', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(390, 844),
      data: _liveData(
        role: SessionRole.participant,
        hasCompleteActivityHistory: false,
      ),
    );

    expect(find.text('Incomplete activity history'), findsOneWidget);
    expect(find.textContaining('Earlier session activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display view is high contrast and control free', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(1280, 720),
      data: _liveData(
        role: SessionRole.display,
        remaining: const Duration(seconds: -75),
        timingPhase: LiveTimingPhase.overtime,
      ),
    );

    expect(find.text('Opening keynote'), findsOneWidget);
    expect(find.text('+01:15'), findsOneWidget);
    expect(find.text('OVERTIME'), findsAtLeastNWidgets(1));
    expect(find.text('Advance'), findsNothing);
    expect(find.text('Got it'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display remains readable in compact landscape at 200 percent', (
    WidgetTester tester,
  ) async {
    await _pumpLive(
      tester,
      size: const Size(568, 320),
      textScale: 2,
      data: _liveData(role: SessionRole.display),
    );

    expect(find.text('Opening keynote'), findsOneWidget);
    expect(find.text('21:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLive(
  WidgetTester tester, {
  required Size size,
  required LiveSessionViewData data,
  VoidCallback? onPauseResume,
  VoidCallback? onAdvance,
  ValueChanged<int>? onAdjustRemaining,
  VoidCallback? onJumpRequested,
  VoidCallback? onAcknowledge,
  VoidCallback? onEndRequested,
  VoidCallback? onShowPeople,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: LiveSessionScreen(
        data: data,
        onShowPeople: onShowPeople,
        onPauseResume: onPauseResume,
        onAdvance: onAdvance,
        onAdjustRemaining: onAdjustRemaining,
        onJumpRequested: onJumpRequested,
        onAcknowledge: onAcknowledge,
        onEndRequested: onEndRequested,
      ),
    ),
  );
  await tester.pump();
}

LiveSessionViewData _liveData({
  required SessionRole role,
  LiveSessionStatus status = LiveSessionStatus.running,
  SessionEndReason? endReason,
  Duration remaining = const Duration(minutes: 21, seconds: 45),
  LiveTimingPhase timingPhase = LiveTimingPhase.normal,
  bool hasCompleteActivityHistory = true,
  List<AcknowledgementViewData> acknowledgements =
      const <AcknowledgementViewData>[],
}) {
  return LiveSessionViewData(
    planTitle: 'Event run of show',
    role: role,
    status: status,
    endReason: endReason,
    currentStepTitle: 'Opening keynote',
    currentStepIndex: 1,
    stepCount: 4,
    elapsed: const Duration(minutes: 8, seconds: 15),
    remaining: remaining,
    variance: const Duration(seconds: 42),
    participantCount: 8,
    nextStepTitle: 'Audience questions',
    nextStepDuration: const Duration(minutes: 10),
    timingPhase: timingPhase,
    currentStepAcknowledgements: acknowledgements,
    hasCompleteActivityHistory: hasCompleteActivityHistory,
    revision: 12,
  );
}

extension on LiveSessionViewData {
  LiveSessionViewData copyWithForTest({
    Duration? remaining,
    LiveTimingPhase? timingPhase,
    bool? isStale,
  }) {
    return LiveSessionViewData(
      planTitle: planTitle,
      role: role,
      status: status,
      endReason: endReason,
      currentStepTitle: currentStepTitle,
      currentStepIndex: currentStepIndex,
      stepCount: stepCount,
      elapsed: elapsed,
      remaining: remaining ?? this.remaining,
      variance: variance,
      participantCount: participantCount,
      nextStepTitle: nextStepTitle,
      nextStepDuration: nextStepDuration,
      timingPhase: timingPhase ?? this.timingPhase,
      currentStepAcknowledgements: currentStepAcknowledgements,
      hasCompleteActivityHistory: hasCompleteActivityHistory,
      isStale: isStale ?? this.isStale,
      staleMessage: staleMessage,
      hasAcknowledged: hasAcknowledged,
      revision: revision,
    );
  }
}
