import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:chronosync/presentation/widgets/design_system/design_system.dart';
import 'package:flutter/material.dart';

class IdentitySettingsScreen extends StatefulWidget {
  const IdentitySettingsScreen({
    required this.repository,
    required this.initialIdentity,
    required this.onIdentityChanged,
    super.key,
  });

  final DeviceIdentitySettingsRepository repository;
  final DeviceIdentity initialIdentity;
  final ValueChanged<DeviceIdentity> onIdentityChanged;

  @override
  State<IdentitySettingsScreen> createState() => _IdentitySettingsScreenState();
}

class _IdentitySettingsScreenState extends State<IdentitySettingsScreen> {
  late final TextEditingController _displayNameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialIdentity.displayName,
    );
  }

  @override
  void didUpdateWidget(IdentitySettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIdentity.displayName !=
        widget.initialIdentity.displayName) {
      _displayNameController.text = widget.initialIdentity.displayName;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = ChronoBreakpoints.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );
    return ListView(
      padding: padding,
      children: <Widget>[
        Text('Settings', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: ChronoSpacing.xxs),
        Text(
          'Your sequences and session history stay on this device.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: ChronoSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ChronoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'This device',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: ChronoSpacing.xs),
                const Text(
                  'No account is required. This name is saved on this device '
                  'and identifies your actions to people in a live session.',
                ),
                const SizedBox(height: ChronoSpacing.sm),
                TextField(
                  controller: _displayNameController,
                  maxLength: 48,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Alex Rivera',
                  ),
                  onSubmitted: (String value) => _save(),
                ),
                const SizedBox(height: ChronoSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ChronoPrimaryButton(
                    label: _saving ? 'Saving…' : 'Save name',
                    icon: Icons.check_rounded,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ChronoSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const ChronoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SettingsLine(
                  icon: Icons.cloud_off_rounded,
                  title: 'Local by default',
                  body:
                      'Sequences never sync automatically. Sharing starts only '
                      'when you create a live session or export a file.',
                ),
                Divider(height: ChronoSpacing.lg),
                _SettingsLine(
                  icon: Icons.lock_outline_rounded,
                  title: 'Private sessions',
                  body:
                      'Invitations expire and include a random encrypted '
                      'session secret. Revoke access by ending the session.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final String displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      _showMessage('Enter a display name.');
      return;
    }
    setState(() => _saving = true);
    try {
      final DeviceIdentity identity = await widget.repository.updateDisplayName(
        displayName,
      );
      widget.onIdentityChanged(identity);
      _showMessage('Display name saved.');
    } on Object {
      _showMessage('Could not save the display name. Try again.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsLine extends StatelessWidget {
  const _SettingsLine({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: context.chronoColors.primary),
        const SizedBox(width: ChronoSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: ChronoSpacing.xxs),
              Text(body),
            ],
          ),
        ),
      ],
    );
  }
}
