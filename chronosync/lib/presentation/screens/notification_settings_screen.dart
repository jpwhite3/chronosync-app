import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/haptic_intensity.dart';
import '../../data/services/haptic_service.dart';
import '../../logic/notification_settings_bloc/notification_settings_bloc.dart';
import '../../logic/notification_settings_bloc/notification_settings_event.dart';
import '../../logic/notification_settings_bloc/notification_settings_state.dart';
import 'sound_picker_screen.dart';

/// Global notification and haptic settings screen
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: BlocBuilder<NotificationSettingsBloc, NotificationSettingsState>(
        builder: (context, state) {
          if (state is NotificationSettingsLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is NotificationSettingsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(state.message),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context
                          .read<NotificationSettingsBloc>()
                          .add(const LoadGlobalSettingsEvent());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is NotificationSettingsLoaded) {
            return ListView(
              children: [
                // Permission banner if needed
                if (!state.hasNotificationPermission)
                  _buildPermissionBanner(context),

                // Notifications section
                _buildSectionHeader('Notifications'),
                Semantics(
                  label: 'Enable or disable event completion notifications',
                  child: SwitchListTile(
                    title: const Text('Enable Notifications'),
                    subtitle: const Text(
                        'Receive notifications when events complete'),
                    value: state.settings.notificationsEnabled,
                    onChanged: (value) {
                      context
                          .read<NotificationSettingsBloc>()
                          .add(ToggleNotificationsEvent(value));
                    },
                  ),
                ),
                const Divider(),

                // Haptic section
                _buildSectionHeader('Haptic Feedback'),
                Semantics(
                  label: 'Enable or disable haptic feedback vibration',
                  child: SwitchListTile(
                    title: const Text('Enable Haptic Feedback'),
                    subtitle: const Text('Vibrate when events complete'),
                    value: state.settings.hapticEnabled,
                    onChanged: (value) {
                      context
                          .read<NotificationSettingsBloc>()
                          .add(ToggleHapticEvent(value));
                    },
                  ),
                ),
                if (state.settings.hapticEnabled)
                  _buildHapticIntensitySelector(context, state),
                const Divider(),

                // Sound section
                _buildSectionHeader('Sound'),
                Semantics(
                  label: 'Enable or disable notification sound',
                  child: SwitchListTile(
                    title: const Text('Enable Sound'),
                    subtitle: const Text('Play sound when events complete'),
                    value: state.settings.soundEnabled,
                    onChanged: (value) {
                      context
                          .read<NotificationSettingsBloc>()
                          .add(ToggleSoundEvent(value));
                    },
                  ),
                ),
                if (state.settings.soundEnabled)
                  ListTile(
                    title: const Text('Notification Sound'),
                    subtitle: Text(
                      state.settings.customSoundPath ?? 'System Default',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selectedSound = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (context) => SoundPickerScreen(
                            currentSoundPath: state.settings.customSoundPath,
                          ),
                        ),
                      );
                      
                      if (selectedSound != null && context.mounted) {
                        context
                            .read<NotificationSettingsBloc>()
                            .add(ChangeCustomSoundEvent(selectedSound));
                      }
                    },
                  ),
              ],
            );
          }

          // Initial state
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    return Container(
      color: Colors.orange.shade100,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notification Permission Required',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Grant permission to receive event notifications',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              context
                  .read<NotificationSettingsBloc>()
                  .add(const RequestNotificationPermissionEvent());
            },
            child: const Text('Grant'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildHapticIntensitySelector(
      BuildContext context, NotificationSettingsLoaded state) {
    final hapticService = HapticService();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Haptic Intensity',
                style: TextStyle(fontSize: 16),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  hapticService.triggerHaptic(state.settings.hapticIntensity);
                },
                icon: const Icon(Icons.vibration, size: 16),
                label: const Text('Test'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: HapticIntensity.values
                .where((intensity) => intensity != HapticIntensity.none)
                .map((intensity) {
              final isSelected = state.settings.hapticIntensity == intensity;
              return ChoiceChip(
                label: Text(intensity.displayName),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    context
                        .read<NotificationSettingsBloc>()
                        .add(ChangeHapticIntensityEvent(intensity));
                    // Trigger haptic feedback to preview the intensity
                    hapticService.triggerHaptic(intensity);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
