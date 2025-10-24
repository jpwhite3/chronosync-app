# Quickstart Guide: Restore Timer Functionality

**Feature**: 003-restore-timer-functionality  
**Date**: October 23, 2025  
**Estimated Time**: 30-45 minutes

## Overview

This is a **UI-only regression fix** to restore dual timer display (countdown + elapsed) in the LiveTimerScreen. All state management already works correctly. You'll modify one file and add widget tests.

## Prerequisites

- ✅ Flutter SDK (Dart 3.9.2) - already installed
- ✅ Existing project dependencies installed (`flutter pub get`)
- ✅ LiveTimerBloc and LiveTimerState already provide all needed data
- ✅ Familiarity with Flutter BLoC pattern

## Step-by-Step Implementation

### Step 1: Understand Current Broken State (2 minutes)

**File**: `chronosync/lib/presentation/screens/live_timer_screen.dart`

**Current problem** (lines 28-43):
```dart
Text(
  state.isOvertime
      ? '00:00'  // ❌ Shows static 00:00 instead of negative time
      : _formatDuration(state.remainingSeconds),
  style: Theme.of(context).textTheme.displayLarge,
),
if (state.isOvertime) ...[
  const SizedBox(height: 10),
  Text(
    'Overtime: ${_formatDuration(state.overtimeSeconds)}',
    // ❌ Overtime shown as separate message, not in countdown
  ),
],
// ❌ MISSING: Elapsed timer completely absent
```

### Step 2: Add Helper Method for Negative Countdown (5 minutes)

**File**: `chronosync/lib/presentation/screens/live_timer_screen.dart`

**Add this method** at the bottom of the class (after `_formatDuration`):

```dart
String _formatCountdown(LiveTimerRunning state) {
  if (state.isOvertime) {
    // Show negative time using overtimeSeconds
    return '-${_formatDuration(state.overtimeSeconds)}';
  }
  // Show remaining time normally
  return _formatDuration(state.remainingSeconds);
}
```

**What this does**: Formats countdown with negative sign when overtime, using existing `_formatDuration` helper.

### Step 3: Replace Timer Display Section (15 minutes)

**File**: `chronosync/lib/presentation/screens/live_timer_screen.dart`

**Find the section** in the `LiveTimerRunning` state builder (currently lines 19-51).

**Replace lines 28-43** with this complete dual timer display:

```dart
// Countdown Timer Section
const SizedBox(height: 20),
Text(
  'Time Remaining',
  style: Theme.of(context).textTheme.labelLarge,
),
const SizedBox(height: 8),
Text(
  _formatCountdown(state),
  style: Theme.of(context).textTheme.displayLarge?.copyWith(
    color: state.isOvertime ? Colors.red : null,
    fontWeight: FontWeight.bold,
  ),
),

// Elapsed Timer Section (NEW)
const SizedBox(height: 32),
Text(
  'Time Elapsed',
  style: Theme.of(context).textTheme.labelLarge,
),
const SizedBox(height: 8),
Text(
  _formatDuration(state.elapsedSeconds),
  style: Theme.of(context).textTheme.displayMedium?.copyWith(
    fontWeight: FontWeight.bold,
  ),
),
```

**Key changes**:
1. ✅ Added "Time Remaining" label above countdown
2. ✅ Countdown uses new `_formatCountdown()` method (supports negative)
3. ✅ Countdown color changes to red when `state.isOvertime` is true
4. ✅ Added complete "Elapsed Timer" section with label and value
5. ✅ Elapsed timer shows `state.elapsedSeconds` (always present)

### Step 4: Verify NEXT Button Still Present (1 minute)

**File**: Same file, check lines after timer display

**Ensure this code remains** (should be around line 60):

```dart
const SizedBox(height: 40),
ElevatedButton(
  onPressed: () {
    context.read<LiveTimerBloc>().add(NextEvent());
  },
  child: const Text('NEXT'),
),
```

