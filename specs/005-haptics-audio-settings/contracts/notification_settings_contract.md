# Notification Settings Contract

**Feature**: 005-haptics-audio-settings  
**Date**: October 24, 2025  
**Type**: Internal Component Interfaces

## Overview

This contract defines the interfaces between data layer (repositories), business logic layer (BLoCs), and presentation layer (UI widgets) for the haptics and audio settings feature. These are internal Dart interfaces, not REST/GraphQL APIs.

---

## Repository Layer Contracts

### NotificationSettingsRepository

**Purpose**: Manages persistence of global and event-level notification settings using Hive.

**Interface**:

```dart
abstract class NotificationSettingsRepository {
  /// Loads global notification settings from persistent storage.
  /// Returns default settings if none exist.
  /// Never throws - returns defaults on error.
  Future<GlobalNotificationSettings> getGlobalSettings();
  
  /// Saves global notification settings to persistent storage.
  /// Throws [StorageException] if save fails after retries.
  Future<void> saveGlobalSettings(GlobalNotificationSettings settings);
  
  /// Loads notification settings for a specific event.
  /// Returns null if event has no custom settings (use defaults).
  /// Never throws - returns null on error.
  Future<EventNotificationSettings?> getEventSettings(String eventId);
  
  /// Saves notification settings for a specific event.
  /// Throws [StorageException] if save fails after retries.
  /// @param eventId The unique identifier of the event
  /// @param settings The notification settings to save
  Future<void> saveEventSettings(
    String eventId,
    EventNotificationSettings settings,
  );
  
  /// Removes custom settings for an event (revert to defaults).
  /// Throws [StorageException] if deletion fails after retries.
  Future<void> resetEventSettingsToDefaults(String eventId);
  
  /// Resolves the effective notification settings for an event.
  /// Combines event-specific overrides with global defaults.
  /// @param eventId The event to resolve settings for
  /// @return Resolved settings with all nulls replaced by global defaults
  Future<ResolvedNotificationSettings> resolveSettings(String eventId);
}
```

**Error Handling**:
- `StorageException`: Thrown when Hive operations fail after 3 retries
- Never return null for `getGlobalSettings()` - always provide defaults

**Default Values**:
```dart
GlobalNotificationSettings.defaults() => GlobalNotificationSettings(
  defaultSoundId: null, // system default
  defaultSoundName: 'System Default',
  hapticEnabled: true,
  defaultHapticIntensity: HapticIntensity.medium,
);
```

---

### DeviceAudioRepository

**Purpose**: Interfaces with platform-specific audio and haptic APIs.

**Interface**:

```dart
abstract class DeviceAudioRepository {
  /// Retrieves list of device's built-in sounds.
  /// Retries on permission/access errors with exponential backoff.
  /// @param retryCount Number of retry attempts (default: 3)
  /// @throws [AudioPermissionException] if access denied after retries
  /// @throws [PlatformException] for other platform-specific errors
  Future<List<DeviceSound>> getSystemSounds({int retryCount = 3});
  
  /// Checks if device supports haptic feedback.
  /// Cached after first call (device capability doesn't change).
  /// Never throws - returns false on error.
  Future<bool> hasHapticSupport();
  
  /// Checks if device supports amplitude control for haptics (Android).
  /// Always returns false on iOS (uses impact styles instead).
  /// Never throws - returns false on error.
  Future<bool> hasAmplitudeControl();
  
  /// Triggers haptic feedback with specified intensity.
  /// No-op if device doesn't support haptics.
  /// Maps intensity to platform-specific values.
  /// Never throws - logs error and returns silently.
  Future<void> triggerHaptic(HapticIntensity intensity);
  
  /// Plays a sound preview for user selection.
  /// @param soundId The platform-specific sound identifier
  /// @throws [SoundNotFoundException] if sound doesn't exist
  /// @throws [AudioPlaybackException] if playback fails
  Future<void> previewSound(String soundId);
  
  /// Stops currently playing sound preview.
  /// No-op if no sound is playing.
  /// Never throws.
  Future<void> stopPreview();
  
  /// Checks current notification permission status.
  /// Never throws - returns denied on error.
  Future<PermissionStatus> checkNotificationPermission();
  
  /// Requests notification permission from user.
  /// Shows system permission dialog.
  /// Returns true if granted, false otherwise.
  /// Never throws.
  Future<bool> requestNotificationPermission();
  
  /// Retrieves URI for a sound (for notification scheduling).
  /// @param soundId The sound identifier
  /// @return Platform-specific URI or null for default sound
  /// @throws [SoundNotFoundException] if sound doesn't exist
  Future<String?> getSoundUri(String soundId);
}
```

