# LiveTimerBloc Events Contract

**Feature**: 004-auto-progress-events  
**Date**: October 23, 2025

## Overview

This contract defines the events that can be dispatched to the LiveTimerBloc to manage live timer sessions with auto-progression support.

## Events

### Existing Events (No Changes)

#### LiveTimerStarted
**Purpose**: Start a new live timer session for a series

**Payload**:
```dart
class LiveTimerStarted extends LiveTimerEvent {
  final Series series;
  
  LiveTimerStarted(this.series);
}
```

**Triggers**: User presses "Start" button on series
**Expected State Transition**: `LiveTimerInitial` → `LiveTimerRunning`

---

#### LiveTimerTicked
**Purpose**: Update timer state every second

**Payload**:
```dart
class LiveTimerTicked extends LiveTimerEvent {}
```

**Triggers**: Timer.periodic callback (every 1 second)
**Expected State Transition**: `LiveTimerRunning` → `LiveTimerRunning` (updated elapsed time)

**Side Effects**: 
- Checks if auto-progression should trigger
- Dispatches `AutoProgressTriggered` if conditions met

---

#### LiveTimerNextEvent
**Purpose**: Manually advance to next event

**Payload**:
```dart
class LiveTimerNextEvent extends LiveTimerEvent {}
```

**Triggers**: User presses "NEXT" button
**Expected State Transition**: 
- `LiveTimerRunning` → `LiveTimerRunning` (next event) OR
- `LiveTimerRunning` → `LiveTimerComplete` (if last event)

---

#### LiveTimerStopped
**Purpose**: Stop the live timer session

**Payload**:
```dart
class LiveTimerStopped extends LiveTimerEvent {}
```

**Triggers**: User exits live timer screen
**Expected State Transition**: `LiveTimerRunning` → `LiveTimerInitial`

---

### New Events

#### AutoProgressTriggered
**Purpose**: Automatically advance to next event when countdown reaches zero

**Payload**:
```dart
class AutoProgressTriggered extends LiveTimerEvent {}
```

**Triggers**: 
- `LiveTimerTicked` detects countdown <= 0 AND autoProgress == true AND minimum display time met
- App resume after backgrounding with auto-progression pending

**Preconditions**:
- Current state is `LiveTimerRunning`
- `currentEvent.autoProgress == true`
- `remainingSeconds <= 0`
- `DateTime.now().difference(eventStartTime).inSeconds >= 1` (minimum display time)

**Expected State Transition**:
- If not last event: `LiveTimerRunning` → `LiveTimerRunning` (next event)
- If last event: `LiveTimerRunning` → `LiveTimerComplete` (with statistics)

**Side Effects**:
- Display visual indicator (SnackBar)
- Play audio cue if `userPreferences.autoProgressAudioEnabled == true`
- Log auto-progression event

**Error Handling**:
- If next event index invalid: Log error, emit `LiveTimerInitial`
- If audio playback fails: Log error, continue (non-blocking)

---

## Event Flow Diagrams

### Manual Progression Flow
```
User presses "Start"
    ↓
LiveTimerStarted dispatched
    ↓
LiveTimerRunning emitted (event 0)
    ↓
LiveTimerTicked every 1 second
    ↓
User presses "NEXT"
    ↓
LiveTimerNextEvent dispatched
    ↓
LiveTimerRunning emitted (event 1)
    ↓
... repeat ...
    ↓
LiveTimerNextEvent on last event
    ↓
LiveTimerComplete emitted (with statistics)
```

### Auto-Progression Flow
```
User presses "Start" (all events have autoProgress=true)
    ↓
LiveTimerStarted dispatched
    ↓
LiveTimerRunning emitted (event 0, eventStartTime set)
    ↓
LiveTimerTicked every 1 second
    ↓
Countdown reaches 00:00 AND minDisplayTime met
    ↓
AutoProgressTriggered dispatched
    ↓
Visual indicator shown + Audio played (if enabled)
    ↓
LiveTimerRunning emitted (event 1, eventStartTime reset)
    ↓
... repeat automatically ...
    ↓
AutoProgressTriggered on last event
    ↓
LiveTimerComplete emitted (with statistics)
```

