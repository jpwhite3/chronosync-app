import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChronoBreakpoints', () {
    test('uses the documented responsive boundaries', () {
      expect(ChronoBreakpoints.forWidth(599), ChronoWindowClass.compact);
      expect(ChronoBreakpoints.forWidth(600), ChronoWindowClass.medium);
      expect(ChronoBreakpoints.forWidth(1023), ChronoWindowClass.medium);
      expect(ChronoBreakpoints.forWidth(1024), ChronoWindowClass.expanded);
    });
  });

  group('ChronoTheme', () {
    test('meets AA contrast for semantic status pairs', () {
      const ChronoColors colors = ChronoColors.light;
      final List<(Color, Color)> pairs = <(Color, Color)>[
        (colors.primary, Colors.white),
        (colors.approaching, colors.approachingContainer),
        (colors.due, colors.dueContainer),
        (colors.overtime, colors.overtimeContainer),
        (colors.live, colors.liveContainer),
        (colors.success, colors.successContainer),
        (colors.disconnected, colors.disconnectedContainer),
        (colors.textSecondary, colors.surfaceMuted),
      ];

      for (final (Color foreground, Color background) in pairs) {
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('meets AA non-text contrast for interactive boundaries', () {
      const ChronoColors colors = ChronoColors.light;
      final ThemeData theme = ChronoTheme.light();
      final OutlineInputBorder enabledInputBorder =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      final BorderSide outlinedButtonSide = theme
          .outlinedButtonTheme
          .style!
          .side!
          .resolve(<WidgetState>{})!;

      for (final (Color foreground, Color background) in <(Color, Color)>[
        (enabledInputBorder.borderSide.color, colors.surface),
        (outlinedButtonSide.color, colors.surface),
        (colors.focus, colors.surface),
      ]) {
        expect(_contrastRatio(foreground, background), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('publishes the ChronoSync palette and accessible controls', (
      WidgetTester tester,
    ) async {
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: ChronoTheme.light(),
          home: Builder(
            builder: (BuildContext context) {
              capturedTheme = Theme.of(context);
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      expect(capturedTheme.scaffoldBackgroundColor, ChronoColors.light.canvas);
      expect(capturedTheme.extension<ChronoColors>(), ChronoColors.light);
      expect(
        capturedTheme.filledButtonTheme.style?.minimumSize?.resolve(
          <WidgetState>{},
        ),
        const Size(
          ChronoSpacing.minimumTouchTarget,
          ChronoSpacing.minimumTouchTarget,
        ),
      );
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  final double foregroundLuminance = foreground.computeLuminance();
  final double backgroundLuminance = background.computeLuminance();
  final double lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final double darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
