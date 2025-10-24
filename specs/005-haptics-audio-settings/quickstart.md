# Quick Start Guide: Haptics and Audio Settings

**Feature**: 005-haptics-audio-settings  
**Date**: October 24, 2025  
**Audience**: Developers implementing this feature

## Overview

This quick start guide provides a step-by-step walkthrough for implementing the haptics and audio settings feature. Follow the phases in order for progressive, testable development.

---

## Prerequisites

### Dependencies to Add

Update `chronosync/pubspec.yaml`:

```yaml
dependencies:
  # Existing dependencies...
  vibration: ^2.0.0
  flutter_local_notifications: ^18.0.0
  permission_handler: ^11.0.0
```

Run:
```bash
cd chronosync
flutter pub get
```

### Platform Configuration

**Android** (`chronosync/android/app/src/main/AndroidManifest.xml`):
```xml
<manifest>
    <!-- Add permission for vibration -->
    <uses-permission android:name="android.permission.VIBRATE" />
    
    <!-- Add permission for notifications (Android 13+) -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    
    <application>
        <!-- ... -->
    </application>
</manifest>
```

**iOS** (`chronosync/ios/Runner/Info.plist`):
```xml
<dict>
    <!-- No additional permissions needed for notifications/haptics -->
    <!-- System will prompt automatically when scheduling notifications -->
</dict>
```

---

## Development Phases

### Phase 1: Data Layer (Priority P1)

**Goal**: Create models and repositories for settings persistence.

**Steps**:

1. **Create Hive Models** (~30 min)

```dart
// lib/data/models/haptic_intensity.dart
import 'package:hive/hive.dart';

part 'haptic_intensity.g.dart';

@HiveType(typeId: 5)
enum HapticIntensity {
  @HiveField(0)
  light,
  
  @HiveField(1)
  medium,
  
  @HiveField(2)
  strong,
}
```

```dart
// lib/data/models/global_notification_settings.dart
import 'package:hive/hive.dart';
import 'haptic_intensity.dart';

part 'global_notification_settings.g.dart';

@HiveType(typeId: 3)
class GlobalNotificationSettings extends HiveObject {
  @HiveField(0)
  String? defaultSoundId;
  
  @HiveField(1)
  String? defaultSoundName;
  
  @HiveField(2)
  bool hapticEnabled;
  
  @HiveField(3)
  HapticIntensity defaultHapticIntensity;
  
  GlobalNotificationSettings({
    this.defaultSoundId,
    this.defaultSoundName,
    this.hapticEnabled = true,
    this.defaultHapticIntensity = HapticIntensity.medium,
  });
  
  factory GlobalNotificationSettings.defaults() {
    return GlobalNotificationSettings(
      hapticEnabled: true,
      defaultHapticIntensity: HapticIntensity.medium,
    );
  }
}
```

```dart
// lib/data/models/event_notification_settings.dart
import 'package:hive/hive.dart';
import 'haptic_intensity.dart';

part 'event_notification_settings.g.dart';

@HiveType(typeId: 4)
class EventNotificationSettings {
  @HiveField(0)
  bool chimeEnabled;
  
  @HiveField(1)
  String? customSoundId;
  
  @HiveField(2)
  String? customSoundName;
  
  @HiveField(3)
  bool? customHapticEnabled;
  
  @HiveField(4)
  HapticIntensity? customHapticIntensity;
  
  EventNotificationSettings({
    this.chimeEnabled = true,
    this.customSoundId,
    this.customSoundName,
    this.customHapticEnabled,
    this.customHapticIntensity,
  });
}
```

```dart
// lib/data/models/device_sound.dart
class DeviceSound {
  final String id;
  final String name;
  final String? uri;
  final bool isAvailable;
  
  const DeviceSound({
    required this.id,
    required this.name,
    this.uri,
    this.isAvailable = true,
  });
  
  factory DeviceSound.fromMap(Map<String, dynamic> map) {
    return DeviceSound(
      id: map['id'] as String,
      name: map['name'] as String,
      uri: map['uri'] as String?,
      isAvailable: map['isAvailable'] as bool? ?? true,
    );
  }
}
```