**Error Types**:
```dart
class AudioPermissionException implements Exception {
  final String message;
  AudioPermissionException(this.message);
}

class SoundNotFoundException implements Exception {
  final String soundId;
  SoundNotFoundException(this.soundId);
}

class AudioPlaybackException implements Exception {
  final String message;
  AudioPlaybackException(this.message);
}

class StorageException implements Exception {
  final String message;
  StorageException(this.message);
}
```

**Permission Status Enum**:
```dart
enum PermissionStatus {
  granted,      // Permission granted
  denied,       // Permission denied (can request again)
  permanentlyDenied, // User selected "don't ask again"
  restricted,   // iOS: parental controls, Android: admin policy
}
```

---

### TimerNotificationService

**Purpose**: Schedules and delivers timer completion notifications using OS notification system.

**Interface**:

```dart
abstract class TimerNotificationService {
  /// Schedules a notification for timer completion.
  /// Uses flutter_local_notifications to register with OS.
  /// @param timerId Unique identifier for this timer
  /// @param completionTime When the timer completes
  /// @param settings Resolved notification settings (no nulls)
  /// @throws [NotificationScheduleException] if scheduling fails
  Future<void> scheduleTimerNotification({
    required int timerId,
    required DateTime completionTime,
    required ResolvedNotificationSettings settings,
  });
  
  /// Cancels a scheduled timer notification.
  /// No-op if notification doesn't exist.
  /// Never throws.
  Future<void> cancelTimerNotification(int timerId);
  
  /// Cancels all scheduled notifications.
  /// Useful for app reset/logout scenarios.
  /// Never throws.
  Future<void> cancelAllNotifications();
  
  /// Checks if a specific timer notification is scheduled.
  /// @return true if notification exists in pending list
  Future<bool> isNotificationScheduled(int timerId);
  
  /// Immediately delivers a notification (for foreground use).
  /// Used when timer completes while app is in foreground.
  /// @param timerId The timer identifier
  /// @param settings Resolved notification settings
  /// Never throws - logs error on failure.
  Future<void> deliverImmediateNotification({
    required int timerId,
    required ResolvedNotificationSettings settings,
  });
}
```

**Error Types**:
```dart
class NotificationScheduleException implements Exception {
  final String message;
  final DateTime attemptedTime;
  NotificationScheduleException(this.message, this.attemptedTime);
}
```

---

## BLoC Layer Contracts

### NotificationSettingsBloc

**Purpose**: Manages state for notification settings screens and forms.

**Events**:

```dart
abstract class NotificationSettingsEvent extends Equatable {}

/// Load global notification settings from repository
class LoadNotificationSettings extends NotificationSettingsEvent {
  @override
  List<Object?> get props => [];
}

/// Update global default audio sound
class UpdateGlobalSound extends NotificationSettingsEvent {
  final String? soundId;
  final String? soundName;
  
  UpdateGlobalSound({this.soundId, this.soundName});
  
  @override
  List<Object?> get props => [soundId, soundName];
}

/// Update global haptic enabled state
class UpdateGlobalHapticEnabled extends NotificationSettingsEvent {
  final bool enabled;
  
  UpdateGlobalHapticEnabled(this.enabled);
  
  @override
  List<Object?> get props => [enabled];
}

/// Update global haptic intensity
class UpdateGlobalHapticIntensity extends NotificationSettingsEvent {
  final HapticIntensity intensity;
  
  UpdateGlobalHapticIntensity(this.intensity);
  
  @override
  List<Object?> get props => [intensity];
}

/// Load settings for a specific event
class LoadEventSettings extends NotificationSettingsEvent {
  final String eventId;
  
  LoadEventSettings(this.eventId);
  
  @override
  List<Object?> get props => [eventId];
}

/// Update event chime enabled state
class UpdateEventChimeEnabled extends NotificationSettingsEvent {
  final String eventId;
  final bool enabled;
  
  UpdateEventChimeEnabled(this.eventId, this.enabled);
  
  @override
  List<Object?> get props => [eventId, enabled];
}

/// Update event custom sound
class UpdateEventCustomSound extends NotificationSettingsEvent {
  final String eventId;
  final String? soundId;
  final String? soundName;
  
  UpdateEventCustomSound(this.eventId, {this.soundId, this.soundName});
  
  @override
  List<Object?> get props => [eventId, soundId, soundName];
}

/// Update event custom haptic settings
class UpdateEventCustomHaptic extends NotificationSettingsEvent {
  final String eventId;
  final bool? enabled;
  final HapticIntensity? intensity;
  
  UpdateEventCustomHaptic(this.eventId, {this.enabled, this.intensity});
  
  @override
  List<Object?> get props => [eventId, enabled, intensity];
}

/// Reset event settings to global defaults
class ResetEventSettings extends NotificationSettingsEvent {
  final String eventId;
  
  ResetEventSettings(this.eventId);
  
  @override
  List<Object?> get props => [eventId];
}

/// Refresh device sounds list
class RefreshDeviceSounds extends NotificationSettingsEvent {
  @override
  List<Object?> get props => [];
}
```

