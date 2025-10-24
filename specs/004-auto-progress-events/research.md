# Research: Auto-Progress Events with Series Statistics

**Feature**: 004-auto-progress-events  
**Date**: October 23, 2025  
**Status**: Complete

## Overview

This document consolidates research findings for implementing auto-progression, visual/audio feedback, and series statistics in ChronoSync. All technical unknowns from the planning phase have been resolved.

## Research Areas

### 1. Timer-Based Auto-Progression in Flutter BLoC

**Decision**: Use Timer.periodic with BLoC event dispatch for auto-progression triggers

**Rationale**:
- LiveTimerBloc already uses Timer.periodic for second-by-second timer updates
- Can check countdown state on each tick and dispatch AutoProgressTriggered event when reaching "00:00"
- BLoC pattern ensures state management consistency and testability
- Avoids introducing new timing mechanisms or dependencies

**Implementation Pattern**:
```dart
// In LiveTimerBloc
_timer = Timer.periodic(Duration(seconds: 1), (timer) {
  final remainingSeconds = _calculateRemaining();
  
  // Check if auto-progress should trigger
  if (remainingSeconds <= 0 && currentEvent.autoProgress && !isLastEvent) {
    add(AutoProgressTriggered());
  }
  
  emit(/* updated state */);
});
```

**Alternatives Considered**:
- **Dart Isolates**: Rejected - overkill for simple timer logic, adds complexity
- **Future.delayed**: Rejected - less reliable for long-running timers, harder to cancel/restart
- **External timer package**: Rejected - Timer.periodic is built-in and sufficient

### 2. Visual Feedback for Auto-Progression

**Decision**: Use Flutter's SnackBar or custom overlay widget for brief visual indicator

**Rationale**:
- SnackBar provides built-in dismiss behavior and positioning
- Can be customized with brief duration (1-2 seconds) to match auto-progression timing
- Non-blocking UI pattern users are familiar with
- Easy to test and maintain

**Implementation Pattern**:
```dart
// Display indicator when auto-progression occurs
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Auto-advancing...'),
    duration: Duration(seconds: 1),
    behavior: SnackBarBehavior.floating,
  ),
);
```

**Alternatives Considered**:
- **Full-screen overlay**: Rejected - too intrusive for 1-second feedback
- **Dialog**: Rejected - blocks user interaction unnecessarily
- **Toast package**: Rejected - avoiding additional dependencies when SnackBar suffices

### 3. Audio Cue Implementation

**Decision**: Use audioplayers package (or assets + just_audio) for brief audio cue playback

**Rationale**:
- just_audio is a popular, well-maintained Flutter audio package
- Supports short audio cues with minimal latency
- Can be initialized once and played on-demand
- Respects device volume settings automatically

**Implementation Pattern**:
```dart
// Initialize audio player
final audioPlayer = AudioPlayer();
await audioPlayer.setAsset('assets/audio/auto_progress_beep.mp3');

// Play when auto-progression occurs (if enabled)
if (userPreferences.autoProgressAudioEnabled) {
  audioPlayer.play();
}
```

**Asset Requirements**:
- Include short audio file (e.g., beep.mp3, ~0.5 seconds)
- Add to pubspec.yaml under assets
- Consider platform-specific volume handling

**Alternatives Considered**:
- **System sounds**: Rejected - limited control over sound selection and timing
- **flutter_beep**: Rejected - limited customization options
- **Synthesized audio**: Rejected - unnecessary complexity for simple cue

### 4. Minimum Display Time Enforcement

**Decision**: Track event start timestamp and enforce 1-second minimum before allowing auto-progression

**Rationale**:
- Prevents UI flashing for very short events (< 1 second)
- Ensures users can read event title during rapid transitions
- Simple to implement with DateTime comparison

**Implementation Pattern**:
```dart
// In LiveTimerBloc state
DateTime eventStartTime;

// When checking for auto-progression
final elapsedSinceStart = DateTime.now().difference(eventStartTime);
if (remainingSeconds <= 0 && 
    currentEvent.autoProgress && 
    elapsedSinceStart.inSeconds >= 1) {
  add(AutoProgressTriggered());
}
```

