# Research: Haptics and Audio Settings

**Feature**: 005-haptics-audio-settings  
**Date**: October 24, 2025  
**Status**: Complete

## Research Questions

This document resolves all NEEDS CLARIFICATION items from the Technical Context and identifies best practices for implementing audio and haptic notifications in Flutter.

---

## 1. Audio Picker Package Selection

**Question**: Which Flutter package should be used for browsing and selecting device built-in sounds?

**Decision**: Use platform channels to access native audio APIs directly (no third-party package)

**Rationale**:
- iOS: Use `AVAudioSession` and `UIAlertController` with `UNNotificationSound.default()` for system sounds
- Android: Use `RingtoneManager` to access system notification sounds, ringtones, and alarms
- Flutter packages for audio picking (like `file_picker_cross`) focus on file selection, not system sounds
- System sounds are platform-specific and best accessed via native APIs
- Direct platform channel implementation provides:
  - Access to actual system sounds (not just files)
  - Native UI for sound selection on each platform
  - Better integration with OS notification system
  - No additional dependencies

**Implementation Approach**:
- Create platform channels in `device_audio_repository.dart`
- iOS: Swift/Objective-C code to enumerate `UNNotificationSound` options
- Android: Kotlin/Java code using `RingtoneManager.TYPE_NOTIFICATION` and `TYPE_ALARM`
- Return sound identifiers that can be used with OS notification system

**Alternatives Considered**:
- `flutter_file_picker`: Only picks files, not system sounds - rejected
- `audio_picker`: Doesn't exist as mature package - rejected
- Bundled audio files: Limited variety, larger app size, doesn't match user's device sounds - rejected

---

## 2. Vibration/Haptics Package Selection

**Question**: Which Flutter package should be used for haptic feedback with intensity levels?

**Decision**: `vibration` package (^2.0.0) for Android, `flutter_platform_widgets` or platform channels for iOS fine-grained control

**Rationale**:
- The `vibration` package provides:
  - Cross-platform support (iOS and Android)
  - Simple API: `Vibration.vibrate(duration: milliseconds, amplitude: 0-255)` on Android
  - Duration and pattern control
  - Permission handling
  - Capability detection (`Vibration.hasVibrator()`, `Vibration.hasAmplitudeControl()`)

- For intensity levels mapping:
  - **Light**: 50ms duration, amplitude 50-80 (Android), haptic feedback light (iOS)
  - **Medium**: 100ms duration, amplitude 120-150 (Android), medium impact (iOS)
  - **Strong**: 200ms duration, amplitude 200-255 (Android), heavy impact (iOS)

- iOS considerations:
  - Use `HapticFeedback` class for basic vibration
  - Use platform channels + `UIImpactFeedbackGenerator` for intensity levels
  - Styles: `.light`, `.medium`, `.heavy`, `.rigid`, `.soft`

**Implementation Approach**:
```dart
// Add to pubspec.yaml
dependencies:
  vibration: ^2.0.0

// Usage in device_audio_repository.dart
class DeviceAudioRepository {
  Future<bool> hasHapticSupport() async {
    return await Vibration.hasVibrator() ?? false;
  }
  
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    if (Platform.isAndroid) {
      final hasAmplitudeControl = await Vibration.hasAmplitudeControl() ?? false;
      if (hasAmplitudeControl) {
        switch (intensity) {
          case HapticIntensity.light:
            await Vibration.vibrate(duration: 50, amplitude: 64);
            break;
          case HapticIntensity.medium:
            await Vibration.vibrate(duration: 100, amplitude: 128);
            break;
          case HapticIntensity.strong:
            await Vibration.vibrate(duration: 200, amplitude: 255);
            break;
        }
      } else {
        // Fallback: use duration only
        final duration = intensity == HapticIntensity.light ? 50 : 
                        intensity == HapticIntensity.medium ? 100 : 200;
        await Vibration.vibrate(duration: duration);
      }
    } else if (Platform.isIOS) {
      // Use platform channel for UIImpactFeedbackGenerator
      await _platformChannel.invokeMethod('triggerHaptic', {
        'style': intensity.toIOSStyle()
      });
    }
  }
}
```

