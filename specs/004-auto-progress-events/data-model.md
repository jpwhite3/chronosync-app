# Data Model: Auto-Progress Events with Series Statistics

**Feature**: 004-auto-progress-events  
**Date**: October 23, 2025  
**Status**: Complete

## Overview

This document defines the data model changes required to support auto-progression and series statistics. Changes are minimal and backward-compatible with existing Hive storage.

## Entities

### 1. Event (Modified)

**Purpose**: Represents a timed activity within a series. Extended to include auto-progression capability.

**Storage**: Hive (typeId: 1)

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| title | String | Yes | - | Event name displayed to user |
| durationInSeconds | int | Yes | - | Event duration in seconds |
| autoProgress | bool | Yes | false | Whether event automatically advances at "00:00" |

**Relationships**:
- Belongs to one Series (contained in Series.events list)

**Validation Rules**:
- `title` must not be empty
- `durationInSeconds` must be positive (> 0)
- `autoProgress` defaults to false (safe default for existing events)

**State Transitions**: None (passive data model)

**Schema Migration**:
```dart
// BEFORE (existing)
@HiveType(typeId: 1)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  int durationInSeconds;

  Event({required this.title, required this.durationInSeconds});
}

// AFTER (modified)
@HiveType(typeId: 1)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  int durationInSeconds;

  @HiveField(2)  // NEW FIELD
  bool autoProgress;

  Event({
    required this.title, 
    required this.durationInSeconds,
    this.autoProgress = false,  // Default ensures backward compatibility
  });

  // Existing helper methods remain unchanged
  Duration get duration => Duration(seconds: durationInSeconds);
  
  Event.fromDuration({
    required this.title, 
    required Duration duration,
    this.autoProgress = false,
  }) : durationInSeconds = duration.inSeconds;
}
```

**Backward Compatibility**: Existing Event records in Hive will automatically receive `autoProgress = false` when loaded after schema update. No manual migration required.

---

### 2. UserPreferences (Modified)

**Purpose**: Stores user settings for the application. Extended to include audio cue toggle for auto-progression.

**Storage**: Hive (typeId: 2)

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| swipeDirection | String | Yes | 'ltr' | Swipe direction preference ('ltr' or 'rtl') |
| autoProgressAudioEnabled | bool | Yes | true | Whether audio cue plays on auto-progression |

**Relationships**: None (singleton preferences object)

**Validation Rules**:
- `swipeDirection` must be 'ltr' or 'rtl'
- `autoProgressAudioEnabled` is a simple boolean toggle

**State Transitions**: None (passive data model)

**Schema Migration**:
```dart
// BEFORE (existing)
@HiveType(typeId: 2)
class UserPreferences extends HiveObject {
  @HiveField(0)
  String swipeDirection;

  UserPreferences({this.swipeDirection = 'ltr'});
  
  // Existing enum helpers remain
  SwipeDirection get swipeDirectionEnum => 
      swipeDirection == 'rtl' ? SwipeDirection.rtl : SwipeDirection.ltr;
}

// AFTER (modified)
@HiveType(typeId: 2)
class UserPreferences extends HiveObject {
  @HiveField(0)
  String swipeDirection;

  @HiveField(1)  // NEW FIELD
  bool autoProgressAudioEnabled;

  UserPreferences({
    this.swipeDirection = 'ltr',
    this.autoProgressAudioEnabled = true,  // Default: audio enabled
  });
  
  // Existing enum helpers remain unchanged
  SwipeDirection get swipeDirectionEnum => 
      swipeDirection == 'rtl' ? SwipeDirection.rtl : SwipeDirection.ltr;
}
```

**Backward Compatibility**: Existing UserPreferences record will automatically receive `autoProgressAudioEnabled = true` when loaded after schema update.

---

### 3. Series (No Changes)

**Purpose**: Container for multiple events representing an agenda.

**Storage**: Hive (typeId: 0)

**Note**: No schema changes required. Series entity remains unchanged.

**Current Structure** (for reference):
```dart
@HiveType(typeId: 0)
class Series extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  List<Event> events;

  Series({required this.title, required this.events});
}
```

---

### 4. SeriesStatistics (New - Transient)

**Purpose**: Calculated summary of series execution displayed at completion. NOT persisted to storage.

**Storage**: In-memory only (part of LiveTimerState)

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| eventCount | int | Yes | - | Total number of events in completed series |
| expectedTimeSeconds | int | Yes | - | Sum of all event durations |
| actualTimeSeconds | int | Yes | - | Actual elapsed time including overtime/undertime |

