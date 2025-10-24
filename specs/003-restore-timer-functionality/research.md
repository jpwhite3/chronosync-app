# Research: Restore Timer Functionality

**Feature**: 003-restore-timer-functionality  
**Date**: October 23, 2025  
**Phase**: 0 (Research & Analysis)

## Overview

This document captures research findings for restoring the dual timer display functionality that was present in the MVP (001-chronosync-mvp) but regressed during feature 002 (swipe-delete-items).

## Current State Analysis

### What Exists (Verified in Codebase)

**LiveTimerState (lib/logic/live_timer_bloc/live_timer_state.dart)**:
- ✅ `elapsedSeconds` property - tracks total time since event started
- ✅ `remainingSeconds` getter - calculates time left (returns 0 if overtime)
- ✅ `overtimeSeconds` getter - calculates negative time (returns 0 if not overtime)
- ✅ `isOvertime` getter - boolean flag for overtime state
- ✅ All calculations already implemented correctly

**LiveTimerScreen Current Implementation (lib/presentation/screens/live_timer_screen.dart)**:
- ❌ Shows countdown timer OR overtime message (mutually exclusive)
- ❌ Missing count-up (elapsed) timer display
- ✅ NEXT button exists and works
- ✅ Completion screen exists
- ✅ `_formatDuration()` helper already supports HH:MM:SS format

### Problem Identified

**Lines 28-43 in live_timer_screen.dart**:
```dart
Text(
  state.isOvertime
      ? '00:00'
      : _formatDuration(state.remainingSeconds),
  style: Theme.of(context).textTheme.displayLarge,
),
if (state.isOvertime) ...[
  const SizedBox(height: 10),
  Text(
    'Overtime: ${_formatDuration(state.overtimeSeconds)}',
    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),
  ),
],
```

**Issue**: The conditional logic shows "00:00" when overtime instead of continuing the countdown into negative territory. The elapsed timer is completely absent.

## Technical Decisions

### Decision 1: Display Layout Pattern

**Decision**: Use Column widget with labeled timer displays stacked vertically

**Rationale**:
- Existing code already uses Column for vertical layout
- Clear visual hierarchy: Event Title → Countdown → Elapsed → NEXT button
- Maintains consistency with current UI structure
- Works on small screens (4 inches) per SC-001

**Alternatives Considered**:
- **Row layout (side-by-side timers)**: Rejected - would require more horizontal space, harder to read on small screens, and label placement becomes awkward
- **Card-based containers**: Rejected - adds unnecessary visual complexity for a timer display that should be glanceable
- **Tabbed view**: Rejected - defeats purpose of "simultaneous" display requirement (FR-001)

**Implementation Pattern**:
```dart
Column(
  children: [
    Text('Event Title'),
    SizedBox(height: 20),
    // Countdown Timer with label
    Text('Time Remaining'),
    Text(countdownValue, style: ..., color: isOvertime ? red : black),
    SizedBox(height: 20),
    // Elapsed Timer with label  
    Text('Time Elapsed'),
    Text(elapsedValue, style: ...),
    SizedBox(height: 40),
    ElevatedButton('NEXT'),
  ],
)
```

### Decision 2: Countdown Display in Overtime

**Decision**: Show negative countdown values with red color (e.g., "-01:30")

**Rationale**:
- Matches MVP requirement FR-008 exactly
- More intuitive than showing static "00:00" - user can see how far over
- Red color provides immediate visual feedback per FR-007
- Consistent with user expectation from acceptance scenarios

**Alternatives Considered**:
- **Continue showing 00:00 in red**: Rejected - loses information about how far overtime
- **Show only overtime separately**: Current broken behavior - doesn't meet dual timer requirement
- **Flash or blink timer**: Rejected - can be distracting and accessibility concern

**Implementation**:
```dart
String formatCountdown(int remainingSeconds, bool isOvertime) {
  if (isOvertime) {
    int overtime = state.overtimeSeconds;
    return '-${_formatDuration(overtime)}';
  }
  return _formatDuration(remainingSeconds);
}
```

### Decision 3: Timer Label Text

**Decision**: 
- Countdown: "Time Remaining" 
- Elapsed: "Time Elapsed"

**Rationale**:
- Clear, unambiguous labels per FR-005 and FR-006
- Common terminology in timer/stopwatch applications
- "Remaining" pairs naturally with "Elapsed"
- Concise enough to fit on small screens

