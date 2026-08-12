import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<Invitation?> showJoinSessionDialog(BuildContext context) {
  return showDialog<Invitation>(
    context: context,
    builder: (BuildContext context) => const JoinSessionDialog(),
  );
}

class JoinSessionDialog extends StatefulWidget {
  const JoinSessionDialog({super.key});

  @override
  State<JoinSessionDialog> createState() => _JoinSessionDialogState();
}

class _JoinSessionDialogState extends State<JoinSessionDialog> {
  final TextEditingController _linkController = TextEditingController();
  bool _isPasting = false;
  String? _error;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(
        ChronoSpacing.md,
        ChronoSpacing.md,
        ChronoSpacing.md,
        0,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        ChronoSpacing.md,
        ChronoSpacing.sm,
        ChronoSpacing.md,
        ChronoSpacing.xs,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        ChronoSpacing.md,
        ChronoSpacing.xs,
        ChronoSpacing.md,
        ChronoSpacing.md,
      ),
      title: Row(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.chronoColors.primaryContainer,
              borderRadius: ChronoRadii.controlBorder,
            ),
            child: Padding(
              padding: const EdgeInsets.all(ChronoSpacing.xs),
              child: Icon(
                Icons.link_rounded,
                color: context.chronoColors.primary,
              ),
            ),
          ),
          const SizedBox(width: ChronoSpacing.sm),
          const Expanded(child: Text('Join a live session')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Paste the invitation link shared by the session host.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: ChronoSpacing.sm),
            TextField(
              controller: _linkController,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Invitation link',
                hintText: 'https://…#invite=…',
                errorText: _error,
                alignLabelWithHint: true,
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: ChronoSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isPasting ? null : _pasteFromClipboard,
                icon: _isPasting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.content_paste_rounded),
                label: Text(_isPasting ? 'Pasting…' : 'Paste from clipboard'),
              ),
            ),
            const SizedBox(height: ChronoSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: context.chronoColors.textSecondary,
                ),
                const SizedBox(width: ChronoSpacing.xs),
                Expanded(
                  child: Text(
                    'No account is required. Invitations are temporary and '
                    'grant access only to this session.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ChronoPrimaryButton(
          label: 'Join session',
          icon: Icons.login_rounded,
          onPressed: _join,
        ),
      ],
    );
  }

  Future<void> _pasteFromClipboard() async {
    setState(() {
      _isPasting = true;
      _error = null;
    });
    try {
      final ClipboardData? clipboard = await Clipboard.getData(
        Clipboard.kTextPlain,
      );
      if (!mounted) {
        return;
      }
      final String value = clipboard?.text?.trim() ?? '';
      if (value.isEmpty) {
        setState(() => _error = 'The clipboard does not contain a link.');
        return;
      }
      _linkController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    } on Object {
      if (mounted) {
        setState(() => _error = 'ChronoSync could not read the clipboard.');
      }
    } finally {
      if (mounted) {
        setState(() => _isPasting = false);
      }
    }
  }

  void _join() {
    final String payload = _linkController.text.trim();
    if (payload.isEmpty) {
      setState(() => _error = 'Paste an invitation link to continue.');
      return;
    }
    try {
      final Invitation invitation = Invitation.fromQrPayload(payload);
      Navigator.pop(context, invitation);
    } on FormatException {
      setState(
        () => _error =
            'That invitation link is not valid. Ask the host to share it again.',
      );
    }
  }
}