**Computed Properties**:
```dart
class SeriesStatistics {
  final int eventCount;
  final int expectedTimeSeconds;
  final int actualTimeSeconds;

  SeriesStatistics({
    required this.eventCount,
    required this.expectedTimeSeconds,
    required this.actualTimeSeconds,
  });

  // Computed: Difference between actual and expected
  int get overUnderTimeSeconds => actualTimeSeconds - expectedTimeSeconds;
  
  // Computed: Status flags for color-coding
  bool get isOvertime => overUnderTimeSeconds > 0;
  bool get isUndertime => overUnderTimeSeconds < 0;
  bool get isOnTime => overUnderTimeSeconds == 0;

  // Computed: Formatted time strings for display
  String get expectedTimeFormatted => _formatTime(expectedTimeSeconds);
  String get actualTimeFormatted => _formatTime(actualTimeSeconds);
  String get overUnderTimeFormatted {
    final sign = isOvertime ? '+' : (isUndertime ? '-' : '');
    return '$sign${_formatTime(overUnderTimeSeconds.abs())}';
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
             '${minutes.toString().padLeft(2, '0')}:'
             '${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
             '${secs.toString().padLeft(2, '0')}';
    }
  }
}
```

**Relationships**: Created by LiveTimerBloc when series completes, passed to LiveTimerComplete state

**Validation Rules**:
- All fields must be non-negative
- `actualTimeSeconds` should be >= 0 (series cannot have negative elapsed time)
- `expectedTimeSeconds` is sum of all event durations (always positive for non-empty series)

**Lifecycle**: 
1. Created when final event completes or manual "NEXT" pressed on final event
2. Stored in LiveTimerComplete state
3. Displayed by SeriesStatisticsPanel widget
4. Discarded when user navigates away from completion screen

---

## State Objects (BLoC)

### LiveTimerState (Modified)

**Purpose**: Represents the current state of the live timer during series execution.

**Existing States** (for reference):
- `LiveTimerInitial`
- `LiveTimerRunning`
- `LiveTimerPaused`
- `LiveTimerComplete`

**Modifications**:

#### LiveTimerRunning (Modified)
Add fields to support auto-progression timing:

```dart
class LiveTimerRunning extends LiveTimerState {
  final Series series;
  final int currentEventIndex;
  final int elapsedSeconds;
  final DateTime eventStartTime;  // NEW: Track event start for minimum display time
  final DateTime? seriesStartTime; // NEW: Track series start for statistics
  final int totalSeriesElapsedSeconds; // NEW: Cumulative elapsed across all events

  // Existing fields remain...
  
  // Computed properties
  Event get currentEvent => series.events[currentEventIndex];
  int get remainingSeconds => currentEvent.durationInSeconds - elapsedSeconds;
  bool get isOvertime => remainingSeconds < 0;
  int get overtimeSeconds => isOvertime ? remainingSeconds.abs() : 0;
  bool get isLastEvent => currentEventIndex >= series.events.length - 1;
  
  // NEW: Check if auto-progression should occur
  bool get shouldAutoProgress {
    final minDisplayTimeElapsed = 
        DateTime.now().difference(eventStartTime).inSeconds >= 1;
    return remainingSeconds <= 0 && 
           currentEvent.autoProgress && 
           minDisplayTimeElapsed;
  }
}
```

#### LiveTimerComplete (Modified)
Add statistics field:

```dart
class LiveTimerComplete extends LiveTimerState {
  final SeriesStatistics statistics;  // NEW: Series statistics for display

  LiveTimerComplete({required this.statistics});
}
```

---

### SettingsState (Modified)

**Purpose**: Represents the current application settings.

**Modification**:
```dart
class SettingsState extends Equatable {
  final SwipeDirection swipeDirection;
  final bool autoProgressAudioEnabled;  // NEW: Audio toggle state

  const SettingsState({
    this.swipeDirection = SwipeDirection.ltr,
    this.autoProgressAudioEnabled = true,  // Default: enabled
  });

  @override
  List<Object?> get props => [swipeDirection, autoProgressAudioEnabled];

  SettingsState copyWith({
    SwipeDirection? swipeDirection,
    bool? autoProgressAudioEnabled,
  }) {
    return SettingsState(
      swipeDirection: swipeDirection ?? this.swipeDirection,
      autoProgressAudioEnabled: 
          autoProgressAudioEnabled ?? this.autoProgressAudioEnabled,
    );
  }
}
```

---

## Entity Relationships Diagram

