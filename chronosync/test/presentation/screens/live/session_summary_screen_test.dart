import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/live/live.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final Size size in <Size>[
    const Size(390, 844),
    const Size(800, 900),
    const Size(1280, 900),
  ]) {
    testWidgets('summary is overflow-free at ${size.width.toInt()} px', (
      WidgetTester tester,
    ) async {
      await _pumpSummary(tester, size: size, data: _summaryData());

      expect(find.text('Planned vs. actual'), findsOneWidget);
      expect(find.text('Opening keynote'), findsOneWidget);
      expect(find.text('Not reached'), findsOneWidget);
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.textContaining('Jul 28'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('CSV export callback is available in summary', (
    WidgetTester tester,
  ) async {
    int exportCount = 0;
    await _pumpSummary(
      tester,
      size: const Size(390, 844),
      data: _summaryData(),
      onExport: () {
        exportCount += 1;
      },
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.download_rounded));
    expect(exportCount, 1);
  });

  testWidgets('compact app bar preserves the title with icon-only export', (
    WidgetTester tester,
  ) async {
    await _pumpSummary(
      tester,
      size: const Size(390, 844),
      data: _summaryData(),
      onDone: () {},
      onExport: () {},
    );

    expect(find.text('Session summary'), findsOneWidget);
    expect(find.text('Export CSV'), findsNothing);
    expect(
      find.byTooltip('Export complete session activity as CSV'),
      findsOneWidget,
    );
    expect(
      find.widgetWithIcon(IconButton, Icons.download_rounded),
      findsOneWidget,
    );
  });

  testWidgets('incomplete summaries explain and disable CSV export', (
    WidgetTester tester,
  ) async {
    int exportCount = 0;
    await _pumpSummary(
      tester,
      size: const Size(390, 844),
      data: _summaryData(hasCompleteActivityHistory: false),
      onExport: () {
        exportCount += 1;
      },
    );

    expect(find.text('Incomplete activity history'), findsOneWidget);
    expect(
      find.textContaining('Export CSV from the host device'),
      findsOneWidget,
    );
    expect(find.text('Available activity entries'), findsOneWidget);
    final IconButton exportButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.download_rounded),
    );
    expect(exportButton.onPressed, isNull);
    expect(exportCount, 0);
  });

  testWidgets(
    'summary remains usable on a compact screen at 300 percent text',
    (WidgetTester tester) async {
      await _pumpSummary(
        tester,
        size: const Size(320, 568),
        data: _summaryData(),
        onExport: () {},
        textScale: 3,
      );

      expect(find.text('Session summary'), findsOneWidget);
      expect(find.text('Planned vs. actual'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an unstarted manual end is labeled without a fabricated start', (
    WidgetTester tester,
  ) async {
    await _pumpSummary(
      tester,
      size: const Size(390, 844),
      data: _summaryData(
        endedBeforeStart: true,
        endReason: SessionEndReason.endedByHost,
      ),
    );

    expect(find.text('Session ended'), findsOneWidget);
    expect(find.textContaining('Ended before start'), findsOneWidget);
    expect(find.text('Session complete'), findsNothing);
    expect(find.textContaining('Started '), findsNothing);
  });
}

Future<void> _pumpSummary(
  WidgetTester tester, {
  required Size size,
  required SessionSummaryViewData data,
  VoidCallback? onExport,
  VoidCallback? onDone,
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
      home: SessionSummaryScreen(
        data: data,
        onDone: onDone,
        onExportCsv: onExport,
      ),
    ),
  );
  await tester.pump();
}

SessionSummaryViewData _summaryData({
  bool hasCompleteActivityHistory = true,
  bool endedBeforeStart = false,
  SessionEndReason endReason = SessionEndReason.completed,
}) {
  return SessionSummaryViewData(
    planTitle: 'Event run of show',
    startedAt: endedBeforeStart ? null : DateTime.utc(2026, 7, 28, 14),
    endedAt: DateTime.utc(2026, 7, 28, 14, 48, 30),
    endReason: endReason,
    plannedDuration: const Duration(minutes: 45),
    actualDuration: const Duration(minutes: 48, seconds: 30),
    variance: const Duration(minutes: 3, seconds: 30),
    activityCount: 17,
    hasCompleteActivityHistory: hasCompleteActivityHistory,
    steps: <StepSummaryViewData>[
      const StepSummaryViewData(
        title: 'Doors open',
        plannedDuration: Duration(minutes: 5),
        actualDuration: Duration(minutes: 4, seconds: 40),
        variance: Duration(seconds: -20),
        wasCompleted: true,
      ),
      StepSummaryViewData(
        title: 'Opening keynote',
        plannedDuration: const Duration(minutes: 30),
        actualDuration: const Duration(minutes: 33, seconds: 50),
        variance: const Duration(minutes: 3, seconds: 50),
        acknowledgements: <AcknowledgementViewData>[
          AcknowledgementViewData(
            actorDeviceId: 'participant-1',
            displayName: 'Sam Rivera',
            role: SessionRole.participant,
            acknowledgedAt: DateTime(2026, 7, 28, 14, 12),
          ),
        ],
        wasCompleted: true,
      ),
      const StepSummaryViewData(
        title: 'Audience questions',
        plannedDuration: Duration(minutes: 10),
        actualDuration: Duration.zero,
        variance: Duration.zero,
        wasCompleted: false,
      ),
    ],
  );
}
