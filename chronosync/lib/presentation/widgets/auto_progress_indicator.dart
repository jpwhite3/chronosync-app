import 'package:flutter/material.dart';

/// Visual indicator shown when auto-progression occurs
///
/// Displays a brief SnackBar notification to inform the user
/// that the timer has automatically advanced to the next event.
class AutoProgressIndicator {
  /// Show the auto-progress indicator using a SnackBar
  static void show(BuildContext context, {String? nextEventTitle}) {
    final message = nextEventTitle != null
        ? 'Auto-advancing to: $nextEventTitle'
        : 'Auto-advancing...';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.play_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