**Alternatives Considered**:
- `flutter_vibrate`: Older, less maintained - rejected
- `haptic_feedback` (Flutter built-in): Only basic feedback types, no intensity control - rejected for full solution but used for simple cases
- Platform channels only: More code, reinventing wheel - rejected in favor of package + channels hybrid

---

## 3. Flutter Local Notifications Integration

**Question**: How should timer completion notifications work when app is backgrounded?

**Decision**: Use `flutter_local_notifications` package (^18.0.0) with scheduled notifications

**Rationale**:
- `flutter_local_notifications` provides:
  - Cross-platform local notification scheduling
  - Custom sound support (both bundled and system sounds)
  - Vibration pattern configuration
  - Works when app is backgrounded or killed
  - Notification channel configuration for Android
  - Integration with iOS notification system

- When timer starts:
  - Schedule a notification for timer completion time
  - Configure notification with selected sound and vibration
  - If timer is cancelled/stopped, cancel the scheduled notification

- Advantages:
  - Notifications delivered by OS, not dependent on app running
  - Respects system DND/silent mode settings
  - Native notification UI on each platform
  - Battery efficient

**Implementation Approach**:
```dart
// Add to pubspec.yaml
dependencies:
  flutter_local_notifications: ^18.0.0

// In timer_notification_bloc.dart
class TimerNotificationService {
  final FlutterLocalNotificationsPlugin _notifications;
  
  Future<void> scheduleTimerNotification({
    required int timerId,
    required DateTime completionTime,
    required NotificationSettings settings,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'timer_channel',
      'Timer Completions',
      importance: Importance.high,
      priority: Priority.high,
      sound: settings.customSound != null 
        ? UriAndroidNotificationSound(settings.customSound!)
        : null,
      enableVibration: settings.hapticEnabled,
      vibrationPattern: settings.hapticEnabled 
        ? _getVibrationPattern(settings.hapticIntensity)
        : null,
    );
    
    final iOSDetails = DarwinNotificationDetails(
      sound: settings.customSound,
      presentSound: settings.audioEnabled,
    );
    
    await _notifications.zonedSchedule(
      timerId,
      'Timer Complete',
      'Your timer has finished',
      completionTime,
      NotificationDetails(android: androidDetails, iOS: iOSDetails),
      uiLocalNotificationDateInterpretation: 
        UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
  
  Int64List? _getVibrationPattern(HapticIntensity intensity) {
    switch (intensity) {
      case HapticIntensity.light:
        return Int64List.fromList([0, 50, 50, 50]);
      case HapticIntensity.medium:
        return Int64List.fromList([0, 100, 50, 100]);
      case HapticIntensity.strong:
        return Int64List.fromList([0, 200, 100, 200]);
    }
  }
}
```

**Alternatives Considered**:
- Background isolates: Complex, battery intensive, may be killed by OS - rejected
- Foreground service: Android only, overkill for timer app - rejected
- WorkManager: For periodic tasks, not precise timing - rejected

---

## 4. Sound Preview Implementation

**Question**: How should sound preview work in settings UI?

**Decision**: Use `just_audio` package (already in project at ^0.9.36) for sound preview playback

**Rationale**:
- `just_audio` is already a project dependency
- Provides simple audio playback API
- Supports both asset and file playback
- Handles platform-specific audio session management
- Works well for short sound previews

**Implementation Approach**:
```dart
// In sound_preview_button.dart widget
class SoundPreviewButton extends StatefulWidget {
  final DeviceSound sound;
  
  @override
  State<SoundPreviewButton> createState() => _SoundPreviewButtonState();
}

class _SoundPreviewButtonState extends State<SoundPreviewButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  
  Future<void> _playPreview() async {
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }
    
    try {
      setState(() => _isPlaying = true);
      
      // Get sound URI from platform channel
      final soundUri = await DeviceAudioRepository.instance
        .getSoundUri(widget.sound.id);
      
      await _player.setUrl(soundUri);
      await _player.play();
      
      // Auto-stop after sound completes
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() => _isPlaying = false);
        }
      });
    } catch (e) {
      // Handle error, show snackbar
      setState(() => _isPlaying = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
      onPressed: _playPreview,
    );
  }
  
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
```

