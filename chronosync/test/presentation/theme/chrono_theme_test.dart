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
    test('publishes the TAS-inspired signature palette', () {
      expect(ChronoColors.light.canvas, const Color(0xFFF4F5FA));
      expect(ChronoColors.light.surface, const Color(0xFFFFFFFF));
      expect(ChronoColors.light.primary, const Color(0xFF1E3A8A));
      expect(ChronoColors.light.focus, const Color(0xFF6366F1));
      expect(ChronoColors.light.approaching, const Color(0xFF765300));
      expect(ChronoColors.light.overtime, const Color(0xFF842331));

      expect(ChronoColors.dark.canvas, const Color(0xFF050608));
      expect(ChronoColors.dark.surface, const Color(0xFF0B0C0E));
      expect(ChronoColors.dark.primary, const Color(0xFF666AF5));
      expect(ChronoColors.dark.focus, const Color(0xFF82AAFF));
      expect(ChronoColors.dark.approaching, const Color(0xFFFFCB6B));
      expect(ChronoColors.dark.overtime, const Color(0xFFFF8994));
    });

    test('uses the bundled Inter family throughout the theme', () {
      for (final ThemeData theme in <ThemeData>[
        ChronoTheme.light(),
        ChronoTheme.dark(),
      ]) {
        expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
        expect(theme.textTheme.headlineLarge?.fontFamily, 'Inter');
      }
    });

    test('meets AA contrast for semantic status pairs', () {
      final List<(String, ChronoColors, ThemeData)> themes =
          <(String, ChronoColors, ThemeData)>[
            ('light', ChronoColors.light, ChronoTheme.light()),
            ('dark', ChronoColors.dark, ChronoTheme.dark()),
          ];

      for (final (String name, ChronoColors colors, ThemeData theme)
          in themes) {
        final List<(Color, Color)> pairs = <(Color, Color)>[
          (theme.colorScheme.onPrimary, colors.primary),
          (theme.colorScheme.onSecondary, theme.colorScheme.secondary),
          (
            theme.colorScheme.onSecondaryContainer,
            theme.colorScheme.secondaryContainer,
          ),
          (theme.colorScheme.onTertiary, theme.colorScheme.tertiary),
          (theme.colorScheme.onError, theme.colorScheme.error),
          (colors.onPrimaryContainer, colors.primaryContainer),
          (colors.textPrimary, colors.surface),
          (colors.textPrimary, colors.canvas),
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
            reason: '$name semantic colors must remain legible',
          );
        }
      }
    });

    test('meets AA non-text contrast for interactive boundaries', () {
      for (final ThemeData theme in <ThemeData>[
        ChronoTheme.light(),
        ChronoTheme.dark(),
      ]) {
        final ChronoColors colors = theme.extension<ChronoColors>()!;
        final OutlineInputBorder enabledInputBorder =
            theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
        final BorderSide outlinedButtonSide = theme
            .outlinedButtonTheme
            .style!
            .side!
            .resolve(<WidgetState>{})!;

        for (final (Color foreground, Color background) in <(Color, Color)>[
          (colors.outline, colors.surface),
          (colors.outline, colors.canvas),
          (enabledInputBorder.borderSide.color, colors.surface),
          (outlinedButtonSide.color, colors.surface),
          (colors.focus, colors.surface),
        ]) {
          expect(
            _contrastRatio(foreground, background),
            greaterThanOrEqualTo(3),
          );
        }
      }
    });

    test('maps Material surface roles to explicit neutral palette colors', () {
      for (final ThemeData theme in <ThemeData>[
        ChronoTheme.light(),
        ChronoTheme.dark(),
      ]) {
        final ChronoColors colors = theme.extension<ChronoColors>()!;
        final ColorScheme scheme = theme.colorScheme;

        expect(scheme.onSurfaceVariant, colors.textSecondary);
        expect(scheme.outline, colors.outlineStrong);
        expect(scheme.outlineVariant, colors.outline);
        expect(
          scheme.surfaceContainerLowest,
          scheme.brightness == Brightness.dark ? colors.canvas : colors.surface,
        );
        expect(
          scheme.surfaceContainerLow,
          scheme.brightness == Brightness.dark ? colors.surface : colors.canvas,
        );
        expect(scheme.surfaceContainerHigh, colors.surfaceMuted);
        expect(scheme.surfaceTint, Colors.transparent);
      }
    });

    test('orders Material surface containers by elevation', () {
      for (final ThemeData theme in <ThemeData>[
        ChronoTheme.light(),
        ChronoTheme.dark(),
      ]) {
        final ColorScheme scheme = theme.colorScheme;
        final List<double> luminances = <Color>[
          scheme.surfaceContainerLowest,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.surfaceContainerHighest,
        ].map((Color color) => color.computeLuminance()).toList();

        for (int index = 1; index < luminances.length; index += 1) {
          if (scheme.brightness == Brightness.dark) {
            expect(luminances[index], greaterThan(luminances[index - 1]));
          } else {
            expect(luminances[index], lessThan(luminances[index - 1]));
          }
        }
      }
    });

    test('publishes a dark semantic palette', () {
      final ThemeData theme = ChronoTheme.dark();

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ChronoColors.dark.canvas);
      expect(theme.extension<ChronoColors>(), ChronoColors.dark);
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
