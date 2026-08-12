import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/chrono_status_pill.dart';
import 'package:flutter/material.dart';

enum ChronoTimerSize { compact, standard, hero }

/// A tabular, scalable timer with semantic status and screen-reader output.
class ChronoTimerDisplay extends StatelessWidget {
  const ChronoTimerDisplay({
    required this.label,
    required this.value,
    this.status = ChronoStatus.neutral,
    this.size = ChronoTimerSize.standard,
    this.textAlign = TextAlign.center,
    this.semanticLabel,
    this.liveRegion = false,
    this.showStatus = false,
    super.key,
  });

  final String label;
  final String value;
  final ChronoStatus status;
  final ChronoTimerSize size;
  final TextAlign textAlign;
  final String? semanticLabel;

  /// Enable only for infrequent changes; announcing every timer tick is noisy.
  final bool liveRegion;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      status,
    );
    final CrossAxisAlignment crossAxisAlignment = switch (textAlign) {
      TextAlign.left || TextAlign.start => CrossAxisAlignment.start,
      TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.center,
    };
    final Alignment fittedAlignment = switch (textAlign) {
      TextAlign.left || TextAlign.start => Alignment.centerLeft,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => Alignment.center,
    };
    final WrapAlignment wrapAlignment = switch (textAlign) {
      TextAlign.left || TextAlign.start => WrapAlignment.start,
      TextAlign.right || TextAlign.end => WrapAlignment.end,
      _ => WrapAlignment.center,
    };
    final TextStyle timerStyle = switch (size) {
      ChronoTimerSize.compact => ChronoTypography.timerCompact,
      ChronoTimerSize.standard => ChronoTypography.timerStandard,
      ChronoTimerSize.hero => ChronoTypography.timerHero,
    };
    final Color timerColor = status == ChronoStatus.neutral
        ? context.chronoColors.textPrimary
        : visual.foreground;

    return Semantics(
      label: semanticLabel ?? '$label, $value, ${status.label}',
      liveRegion: liveRegion,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment,
          children: <Widget>[
            Wrap(
              alignment: wrapAlignment,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ChronoSpacing.xs,
              runSpacing: ChronoSpacing.xxs,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: textAlign,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (showStatus) ChronoStatusPill(status: status, compact: true),
              ],
            ),
            const SizedBox(height: ChronoSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: fittedAlignment,
                child: Text(
                  value,
                  maxLines: 1,
                  style: timerStyle.copyWith(color: timerColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