**Alternatives Considered**:
- `audioplayers`: Older API, less maintained - rejected
- Platform channels only: More complex than needed - rejected
- No preview: Poor UX, users can't hear before selecting - rejected

---

## 5. Hive Data Model Best Practices

**Question**: How should notification settings be stored in Hive?

**Decision**: Create separate Hive type adapters for `GlobalNotificationSettings` and embedded `EventNotificationSettings` within existing Event model

**Rationale**:
- Hive already used in project for Event persistence
- Type adapters provide efficient binary serialization
- Global settings stored as singleton (box with single entry)
- Event settings embedded in Event model (composition)
- Use `@HiveType` and `@HiveField` annotations

**Implementation Approach**:
```dart
// In global_notification_settings.dart
@HiveType(typeId: 3) // Increment typeId from existing types
class GlobalNotificationSettings extends HiveObject {
  @HiveField(0)
  String? defaultSoundId;
  
  @HiveField(1)
  bool hapticEnabled;
  
  @HiveField(2)
  HapticIntensity defaultHapticIntensity;
  
  GlobalNotificationSettings({
    this.defaultSoundId,
    this.hapticEnabled = true,
    this.defaultHapticIntensity = HapticIntensity.medium,
  });
}

// In event_notification_settings.dart
@HiveType(typeId: 4)
class EventNotificationSettings {
  @HiveField(0)
  bool chimeEnabled;
  
  @HiveField(1)
  String? customSoundId;
  
  @HiveField(2)
  bool? customHapticEnabled; // null = use global default
  
  @HiveField(3)
  HapticIntensity? customHapticIntensity; // null = use global default
  
  EventNotificationSettings({
    this.chimeEnabled = true,
    this.customSoundId,
    this.customHapticEnabled,
    this.customHapticIntensity,
  });
}

// In haptic_intensity.dart (enum)
@HiveType(typeId: 5)
enum HapticIntensity {
  @HiveField(0)
  light,
  
  @HiveField(1)
  medium,
  
  @HiveField(2)
  strong,
}

// Update existing Event model to include notification settings
class Event extends HiveObject {
  // ... existing fields ...
  
  @HiveField(10) // Use next available field number
  EventNotificationSettings? notificationSettings;
}
```

**Migration Strategy**:
- Existing events without `notificationSettings` field will have null value
- Repository layer provides defaults (chime ON, use global settings)
- Generate type adapters with `build_runner`: `flutter pub run build_runner build`

**Alternatives Considered**:
- SharedPreferences: Less efficient for complex objects - rejected
- JSON files: Manual serialization overhead - rejected
- SQLite: Overkill for simple key-value storage - rejected

---

## 6. Permission Handling Strategy

**Question**: How should the app handle audio and notification permissions?

**Decision**: Use `permission_handler` package (^11.0.0) with graceful degradation and retry logic

**Rationale**:
- `permission_handler` provides:
  - Unified API for checking and requesting permissions
  - Platform-specific permission handling (iOS vs Android)
  - Status checking (granted, denied, permanentlyDenied)
  - Opens app settings when needed

- Required permissions:
  - iOS: None for notification sounds (handled by system)
  - Android: `VIBRATE` for haptic feedback (add to AndroidManifest.xml)
  - Both: Notification permission (iOS 10+, Android 13+)