**Alternatives Considered**:
- **Delay auto-progression with Future.delayed**: Rejected - introduces timing complexity
- **Warn users about short events**: Rejected - enforcement is better UX than warning

### 5. Series Statistics Calculation

**Decision**: Calculate statistics in LiveTimerBloc when series completes, store in state (not persisted)

**Rationale**:
- Statistics are derived data (event count, sum of durations, actual elapsed time)
- No persistence required per clarification session (statistics are transient)
- Can be calculated at series completion with simple arithmetic
- BLoC state provides natural place to hold statistics for display

**Implementation Pattern**:
```dart
// Calculate statistics when final event completes
final stats = SeriesStatistics(
  eventCount: series.events.length,
  expectedTime: series.events.fold(0, (sum, e) => sum + e.durationInSeconds),
  actualTime: totalElapsedSeconds, // tracked throughout series
  overUnderTime: actualTime - expectedTime,
);

emit(LiveTimerComplete(statistics: stats));
```

**Data Structure**:
```dart
class SeriesStatistics {
  final int eventCount;
  final int expectedTimeSeconds;
  final int actualTimeSeconds;
  
  int get overUnderTimeSeconds => actualTimeSeconds - expectedTimeSeconds;
  bool get isOvertime => overUnderTimeSeconds > 0;
  bool get isUndertime => overUnderTimeSeconds < 0;
  bool get isOnTime => overUnderTimeSeconds == 0;
}
```

**Alternatives Considered**:
- **Persist to Hive**: Rejected - per clarification, statistics are transient
- **Calculate in UI layer**: Rejected - business logic belongs in BLoC
- **Separate statistics service**: Rejected - simple calculation doesn't warrant new service

### 6. Hive Schema Migration for autoProgress Field

**Decision**: Add autoProgress field with default value false, regenerate type adapters

**Rationale**:
- Hive supports adding fields to existing types with default values
- Existing events will automatically get autoProgress = false (safe default)
- No manual migration code required
- Type adapter regeneration handles serialization

**Implementation Pattern**:
```dart
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
    this.autoProgress = false,  // Default to false
  });
}
```

**Migration Steps**:
1. Add field to Event model
2. Run `flutter packages pub run build_runner build --delete-conflicting-outputs`
3. Test with existing Hive data to verify backward compatibility

**Alternatives Considered**:
- **New Event class**: Rejected - unnecessary breaking change
- **Manual migration**: Rejected - Hive handles field additions gracefully

### 7. Background/Foreground Auto-Progression Handling

**Decision**: Leverage existing app lifecycle listeners to check timer state on resume

**Rationale**:
- Flutter provides AppLifecycleState for detecting background/foreground transitions
- Can calculate elapsed time during background period using timestamps
- Trigger auto-progression if countdown reached "00:00" while backgrounded
- Maintains timer precision per requirements

**Implementation Pattern**:
```dart
// In LiveTimerBloc or main app
class AppLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check if auto-progression should have occurred during background
      final elapsed = DateTime.now().difference(backgroundStartTime);
      if (shouldHaveAutoProgressed(elapsed)) {
        liveTimerBloc.add(AutoProgressTriggered());
      }
    } else if (state == AppLifecycleState.paused) {
      backgroundStartTime = DateTime.now();
    }
  }
}
```

**Alternatives Considered**:
- **Ignore background period**: Rejected - fails SC-008 requirement
- **Background timer**: Rejected - platform restrictions on background execution
- **Workmanager package**: Rejected - overkill for local timer state check

### 8. Timer Precision Maintenance

**Decision**: Use DateTime-based elapsed time calculation rather than tick counting

**Rationale**:
- Tick-based timers can drift due to event loop delays
- DateTime.now().difference() provides wall-clock accuracy
- Ensures 1-second precision requirement (SC-002a) is maintained
- Standard pattern for accurate timers in Flutter

