# Widget Contracts: Restore Timer Functionality

**Feature**: 003-restore-timer-functionality  
**Date**: October 23, 2025  
**Phase**: 1 (Design)

## Overview

This feature has no API contracts (no external services, no new BLoC events). This document defines the widget interface contract for the updated LiveTimerScreen.

## LiveTimerScreen Widget Contract

### Input Contract (BLoC State)

**Widget consumes**: `LiveTimerState` from `LiveTimerBloc`

**Required State Properties** (all already exist):
```dart
class LiveTimerRunning extends LiveTimerState {
  final Series series;
  final int currentEventIndex;
  final int elapsedSeconds;
  
  // Computed getters
  Event get currentEvent;
  int get remainingSeconds;
  int get overtimeSeconds;
  bool get isOvertime;
}
```

**State Transitions Widget Must Handle**:
1. `LiveTimerInitial` → Show loading/initializing message
2. `LiveTimerRunning` → Show dual timer display with NEXT button
3. `LiveTimerCompleted` → Show completion screen with back button

### Output Contract (User Actions)

**Widget dispatches**: BLoC events via `context.read<LiveTimerBloc>()`

**Events** (all already exist, no new events):
```dart
// When user presses NEXT button
NextEvent()

// Widget does NOT dispatch StartTimer or TimerTick
// Those are handled by series list screen and BLoC internally
```

**Navigation Actions**:
```dart
// When user presses "Back to Series" on completion screen
Navigator.pop(context)
```

## Visual Display Contract

### Normal State (Not Overtime)

**MUST display** (FR-001 through FR-006):
1. Event title at top (already working)
2. "Time Remaining" label above countdown timer
3. Countdown timer showing `remainingSeconds` in MM:SS or HH:MM:SS format
4. "Time Elapsed" label above count-up timer  
5. Count-up timer showing `elapsedSeconds` in MM:SS or HH:MM:SS format
6. NEXT button at bottom (already working)

**Color requirements**:
- Countdown timer: default text color (typically black or theme primary)
- Elapsed timer: default text color

**Layout constraints**:
- All elements visible without scrolling on 4-inch screens (SC-001)
- Countdown timer font size: displayLarge (existing)
- Elapsed timer font size: displayMedium or headlineMedium (recommended)
- Spacing: minimum 20dp between major elements

### Overtime State

**MUST display** (FR-007 through FR-010):
1. Event title at top (already working)
2. "Time Remaining" label above countdown timer
3. Countdown timer showing **negative value** `-${overtimeSeconds}` in MM:SS format
4. "Time Elapsed" label above count-up timer
5. Count-up timer showing `elapsedSeconds` in MM:SS or HH:MM:SS format  
6. NEXT button at bottom (already working)

**Color requirements**:
- Countdown timer: **RED** (Colors.red or Theme.of(context).colorScheme.error)
- Elapsed timer: default text color (NO color change per FR-010)

**Format requirements** (FR-016 through FR-018):
- Negative sign MUST prefix countdown in overtime: "-01:30", "-00:05"
- Use MM:SS for times under 1 hour: "05:30", "-02:15"
- Use HH:MM:SS for times 1 hour or more: "01:23:45", "-02:30:15"

### Completion State

**MUST display** (FR-015):
1. "All events completed!" message (already working)
2. "Back to Series" button that navigates back (already working)

No changes required for completion state.

## Example Widget Tree Structure

```dart
Scaffold(
  appBar: AppBar(title: Text('Live Timer')),
  body: BlocBuilder<LiveTimerBloc, LiveTimerState>(
    builder: (context, state) {
      if (state is LiveTimerRunning) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Event Title
              Text(state.currentEvent.title, style: headlineMedium),
              SizedBox(height: 20),
              
              // Countdown Timer Section
              Text('Time Remaining', style: labelLarge),
              Text(
                _formatCountdown(state),
                style: displayLarge.copyWith(
                  color: state.isOvertime ? Colors.red : null,
                ),
              ),
              SizedBox(height: 20),
              
              // Elapsed Timer Section (NEW)
              Text('Time Elapsed', style: labelLarge),
              Text(
                _formatDuration(state.elapsedSeconds),
                style: displayMedium,
              ),
              SizedBox(height: 40),
              
              // NEXT Button
              ElevatedButton(
                onPressed: () => context.read<LiveTimerBloc>().add(NextEvent()),
                child: Text('NEXT'),
              ),
            ],
          ),
        );
      }
      // ... handle other states ...
    },
  ),
)
```

## Helper Method Contracts

### `_formatCountdown(LiveTimerRunning state) -> String`

**Purpose**: Format countdown timer value with negative support for overtime

**Logic**:
```dart
String _formatCountdown(LiveTimerRunning state) {
  if (state.isOvertime) {
    // Show negative time
    return '-${_formatDuration(state.overtimeSeconds)}';
  }
  // Show remaining time
  return _formatDuration(state.remainingSeconds);
}
```

**Returns**:
- Normal: "05:30", "01:23:45"
- Overtime: "-01:30", "-00:05"

### `_formatDuration(int seconds) -> String`

**Purpose**: Format seconds as MM:SS or HH:MM:SS

**Logic** (already exists, no changes):
```dart
String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
           '${minutes.toString().padLeft(2, '0')}:'
           '${secs.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
         '${secs.toString().padLeft(2, '0')}';
}
```

**Returns**:
- Under 1 hour: "05:30", "00:05"
- 1 hour or more: "01:23:45", "02:00:00"

## Accessibility Contract

**Semantic Labels** (recommended but not required for MVP restoration):
```dart
Semantics(
  label: 'Time remaining ${_formatCountdown(state)}',
  child: Text(...),
)

Semantics(
  label: 'Time elapsed ${_formatDuration(state.elapsedSeconds)}',
  child: Text(...),
)
```

**Why recommended**: Screen reader users benefit from explicit context about which timer is which.

## Testing Contract

Widget tests MUST verify:

1. **Both timers visible simultaneously** (FR-001)
   - Find text containing "Time Remaining"
   - Find text containing "Time Elapsed"
   - Find countdown value text
   - Find elapsed value text

2. **Countdown format correct** (FR-002, FR-016, FR-017)
   - Normal state: find text matching /^\d{2}:\d{2}$/
   - Overtime state: find text matching /^-\d{2}:\d{2}$/
   - Long duration: find text matching /^\d{2}:\d{2}:\d{2}$/

3. **Elapsed format correct** (FR-003, FR-016, FR-017)
   - Find text matching /^\d{2}:\d{2}$/
   - Long duration: find text matching /^\d{2}:\d{2}:\d{2}$/

4. **Color changes in overtime** (FR-007, FR-009, FR-010)
   - Countdown text has red color when isOvertime=true
   - Elapsed text does NOT have red color

5. **NEXT button present** (FR-011)
   - Find button with text "NEXT"
   - Verify onPressed dispatches NextEvent

## No API Contracts

This feature has no:
- REST endpoints
- GraphQL queries/mutations  
- WebSocket connections
- External service integrations
- BLoC event additions
- BLoC state additions

All interaction is internal to the Flutter app via existing BLoC architecture.
