import 'package:equatable/equatable.dart';
import '../../data/models/haptic_intensity.dart';

/// Events for NotificationSettingsBloc
abstract class NotificationSettingsEvent extends Equatable {
  const NotificationSettingsEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Load global settings from repository
class LoadGlobalSettingsEvent extends NotificationSettingsEvent {
  const LoadGlobalSettingsEvent();
}

/// Toggle notifications on/off
class ToggleNotificationsEvent extends NotificationSettingsEvent {
  final bool enabled;

  const ToggleNotificationsEvent(this.enabled);

  @override
  List<Object?> get props => <Object?>[enabled];
}

/// Toggle haptic feedback on/off
class ToggleHapticEvent extends NotificationSettingsEvent {
  final bool enabled;

  const ToggleHapticEvent(this.enabled);

  @override
  List<Object?> get props => <Object?>[enabled];
}

/// Change haptic intensity
class ChangeHapticIntensityEvent extends NotificationSettingsEvent {
  final HapticIntensity intensity;

  const ChangeHapticIntensityEvent(this.intensity);

  @override
  List<Object?> get props => <Object?>[intensity];
}

/// Toggle notification sound on/off
class ToggleSoundEvent extends NotificationSettingsEvent {
  final bool enabled;

  const ToggleSoundEvent(this.enabled);

  @override
  List<Object?> get props => <Object?>[enabled];
}

/// Change custom notification sound
class ChangeCustomSoundEvent extends NotificationSettingsEvent {
  final String? soundPath;

  const ChangeCustomSoundEvent(this.soundPath);

  @override
  List<Object?> get props => <Object?>[soundPath];
}

/// Request notification permission (triggers permission dialog)
class RequestNotificationPermissionEvent extends NotificationSettingsEvent {
  const RequestNotificationPermissionEvent();
}