**No changes needed here** - just verify it's still there and properly formatted.

### Step 5: Full Code Review (3 minutes)

Your complete `LiveTimerRunning` widget tree should now look like:

```dart
if (state is LiveTimerRunning) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Event Title
        Text(
          state.currentEvent.title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        
        // Countdown Timer Section
        const SizedBox(height: 20),
        Text(
          'Time Remaining',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _formatCountdown(state),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            color: state.isOvertime ? Colors.red : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        // Elapsed Timer Section
        const SizedBox(height: 32),
        Text(
          'Time Elapsed',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _formatDuration(state.elapsedSeconds),
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        
        // NEXT Button
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () {
            context.read<LiveTimerBloc>().add(NextEvent());
          },
          child: const Text('NEXT'),
        ),
      ],
    ),
  );
}
```

### Step 6: Manual Testing (5 minutes)

**Run the app**:
```bash
cd chronosync
flutter run
```

**Test scenarios**:

1. **Normal timer display**:
   - Create a series with a 2-minute event
   - Start the timer
   - ✅ Verify both "Time Remaining" and "Time Elapsed" labels visible
   - ✅ Verify countdown decreases (01:59, 01:58, ...)
   - ✅ Verify elapsed increases (00:01, 00:02, ...)
   - ✅ Verify countdown is black (not red)

2. **Overtime behavior**:
   - Let the timer run past 2 minutes
   - ✅ Verify countdown shows "-00:01", "-00:02", etc.
   - ✅ Verify countdown turns RED
   - ✅ Verify elapsed continues normally (02:01, 02:02, ...) in default color
   - ✅ Verify both timers still visible simultaneously

3. **NEXT button**:
   - Press NEXT during normal time
   - ✅ Verify advances to next event with timers reset
   - Press NEXT during overtime
   - ✅ Verify advances to next event normally
   - Press NEXT on last event
   - ✅ Verify shows completion screen

4. **Long duration** (optional):
   - Create event with 65-minute duration
   - Fast-forward device time or wait
   - ✅ Verify format switches to HH:MM:SS (01:05:00)

### Step 7: Add Widget Tests (10 minutes)

**Create new file**: `chronosync/test/presentation/screens/live_timer_screen_test.dart`

```dart
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:chronosync/presentation/screens/live_timer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'live_timer_screen_test.mocks.dart';

@GenerateMocks([Box, LiveTimerBloc])
void main() {
  late MockLiveTimerBloc mockBloc;
  late MockBox<Event> mockEventBox;
  late Series testSeries;

  setUp(() {
    mockBloc = MockLiveTimerBloc();
    mockEventBox = MockBox<Event>();
    when(mockEventBox.name).thenReturn('events');

    testSeries = Series(
      title: 'Test Series',
      events: HiveList(mockEventBox),
    );
    testSeries.events.add(Event(
      title: 'Test Event',
      duration: const Duration(minutes: 5),
    ));

    when(mockBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget createWidgetUnderTest(LiveTimerState state) {
    when(mockBloc.state).thenReturn(state);

    return MaterialApp(
      home: BlocProvider<LiveTimerBloc>.value(
        value: mockBloc,
        child: const LiveTimerScreen(),
      ),
    );
  }

  group('LiveTimerScreen - Normal State', () {
    testWidgets('displays both countdown and elapsed timers', (tester) async {
      final state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 120, // 2 minutes elapsed
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Verify labels
      expect(find.text('Time Remaining'), findsOneWidget);
      expect(find.text('Time Elapsed'), findsOneWidget);

      // Verify countdown shows 3 minutes remaining
      expect(find.text('03:00'), findsOneWidget);

      // Verify elapsed shows 2 minutes
      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('countdown is not red in normal state', (tester) async {
      final state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 60,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      final countdownWidget = tester.widget<Text>(find.text('04:00'));
      expect(countdownWidget.style?.color, isNot(Colors.red));
    });
  });

  group('LiveTimerScreen - Overtime State', () {
    testWidgets('displays negative countdown in overtime', (tester) async {
      final state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 360, // 6 minutes elapsed (1 min over)
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Verify countdown shows negative time
      expect(find.text('-01:00'), findsOneWidget);

      // Verify elapsed continues normally
      expect(find.text('06:00'), findsOneWidget);
    });

    testWidgets('countdown turns red in overtime', (tester) async {
      final state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 330, // 30 seconds over
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      final countdownWidget = tester.widget<Text>(find.text('-00:30'));
      expect(countdownWidget.style?.color, Colors.red);
    });

    testWidgets('elapsed timer stays default color in overtime', (tester) async {
      final state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 330,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      final elapsedWidget = tester.widget<Text>(find.text('05:30'));
      expect(elapsedWidget.style?.color, isNot(Colors.red));
    });
  });

  group('LiveTimerScreen - NEXT Button', () {
    testWidgets('NEXT button is present', (tester) async {
      final state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 60,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      expect(find.widgetWithText(ElevatedButton, 'NEXT'), findsOneWidget);
    });
  });
}
```

