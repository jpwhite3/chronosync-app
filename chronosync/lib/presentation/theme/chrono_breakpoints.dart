import 'package:chronosync/presentation/theme/chrono_spacing.dart';
import 'package:flutter/widgets.dart';

enum ChronoWindowClass { compact, medium, expanded }

/// Responsive thresholds shared by plans, live sessions, and displays.
abstract final class ChronoBreakpoints {
  static const double medium = 600;
  static const double expanded = 1024;
  static const double maximumContentWidth = 1440;

  static ChronoWindowClass forWidth(double width) {
    if (width < medium) {
      return ChronoWindowClass.compact;
    }
    if (width < expanded) {
      return ChronoWindowClass.medium;
    }
    return ChronoWindowClass.expanded;
  }

  static ChronoWindowClass of(BuildContext context) {
    return forWidth(MediaQuery.sizeOf(context).width);
  }

  static EdgeInsets pagePaddingFor(double width) {
    return switch (forWidth(width)) {
      ChronoWindowClass.compact => const EdgeInsets.all(ChronoSpacing.sm),
      ChronoWindowClass.medium => const EdgeInsets.all(ChronoSpacing.md),
      ChronoWindowClass.expanded => const EdgeInsets.symmetric(
        horizontal: ChronoSpacing.lg,
        vertical: ChronoSpacing.md,
      ),
    };
  }
}

typedef ChronoResponsiveWidgetBuilder =
    Widget Function(
      BuildContext context,
      ChronoWindowClass windowClass,
      BoxConstraints constraints,
    );

/// Builds one responsive composition without scattering width checks.
class ChronoResponsiveBuilder extends StatelessWidget {
  const ChronoResponsiveBuilder({required this.builder, super.key});

  final ChronoResponsiveWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return builder(
          context,
          ChronoBreakpoints.forWidth(availableWidth),
          constraints,
        );
      },
    );
  }
}