**Alternatives Considered**:
- **"Time Left" / "Time Passed"**: Valid but slightly less formal
- **"Countdown" / "Count-up"**: Too technical, less user-friendly
- **Icons only**: Rejected - accessibility concern, unclear meaning
- **"Remaining" / "Duration"**: Rejected - "Duration" ambiguous (could mean total or elapsed)

### Decision 4: Color Scheme for Overtime

**Decision**: 
- Countdown in overtime: Red text (#FF0000 or Theme.of(context).colorScheme.error)
- Elapsed timer: Always default text color (no color change)

**Rationale**:
- Red universally signals warning/alert per FR-007
- Keeps focus on the problem (overtime) without cluttering elapsed timer
- Matches existing codebase color usage for errors
- FR-010 explicitly states elapsed timer should not change color

**Alternatives Considered**:
- **Both timers turn red**: Rejected - FR-010 explicitly says elapsed stays normal
- **Yellow/amber for overtime**: Rejected - red is stronger signal, spec says "red"
- **Background color change**: Rejected - more invasive, text color sufficient

### Decision 5: Testing Strategy

**Decision**: Add widget tests for LiveTimerScreen focusing on visual assertions

**Rationale**:
- BLoC tests already exist and should still pass (no logic changes)
- Need to verify UI renders both timers correctly
- Test color changes for overtime scenario
- Validate label text presence

**Test Coverage**:
1. **Test**: Both timers visible in normal state
2. **Test**: Countdown shows negative value in overtime
3. **Test**: Countdown turns red in overtime
4. **Test**: Elapsed timer always present and default color
5. **Test**: Labels are correct ("Time Remaining", "Time Elapsed")
6. **Test**: NEXT button still present and functional

**Test Location**: `test/presentation/screens/live_timer_screen_test.dart` (new file)

## Flutter Widget Best Practices

### Relevant Flutter Patterns for This Fix

**Text Styling with Conditional Color**:
```dart
Text(
  value,
  style: Theme.of(context).textTheme.displayLarge?.copyWith(
    color: isOvertime ? Colors.red : null, // null uses default
  ),
)
```

**Semantic Labels for Accessibility**:
```dart
Semantics(
  label: 'Time remaining',
  child: Text(countdownValue),
)
```

**Testing Text Color in Widget Tests**:
```dart
final textWidget = tester.widget<Text>(find.text('-01:30'));
final textStyle = textWidget.style;
expect(textStyle?.color, Colors.red);
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing timer tick logic | Low | High | No BLoC changes, only UI. Existing tests will catch issues |
| Layout overflow on small screens | Low | Medium | Use SingleChildScrollView if needed, test on 4" screen |
| Color contrast accessibility | Low | Low | Use theme colors, red on white/black backgrounds meets WCAG |
| Regression in NEXT button | Very Low | Medium | Manual testing, button code unchanged |

## Dependencies & Integration Points

**No External Dependencies**:
- No new packages required
- No API calls
- No database schema changes
- No new BLoC events or states

**Integration Points**:
- LiveTimerBloc state (read-only access)
- Theme system for colors and text styles
- Navigator for NEXT button (existing)

## Performance Considerations

**Expected Performance**:
- No performance degradation expected
- Adds one additional Text widget (elapsed timer) - negligible cost
- No additional Timer.periodic calls (already ticking every second)
- Text rendering is highly optimized in Flutter

**Validation**:
- Meets SC-002: Timer accuracy within 1 second (no change to timing logic)
- Meets SC-003: Transitions <500ms (no change to transition logic)
- Meets SC-006: Responsive for 2+ hours (no additional computation per tick)

## Open Questions

None. All implementation details are clear from existing codebase analysis and MVP spec comparison.

## References

- MVP Spec: `/Users/jpwhite/Code/cronos-app/specs/001-chronosync-mvp/spec.md`
- Feature 002 Spec: `/Users/jpwhite/Code/cronos-app/specs/002-swipe-delete-items/spec.md`
- Current LiveTimerState: `chronosync/lib/logic/live_timer_bloc/live_timer_state.dart`
- Target File: `chronosync/lib/presentation/screens/live_timer_screen.dart`
- Flutter BLoC Docs: https://bloclibrary.dev/
- Flutter Testing Guide: https://docs.flutter.dev/testing
