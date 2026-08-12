import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';

/// A text-and-icon status treatment that never relies on color alone.
class ChronoStatusPill extends StatelessWidget {
  const ChronoStatusPill({
    required this.status,
    this.label,
    this.semanticLabel,
    this.compact = false,
    super.key,
  });

  final ChronoStatus status;
  final String? label;
  final String? semanticLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ChronoStatusVisual visual = ChronoStatusVisual.resolve(
      context,
      status,
    );
    final String resolvedLabel = label ?? status.label;

    return Semantics(
      label: semanticLabel ?? resolvedLabel,
      container: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: visual.background,
            border: Border.all(color: visual.border),
            borderRadius: BorderRadius.circular(ChronoRadii.pill),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 5 : 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  status.icon,
                  size: compact ? 14 : 16,
                  color: visual.foreground,
                ),
                const SizedBox(width: ChronoSpacing.xxs),
                Flexible(
                  child: Text(
                    resolvedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: visual.foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
