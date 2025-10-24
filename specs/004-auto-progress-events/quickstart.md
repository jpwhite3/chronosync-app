# Quickstart Guide: Auto-Progress Events with Series Statistics

**Feature**: 004-auto-progress-events  
**Date**: October 23, 2025  
**Estimated Time**: 6-8 hours

## Overview

This guide provides a step-by-step implementation path for adding auto-progression and series statistics to ChronoSync. Follow the phases in order for incremental, testable progress.

## Prerequisites

- ✅ Specification complete and clarified
- ✅ Research complete (see research.md)
- ✅ Data model defined (see data-model.md)
- ✅ Contracts defined (see contracts/)
- ✅ Constitution checks passed

## Implementation Phases

### Phase 1: Data Model Updates (1-2 hours)

#### Step 1.1: Update Event Model
**File**: `lib/data/models/event.dart`

```dart
// Add autoProgress field
@HiveField(2)
bool autoProgress;

// Update constructor
Event({
  required this.title, 
  required this.durationInSeconds,
  this.autoProgress = false,
});

// Update fromDuration constructor
Event.fromDuration({
  required this.title, 
  required Duration duration,
  this.autoProgress = false,
}) : durationInSeconds = duration.inSeconds;
```

**Test**: Create unit test for autoProgress default value

#### Step 1.2: Update UserPreferences Model
**File**: `lib/data/models/user_preferences.dart`

```dart
// Add audio toggle field
@HiveField(1)
bool autoProgressAudioEnabled;

// Update constructor
UserPreferences({
  this.swipeDirection = 'ltr',
  this.autoProgressAudioEnabled = true,
});
```

**Test**: Create unit test for autoProgressAudioEnabled default

#### Step 1.3: Regenerate Type Adapters
```bash
cd chronosync
flutter packages pub run build_runner build --delete-conflicting-outputs
```

**Verify**: Check that `event.g.dart` and `user_preferences.g.dart` were regenerated

#### Step 1.4: Create SeriesStatistics Class
**File**: `lib/data/models/series_statistics.dart` (new)

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

  int get overUnderTimeSeconds => actualTimeSeconds - expectedTimeSeconds;
  bool get isOvertime => overUnderTimeSeconds > 0;
  bool get isUndertime => overUnderTimeSeconds < 0;
  bool get isOnTime => overUnderTimeSeconds == 0;

  // Add formatted string methods from data-model.md
}
```

**Test**: Create unit tests for computed properties and formatting

**Checkpoint**: Run tests, verify data model changes work

---

### Phase 2: Settings & Audio (1 hour)

#### Step 2.1: Update SettingsState
**File**: `lib/logic/settings_cubit/settings_state.dart`

```dart
class SettingsState extends Equatable {
  final SwipeDirection swipeDirection;
  final bool autoProgressAudioEnabled;

