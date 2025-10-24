# Data Model: Haptics and Audio Settings

**Feature**: 005-haptics-audio-settings  
**Date**: October 24, 2025  
**Status**: Complete

## Overview

This document defines the data entities, relationships, and validation rules for the haptics and audio settings feature. The model supports both global default settings and event-level overrides with proper fallback behavior.

---

## Entity Definitions

### 1. GlobalNotificationSettings

**Purpose**: Stores user's default notification preferences that apply to all events unless overridden.

**Storage**: Hive box with single entry (singleton pattern)

**Hive Configuration**:
- Type ID: 3
- Box name: `globalNotificationSettings`

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `defaultSoundId` | `String?` | No | `null` | Device sound identifier; null = system default |
| `defaultSoundName` | `String?` | No | `null` | Display name of selected sound for UI |
| `hapticEnabled` | `bool` | Yes | `true` | Whether haptic feedback is enabled by default |
| `defaultHapticIntensity` | `HapticIntensity` | Yes | `medium` | Default intensity level for haptic feedback |

**Validation Rules**:
- If `defaultSoundId` is non-null, `defaultSoundName` must also be non-null
- `hapticEnabled` cannot be null
- `defaultHapticIntensity` must be one of: `light`, `medium`, `strong`

**Example**:
```dart
GlobalNotificationSettings(
  defaultSoundId: 'system_sound_1001',
  defaultSoundName: 'Chime',
  hapticEnabled: true,
  defaultHapticIntensity: HapticIntensity.medium,
)
```

---

### 2. EventNotificationSettings

**Purpose**: Stores event-specific notification overrides. Embedded within Event entity.

**Storage**: Embedded in Event model (not separate Hive box)

**Hive Configuration**:
- Type ID: 4
- Stored as field in Event entity

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `chimeEnabled` | `bool` | Yes | `true` | Master toggle for notifications on this event |
| `customSoundId` | `String?` | No | `null` | Custom sound override; null = use global default |
| `customSoundName` | `String?` | No | `null` | Display name for custom sound |
| `customHapticEnabled` | `bool?` | No | `null` | Custom haptic override; null = use global default |
| `customHapticIntensity` | `HapticIntensity?` | No | `null` | Custom intensity; null = use global default |

**Validation Rules**:
- `chimeEnabled` cannot be null
- If `chimeEnabled` is `false`, all other fields are ignored (no notifications)
- If `customSoundId` is non-null, `customSoundName` must also be non-null
- If `customHapticEnabled` is `false`, `customHapticIntensity` is ignored
- If `customHapticEnabled` is `true` and `customHapticIntensity` is `null`, default to `medium`
- `customHapticIntensity` must be one of: `light`, `medium`, `strong` (if non-null)

**Inheritance Logic** (null = use global default):
- `customSoundId == null` → use `GlobalNotificationSettings.defaultSoundId`
- `customHapticEnabled == null` → use `GlobalNotificationSettings.hapticEnabled`
- `customHapticIntensity == null` → use `GlobalNotificationSettings.defaultHapticIntensity`

**Examples**:
```dart
// Example 1: Use all global defaults
EventNotificationSettings(
  chimeEnabled: true,
  customSoundId: null,
  customSoundName: null,
  customHapticEnabled: null,
  customHapticIntensity: null,
)

// Example 2: Custom sound, default haptics
EventNotificationSettings(
  chimeEnabled: true,
  customSoundId: 'system_sound_1005',
  customSoundName: 'Bell',
  customHapticEnabled: null,
  customHapticIntensity: null,
)

// Example 3: Audio only (haptics disabled)
EventNotificationSettings(
  chimeEnabled: true,
  customSoundId: null,
  customSoundName: null,
  customHapticEnabled: false,
  customHapticIntensity: null,
)

// Example 4: Silent (no notifications)
EventNotificationSettings(
  chimeEnabled: false,
  customSoundId: null,
  customSoundName: null,
  customHapticEnabled: null,
  customHapticIntensity: null,
)
```

---

### 3. HapticIntensity (Enum)

**Purpose**: Defines available haptic feedback intensity levels.

**Storage**: Hive enum

**Hive Configuration**:
- Type ID: 5

**Values**:

| Value | Hive Field | Description | Android Mapping | iOS Mapping |
|-------|------------|-------------|-----------------|-------------|
| `light` | 0 | Subtle vibration | 50ms, amplitude 64 | UIImpactFeedbackStyle.light |
| `medium` | 1 | Moderate vibration | 100ms, amplitude 128 | UIImpactFeedbackStyle.medium |
| `strong` | 2 | Pronounced vibration | 200ms, amplitude 255 | UIImpactFeedbackStyle.heavy |

**Example**:
```dart
enum HapticIntensity {
  @HiveField(0)
  light,
  
  @HiveField(1)
  medium,
  
  @HiveField(2)
  strong,
}
```

