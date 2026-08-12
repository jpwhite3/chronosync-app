import 'dart:async';

import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';

enum SessionRecoveryChoice { resume, discard }

Future<SessionRecoveryChoice?> showSessionRecoveryDialog(
  BuildContext context, {
  required LiveSession session,
  required Future<void> Function() onPrepareResume,
}) {
  return showDialog<SessionRecoveryChoice>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => PopScope(
      canPop: false,
      child: _SessionRecoveryDialog(
        session: session,
        onPrepareResume: onPrepareResume,
      ),
    ),
  );
}

class _SessionRecoveryDialog extends StatefulWidget {
  const _SessionRecoveryDialog({
    required this.session,
    required this.onPrepareResume,
  });

  final LiveSession session;
  final Future<void> Function() onPrepareResume;

  @override
  State<_SessionRecoveryDialog> createState() => _SessionRecoveryDialogState();
}

class _SessionRecoveryDialogState extends State<_SessionRecoveryDialog> {
  bool _preparing = false;
  bool _prepareFailed = false;

  @override
  Widget build(BuildContext context) {
    final LiveSession session = widget.session;
    return AlertDialog(
      scrollable: true,
      icon: Icon(
        Icons.restore_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: 32,
      ),
      title: const Text('Resume solo session?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              session.planSnapshot.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: ChronoSpacing.xs),
            Row(
              children: <Widget>[
                Icon(
                  Icons.playlist_play_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: ChronoSpacing.xs),
                Expanded(
                  child: Text(
                    session.currentStep.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ChronoSpacing.sm),
            Text(_recoveryExplanation(session.status)),
            if (_prepareFailed) ...<Widget>[
              const SizedBox(height: ChronoSpacing.sm),
              Text(
                'ChronoSync could not prepare the session. Try again or '
                'discard it.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _preparing
              ? null
              : () => Navigator.pop(context, SessionRecoveryChoice.discard),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            minimumSize: const Size(44, 44),
          ),
          child: const Text('Discard session'),
        ),
        FilledButton.icon(
          onPressed: _preparing ? null : () => unawaited(_resume()),
          icon: _preparing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: const Text('Resume'),
        ),
      ],
    );
  }

  Future<void> _resume() async {
    setState(() {
      _preparing = true;
      _prepareFailed = false;
    });
    try {
      await widget.onPrepareResume();
      if (mounted) {
        Navigator.pop(context, SessionRecoveryChoice.resume);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _preparing = false;
          _prepareFailed = true;
        });
      }
    }
  }
}

String _recoveryExplanation(LiveSessionStatus status) {
  return switch (status) {
    LiveSessionStatus.waiting =>
      'This solo session was ready but had not started. It will reopen at '
          'the first step.',
    LiveSessionStatus.running =>
      'ChronoSync closed while this timer was running. Time continued while '
          'the app was closed.',
    LiveSessionStatus.paused =>
      'ChronoSync closed while this timer was paused. It will reopen paused.',
    LiveSessionStatus.ended =>
      'This session has already ended and cannot be resumed.',
  };
}
