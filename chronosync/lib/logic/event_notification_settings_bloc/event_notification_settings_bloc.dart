import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/event_notification_settings.dart';
import 'event_notification_settings_event.dart';
import 'event_notification_settings_state.dart';

/// BLoC for managing event-level notification settings overrides
class EventNotificationSettingsBloc extends Bloc<
    EventNotificationSettingsEvent, EventNotificationSettingsState> {
  EventNotificationSettingsBloc()
      : super(const EventNotificationSettingsInitial()) {
    on<LoadEventSettingsEvent>(_onLoadEventSettings);
    on<ToggleEventNotificationsEvent>(_onToggleEventNotifications);
    on<ToggleEventHapticEvent>(_onToggleEventHaptic);
    on<ChangeEventHapticIntensityEvent>(_onChangeEventHapticIntensity);
    on<ToggleEventSoundEvent>(_onToggleEventSound);
    on<ChangeEventCustomSoundEvent>(_onChangeEventCustomSound);
    on<ClearEventOverridesEvent>(_onClearEventOverrides);
    on<SaveEventSettingsEvent>(_onSaveEventSettings);
  }

  Future<void> _onLoadEventSettings(
    LoadEventSettingsEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    emit(const EventNotificationSettingsLoading());
    try {
      final EventNotificationSettings settings =
          event.event.notificationSettings ?? EventNotificationSettings.useGlobal();
      emit(EventNotificationSettingsLoaded(
        event: event.event,
        settings: settings,
      ));
    } catch (e) {
      emit(EventNotificationSettingsError('Failed to load settings: $e'));
    }
  }

  Future<void> _onToggleEventNotifications(
    ToggleEventNotificationsEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;
    final EventNotificationSettings updatedSettings = currentState.settings.copyWith(
      notificationsEnabled: event.enabled,
    );

    emit(currentState.copyWith(settings: updatedSettings));
  }

  Future<void> _onToggleEventHaptic(
    ToggleEventHapticEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;
    final EventNotificationSettings updatedSettings = currentState.settings.copyWith(
      hapticEnabled: event.enabled,
    );

    emit(currentState.copyWith(settings: updatedSettings));
  }

  Future<void> _onChangeEventHapticIntensity(
    ChangeEventHapticIntensityEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;
    final EventNotificationSettings updatedSettings = currentState.settings.copyWith(
      hapticIntensity: event.intensity,
    );

    emit(currentState.copyWith(settings: updatedSettings));
  }

  Future<void> _onToggleEventSound(
    ToggleEventSoundEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;
    final EventNotificationSettings updatedSettings = currentState.settings.copyWith(
      soundEnabled: event.enabled,
    );

    emit(currentState.copyWith(settings: updatedSettings));
  }

  Future<void> _onChangeEventCustomSound(
    ChangeEventCustomSoundEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;
    final EventNotificationSettings updatedSettings = currentState.settings.copyWith(
      customSoundPath: event.soundPath,
    );

    emit(currentState.copyWith(settings: updatedSettings));
  }

  Future<void> _onClearEventOverrides(
    ClearEventOverridesEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;
    final EventNotificationSettings clearedSettings = EventNotificationSettings.useGlobal();

    emit(currentState.copyWith(settings: clearedSettings));
  }

  Future<void> _onSaveEventSettings(
    SaveEventSettingsEvent event,
    Emitter<EventNotificationSettingsState> emit,
  ) async {
    if (state is! EventNotificationSettingsLoaded) return;

    final EventNotificationSettingsLoaded currentState = state as EventNotificationSettingsLoaded;

    try {
      // Update the event's notification settings
      currentState.event.notificationSettings = currentState.settings.hasOverrides
          ? currentState.settings
          : null;

      // Save the event to Hive
      await currentState.event.save();
    } catch (e) {
      emit(EventNotificationSettingsError('Failed to save settings: $e'));
    }
  }
}