2. **Generate Hive Type Adapters** (~2 min)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

3. **Update Existing Event Model** (~10 min)

```dart
// lib/data/models/event.dart (existing file)
import 'event_notification_settings.dart';

@HiveType(typeId: 1) // Existing type ID
class Event extends HiveObject {
  // ... existing fields ...
  
  @HiveField(10) // Use next available field number
  EventNotificationSettings? notificationSettings;
  
  Event({
    // ... existing constructor params ...
    this.notificationSettings,
  });
}
```

Regenerate adapters after modifying Event:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. **Create Notification Settings Repository** (~45 min)

```dart
// lib/data/repositories/notification_settings_repository.dart
import 'package:hive/hive.dart';
import '../models/global_notification_settings.dart';
import '../models/event_notification_settings.dart';

class NotificationSettingsRepository {
  static const String _globalBoxName = 'globalNotificationSettings';
  static const String _globalSettingsKey = 'settings';
  
  Future<GlobalNotificationSettings> getGlobalSettings() async {
    try {
      final box = await Hive.openBox<GlobalNotificationSettings>(_globalBoxName);
      return box.get(_globalSettingsKey) ?? GlobalNotificationSettings.defaults();
    } catch (e) {
      // Return defaults on error
      return GlobalNotificationSettings.defaults();
    }
  }
  
  Future<void> saveGlobalSettings(GlobalNotificationSettings settings) async {
    final box = await Hive.openBox<GlobalNotificationSettings>(_globalBoxName);
    await box.put(_globalSettingsKey, settings);
  }
  
  Future<EventNotificationSettings?> getEventSettings(String eventId) async {
    try {
      final box = await Hive.openBox('events');
      final event = box.get(eventId);
      return event?.notificationSettings;
    } catch (e) {
      return null;
    }
  }
  
  Future<void> saveEventSettings(
    String eventId,
    EventNotificationSettings settings,
  ) async {
    final box = await Hive.openBox('events');
    final event = box.get(eventId);
    if (event != null) {
      event.notificationSettings = settings;
      await event.save();
    }
  }
  
  Future<void> resetEventSettingsToDefaults(String eventId) async {
    await saveEventSettings(
      eventId,
      EventNotificationSettings(chimeEnabled: true),
    );
  }
}
```

5. **Test Data Layer** (~30 min)

```dart
// test/data/repositories/notification_settings_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/repositories/notification_settings_repository.dart';

void main() {
  late NotificationSettingsRepository repository;
  
  setUpAll(() async {
    await Hive.initFlutter();
    Hive.registerAdapter(GlobalNotificationSettingsAdapter());
    Hive.registerAdapter(HapticIntensityAdapter());
  });
  
  setUp(() {
    repository = NotificationSettingsRepository();
  });
  
  tearDown(() async {
    await Hive.deleteFromDisk();
  });
  
  group('GlobalSettings', () {
    test('returns defaults when no settings exist', () async {
      final settings = await repository.getGlobalSettings();
      expect(settings.hapticEnabled, true);
      expect(settings.defaultHapticIntensity, HapticIntensity.medium);
    });
    
    test('saves and retrieves settings', () async {
      final newSettings = GlobalNotificationSettings(
        defaultSoundId: 'test_sound',
        defaultSoundName: 'Test',
        hapticEnabled: false,
        defaultHapticIntensity: HapticIntensity.light,
      );
      
      await repository.saveGlobalSettings(newSettings);
      final retrieved = await repository.getGlobalSettings();
      
      expect(retrieved.defaultSoundId, 'test_sound');
      expect(retrieved.hapticEnabled, false);
    });
  });
}
```

Run tests:
```bash
flutter test test/data/repositories/notification_settings_repository_test.dart
```

**Checkpoint**: Data layer complete and tested. Commit: "feat: add notification settings data models and repository"

---

### Phase 2: Device Integration (Priority P1)

**Goal**: Implement platform channels for device audio and haptics.

**Steps**:

1. **Create Device Audio Repository** (~60 min)

