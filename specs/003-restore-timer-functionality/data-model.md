# Data Model: Restore Timer Functionality

**Feature**: 003-restore-timer-functionality  
**Date**: October 23, 2025  
**Phase**: 1 (Design)

## Overview

This feature is a UI-only regression fix. **No data model changes are required.** All necessary data structures already exist and function correctly.

## Existing Entities (No Changes)

### Event
**Location**: `chronosync/lib/data/models/event.dart`  
**Status**: ✅ No changes required

**Attributes**:
- `title`: String - event name
- `duration`: Duration - scheduled event length

**Usage in This Feature**: 
- Read-only access via `LiveTimerState.currentEvent`
- Provides duration for countdown calculations (already working)

---

### Series
**Location**: `chronosync/lib/data/models/series.dart`  
**Status**: ✅ No changes required

**Attributes**:
- `title`: String - series name
- `events`: HiveList<Event> - ordered list of events

**Usage in This Feature**:
- Read-only access via `LiveTimerState.series`
- Provides event sequence for NEXT button logic (already working)

---

### LiveTimerState (BLoC State)
**Location**: `chronosync/lib/logic/live_timer_bloc/live_timer_state.dart`  
**Status**: ✅ No changes required - **already provides all necessary data**

**Attributes**:
- `series`: Series - current series being timed
- `currentEventIndex`: int - index of active event
- `elapsedSeconds`: int - **KEY**: total seconds since event started

**Computed Properties** (already implemented):
- `currentEvent`: Event - convenience getter for current event
- `remainingSeconds`: int - **KEY**: calculated as `duration - elapsed` (returns 0 if negative)
- `overtimeSeconds`: int - **KEY**: calculated as `elapsed - duration` (returns 0 if not overtime)
- `isOvertime`: bool - **KEY**: true when elapsed > duration

**Why No Changes Needed**:
All timer calculations are already correct. The regression is in the UI layer which was showing either countdown OR overtime, but not displaying the elapsed timer at all. The state provides:
1. `elapsedSeconds` for count-up display (FR-003) ✅
2. `remainingSeconds` for countdown display (FR-002) ✅  
3. `overtimeSeconds` for negative countdown (FR-008) ✅
4. `isOvertime` for color change trigger (FR-007) ✅

## State Flow (No Changes)

The timer state flow remains unchanged:

```
LiveTimerInitial
    ↓ [StartTimer event]
LiveTimerRunning (elapsedSeconds = 0)
    ↓ [TimerTick every 1s]
LiveTimerRunning (elapsedSeconds++)
    ↓ [elapsedSeconds > duration]
LiveTimerRunning (isOvertime = true)
    ↓ [NextEvent]
LiveTimerRunning (next event, elapsedSeconds = 0) OR LiveTimerCompleted
```

**No state transitions are added or modified.**

## UI-Only Changes Summary

The fix involves only presentation layer changes in `live_timer_screen.dart`:

**Before (Broken)**:
```dart
if (state is LiveTimerRunning) {
  // Shows countdown OR overtime message
  Text(state.isOvertime ? '00:00' : formatDuration(state.remainingSeconds))
  if (state.isOvertime) Text('Overtime: ...')
}
```

**After (Fixed)**:
```dart
if (state is LiveTimerRunning) {
  // ALWAYS show countdown (negative if overtime)
  Text('Time Remaining')
  Text(formatCountdown(state), color: state.isOvertime ? red : null)
  
  // ALWAYS show elapsed
  Text('Time Elapsed')  
  Text(formatDuration(state.elapsedSeconds))
}
```

## Validation Rules (No Changes)

Existing validation rules in Event and Series remain unchanged:
- Event duration must be positive
- Series must contain at least one event to start timer
- Current event index must be valid

These rules are enforced in BLoC layer and are unaffected by UI changes.

## Migration Requirements

**None.** No database schema changes, no data migration needed.

## Testing Data Model

For widget tests, mock `LiveTimerState` instances:

```dart
// Normal state (2 minutes elapsed, 3 minutes remaining)
final normalState = LiveTimerRunning(
  series: mockSeries,
  currentEventIndex: 0,
  elapsedSeconds: 120, // 2 minutes
  // Event duration: 5 minutes (300 seconds)
  // remainingSeconds = 180 (3 minutes)
);

// Overtime state (6 minutes elapsed, -1 minute)  
final overtimeState = LiveTimerRunning(
  series: mockSeries,
  currentEventIndex: 0,
  elapsedSeconds: 360, // 6 minutes
  // Event duration: 5 minutes (300 seconds)
  // remainingSeconds = 0
  // overtimeSeconds = 60 (1 minute)
  // isOvertime = true
);
```

## Diagram

Since this is a UI-only fix with no data model changes, here's the data flow:

```
┌─────────────────────┐
│  LiveTimerBloc      │
│  (no changes)       │
└──────────┬──────────┘
           │ emits
           ▼
┌─────────────────────┐
│  LiveTimerState     │
│  - elapsedSeconds   │ ◄── Already exists
│  - remainingSeconds │ ◄── Already computed correctly
│  - overtimeSeconds  │ ◄── Already computed correctly  
│  - isOvertime        │ ◄── Already computed correctly
└──────────┬──────────┘
           │ read by
           ▼
┌─────────────────────┐
│ LiveTimerScreen     │ ◄── FIX LOCATION: UI rendering only
│ (UI layer)          │
│  - Shows countdown  │ ◄── Add negative support
│  - Shows elapsed    │ ◄── Add this (currently missing)
│  - NEXT button      │ ◄── Already works
└─────────────────────┘
```

## Summary

**No data model work required for this feature.** All state management, calculations, and data persistence are working correctly. The regression is isolated to the presentation layer where the UI stopped displaying the elapsed timer and stopped showing negative countdown values during overtime. The fix is purely updating the widget tree in `live_timer_screen.dart` to consume the existing, correctly-functioning state data.