---

### 4. DeviceSound

**Purpose**: Represents a sound available on the user's device (system sounds, not custom files).

**Storage**: Not persisted in Hive - transient, fetched from device via platform channels

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `String` | Yes | Platform-specific sound identifier |
| `name` | `String` | Yes | Human-readable name for UI display |
| `uri` | `String?` | No | Platform-specific URI for playback (Android) |
| `isAvailable` | `bool` | Yes | Whether sound is currently accessible |

**Validation Rules**:
- `id` must be non-empty
- `name` must be non-empty
- `isAvailable` defaults to `true`

**Platform Specifics**:
- **iOS**: `id` is notification sound name (e.g., "default", "chime")
- **Android**: `id` is Ringtone URI or resource ID, `uri` is the content URI

**Example**:
```dart
DeviceSound(
  id: 'system_sound_1001',
  name: 'Chime',
  uri: 'content://media/internal/audio/media/42',
  isAvailable: true,
)
```

---

### 5. Event (Modified)

**Purpose**: Existing Event entity extended with notification settings.

**New Field**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `notificationSettings` | `EventNotificationSettings?` | No | `null` | Event-specific notification config; null = use global defaults |

**Migration Strategy**:
- Existing events without `notificationSettings` field will have `null` value
- Repository layer interprets `null` as: "chime enabled, use all global defaults"
- No data migration needed - handled at runtime

**Validation Rules**:
- If `notificationSettings` is `null`, treated as default EventNotificationSettings with chime enabled
- Validation rules from EventNotificationSettings apply when non-null

**Example**:
```dart
Event(
  id: 'event-123',
  title: 'Work Timer',
  duration: Duration(minutes: 25),
  notificationSettings: EventNotificationSettings(
    chimeEnabled: true,
    customSoundId: 'system_sound_1005',
    customSoundName: 'Bell',
    customHapticEnabled: null,
    customHapticIntensity: null,
  ),
)
```

---

## Relationships

```
GlobalNotificationSettings (1:1 singleton)
    ↓ provides defaults
EventNotificationSettings (1:1 per Event)
    ↓ belongs to
Event (1:many)

DeviceSound (many, transient)
    ↓ referenced by
GlobalNotificationSettings.defaultSoundId
EventNotificationSettings.customSoundId
```

**Relationship Rules**:
1. **GlobalNotificationSettings** is a singleton - only one instance exists per app installation
2. Each **Event** may have zero or one **EventNotificationSettings** (optional, defaults applied if null)
3. **DeviceSound** instances are not persisted - fetched from OS on demand
4. Sound IDs in settings must reference valid **DeviceSound** entries (validated at selection time)
5. If a referenced sound becomes unavailable, fallback logic applies (see State Transitions)

---

## State Transitions

### EventNotificationSettings Lifecycle

```
[Event Created]
    ↓
notificationSettings = null (implicit: use global defaults)
    ↓
[User Toggles Chime OFF]
    ↓
notificationSettings = EventNotificationSettings(chimeEnabled: false, ...)
    ↓
[User Toggles Chime ON]
    ↓
notificationSettings = EventNotificationSettings(chimeEnabled: true, ...) // custom fields null = defaults
    ↓
[User Selects Custom Sound]
    ↓
notificationSettings.customSoundId = 'xyz'
notificationSettings.customSoundName = 'ABC'
    ↓
[User Resets to Default]
    ↓
notificationSettings.customSoundId = null
notificationSettings.customSoundName = null // reverts to global default
```

### Sound Availability States

```
[Sound Selected]
    ↓
DeviceSound(isAvailable: true)
    ↓
[Timer Ends, Sound Check]
    ↓
Sound Available? ──YES──> Play Selected Sound
    │
    NO
    ↓
[Retry 2-3 times with backoff]
    ↓
Still Unavailable? ──YES──> Fallback Logic
    │
    NO
    ↓
Play Selected Sound

[Fallback Logic]
    ↓
Is Event-Level Custom Sound? ──YES──> Use Global Default Sound
    │
    NO (is global default)
    ↓
Use System Fallback Beep
```

---

## Data Access Patterns

### Repository Methods

**NotificationSettingsRepository**:
- `Future<GlobalNotificationSettings> getGlobalSettings()`
- `Future<void> saveGlobalSettings(GlobalNotificationSettings settings)`
- `Future<EventNotificationSettings> getEventSettings(String eventId)`
- `Future<void> saveEventSettings(String eventId, EventNotificationSettings settings)`
- `Future<void> resetEventSettingsToDefaults(String eventId)`

**DeviceAudioRepository**:
- `Future<List<DeviceSound>> getSystemSounds({int retryCount = 3})`
- `Future<bool> hasHapticSupport()`
- `Future<void> triggerHaptic(HapticIntensity intensity)`
- `Future<void> previewSound(String soundId)`
- `Future<PermissionStatus> checkNotificationPermission()`
- `Future<bool> requestNotificationPermission()`

