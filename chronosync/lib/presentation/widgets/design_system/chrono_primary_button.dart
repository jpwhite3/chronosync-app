import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';

/// The primary call-to-action used for starts, joins, and live controls.
class ChronoPrimaryButton extends StatelessWidget {
  const ChronoPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.semanticLabel,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;
  final String? semanticLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final String resolvedSemanticLabel = isLoading
        ? '${semanticLabel ?? label}, in progress'
        : semanticLabel ?? label;
    final Widget button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      autofocus: autofocus,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (isLoading)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          if (isLoading || icon != null)
            const SizedBox(width: ChronoSpacing.xs),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

    return Semantics(
      label: resolvedSemanticLabel,
      button: true,
      enabled: !isLoading && onPressed != null,
      child: ExcludeSemantics(
        child: expand
            ? SizedBox(width: double.infinity, child: button)
            : button,
      ),
    );
  }
}
