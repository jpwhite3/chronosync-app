import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/presentation/screens/session_setup_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launch options expose availability and dispatch their mode', (
    WidgetTester tester,
  ) async {
    SessionLaunchMode? selectedMode;
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpSetup(
      tester,
      onLaunch: (SessionLaunchMode mode) => selectedMode = mode,
      nearbyAvailable: false,
      onlineAvailable: true,
    );

    expect(
      find.bySemanticsLabel(RegExp(r'Just me.*Available')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Nearby team.*Unavailable')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Online team.*Available')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Online team'));
    await tester.tap(find.text('Online team'));
    expect(selectedMode, SessionLaunchMode.online);
    semantics.dispose();
  });

  testWidgets('launch errors are announced without hiding the options', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpSetup(
      tester,
      onLaunch: (SessionLaunchMode _) {},
      errorMessage: 'Could not start the session. Check your connection.',
    );

    expect(
      find.text('Could not start the session. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text('Just me'), findsOneWidget);
    final SemanticsNode node = tester.getSemantics(
      find.text('Could not start the session. Check your connection.'),
    );
    expect(node.flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });

  testWidgets('compact setup is overflow-free at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpSetup(tester, onLaunch: (SessionLaunchMode _) {}, textScale: 2);

    expect(find.text('Just me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable online mode uses user-facing release copy', (
    WidgetTester tester,
  ) async {
    await _pumpSetup(
      tester,
      onLaunch: (SessionLaunchMode _) {},
      onlineAvailable: false,
    );

    expect(
      find.textContaining('Online rooms aren’t available in this build'),
      findsOneWidget,
    );
    expect(find.textContaining('CHRONOSYNC_RELAY_URL'), findsNothing);
  });
}

Future<void> _pumpSetup(
  WidgetTester tester, {
  required ValueChanged<SessionLaunchMode> onLaunch,
  bool nearbyAvailable = true,
  bool onlineAvailable = true,
  String? errorMessage,
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
      home: SessionSetupScreen(
        plan: _plan(),
        nearbyAvailable: nearbyAvailable,
        onlineAvailable: onlineAvailable,
        onLaunch: onLaunch,
        errorMessage: errorMessage,
      ),
    ),
  );
  await tester.pump();
}

Plan _plan() {
  final DateTime timestamp = DateTime.utc(2026, 1, 1);
  return Plan(
    id: 'plan-1',
    title: 'Opening night run of show',
    plannedStartTime: DateTime.utc(2026, 8, 12, 19),
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
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