**Implementation Approach**:
```dart
// Add to pubspec.yaml
dependencies:
  permission_handler: ^11.0.0

// In device_audio_repository.dart
class DeviceAudioRepository {
  Future<PermissionStatus> checkNotificationPermission() async {
    return await Permission.notification.status;
  }
  
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
  
  Future<List<DeviceSound>> getSystemSounds({int retryCount = 3}) async {
    for (int i = 0; i < retryCount; i++) {
      try {
        // Platform channel call to get system sounds
        final sounds = await _platformChannel.invokeMethod('getSystemSounds');
        return sounds.map((s) => DeviceSound.fromMap(s)).toList();
      } catch (e) {
        if (i == retryCount - 1) {
          // Final retry failed, throw with user-friendly message
          throw AudioPermissionException(
            'Unable to access device sounds. Please check app permissions in Settings.',
          );
        }
        // Wait before retry (exponential backoff)
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }
    return [];
  }
}

// In notification_settings_screen.dart
void _handlePermissionError(AudioPermissionException e) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Permission Required'),
      content: Text(e.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            openAppSettings(); // From permission_handler
            Navigator.pop(context);
          },
          child: Text('Open Settings'),
        ),
      ],
    ),
  );
}
```

**Alternatives Considered**:
- No permission handling: Silent failures, poor UX - rejected
- Manual platform-specific code: Duplicated logic - rejected
- Immediate failure: No retry resilience - rejected

---

## 7. BLoC Architecture Pattern

**Question**: How should state management be structured for settings and notifications?

**Decision**: Two separate BLoCs following single responsibility principle

**BLoC 1: NotificationSettingsBloc**
- Manages global and event-level settings state
- Events: LoadSettings, UpdateGlobalSettings, UpdateEventSettings, ResetToDefaults
- States: SettingsLoading, SettingsLoaded, SettingsError
- Handles persistence via repository pattern

**BLoC 2: TimerNotificationBloc**
- Manages timer completion notification lifecycle
- Events: ScheduleNotification, CancelNotification, NotificationTriggered
- States: NotificationIdle, NotificationScheduled, NotificationDelivered, NotificationError
- Integrates with flutter_local_notifications

**Rationale**:
- Separation of concerns: Settings management vs. notification delivery
- Independent testing of each BLoC
- Different lifecycles: Settings persist, notifications are transient
- Follows existing project BLoC pattern (flutter_bloc package)

**Implementation Pattern**:
```dart
// notification_settings_bloc/notification_settings_event.dart
abstract class NotificationSettingsEvent extends Equatable {}

class LoadNotificationSettings extends NotificationSettingsEvent {
  @override
  List<Object?> get props => [];
}

class UpdateGlobalSettings extends NotificationSettingsEvent {
  final GlobalNotificationSettings settings;
  UpdateGlobalSettings(this.settings);
  @override
  List<Object?> get props => [settings];
}

class UpdateEventSettings extends NotificationSettingsEvent {
  final String eventId;
  final EventNotificationSettings settings;
  UpdateEventSettings(this.eventId, this.settings);
  @override
  List<Object?> get props => [eventId, settings];
}

// notification_settings_bloc/notification_settings_state.dart
abstract class NotificationSettingsState extends Equatable {}

class NotificationSettingsLoading extends NotificationSettingsState {
  @override
  List<Object?> get props => [];
}

class NotificationSettingsLoaded extends NotificationSettingsState {
  final GlobalNotificationSettings globalSettings;
  final bool hasHapticSupport;
  final List<DeviceSound> availableSounds;
  
  NotificationSettingsLoaded({
    required this.globalSettings,
    required this.hasHapticSupport,
    required this.availableSounds,
  });
  
  @override
  List<Object?> get props => [globalSettings, hasHapticSupport, availableSounds];
}

class NotificationSettingsError extends NotificationSettingsState {
  final String message;
  NotificationSettingsError(this.message);
  @override
  List<Object?> get props => [message];
}
```

**Alternatives Considered**:
- Single BLoC: Violates single responsibility, harder to test - rejected
- Provider/Riverpod: Different pattern than existing codebase - rejected
- GetX: Too opinionated, not using in project - rejected

---

## 8. UI/UX Best Practices for Settings

**Question**: What are Flutter best practices for settings UI and sound/haptic selection?