### Mixed Manual/Auto Flow
```
LiveTimerRunning (event 0, autoProgress=false)
    ↓
Countdown reaches 00:00
    ↓
NO auto-progression (continues to overtime)
    ↓
User presses "NEXT"
    ↓
LiveTimerNextEvent dispatched
    ↓
LiveTimerRunning emitted (event 1, autoProgress=true)
    ↓
Countdown reaches 00:00
    ↓
AutoProgressTriggered dispatched
    ↓
LiveTimerRunning emitted (event 2)
```

---

## Event Processing Logic

### LiveTimerTicked Handler (Modified)
```dart
void _onTicked(LiveTimerTicked event, Emitter<LiveTimerState> emit) {
  if (state is LiveTimerRunning) {
    final running = state as LiveTimerRunning;
    final newElapsed = running.elapsedSeconds + 1;
    final newTotalElapsed = running.totalSeriesElapsedSeconds + 1;
    
    // Check for auto-progression
    if (running.shouldAutoProgress) {
      add(AutoProgressTriggered());
      return; // Let AutoProgressTriggered handler manage transition
    }
    
    // Regular tick update
    emit(running.copyWith(
      elapsedSeconds: newElapsed,
      totalSeriesElapsedSeconds: newTotalElapsed,
    ));
  }
}
```

### AutoProgressTriggered Handler (New)
```dart
void _onAutoProgressTriggered(
  AutoProgressTriggered event, 
  Emitter<LiveTimerState> emit,
) async {
  if (state is! LiveTimerRunning) return;
  
  final running = state as LiveTimerRunning;
  
  // Log auto-progression start
  debugPrint('[AutoProgress] Triggered: ${running.currentEvent.title}');
  
  // Show visual feedback
  _showAutoProgressIndicator();
  
  // Play audio cue if enabled
  if (_settingsCubit.state.autoProgressAudioEnabled) {
    try {
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('[AutoProgress] ERROR: Audio playback failed - $e');
    }
  }
  
  // Advance to next event or complete
  if (running.isLastEvent) {
    // Calculate statistics
    final stats = _calculateStatistics(running);
    debugPrint('[AutoProgress] Completed series with stats: $stats');
    emit(LiveTimerComplete(statistics: stats));
  } else {
    // Move to next event
    final nextIndex = running.currentEventIndex + 1;
    emit(LiveTimerRunning(
      series: running.series,
      currentEventIndex: nextIndex,
      elapsedSeconds: 0,
      eventStartTime: DateTime.now(),
      seriesStartTime: running.seriesStartTime,
      totalSeriesElapsedSeconds: running.totalSeriesElapsedSeconds,
    ));
    debugPrint('[AutoProgress] Advanced to event $nextIndex');
  }
}
```

---

## Testing Contract

### Unit Tests Required

#### AutoProgressTriggered Event
```dart
blocTest<LiveTimerBloc, LiveTimerState>(
  'emits next event when AutoProgressTriggered and not last event',
  build: () => LiveTimerBloc(...),
  seed: () => LiveTimerRunning(
    series: seriesWithAutoProgress,
    currentEventIndex: 0,
    elapsedSeconds: 60,
    eventStartTime: DateTime.now().subtract(Duration(seconds: 61)),
    seriesStartTime: DateTime.now().subtract(Duration(seconds: 61)),
    totalSeriesElapsedSeconds: 61,
  ),
  act: (bloc) => bloc.add(AutoProgressTriggered()),
  expect: () => [
    isA<LiveTimerRunning>()
        .having((s) => s.currentEventIndex, 'currentEventIndex', 1)
        .having((s) => s.elapsedSeconds, 'elapsedSeconds', 0),
  ],
  verify: (_) {
    // Verify visual indicator shown
    // Verify audio played (if enabled)
    // Verify logging occurred
  },
);

blocTest<LiveTimerBloc, LiveTimerState>(
  'emits LiveTimerComplete with statistics when AutoProgressTriggered on last event',
  build: () => LiveTimerBloc(...),
  seed: () => LiveTimerRunning(
    series: seriesWithAutoProgress,
    currentEventIndex: 2, // last event
    elapsedSeconds: 60,
    eventStartTime: DateTime.now().subtract(Duration(seconds: 61)),
    seriesStartTime: DateTime.now().subtract(Duration(minutes: 3)),
    totalSeriesElapsedSeconds: 181,
  ),
  act: (bloc) => bloc.add(AutoProgressTriggered()),
  expect: () => [
    isA<LiveTimerComplete>()
        .having((s) => s.statistics.eventCount, 'eventCount', 3)
        .having((s) => s.statistics.actualTimeSeconds, 'actualTime', 181),
  ],
);
```

