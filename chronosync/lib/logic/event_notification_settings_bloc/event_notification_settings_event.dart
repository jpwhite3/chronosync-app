import 'package:equatable/equatable.dart';
import '../../data/models/event.dart';
import '../../data/models/haptic_intensity.dart';

/// Events for EventNotificationSettingsBloc
abstract class EventNotificationSettingsEvent extends Equatable {
  const EventNotificationSettingsEvent();

  @override
  List<Object?> get props => [];
}

/// Load event notification settings
class LoadEventSettingsEvent extends EventNotificationSettingsEvent {
  final Event event;

  const LoadEventSettingsEvent(this.event);

  @override
  List<Object?> get props => [event];
}

/// Toggle event-level notification override
class ToggleEventNotificationsEvent extends EventNotificationSettingsEvent {
  final bool? enabled;

  const ToggleEventNotificationsEvent(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

/// Toggle event-level haptic override
class ToggleEventHapticEvent extends EventNotificationSettingsEvent {
  final bool? enabled;

  const ToggleEventHapticEvent(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

/// Change event-level haptic intensity override
class ChangeEventHapticIntensityEvent extends EventNotificationSettingsEvent {
  final HapticIntensity? intensity;

  const ChangeEventHapticIntensityEvent(this.intensity);

  @override
  List<Object?> get props => [intensity];
}

/// Toggle event-level sound override
class ToggleEventSoundEvent extends EventNotificationSettingsEvent {
  final bool? enabled;

  const ToggleEventSoundEvent(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

/// Change event-level custom sound override
class ChangeEventCustomSoundEvent extends EventNotificationSettingsEvent {
  final String? soundPath;

  const ChangeEventCustomSoundEvent(this.soundPath);

  @override
  List<Object?> get props => [soundPath];
}

/// Clear all event-level overrides (revert to global)
class ClearEventOverridesEvent extends EventNotificationSettingsEvent {
  const ClearEventOverridesEvent();
}

/// Save event settings to repository
class SaveEventSettingsEvent extends EventNotificationSettingsEvent {
  const SaveEventSettingsEvent();
}