```dart
// lib/data/repositories/device_audio_repository.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/device_sound.dart';
import '../models/haptic_intensity.dart';

class DeviceAudioRepository {
  static const _channel = MethodChannel('dev.chronosync/device_audio');
  final AudioPlayer _previewPlayer = AudioPlayer();
  
  Future<List<DeviceSound>> getSystemSounds({int retryCount = 3}) async {
    for (int i = 0; i < retryCount; i++) {
      try {
        final result = await _channel.invokeMethod('getSystemSounds');
        final List<dynamic> soundMaps = result as List<dynamic>;
        return soundMaps.map((m) => DeviceSound.fromMap(m as Map<String, dynamic>)).toList();
      } catch (e) {
        if (i == retryCount - 1) {
          throw Exception('Unable to access device sounds: $e');
        }
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }
    return [];
  }
  
  Future<bool> hasHapticSupport() async {
    return await Vibration.hasVibrator() ?? false;
  }
  
  Future<bool> hasAmplitudeControl() async {
    if (Platform.isAndroid) {
      return await Vibration.hasAmplitudeControl() ?? false;
    }
    return false;
  }
  
  Future<void> triggerHaptic(HapticIntensity intensity) async {
    if (Platform.isAndroid) {
      final hasAmplitude = await hasAmplitudeControl();
      if (hasAmplitude) {
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
        final duration = intensity == HapticIntensity.light ? 50 : 
                        intensity == HapticIntensity.medium ? 100 : 200;
        await Vibration.vibrate(duration: duration);
      }
    } else if (Platform.isIOS) {
      await _channel.invokeMethod('triggerHaptic', {
        'style': intensity.toString().split('.').last
      });
    }
  }
  
  Future<void> previewSound(String soundId) async {
    try {
      final uri = await _channel.invokeMethod('getSoundUri', {'soundId': soundId});
      if (uri != null) {
        await _previewPlayer.setUrl(uri);
        await _previewPlayer.play();
      }
    } catch (e) {
      throw Exception('Failed to preview sound: $e');
    }
  }
  
  Future<void> stopPreview() async {
    await _previewPlayer.stop();
  }
  
  Future<PermissionStatus> checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return PermissionStatus.granted;
    if (status.isDenied) return PermissionStatus.denied;
    if (status.isPermanentlyDenied) return PermissionStatus.permanentlyDenied;
    return PermissionStatus.restricted;
  }
  
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
  
  void dispose() {
    _previewPlayer.dispose();
  }
}

enum PermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}
```

2. **Implement iOS Platform Channel** (~45 min)

```swift
// ios/Runner/AppDelegate.swift
import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let deviceAudioChannel = FlutterMethodChannel(
      name: "dev.chronosync/device_audio",
      binaryMessenger: controller.binaryMessenger
    )
    
    deviceAudioChannel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "getSystemSounds":
        self?.getSystemSounds(result: result)
      case "getSoundUri":
        self?.getSoundUri(call: call, result: result)
      case "triggerHaptic":
        self?.triggerHaptic(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func getSystemSounds(result: @escaping FlutterResult) {
    let sounds = [
      ["id": "default", "name": "Default"],
      ["id": "chime", "name": "Chime"],
      ["id": "bell", "name": "Bell"],
      ["id": "glass", "name": "Glass"],
      ["id": "horn", "name": "Horn"],
    ]
    result(sounds)
  }
  
  private func getSoundUri(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let soundId = args["soundId"] as? String else {
      result(nil)
      return
    }
    result(soundId) // iOS uses sound name as identifier
  }
  
  private func triggerHaptic(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let style = args["style"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing style", details: nil))
      return
    }
    
    let generator = UIImpactFeedbackGenerator(style: {
      switch style {
      case "light": return .light
      case "strong": return .heavy
      default: return .medium
      }
    }())
    
    generator.impactOccurred()
    result(nil)
  }
}
```

3. **Implement Android Platform Channel** (~45 min)

