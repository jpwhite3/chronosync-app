import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/event.dart';
import '../../data/models/haptic_intensity.dart';
import '../../logic/event_notification_settings_bloc/event_notification_settings_bloc.dart';
import '../../logic/event_notification_settings_bloc/event_notification_settings_event.dart';
import '../../logic/event_notification_settings_bloc/event_notification_settings_state.dart';
import '../screens/sound_picker_screen.dart';

/// Widget for managing event-level notification setting overrides
class EventNotificationOverrides extends StatelessWidget {
  final Event event;

  const EventNotificationOverrides({
    super.key,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EventNotificationSettingsBloc()
        ..add(LoadEventSettingsEvent(event)),
      child: BlocBuilder<EventNotificationSettingsBloc,
          EventNotificationSettingsState>(
        builder: (context, state) {
          if (state is EventNotificationSettingsLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is EventNotificationSettingsError) {
            return Center(child: Text('Error: ${state.message}'));
          }

          if (state is EventNotificationSettingsLoaded) {
            final hasOverrides = state.settings.hasOverrides;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with "Use Global" / "Clear Overrides" button
                Row(
                  children: [
                    const Text(
                      'Notification Overrides',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (hasOverrides)
                      TextButton.icon(
                        onPressed: () {
                          context
                              .read<EventNotificationSettingsBloc>()
                              .add(const ClearEventOverridesEvent());
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Use Global'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Override global notification settings for this event',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Notifications override
                _buildOverrideSwitch(
                  context,
                  title: 'Notifications',
                  value: state.settings.notificationsEnabled,
                  onChanged: (value) {
                    context
                        .read<EventNotificationSettingsBloc>()
                        .add(ToggleEventNotificationsEvent(value));
                  },
                ),

                // Haptic override
                _buildOverrideSwitch(
                  context,
                  title: 'Haptic Feedback',
                  value: state.settings.hapticEnabled,
                  onChanged: (value) {
                    context
                        .read<EventNotificationSettingsBloc>()
                        .add(ToggleEventHapticEvent(value));
                  },
                ),

                // Haptic intensity (if haptic override is enabled)
                if (state.settings.hapticEnabled != null &&
                    state.settings.hapticEnabled == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: _buildHapticIntensityOverride(context, state),
                  ),

                // Sound override
                _buildOverrideSwitch(
                  context,
                  title: 'Sound',
                  value: state.settings.soundEnabled,
                  onChanged: (value) {
                    context
                        .read<EventNotificationSettingsBloc>()
                        .add(ToggleEventSoundEvent(value));
                  },
                ),

                // Custom sound (if sound override is enabled)
                if (state.settings.soundEnabled != null &&
                    state.settings.soundEnabled == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Row(
                      children: [
                        Text(
                          'Sound: ${state.settings.customSoundPath ?? "System Default"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final selectedSound = await Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                builder: (context) => SoundPickerScreen(
                                  currentSoundPath: state.settings.customSoundPath,
                                ),
                              ),
                            );
                            
                            if (selectedSound != null && context.mounted) {
                              context
                                  .read<EventNotificationSettingsBloc>()
                                  .add(ChangeEventCustomSoundEvent(selectedSound));
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ),

                // Save button (shown if overrides are set)
                if (hasOverrides)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          context
                              .read<EventNotificationSettingsBloc>()
                              .add(const SaveEventSettingsEvent());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Event settings saved'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('Save Overrides'),
                      ),
                    ),
                  ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildOverrideSwitch(
    BuildContext context, {
    required String title,
    required bool? value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(title)),
        DropdownButton<bool?>(
          value: value,
          items: const [
            DropdownMenuItem(value: null, child: Text('Global')),
            DropdownMenuItem(value: true, child: Text('On')),
            DropdownMenuItem(value: false, child: Text('Off')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildHapticIntensityOverride(
      BuildContext context, EventNotificationSettingsLoaded state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Haptic Intensity',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        DropdownButton<HapticIntensity?>(
          value: state.settings.hapticIntensity,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('Global')),
            ...HapticIntensity.values
                .where((i) => i != HapticIntensity.none)
                .map(
                  (intensity) => DropdownMenuItem(
                    value: intensity,
                    child: Text(intensity.displayName),
                  ),
                ),
          ],
          onChanged: (value) {
            context
                .read<EventNotificationSettingsBloc>()
                .add(ChangeEventHapticIntensityEvent(value));
          },
        ),
      ],
    );
  }
}