**States**:

```dart
abstract class NotificationSettingsState extends Equatable {}

/// Initial state before any data loaded
class NotificationSettingsInitial extends NotificationSettingsState {
  @override
  List<Object?> get props => [];
}

/// Loading global or event settings
class NotificationSettingsLoading extends NotificationSettingsState {
  @override
  List<Object?> get props => [];
}

/// Settings loaded successfully
class NotificationSettingsLoaded extends NotificationSettingsState {
  final GlobalNotificationSettings globalSettings;
  final EventNotificationSettings? eventSettings;
  final String? currentEventId;
  final bool hasHapticSupport;
  final List<DeviceSound> availableSounds;
  final bool isRefreshing;
  
  NotificationSettingsLoaded({
    required this.globalSettings,
    this.eventSettings,
    this.currentEventId,
    required this.hasHapticSupport,
    required this.availableSounds,
    this.isRefreshing = false,
  });
  
  @override
  List<Object?> get props => [
    globalSettings,
    eventSettings,
    currentEventId,
    hasHapticSupport,
    availableSounds,
    isRefreshing,
  ];
  
  /// Helper to check if event has custom sound
  bool get hasCustomSound => eventSettings?.customSoundId != null;
  
  /// Helper to check if event has custom haptics
  bool get hasCustomHaptics => eventSettings?.customHapticEnabled != null;
  
  /// Copy with for state updates
  NotificationSettingsLoaded copyWith({
    GlobalNotificationSettings? globalSettings,
    EventNotificationSettings? eventSettings,
    String? currentEventId,
    bool? hasHapticSupport,
    List<DeviceSound>? availableSounds,
    bool? isRefreshing,
  }) {
    return NotificationSettingsLoaded(
      globalSettings: globalSettings ?? this.globalSettings,
      eventSettings: eventSettings ?? this.eventSettings,
      currentEventId: currentEventId ?? this.currentEventId,
      hasHapticSupport: hasHapticSupport ?? this.hasHapticSupport,
      availableSounds: availableSounds ?? this.availableSounds,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

/// Error loading or saving settings
class NotificationSettingsError extends NotificationSettingsState {
  final String message;
  final NotificationSettingsState? previousState;
  
  NotificationSettingsError(this.message, [this.previousState]);
  
  @override
  List<Object?> get props => [message, previousState];
}
```

---

### TimerNotificationBloc

**Purpose**: Manages timer notification scheduling and delivery lifecycle.

**Events**:

```dart
abstract class TimerNotificationEvent extends Equatable {}

/// Schedule notification for timer completion
class ScheduleTimerNotification extends TimerNotificationEvent {
  final int timerId;
  final DateTime completionTime;
  final String eventId;
  
  ScheduleTimerNotification({
    required this.timerId,
    required this.completionTime,
    required this.eventId,
  });
  
  @override
  List<Object?> get props => [timerId, completionTime, eventId];
}

/// Cancel scheduled notification
class CancelTimerNotification extends TimerNotificationEvent {
  final int timerId;
  
  CancelTimerNotification(this.timerId);
  
  @override
  List<Object?> get props => [timerId];
}

/// Timer completed, deliver notification immediately (foreground)
class DeliverTimerNotification extends TimerNotificationEvent {
  final int timerId;
  final String eventId;
  
  DeliverTimerNotification({
    required this.timerId,
    required this.eventId,
  });
  
  @override
  List<Object?> get props => [timerId, eventId];
}

/// Check if notification is scheduled
class CheckNotificationStatus extends TimerNotificationEvent {
  final int timerId;
  
  CheckNotificationStatus(this.timerId);
  
  @override
  List<Object?> get props => [timerId];
}
```

**States**:

```dart
abstract class TimerNotificationState extends Equatable {}

/// No notifications scheduled
class TimerNotificationIdle extends TimerNotificationState {
  @override
  List<Object?> get props => [];
}

/// Notification scheduled successfully
class TimerNotificationScheduled extends TimerNotificationState {
  final int timerId;
  final DateTime completionTime;
  
  TimerNotificationScheduled(this.timerId, this.completionTime);
  
  @override
  List<Object?> get props => [timerId, completionTime];
}

/// Notification delivered
class TimerNotificationDelivered extends TimerNotificationState {
  final int timerId;
  final DateTime deliveredAt;
  
  TimerNotificationDelivered(this.timerId, this.deliveredAt);
  
  @override
  List<Object?> get props => [timerId, deliveredAt];
}

/// Notification cancelled
class TimerNotificationCancelled extends TimerNotificationState {
  final int timerId;
  
  TimerNotificationCancelled(this.timerId);
  
  @override
  List<Object?> get props => [timerId];
}

/// Error scheduling/delivering notification
class TimerNotificationError extends TimerNotificationState {
  final String message;
  final int? timerId;
  
  TimerNotificationError(this.message, [this.timerId]);
  
  @override
  List<Object?> get props => [message, timerId];
}
```

---

## Helper Types

### ResolvedNotificationSettings

**Purpose**: Settings with all nulls resolved to global defaults. Used for notification scheduling.

```dart
class ResolvedNotificationSettings {
  final bool chimeEnabled;
  final String? soundId;
  final String? soundName;
  final bool audioEnabled;
  final bool hapticEnabled;
  final HapticIntensity hapticIntensity;
  
  const ResolvedNotificationSettings({
    required this.chimeEnabled,
    this.soundId,
    this.soundName,
    required this.audioEnabled,
    required this.hapticEnabled,
    required this.hapticIntensity,
  });
  
  /// Resolves event settings with global defaults
  factory ResolvedNotificationSettings.fromEventSettings({
    required EventNotificationSettings? eventSettings,
    required GlobalNotificationSettings globalSettings,
  }) {
    if (eventSettings == null || !eventSettings.chimeEnabled) {
      return ResolvedNotificationSettings(
        chimeEnabled: eventSettings?.chimeEnabled ?? true,
        soundId: globalSettings.defaultSoundId,
        soundName: globalSettings.defaultSoundName,
        audioEnabled: globalSettings.defaultSoundId != null,
        hapticEnabled: globalSettings.hapticEnabled,
        hapticIntensity: globalSettings.defaultHapticIntensity,
      );
    }
    
    final soundId = eventSettings.customSoundId ?? globalSettings.defaultSoundId;
    final soundName = eventSettings.customSoundName ?? globalSettings.defaultSoundName;
    final hapticEnabled = eventSettings.customHapticEnabled ?? globalSettings.hapticEnabled;
    final intensity = eventSettings.customHapticIntensity ?? globalSettings.defaultHapticIntensity;
    
    return ResolvedNotificationSettings(
      chimeEnabled: true,
      soundId: soundId,
      soundName: soundName,
      audioEnabled: soundId != null,
      hapticEnabled: hapticEnabled,
      hapticIntensity: intensity,
    );
  }
}
```

---

## UI Widget Contracts

### SoundPickerWidget

**Purpose**: Modal bottom sheet for selecting device sounds with preview.