```text
┌─────────────────┐
│     Series      │
│  (No Changes)   │
└────────┬────────┘
         │
         │ 1:N (contains)
         │
         ▼
┌─────────────────┐
│      Event      │
│   (Modified)    │
│─────────────────│
│ + autoProgress  │  ◄── NEW FIELD (bool, default: false)
└─────────────────┘

┌─────────────────────────┐
│   UserPreferences       │
│     (Modified)          │
│─────────────────────────│
│ + autoProgressAudio...  │  ◄── NEW FIELD (bool, default: true)
└─────────────────────────┘

┌─────────────────────────┐
│  SeriesStatistics       │
│  (New - Transient)      │
│─────────────────────────│
│ eventCount              │
│ expectedTimeSeconds     │
│ actualTimeSeconds       │
│─────────────────────────│
│ Computed:               │
│ • overUnderTimeSeconds  │
│ • isOvertime/Under/On   │
│ • formatted strings     │
└─────────────────────────┘
         ▲
         │ created by
         │
┌────────┴────────┐
│ LiveTimerBloc   │
│  (on complete)  │
└─────────────────┘
```

---

## Migration Guide

### Step 1: Update Models
1. Add `autoProgress` field to Event model with default `false`
2. Add `autoProgressAudioEnabled` field to UserPreferences with default `true`
3. Create SeriesStatistics class (not a Hive model)

### Step 2: Regenerate Type Adapters
```bash
cd chronosync
flutter packages pub run build_runner build --delete-conflicting-outputs
```

This generates:
- `lib/data/models/event.g.dart` (updated)
- `lib/data/models/user_preferences.g.dart` (updated)

### Step 3: Test Backward Compatibility
1. Open app with existing Hive data
2. Verify events load with `autoProgress = false`
3. Verify preferences load with `autoProgressAudioEnabled = true`
4. Create new event, toggle auto-progress, save, reload
5. Change audio setting, restart app, verify persistence

### Step 4: Update BLoC States
1. Add new fields to LiveTimerRunning state
2. Update LiveTimerComplete to include SeriesStatistics
3. Add autoProgressAudioEnabled to SettingsState

---

## Validation & Constraints

### Event Validation
```dart
class EventValidation {
  static String? validateTitle(String title) {
    if (title.trim().isEmpty) {
      return 'Event title cannot be empty';
    }
    return null;
  }

  static String? validateDuration(int durationInSeconds) {
    if (durationInSeconds <= 0) {
      return 'Duration must be greater than 0';
    }
    return null;
  }
}
```

### SeriesStatistics Validation
```dart
class SeriesStatisticsValidation {
  static bool isValid(SeriesStatistics stats) {
    return stats.eventCount > 0 &&
           stats.expectedTimeSeconds >= 0 &&
           stats.actualTimeSeconds >= 0;
  }
}
```

---

## Performance Considerations

### Storage Impact
- **Event**: +1 byte per event (boolean field)
- **UserPreferences**: +1 byte (boolean field)
- **SeriesStatistics**: 0 bytes (not persisted)
- **Total Impact**: Negligible (< 1KB for typical app data)

### Memory Impact
- **SeriesStatistics**: ~40 bytes per statistics object (3 ints + computed properties)
- **Lifecycle**: Created once per series completion, discarded on screen exit
- **Total Impact**: Negligible

### Computation Cost
- **Statistics Calculation**: O(1) - simple arithmetic on pre-tracked values
- **Auto-Progress Check**: O(1) - boolean comparisons on each timer tick
- **Impact**: Negligible (<1ms per check)

---

## Testing Considerations

### Unit Tests Required
- **Event**: Test autoProgress default value, serialization, deserialization
- **UserPreferences**: Test autoProgressAudioEnabled default, serialization
- **SeriesStatistics**: Test computed properties, formatting, edge cases (zero time, negative, large values)

### Integration Tests Required
- Hive migration: Load app with existing data, verify defaults applied
- Round-trip: Save event with autoProgress, reload, verify persistence
- Statistics lifecycle: Complete series, verify stats calculation, navigate away, verify disposal

---

## Summary

**Data Model Changes**:
- ✅ Event: Add `autoProgress` field (backward-compatible)
- ✅ UserPreferences: Add `autoProgressAudioEnabled` field (backward-compatible)
- ✅ SeriesStatistics: New transient class (not persisted)
- ✅ LiveTimerState: Extended to support auto-progression and statistics
- ✅ SettingsState: Extended to include audio toggle

**Migration Strategy**: Additive changes with safe defaults ensure zero-downtime migration for existing users.

**Storage Impact**: Minimal (<1KB)

**Next Steps**: See `contracts/` for state management contracts and `quickstart.md` for implementation guide.