```kotlin
// android/app/src/main/kotlin/com/yourcompany/chronosync/MainActivity.kt
package com.yourcompany.chronosync

import android.media.RingtoneManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "dev.chronosync/device_audio"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemSounds" -> getSystemSounds(result)
                "getSoundUri" -> getSoundUri(call.argument("soundId"), result)
                else -> result.notImplemented()
            }
        }
    }
    
    private fun getSystemSounds(result: MethodChannel.Result) {
        val ringtoneManager = RingtoneManager(this)
        ringtoneManager.setType(RingtoneManager.TYPE_NOTIFICATION)
        val cursor = ringtoneManager.cursor
        
        val sounds = mutableListOf<Map<String, Any>>()
        
        while (cursor.moveToNext()) {
            val id = cursor.getString(RingtoneManager.ID_COLUMN_INDEX)
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
            val uri = ringtoneManager.getRingtoneUri(cursor.position).toString()
            
            sounds.add(mapOf(
                "id" to id,
                "name" to title,
                "uri" to uri,
                "isAvailable" to true
            ))
        }
        
        result.success(sounds)
    }
    
    private fun getSoundUri(soundId: String?, result: MethodChannel.Result) {
        if (soundId == null) {
            result.success(null)
            return
        }
        
        val ringtoneManager = RingtoneManager(this)
        ringtoneManager.setType(RingtoneManager.TYPE_NOTIFICATION)
        val cursor = ringtoneManager.cursor
        
        while (cursor.moveToNext()) {
            val id = cursor.getString(RingtoneManager.ID_COLUMN_INDEX)
            if (id == soundId) {
                val uri = ringtoneManager.getRingtoneUri(cursor.position).toString()
                result.success(uri)
                return
            }
        }
        
        result.success(null)
    }
}
```

**Checkpoint**: Platform integration complete. Test on both iOS and Android devices. Commit: "feat: add device audio and haptic platform channels"

---

### Phase 3: Business Logic (Priority P1)

**Goal**: Implement BLoCs for state management.

**Steps**:

1. **Create NotificationSettingsBloc** (~60 min)

See contract document for full event/state definitions. Implement bloc with proper error handling and state transitions.

```dart
// lib/logic/blocs/notification_settings_bloc/notification_settings_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'notification_settings_event.dart';
import 'notification_settings_state.dart';
import '../../../data/repositories/notification_settings_repository.dart';
import '../../../data/repositories/device_audio_repository.dart';

class NotificationSettingsBloc extends Bloc<NotificationSettingsEvent, NotificationSettingsState> {
  final NotificationSettingsRepository _settingsRepo;
  final DeviceAudioRepository _deviceRepo;
  
  NotificationSettingsBloc(this._settingsRepo, this._deviceRepo) : super(NotificationSettingsInitial()) {
    on<LoadNotificationSettings>(_onLoad);
    on<UpdateGlobalSound>(_onUpdateGlobalSound);
    on<UpdateGlobalHapticEnabled>(_onUpdateGlobalHapticEnabled);
    // ... other event handlers
  }
  
  Future<void> _onLoad(LoadNotificationSettings event, Emitter<NotificationSettingsState> emit) async {
    emit(NotificationSettingsLoading());
    try {
      final globalSettings = await _settingsRepo.getGlobalSettings();
      final hasHaptic = await _deviceRepo.hasHapticSupport();
      final sounds = await _deviceRepo.getSystemSounds();
      
      emit(NotificationSettingsLoaded(
        globalSettings: globalSettings,
        hasHapticSupport: hasHaptic,
        availableSounds: sounds,
      ));
    } catch (e) {
      emit(NotificationSettingsError(e.toString()));
    }
  }
  
  // ... implement other event handlers
}
```

2. **Test BLoC** (~30 min)