**Input Props**:
```dart
class SoundPickerWidget extends StatelessWidget {
  final String? currentSoundId;
  final List<DeviceSound> availableSounds;
  final Function(DeviceSound?) onSoundSelected;
  final bool allowNone; // Show "Use Default" or "None" option
  
  const SoundPickerWidget({
    this.currentSoundId,
    required this.availableSounds,
    required this.onSoundSelected,
    this.allowNone = true,
  });
}
```

**Output**: Calls `onSoundSelected` with chosen sound or null for default

---

### HapticIntensityPicker

**Purpose**: Segmented control or radio group for haptic intensity selection.

**Input Props**:
```dart
class HapticIntensityPicker extends StatelessWidget {
  final HapticIntensity? currentIntensity;
  final Function(HapticIntensity) onIntensitySelected;
  final bool enabled; // Disabled if no haptic support
  
  const HapticIntensityPicker({
    this.currentIntensity,
    required this.onIntensitySelected,
    this.enabled = true,
  });
}
```

**Behavior**: Triggers sample haptic on selection for immediate feedback

---

### ChimeSettingsWidget

**Purpose**: Collapsible section in event form for chime toggle and custom settings.

**Input Props**:
```dart
class ChimeSettingsWidget extends StatelessWidget {
  final EventNotificationSettings? settings;
  final GlobalNotificationSettings globalDefaults;
  final List<DeviceSound> availableSounds;
  final bool hasHapticSupport;
  final Function(EventNotificationSettings) onSettingsChanged;
  final bool isTimerRunning; // Show warning if editing during timer
  
  const ChimeSettingsWidget({
    this.settings,
    required this.globalDefaults,
    required this.availableSounds,
    required this.hasHapticSupport,
    required this.onSettingsChanged,
    this.isTimerRunning = false,
  });
}
```

**Behavior**: 
- Shows warning banner if `isTimerRunning = true`
- Emits `onSettingsChanged` on any toggle/selection
- Displays "Using default: [name]" when custom settings are null

---

## Testing Contracts

### Mock Repositories

```dart
class MockNotificationSettingsRepository extends Mock 
    implements NotificationSettingsRepository {}

class MockDeviceAudioRepository extends Mock 
    implements DeviceAudioRepository {}

class MockTimerNotificationService extends Mock 
    implements TimerNotificationService {}
```

### Test Fixtures

```dart
// Standard test data
final testGlobalSettings = GlobalNotificationSettings(
  defaultSoundId: 'test_sound_1',
  defaultSoundName: 'Test Chime',
  hapticEnabled: true,
  defaultHapticIntensity: HapticIntensity.medium,
);

final testEventSettings = EventNotificationSettings(
  chimeEnabled: true,
  customSoundId: null,
  customSoundName: null,
  customHapticEnabled: null,
  customHapticIntensity: null,
);

final testDeviceSounds = [
  DeviceSound(
    id: 'test_sound_1',
    name: 'Test Chime',
    uri: 'content://test/1',
    isAvailable: true,
  ),
  DeviceSound(
    id: 'test_sound_2',
    name: 'Test Bell',
    uri: 'content://test/2',
    isAvailable: true,
  ),
];
```

---

## Platform Channel Contracts

### MethodChannel: "dev.chronosync/device_audio"

**iOS Methods**:
```
getSystemSounds() -> List<Map<String, dynamic>>
  Returns: [{ "id": String, "name": String }, ...]

getSoundUri(String soundId) -> String?
  Returns: Sound identifier for UNNotificationSound

triggerHaptic(String style) -> void
  style: "light" | "medium" | "heavy"

hasVibrator() -> bool
```

**Android Methods**:
```
getSystemSounds() -> List<Map<String, dynamic>>
  Returns: [{ "id": String, "name": String, "uri": String }, ...]

getSoundUri(String soundId) -> String?
  Returns: Content URI for RingtoneManager

hasVibrator() -> bool

hasAmplitudeControl() -> bool
```

---

## Summary

**Contracts Defined**: 9 (3 repositories, 2 BLoCs, 3 widgets, 1 platform channel)

**Error Types**: 5 custom exceptions with clear semantics

**State Machines**: 2 (NotificationSettingsBloc, TimerNotificationBloc)

**Data Flow**: Repository → BLoC → Widget (unidirectional)

**Testing**: Mockable interfaces with standard fixtures provided

Ready for Phase 1 completion with quickstart.md.