**Implementation Pattern**:
```dart
// Track start time
final seriesStartTime = DateTime.now();

// Calculate elapsed on each tick
final elapsedSeconds = DateTime.now().difference(seriesStartTime).inSeconds;

// Calculate remaining based on actual elapsed time
final remainingSeconds = event.durationInSeconds - elapsedSeconds;
```

**Alternatives Considered**:
- **Tick counter (_tickCount++)**: Rejected - can drift over time
- **High-precision timer package**: Rejected - 1-second precision is sufficient

### 9. Logging Implementation

**Decision**: Use Flutter's built-in debugPrint with conditional logging based on build mode

**Rationale**:
- No additional dependencies required
- debugPrint automatically handles release mode (no-op)
- Can be replaced with logging package (e.g., logger) in future if needed
- Sufficient for initial debugging requirements (FR-012a/b/c)

**Implementation Pattern**:
```dart
// Log auto-progression events
debugPrint('[AutoProgress] Starting: ${event.title} (${event.duration})');
debugPrint('[AutoProgress] Completed: ${event.title} at ${DateTime.now()}');
debugPrint('[AutoProgress] ERROR: Failed to advance - ${error.toString()}');
```

**Future Enhancement**:
- Consider logger package for structured logging if needed
- Could add log level filtering (info, warning, error)
- Could persist logs to file for support debugging

**Alternatives Considered**:
- **logger package**: Deferred - can add later if structured logging needed
- **Custom logging service**: Rejected - premature abstraction
- **Firebase Crashlytics**: Deferred - analytics out of scope for MVP

## Best Practices

### Flutter BLoC State Management
- **Single Responsibility**: Each BLoC manages one domain concept
- **Event-Driven**: All state changes triggered by events
- **Testability**: BLoCs are pure Dart classes, easily testable with bloc_test
- **Immutable State**: Use Equatable for state comparison and rebuild optimization

### Hive Data Persistence
- **Type Adapters**: Always regenerate after model changes
- **Type IDs**: Never reuse or change existing type IDs
- **Backward Compatibility**: Test new fields with existing data
- **Box Management**: Open boxes once at app startup, close on shutdown

### Timer Management
- **Cancellation**: Always cancel timers in BLoC close() method
- **Accuracy**: Use DateTime for wall-clock accuracy vs. tick counting
- **Resource Cleanup**: Dispose audio players and cancel timers properly

### Widget Composition
- **Reusability**: Extract complex UI into widgets
- **Single Purpose**: Each widget has one responsibility
- **Testing**: Widget tests validate UI behavior independently

## Dependencies Required

### New Dependencies
- **just_audio**: ^0.9.36 (or latest) - For audio cue playback
  - Add to pubspec.yaml under dependencies
  - Asset support for audio files

### Existing Dependencies (No Changes)
- flutter_bloc: ^9.1.1
- hive: ^2.2.3
- hive_flutter: ^1.1.0
- equatable: ^2.0.7
- hive_generator: ^2.0.1 (dev)
- build_runner: ^2.4.13 (dev)

### Asset Requirements
- Add audio file (e.g., assets/audio/auto_progress_beep.mp3)
- Update pubspec.yaml assets section

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Timer drift during long series | Medium | Low | Use DateTime-based calculations |
| Background auto-progression miss | Low | Medium | Check state on app resume |
| Audio cue fails to play | Low | Low | Make audio optional, log errors |
| UI flashing with rapid events | Medium | Medium | Enforce 1-second minimum display |
| Hive migration breaks existing data | Low | High | Test with existing data, default values |

## Open Questions

**None** - All clarifications resolved during specification phase:
- Statistics persistence: Not persisted (transient)
- Visual feedback: Toast/SnackBar + optional audio
- Rapid progression: 1-second minimum display enforced
- Timer precision: 1-second tolerance
- Logging: Basic event/error logging

## References

- Flutter BLoC documentation: https://bloclibrary.dev/
- Hive documentation: https://docs.hivedb.dev/
- Flutter Timer class: https://api.flutter.dev/flutter/dart-async/Timer-class.html
- Flutter AppLifecycleState: https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html
- just_audio package: https://pub.dev/packages/just_audio
