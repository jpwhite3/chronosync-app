import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';

/// A consistent ChronoSync surface, optionally made interactive.
class ChronoCard extends StatelessWidget {
  const ChronoCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(ChronoSpacing.sm),
    this.margin = EdgeInsets.zero,
    this.backgroundColor,
    this.borderColor,
    this.selected = false,
    this.semanticLabel,
    this.autofocus = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool selected;
  final String? semanticLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final ChronoColors colors = context.chronoColors;
    final BorderSide border = BorderSide(
      color: borderColor ?? (selected ? colors.primary : colors.outline),
      width: selected ? 2 : 1,
    );
    final Widget content = Padding(padding: padding, child: child);
    final Widget surface = Material(
      color: backgroundColor ?? colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: selected ? 1 : 0,
      shadowColor: const Color(0x140F1D17),
      shape: RoundedRectangleBorder(
        borderRadius: ChronoRadii.surfaceBorder,
        side: border,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ChronoSpacing.minimumTouchTarget,
              ),
              child: InkWell(
                onTap: onTap,
                autofocus: autofocus,
                borderRadius: ChronoRadii.surfaceBorder,
                child: content,
              ),
            ),
    );

    return Padding(
      padding: margin,
      child: semanticLabel == null
          ? surface
          : Semantics(
              label: semanticLabel,
              container: true,
              explicitChildNodes: true,
              button: onTap != null,
              selected: selected,
              child: surface,
            ),
    );
  }
}