  const SettingsState({
    this.swipeDirection = SwipeDirection.ltr,
    this.autoProgressAudioEnabled = true,
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

#### Step 2.2: Update SettingsCubit
**File**: `lib/logic/settings_cubit/settings_cubit.dart`

```dart
// Add method to toggle audio
void toggleAutoProgressAudio(bool enabled) {
  final preferences = _preferencesRepository.getPreferences();
  preferences.autoProgressAudioEnabled = enabled;
  _preferencesRepository.savePreferences(preferences);
  emit(state.copyWith(autoProgressAudioEnabled: enabled));
}
```

#### Step 2.3: Add Audio Dependency
**File**: `chronosync/pubspec.yaml`

```yaml
dependencies:
  just_audio: ^0.9.36
```

Run: `flutter pub get`

#### Step 2.4: Add Audio Asset
1. Create `chronosync/assets/audio/` directory
2. Add short beep audio file (e.g., `auto_progress_beep.mp3`)
3. Update `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/audio/auto_progress_beep.mp3
```

#### Step 2.5: Update Settings Screen
**File**: `lib/presentation/screens/settings_screen.dart`

```dart
// Add audio toggle switch
SwitchListTile(
  title: Text('Auto-Progress Audio'),
  subtitle: Text('Play sound when events auto-advance'),
  value: state.autoProgressAudioEnabled,
  onChanged: (value) {
    context.read<SettingsCubit>().toggleAutoProgressAudio(value);
  },
)
```

**Test**: Manual test - toggle audio setting, restart app, verify persistence

**Checkpoint**: Verify settings screen shows audio toggle and persists changes

---

### Phase 3: LiveTimerBloc Updates (2-3 hours)

#### Step 3.1: Update LiveTimerState
**File**: `lib/logic/live_timer_bloc/live_timer_state.dart`

```dart
// Add fields to LiveTimerRunning
class LiveTimerRunning extends LiveTimerState {
  // Existing fields...
  final DateTime eventStartTime;
  final DateTime? seriesStartTime;
  final int totalSeriesElapsedSeconds;

  // Add computed property
  bool get shouldAutoProgress {
    final minDisplayTimeElapsed = 
        DateTime.now().difference(eventStartTime).inSeconds >= 1;
    return remainingSeconds <= 0 && 
           currentEvent.autoProgress && 
           minDisplayTimeElapsed;
  }
  
  // Update copyWith to include new fields
}

// Update LiveTimerComplete
class LiveTimerComplete extends LiveTimerState {
  final SeriesStatistics statistics;
  
  LiveTimerComplete({required this.statistics});
}
```

#### Step 3.2: Add AutoProgressTriggered Event
**File**: `lib/logic/live_timer_bloc/live_timer_event.dart`

```dart
class AutoProgressTriggered extends LiveTimerEvent {
  @override
  List<Object?> get props => [];
}
```

#### Step 3.3: Update LiveTimerBloc
**File**: `lib/logic/live_timer_bloc/live_timer_bloc.dart`

**Add audio player field**:
```dart
class LiveTimerBloc extends Bloc<LiveTimerEvent, LiveTimerState> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SettingsCubit _settingsCubit;
  
  // Constructor initialization
  // Load audio asset in constructor
}
```

**Update LiveTimerStarted handler**:
```dart
void _onStarted(LiveTimerStarted event, Emitter<LiveTimerState> emit) {
  emit(LiveTimerRunning(
    series: event.series,
    currentEventIndex: 0,
    elapsedSeconds: 0,
    eventStartTime: DateTime.now(),
    seriesStartTime: DateTime.now(),
    totalSeriesElapsedSeconds: 0,
  ));
  
  _startTimer();
}
```

**Update LiveTimerTicked handler**:
```dart
void _onTicked(LiveTimerTicked event, Emitter<LiveTimerState> emit) {
  if (state is LiveTimerRunning) {
    final running = state as LiveTimerRunning;
    final newElapsed = running.elapsedSeconds + 1;
    final newTotal = running.totalSeriesElapsedSeconds + 1;
    
    // Check for auto-progression
    if (running.shouldAutoProgress) {
      add(AutoProgressTriggered());
      return;
    }
    
    emit(running.copyWith(
      elapsedSeconds: newElapsed,
      totalSeriesElapsedSeconds: newTotal,
    ));
  }
}
```

**Add AutoProgressTriggered handler**:
```dart
Future<void> _onAutoProgressTriggered(
  AutoProgressTriggered event,
  Emitter<LiveTimerState> emit,
) async {
  if (state is! LiveTimerRunning) return;
  
  final running = state as LiveTimerRunning;
  
  debugPrint('[AutoProgress] Triggered: ${running.currentEvent.title}');
  
  // Play audio if enabled
  if (_settingsCubit.state.autoProgressAudioEnabled) {
    try {
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('[AutoProgress] ERROR: Audio failed - $e');
    }
  }
  
  // Advance or complete
  if (running.isLastEvent) {
    final stats = _calculateStatistics(running);
    emit(LiveTimerComplete(statistics: stats));
  } else {
    emit(LiveTimerRunning(
      series: running.series,
      currentEventIndex: running.currentEventIndex + 1,
      elapsedSeconds: 0,
      eventStartTime: DateTime.now(),
      seriesStartTime: running.seriesStartTime,
      totalSeriesElapsedSeconds: running.totalSeriesElapsedSeconds,
    ));
  }
}
```

**Add statistics calculation**:
```dart
SeriesStatistics _calculateStatistics(LiveTimerRunning running) {
  final eventCount = running.series.events.length;
  final expectedTime = running.series.events
      .fold(0, (sum, e) => sum + e.durationInSeconds);
  final actualTime = running.totalSeriesElapsedSeconds;
  
  return SeriesStatistics(
    eventCount: eventCount,
    expectedTimeSeconds: expectedTime,
    actualTimeSeconds: actualTime,
  );
}
```

**Update close() method**:
```dart
@override
Future<void> close() {
  _timer?.cancel();
  _audioPlayer.dispose();
  return super.close();
}
```

**Test**: Create bloc_test for AutoProgressTriggered event

**Checkpoint**: Run BLoC tests, verify auto-progression logic works

---

### Phase 4: UI Updates (2-3 hours)

#### Step 4.1: Update Event List Screen
**File**: `lib/presentation/screens/event_list_screen.dart`

Add auto-progress toggle to event creation/edit dialog:

```dart
// In event dialog
SwitchListTile(
  title: Text('Auto-progress'),
  subtitle: Text('Automatically advance when time expires'),
  value: autoProgress,
  onChanged: (value) {
    setState(() {
      autoProgress = value;
    });
  },
)
```

Update event list item to show auto-progress indicator:

```dart
// In event list tile
trailing: Row(
  children: [
    if (event.autoProgress)
      Icon(Icons.fast_forward, color: Colors.blue),
    // Existing trailing widgets...
  ],
)
```

**Test**: Manual test - create event with auto-progress, verify icon shows

#### Step 4.2: Create Auto-Progress Indicator Widget
**File**: `lib/presentation/widgets/auto_progress_indicator.dart` (new)

```dart
import 'package:flutter/material.dart';

class AutoProgressIndicator {
  static void show(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.fast_forward, color: Colors.white),
            SizedBox(width: 8),
            Text('Auto-advancing...'),
          ],
        ),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blue,
      ),
    );
  }
}
```

**Test**: Widget test for SnackBar display

#### Step 4.3: Create Series Statistics Panel Widget
**File**: `lib/presentation/widgets/series_statistics_panel.dart` (new)

```dart
import 'package:flutter/material.dart';
import '../../data/models/series_statistics.dart';

class SeriesStatisticsPanel extends StatelessWidget {
  final SeriesStatistics statistics;

  const SeriesStatisticsPanel({Key? key, required this.statistics}) 
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Series Summary', 
                style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: 16),
            _buildStatRow('Events', '${statistics.eventCount}'),
            _buildStatRow('Expected Time', 
                statistics.expectedTimeFormatted),
            _buildStatRow('Actual Time', 
                statistics.actualTimeFormatted),
            _buildStatRow(
              'Over/Under', 
              statistics.overUnderTimeFormatted,
              color: _getOverUnderColor(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(value, 
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              )),
        ],
      ),
    );
  }

  Color _getOverUnderColor() {
    if (statistics.isOvertime) return Colors.red;
    if (statistics.isUndertime) return Colors.green;
    return Colors.grey;
  }
}
```

**Test**: Widget test for statistics display and color coding

#### Step 4.4: Update Live Timer Screen
**File**: `lib/presentation/screens/live_timer_screen.dart`

**Add BLoC listener for auto-progression**:
```dart
BlocListener<LiveTimerBloc, LiveTimerState>(
  listener: (context, state) {
    if (state is LiveTimerRunning && 
        state.currentEventIndex > previousEventIndex) {
      // Auto-progression occurred
      AutoProgressIndicator.show(context);
    }
  },
  child: // existing UI
)
```

**Update completion screen**:
```dart
if (state is LiveTimerComplete) {
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text('Series Complete!', 
          style: Theme.of(context).textTheme.headlineMedium),
      SizedBox(height: 24),
      SeriesStatisticsPanel(statistics: state.statistics),
      SizedBox(height: 24),
      ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Back to Series'),
      ),
    ],
  );
}
```

**Test**: Manual integration test - run series with auto-progress, verify:
1. Visual indicator shows on auto-advance
2. Audio plays (if enabled)
3. Statistics display at completion

**Checkpoint**: Full feature integration test

---

### Phase 5: Testing & Polish (1 hour)

#### Step 5.1: Run All Tests
```bash
cd chronosync
flutter test
```

Fix any failing tests.

#### Step 5.2: Manual Testing Checklist
- [ ] Create event with auto-progress enabled
- [ ] Create event with auto-progress disabled
- [ ] Start series with mixed auto/manual events
- [ ] Verify visual indicator shows on auto-advance
- [ ] Toggle audio setting and verify playback
- [ ] Verify statistics calculation accuracy
- [ ] Test background/foreground auto-progression
- [ ] Test minimum 1-second display time with short events
- [ ] Verify manual "NEXT" overrides auto-progression
- [ ] Test completion screen shows statistics correctly
- [ ] Verify color coding for over/under time

#### Step 5.3: Performance Testing
- [ ] Run series with 20+ events, verify smooth progression
- [ ] Check memory usage during long series
- [ ] Verify timer precision within 1 second over 10-minute series

#### Step 5.4: Edge Cases
- [ ] Series with single event (auto-progress)
- [ ] Very short event duration (< 1 second)
- [ ] All events complete early (under-time)
- [ ] All events run overtime
- [ ] App backgrounded during auto-progression

---

## Common Issues & Solutions

### Issue: Type adapter not regenerated
**Solution**: Delete `.dart_tool/` and rerun build_runner

### Issue: Audio file not found
**Solution**: Verify asset path in pubspec.yaml matches actual file location

### Issue: Auto-progression triggers too early
**Solution**: Check minimum display time logic (eventStartTime comparison)

### Issue: Statistics incorrect
**Solution**: Verify totalSeriesElapsedSeconds accumulates correctly across events

### Issue: Tests fail after state changes
**Solution**: Update seed states in bloc_test to include new required fields

---

## Rollout Plan

### Step 1: Deploy with Auto-Progress Disabled by Default
- Existing users see no behavior change
- New event creation defaults to autoProgress = false

### Step 2: User Education
- Add tooltip/help text explaining auto-progress feature
- Show example series in onboarding

### Step 3: Monitor Usage
- Track analytics: % of events created with auto-progress
- Collect feedback on audio cue preference

### Step 4: Iterate
- Consider adding more audio cue options
- Consider adding statistics history if users request it

---

## Success Criteria Verification

After implementation, verify against spec success criteria:

- **SC-001**: Users enable/disable auto-progress in < 5 seconds ✓
- **SC-002**: Auto-progression completes within 1 second ✓
- **SC-002a**: Timer precision within 1 second ✓
- **SC-003**: Fully automated series runs smoothly ✓
- **SC-004**: Statistics panel visible without scrolling ✓
- **SC-005**: Statistics calculate within 1 second ✓
- **SC-006**: 90% can identify auto-progress events ✓
- **SC-007**: Manual NEXT interrupts auto-progression ✓
- **SC-008**: Background/foreground auto-progression works ✓

---

## Resources

- **Spec**: `../spec.md`
- **Research**: `../research.md`
- **Data Model**: `../data-model.md`
- **Contracts**: `../contracts/`
- **BLoC Documentation**: https://bloclibrary.dev/
- **Hive Documentation**: https://docs.hivedb.dev/
- **just_audio Documentation**: https://pub.dev/packages/just_audio

---

## Next Command

After implementation is complete, run:

```bash
/speckit.tasks
```

This will generate the task breakdown for tracking implementation progress.

---

**Estimated Total Time**: 6-8 hours  
**Complexity**: Medium  
**Risk Level**: Low (additive feature, backward-compatible changes)