#### LiveTimerTicked with Auto-Progression Check
```dart
blocTest<LiveTimerBloc, LiveTimerState>(
  'dispatches AutoProgressTriggered when countdown reaches zero and autoProgress enabled',
  build: () => LiveTimerBloc(...),
  seed: () => LiveTimerRunning(
    series: seriesWithAutoProgress,
    currentEventIndex: 0,
    elapsedSeconds: 59,
    eventStartTime: DateTime.now().subtract(Duration(seconds: 60)),
    seriesStartTime: DateTime.now().subtract(Duration(seconds: 60)),
    totalSeriesElapsedSeconds: 60,
  ),
  act: (bloc) => bloc.add(LiveTimerTicked()),
  expect: () => [
    isA<LiveTimerRunning>()
        .having((s) => s.currentEventIndex, 'currentEventIndex', 1),
  ],
  verify: (bloc) {
    // Verify AutoProgressTriggered was dispatched internally
  },
);

blocTest<LiveTimerBloc, LiveTimerState>(
  'does NOT dispatch AutoProgressTriggered when autoProgress disabled',
  build: () => LiveTimerBloc(...),
  seed: () => LiveTimerRunning(
    series: seriesWithoutAutoProgress,
    currentEventIndex: 0,
    elapsedSeconds: 60,
    eventStartTime: DateTime.now().subtract(Duration(seconds: 61)),
    seriesStartTime: DateTime.now().subtract(Duration(seconds: 61)),
    totalSeriesElapsedSeconds: 61,
  ),
  act: (bloc) => bloc.add(LiveTimerTicked()),
  expect: () => [
    isA<LiveTimerRunning>()
        .having((s) => s.currentEventIndex, 'currentEventIndex', 0) // Still on same event
        .having((s) => s.elapsedSeconds, 'elapsedSeconds', 61),
  ],
);
```

---

## Error Handling

| Scenario | Response | State Transition |
|----------|----------|------------------|
| AutoProgressTriggered when not in LiveTimerRunning | Log warning, ignore | No change |
| Audio playback fails | Log error, continue auto-progression | Normal progression |
| Invalid next event index | Log error, emit LiveTimerInitial | → LiveTimerInitial |
| Statistics calculation fails | Log error, emit LiveTimerComplete with zero stats | → LiveTimerComplete |

---

## Performance Considerations

- **Event Frequency**: LiveTimerTicked fires every 1 second (low frequency)
- **Auto-Progression Check**: O(1) boolean comparisons on each tick
- **Audio Playback**: Non-blocking async operation
- **Visual Indicator**: UI update triggered asynchronously
- **Impact**: Negligible (<1ms overhead per tick)

---

## Dependencies

- **SettingsCubit**: Read `autoProgressAudioEnabled` setting
- **AudioPlayer**: Play audio cue (just_audio package)
- **UI Layer**: Display SnackBar indicator via BuildContext

---

## Backward Compatibility

- Existing events (LiveTimerStarted, LiveTimerTicked, LiveTimerNextEvent, LiveTimerStopped) unchanged
- New AutoProgressTriggered event is additive (doesn't affect existing flows)
- Events without `autoProgress=true` behave exactly as before

---

## Next Steps

See `live_timer_states.md` for state contract details.