**Run tests**:
```bash
flutter test test/presentation/screens/live_timer_screen_test.dart
```

**Generate mocks** (if needed):
```bash
flutter pub run build_runner build
```

### Step 8: Verify Existing Tests Still Pass (2 minutes)

**Run all tests**:
```bash
flutter test
```

**Expected**: All existing BLoC tests should still pass since no state logic changed.

## Verification Checklist

- [ ] Both "Time Remaining" and "Time Elapsed" labels visible
- [ ] Countdown timer shows remaining time in MM:SS format
- [ ] Countdown shows negative values in overtime (e.g., "-01:30")
- [ ] Countdown turns red when overtime
- [ ] Elapsed timer shows elapsed time in MM:SS format
- [ ] Elapsed timer never changes color (stays default)
- [ ] Both timers update every second
- [ ] NEXT button present and functional
- [ ] Completion screen works on last event
- [ ] All tests pass (existing + new widget tests)

## Common Issues & Solutions

**Issue**: Countdown showing "00:00" instead of negative
- **Solution**: Verify you're using `_formatCountdown(state)` not `_formatDuration(state.remainingSeconds)`

**Issue**: Elapsed timer missing
- **Solution**: Check you added the entire "Time Elapsed" section after countdown

**Issue**: Both timers are red in overtime
- **Solution**: Only countdown should have conditional color, elapsed should have no color specified

**Issue**: Layout overflow on small screens
- **Solution**: Wrap Column in SingleChildScrollView if needed, or reduce spacing

**Issue**: Tests fail with "LateInitializationError"
- **Solution**: Ensure mock box has `when(mockEventBox.name).thenReturn('events')`

## Performance Notes

- **No performance impact**: Added one Text widget (negligible)
- **No new timer ticks**: Still using existing 1-second tick
- **No BLoC changes**: Zero impact on state management performance

## Files Modified Summary

**Modified** (1 file):
- `chronosync/lib/presentation/screens/live_timer_screen.dart`

**Created** (1 file):
- `chronosync/test/presentation/screens/live_timer_screen_test.dart`

**Total LOC Changed**: ~50 lines modified, ~100 lines added (tests)

## Next Steps

1. Commit changes: `git add . && git commit -m "Fix: Restore dual timer display with overtime support"`
2. Push to feature branch: `git push origin 003-restore-timer-functionality`
3. Create pull request targeting `main`
4. Manual QA on physical device (especially small screens)
5. Merge after approval

## Resources

- BLoC Pattern: https://bloclibrary.dev/
- Flutter Widget Testing: https://docs.flutter.dev/testing/overview#widget-tests
- Material Design Typography: https://m3.material.io/styles/typography/overview