### Caching Strategy

- **GlobalNotificationSettings**: Cached in memory after first load, updated on change
- **EventNotificationSettings**: Loaded with parent Event, cached with Event
- **DeviceSound list**: Cached for app session duration, refreshed on settings screen open
- **Haptic support**: Cached on app launch (device capability doesn't change)

---

## Validation Summary

### Field-Level Validation

| Entity | Field | Validation |
|--------|-------|------------|
| GlobalNotificationSettings | defaultSoundId | If non-null, must reference valid DeviceSound |
| GlobalNotificationSettings | hapticEnabled | Cannot be null |
| GlobalNotificationSettings | defaultHapticIntensity | Must be light/medium/strong |
| EventNotificationSettings | chimeEnabled | Cannot be null |
| EventNotificationSettings | customSoundId | If non-null, must reference valid DeviceSound |
| EventNotificationSettings | customHapticIntensity | If non-null, must be light/medium/strong |
| DeviceSound | id | Cannot be empty |
| DeviceSound | name | Cannot be empty |

### Business Rule Validation

1. **Sound Availability**: When timer ends, validate sound still exists before playing
2. **Haptic Support**: Check device capability before showing haptic options in UI
3. **Permission**: Check notification permission before scheduling timer notifications
4. **Chime Disabled**: If `chimeEnabled = false`, ignore all other notification settings
5. **Null = Default**: Null values in EventNotificationSettings inherit from GlobalNotificationSettings

---

## Migration & Backward Compatibility

### Existing Event Data

**Current State**: Events may exist without `notificationSettings` field

**Handling**:
```dart
// In repository/bloc layer
EventNotificationSettings getEffectiveSettings(Event event, GlobalNotificationSettings global) {
  if (event.notificationSettings == null) {
    // Existing event without notification settings
    return EventNotificationSettings(
      chimeEnabled: true,
      customSoundId: null, // use global default
      customSoundName: null,
      customHapticEnabled: null, // use global default
      customHapticIntensity: null,
    );
  }
  return event.notificationSettings!;
}
```

**No Schema Migration Required**: Runtime interpretation handles backward compatibility

### Hive Type IDs

Ensure new type IDs don't conflict with existing:
- Type ID 3: GlobalNotificationSettings (NEW)
- Type ID 4: EventNotificationSettings (NEW)
- Type ID 5: HapticIntensity (NEW)

Verify existing type IDs in codebase and increment if needed.

---

## Performance Considerations

1. **Hive Access**: O(1) for global settings (single entry), O(1) for event settings (embedded)
2. **Sound List**: Fetched once per settings screen session, ~10-50 items typical
3. **Sound Preview**: Async operation, ~100-500ms depending on sound duration
4. **Haptic Trigger**: Synchronous, <10ms
5. **Notification Scheduling**: Async, <50ms via flutter_local_notifications

**Optimization**:
- Cache DeviceSound list in repository
- Lazy load sound previews (only when user taps preview button)
- Debounce setting changes to reduce Hive writes

---

## Testing Considerations

### Unit Tests

- Validation rules for all entities
- State transition logic
- Fallback behavior for unavailable sounds
- Null handling for optional fields
- Inheritance logic (EventSettings -> GlobalSettings)

### Integration Tests

- Hive persistence and retrieval
- Sound availability checking
- Permission request flows
- Notification scheduling with settings

### Mock Data

```dart
// Test fixtures
final mockGlobalSettings = GlobalNotificationSettings(
  defaultSoundId: 'test_sound_1',
  defaultSoundName: 'Test Chime',
  hapticEnabled: true,
  defaultHapticIntensity: HapticIntensity.medium,
);

final mockEventSettings = EventNotificationSettings(
  chimeEnabled: true,
  customSoundId: 'test_sound_2',
  customSoundName: 'Custom Bell',
  customHapticEnabled: false,
  customHapticIntensity: null,
);

final mockDeviceSounds = [
  DeviceSound(id: 'test_sound_1', name: 'Test Chime', isAvailable: true),
  DeviceSound(id: 'test_sound_2', name: 'Custom Bell', isAvailable: true),
  DeviceSound(id: 'test_sound_3', name: 'Unavailable', isAvailable: false),
];
```

---

## Summary

**Core Entities**: 5 (GlobalNotificationSettings, EventNotificationSettings, HapticIntensity, DeviceSound, Event modification)

**Hive Types**: 3 new type adapters required

**Relationships**: Composition (Event → EventNotificationSettings), Reference (Settings → DeviceSound by ID)

**Key Patterns**: Singleton (GlobalSettings), Optional Composition (Event.notificationSettings), Fallback Inheritance (null = use defaults)

**Validation**: Field-level constraints + business rule validation + runtime availability checking

Ready for contract definition in Phase 1 continuation.
