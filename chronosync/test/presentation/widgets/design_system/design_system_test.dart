import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary button is accessible and responds to taps', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      _TestApp(
        child: Center(
          child: ChronoPrimaryButton(
            label: 'Start session',
            icon: Icons.play_arrow_rounded,
            onPressed: () {
              taps += 1;
            },
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(ChronoSpacing.minimumTouchTarget),
    );
    expect(find.bySemanticsLabel('Start session'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
  });

  testWidgets('status pill exposes text and an icon in one semantic label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const _TestApp(
        child: Center(child: ChronoStatusPill(status: ChronoStatus.overtime)),
      ),
    );

    expect(find.text('Overtime'), findsOneWidget);
    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Overtime'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('timer uses tabular figures and scales inside narrow layouts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        child: Center(
          child: SizedBox(
            width: 180,
            child: ChronoTimerDisplay(
              label: 'Time remaining',
              value: '01:24:39',
              status: ChronoStatus.approaching,
              size: ChronoTimerSize.hero,
              showStatus: true,
            ),
          ),
        ),
      ),
    );

    final Text timer = tester.widget<Text>(find.text('01:24:39'));
    expect(timer.style?.fontFeatures, isNotEmpty);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive builder reports its window class', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 700,
          child: ChronoResponsiveBuilder(
            builder:
                (
                  BuildContext context,
                  ChronoWindowClass windowClass,
                  BoxConstraints constraints,
                ) {
                  return Text(windowClass.name);
                },
          ),
        ),
      ),
    );

    expect(find.text('medium'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ChronoTheme.light(),
      home: Scaffold(body: child),
    );
  }
}
