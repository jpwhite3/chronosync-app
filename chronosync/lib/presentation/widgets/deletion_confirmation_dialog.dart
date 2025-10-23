import 'package:flutter/material.dart';
import 'package:chronosync/data/models/series.dart';

class DeletionConfirmationDialog extends StatelessWidget {
  final Series series;

  const DeletionConfirmationDialog({
    super.key,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    // Truncate series title if longer than 50 characters
    String displayTitle = series.title;
    if (displayTitle.length > 50) {
      displayTitle = '${displayTitle.substring(0, 50)}...';
    }

    return AlertDialog(
      title: Text('Delete series "$displayTitle"?'),
      content: Text(
        'This will permanently delete ${series.events.length} event(s).',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