**Decision**: Use Material Design 3 patterns with adaptive components

**Key Patterns**:

1. **Settings Screen**:
   - `ListView` with `SwitchListTile` for enable/disable options
   - `ListTile` with trailing icon for navigation to pickers
   - `ExpansionTile` for grouped settings
   - Save settings immediately on change (no submit button)

2. **Sound Picker**:
   - Bottom sheet modal with searchable list
   - Preview button for each sound
   - Current selection highlighted
   - "Use Device Default" option at top

3. **Haptic Intensity Picker**:
   - Segmented button or radio list
   - Trigger sample haptic on selection for immediate feedback
   - Visual labels: "Light", "Medium", "Strong" with icons

4. **Event Chime Settings**:
   - Collapsible section in event form
   - Master toggle for chime enable/disable
   - Nested options only visible when chime enabled
   - Clear visual indication of "Using default" vs. custom

**Example Widget Structure**:
```dart
// notification_settings_screen.dart
class NotificationSettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notification Settings')),
      body: BlocBuilder<NotificationSettingsBloc, NotificationSettingsState>(
        builder: (context, state) {
          if (state is NotificationSettingsLoaded) {
            return ListView(
              children: [
                _buildAudioSection(state),
                Divider(),
                _buildHapticSection(state),
              ],
            );
          }
          return Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
  
  Widget _buildAudioSection(NotificationSettingsLoaded state) {
    return ExpansionTile(
      title: Text('Audio'),
      leading: Icon(Icons.volume_up),
      children: [
        ListTile(
          title: Text('Default Sound'),
          subtitle: Text(state.globalSettings.defaultSoundName ?? 'System Default'),
          trailing: Icon(Icons.chevron_right),
          onTap: () => _showSoundPicker(context),
        ),
        SoundPreviewButton(sound: state.globalSettings.defaultSound),
      ],
    );
  }
  
  Widget _buildHapticSection(NotificationSettingsLoaded state) {
    if (!state.hasHapticSupport) {
      return ListTile(
        title: Text('Haptic Feedback'),
        subtitle: Text('Not supported on this device'),
        enabled: false,
      );
    }
    
    return ExpansionTile(
      title: Text('Haptic Feedback'),
      leading: Icon(Icons.vibration),
      children: [
        SwitchListTile(
          title: Text('Enable Haptics'),
          value: state.globalSettings.hapticEnabled,
          onChanged: (value) => _updateHapticEnabled(context, value),
        ),
        if (state.globalSettings.hapticEnabled)
          _buildHapticIntensityPicker(state),
      ],
    );
  }
}
```

**Accessibility Considerations**:
- Semantic labels for screen readers
- Sufficient color contrast
- Touch target sizes ≥48dp
- Haptic feedback as optional feature (visual-only alternatives)

**Alternatives Considered**:
- Cupertino widgets: Not matching app theme - rejected
- Custom widgets: Unnecessary when Material 3 provides patterns - rejected
- Multi-step wizard: Overkill for simple settings - rejected

---

## Summary

All NEEDS CLARIFICATION items resolved. Technology stack selected:

**New Dependencies**:
- `vibration: ^2.0.0` - Haptic feedback with intensity control
- `flutter_local_notifications: ^18.0.0` - Scheduled notifications when backgrounded
- `permission_handler: ^11.0.0` - Permission checking and requests

**Existing Dependencies** (reused):
- `just_audio: ^0.9.36` - Sound preview playback
- `flutter_bloc: ^9.1.1` - State management
- `hive: ^2.2.3` - Local data persistence

**Platform Channels Required**:
- Device system sounds enumeration (iOS/Android)
- Fine-grained haptic control on iOS
- Custom notification sounds integration

**Architecture Decisions**:
- Two BLoCs: NotificationSettingsBloc (settings state) and TimerNotificationBloc (notification lifecycle)
- Repository pattern for data access
- Hive type adapters for efficient serialization
- Material Design 3 UI patterns

Ready to proceed to Phase 1: Data Model and Contract Design.