```dart
// test/logic/blocs/notification_settings_bloc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mockito/mockito.dart';
import 'package:chronosync/logic/blocs/notification_settings_bloc/notification_settings_bloc.dart';

void main() {
  late NotificationSettingsBloc bloc;
  late MockNotificationSettingsRepository mockRepo;
  late MockDeviceAudioRepository mockDevice;
  
  setUp(() {
    mockRepo = MockNotificationSettingsRepository();
    mockDevice = MockDeviceAudioRepository();
    bloc = NotificationSettingsBloc(mockRepo, mockDevice);
  });
  
  blocTest<NotificationSettingsBloc, NotificationSettingsState>(
    'loads settings successfully',
    build: () {
      when(mockRepo.getGlobalSettings()).thenAnswer((_) async => GlobalNotificationSettings.defaults());
      when(mockDevice.hasHapticSupport()).thenAnswer((_) async => true);
      when(mockDevice.getSystemSounds()).thenAnswer((_) async => []);
      return bloc;
    },
    act: (bloc) => bloc.add(LoadNotificationSettings()),
    expect: () => [
      NotificationSettingsLoading(),
      isA<NotificationSettingsLoaded>(),
    ],
  );
}
```

**Checkpoint**: Business logic implemented and tested. Commit: "feat: add notification settings bloc"

---

### Phase 4: UI Implementation (Priority P2/P3)

**Goal**: Build settings screens and widgets.

**Steps**:

1. **Global Settings Screen** (P1 - ~90 min)
2. **Sound Picker Widget** (P2 - ~60 min)
3. **Haptic Intensity Picker** (P2 - ~45 min)
4. **Event Chime Settings Widget** (P3 - ~60 min)

See contract document for widget interfaces and props.

**Checkpoint**: UI complete and functional. Commit: "feat: add notification settings UI"

---

### Phase 5: Notification Integration (Priority P1)

**Goal**: Integrate with flutter_local_notifications for timer completions.

**Steps**:

1. **Initialize Notifications** (in main.dart)
2. **Create TimerNotificationService**
3. **Schedule notifications when timer starts**
4. **Cancel notifications when timer stops**
5. **Test background notification delivery**

**Checkpoint**: End-to-end notification flow working. Commit: "feat: integrate timer notifications"

---

## Testing Strategy

### Unit Tests
- All models (validation, serialization)
- All repositories (CRUD operations)
- All BLoCs (event handling, state transitions)

### Widget Tests
- Sound picker selection
- Haptic intensity selection
- Chime settings toggle behavior

### Integration Tests
- Global settings save and load
- Event settings override global defaults
- Notification scheduling and delivery
- Permission request flows

### Manual Testing Checklist
- [ ] iOS device: sounds list loads
- [ ] Android device: sounds list loads
- [ ] Sound preview plays correctly
- [ ] Haptic feedback triggers on tap
- [ ] Settings persist across app restart
- [ ] Notifications fire when app backgrounded
- [ ] Notifications respect device silent mode
- [ ] Graceful degradation on devices without haptic support

---

## Troubleshooting

### Issue: Sounds list empty
**Solution**: Check platform channel implementation and permissions

### Issue: Haptic not working
**Solution**: Verify VIBRATE permission in AndroidManifest.xml

### Issue: Notifications not appearing
**Solution**: Check notification permissions, ensure timer scheduling is working

### Issue: Sound URI not found
**Solution**: Verify getSoundUri implementation returns valid content URI

---

## Next Steps After Implementation

1. Run full test suite: `flutter test`
2. Test on both iOS and Android physical devices
3. Update `/speckit.tasks` for task tracking
4. Create PR with reference to spec and plan documents
5. Request code review focusing on:
   - Error handling in repositories
   - State management in BLoCs
   - UI/UX patterns
   - Platform-specific behavior

---

## Estimated Time

- **Phase 1 (Data Layer)**: 2 hours
- **Phase 2 (Device Integration)**: 2.5 hours
- **Phase 3 (Business Logic)**: 2 hours
- **Phase 4 (UI)**: 4.5 hours
- **Phase 5 (Notification Integration)**: 2 hours
- **Testing & Refinement**: 2 hours

**Total**: ~15 hours (2 development days)

---

## Resources

- [Flutter BLoC Documentation](https://bloclibrary.dev/)
- [Hive Documentation](https://docs.hivedb.dev/)
- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
- [vibration package](https://pub.dev/packages/vibration)
- [permission_handler](https://pub.dev/packages/permission_handler)

Ready for implementation!
