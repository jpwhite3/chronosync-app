import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/repositories/notification_settings_repository.dart';
import 'notification_settings_event.dart';
import 'notification_settings_state.dart';

/// BLoC for managing global notification and haptic settings
class NotificationSettingsBloc
    extends Bloc<NotificationSettingsEvent, NotificationSettingsState> {
  final NotificationSettingsRepository _repository;

  NotificationSettingsBloc({
    required NotificationSettingsRepository repository,
  })  : _repository = repository,
        super(const NotificationSettingsInitial()) {
    on<LoadGlobalSettingsEvent>(_onLoadGlobalSettings);
    on<ToggleNotificationsEvent>(_onToggleNotifications);
    on<ToggleHapticEvent>(_onToggleHaptic);
    on<ChangeHapticIntensityEvent>(_onChangeHapticIntensity);
    on<ToggleSoundEvent>(_onToggleSound);
    on<ChangeCustomSoundEvent>(_onChangeCustomSound);
    on<RequestNotificationPermissionEvent>(_onRequestNotificationPermission);
  }

  Future<void> _onLoadGlobalSettings(
    LoadGlobalSettingsEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    emit(const NotificationSettingsLoading());
    try {
      final settings = await _repository.getGlobalSettings();
      final hasPermission = await _checkNotificationPermission();
      emit(NotificationSettingsLoaded(
        settings: settings,
        hasNotificationPermission: hasPermission,
      ));
    } catch (e) {
      emit(NotificationSettingsError('Failed to load settings: $e'));
    }
  }

  Future<void> _onToggleNotifications(
    ToggleNotificationsEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    if (state is! NotificationSettingsLoaded) return;

    final currentState = state as NotificationSettingsLoaded;
    final updatedSettings =
        currentState.settings.copyWith(notificationsEnabled: event.enabled);

    try {
      await _repository.saveGlobalSettings(updatedSettings);
      emit(currentState.copyWith(settings: updatedSettings));
    } catch (e) {
      emit(NotificationSettingsError('Failed to save settings: $e'));
    }
  }

  Future<void> _onToggleHaptic(
    ToggleHapticEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    if (state is! NotificationSettingsLoaded) return;

    final currentState = state as NotificationSettingsLoaded;
    final updatedSettings =
        currentState.settings.copyWith(hapticEnabled: event.enabled);

    try {
      await _repository.saveGlobalSettings(updatedSettings);
      emit(currentState.copyWith(settings: updatedSettings));
    } catch (e) {
      emit(NotificationSettingsError('Failed to save settings: $e'));
    }
  }

  Future<void> _onChangeHapticIntensity(
    ChangeHapticIntensityEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    if (state is! NotificationSettingsLoaded) return;

    final currentState = state as NotificationSettingsLoaded;
    final updatedSettings =
        currentState.settings.copyWith(hapticIntensity: event.intensity);

    try {
      await _repository.saveGlobalSettings(updatedSettings);
      emit(currentState.copyWith(settings: updatedSettings));
    } catch (e) {
      emit(NotificationSettingsError('Failed to save settings: $e'));
    }
  }

  Future<void> _onToggleSound(
    ToggleSoundEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    if (state is! NotificationSettingsLoaded) return;

    final currentState = state as NotificationSettingsLoaded;
    final updatedSettings =
        currentState.settings.copyWith(soundEnabled: event.enabled);

    try {
      await _repository.saveGlobalSettings(updatedSettings);
      emit(currentState.copyWith(settings: updatedSettings));
    } catch (e) {
      emit(NotificationSettingsError('Failed to save settings: $e'));
    }
  }

  Future<void> _onChangeCustomSound(
    ChangeCustomSoundEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    if (state is! NotificationSettingsLoaded) return;

    final currentState = state as NotificationSettingsLoaded;
    final updatedSettings =
        currentState.settings.copyWith(customSoundPath: event.soundPath);

    try {
      await _repository.saveGlobalSettings(updatedSettings);
      emit(currentState.copyWith(settings: updatedSettings));
    } catch (e) {
      emit(NotificationSettingsError('Failed to save settings: $e'));
    }
  }

  Future<void> _onRequestNotificationPermission(
    RequestNotificationPermissionEvent event,
    Emitter<NotificationSettingsState> emit,
  ) async {
    if (state is! NotificationSettingsLoaded) return;

    final hasPermission = await _requestNotificationPermission();

    final currentState = state as NotificationSettingsLoaded;
    emit(currentState.copyWith(hasNotificationPermission: hasPermission));
  }

  /// Check if notification permission is granted
  Future<bool> _checkNotificationPermission() async {
    // permission_handler only works on iOS and Android
    if (kIsWeb || Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return true; // Desktop/web don't require runtime permissions
    }

    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      // If permission check fails, assume granted (graceful degradation)
      debugPrint('Permission check failed: $e');
      return true;
    }
  }

  /// Request notification permission
  Future<bool> _requestNotificationPermission() async {
    // permission_handler only works on iOS and Android
    if (kIsWeb || Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return true; // Desktop/web don't require runtime permissions
    }

    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      // If permission request fails, assume granted (graceful degradation)
      debugPrint('Permission request failed: $e');
      return true;
    }
  }
}
