# Quickstart Guide: Swipe-to-Delete Implementation

**Feature**: 002-swipe-delete-items  
**Date**: October 23, 2025  
**Audience**: Developers implementing the feature

## Prerequisites

- Flutter SDK installed (Dart 3.9.2+)
- Existing ChronoSync project cloned
- Branch `002-swipe-delete-items` checked out
- Dependencies already installed (run `flutter pub get` if needed)

**Estimated Time**: 8-12 hours for full implementation

---

## Implementation Order (By Priority)

Follow spec user story priorities for incremental delivery:

### Phase 1: P1 - Event Deletion (Core Feature)
**Time**: 4-5 hours  
**Deliverable**: Users can swipe to delete events with undo

1. Create UserPreferences model
2. Create PreferencesRepository
3. Create SettingsCubit (default direction only)
4. Create DismissibleEventItem widget
5. Modify SeriesBloc for event deletion
6. Update event_list_screen with Dismissible
7. Implement undo snackbar
8. Add tests

### Phase 2: P2 - Series Deletion
**Time**: 2-3 hours  
**Deliverable**: Users can swipe to delete series with confirmation

9. Create DeletionConfirmationDialog widget
10. Create DismissibleSeriesItem widget
11. Extend SeriesBloc for series deletion
12. Update series_list_screen with Dismissible
13. Add tests

### Phase 3: P3 - Settings UI
**Time**: 2-3 hours  
**Deliverable**: Users can configure swipe direction

14. Create SettingsScreen
15. Add settings icon to app bar
16. Wire up SettingsCubit to UI
17. Add tests

---

## Quick Implementation Steps

### Step 1: Create UserPreferences Model

**File**: `lib/data/models/user_preferences.dart`

```dart
import 'package:hive/hive.dart';

part 'user_preferences.g.dart';

@HiveType(typeId: 2)
class UserPreferences extends HiveObject {
  @HiveField(0)
  String swipeDirection; // 'ltr' or 'rtl'

  UserPreferences({this.swipeDirection = 'ltr'});
  
  SwipeDirection get swipeDirectionEnum =>
      swipeDirection == 'rtl' ? SwipeDirection.rtl : SwipeDirection.ltr;
}

enum SwipeDirection {
  ltr,
  rtl;
  
  String get value => name;
  DismissDirection get dismissDirection =>
      this == ltr ? DismissDirection.startToEnd : DismissDirection.endToStart;
}
```

**Generate adapter**: `dart run build_runner build --delete-conflicting-outputs`

---

### Step 2: Register in main.dart

**File**: `lib/main.dart`

```dart
Future<void> main() async {
  await Hive.initFlutter();
  Hive.registerAdapter(SeriesAdapter());
  Hive.registerAdapter(EventAdapter());
  Hive.registerAdapter(UserPreferencesAdapter()); // NEW
  
  await Hive.openBox<Series>('series');
  await Hive.openBox<Event>('events');
  await Hive.openBox<UserPreferences>('preferences'); // NEW
  
  // Initialize default preferences if not exists
  final prefsBox = Hive.box<UserPreferences>('preferences');
  if (prefsBox.isEmpty) {
    await prefsBox.put('0', UserPreferences());
  }
  
  runApp(const MyApp());
}
```

---

### Step 3: Create PreferencesRepository

**File**: `lib/data/repositories/preferences_repository.dart`

```dart
import 'package:hive/hive.dart';
import 'package:chronosync/data/models/user_preferences.dart';

class PreferencesRepository {
  final Box<UserPreferences> _box;

  PreferencesRepository(this._box);

  UserPreferences getPreferences() {
    return _box.get('0') ?? UserPreferences();
  }

  Future<void> saveSwipeDirection(SwipeDirection direction) async {
    final prefs = getPreferences();
    prefs.swipeDirection = direction.value;
    await prefs.save();
  }

  SwipeDirection getSwipeDirection() {
    return getPreferences().swipeDirectionEnum;
  }
}
```

---

### Step 4: Create SettingsCubit

**File**: `lib/logic/settings_cubit/settings_cubit.dart`

```dart
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/data/repositories/preferences_repository.dart';

part 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final PreferencesRepository _repository;

  SettingsCubit(this._repository)
      : super(SettingsLoaded(_repository.getSwipeDirection()));

  void setSwipeDirection(SwipeDirection direction) {
    _repository.saveSwipeDirection(direction);
    emit(SettingsLoaded(direction));
  }

  SwipeDirection getSwipeDirection() {
    return (state as SettingsLoaded).swipeDirection;
  }
}
```

**File**: `lib/logic/settings_cubit/settings_state.dart`

```dart
part of 'settings_cubit.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();
  
  @override
  List<Object> get props => [];
}

class SettingsLoaded extends SettingsState {
  final SwipeDirection swipeDirection;

  const SettingsLoaded(this.swipeDirection);

  @override
  List<Object> get props => [swipeDirection];
}
```

---

### Step 5: Provide SettingsCubit in main.dart

**File**: `lib/main.dart` (modify MyApp widget)

```dart
@override
Widget build(BuildContext context) {
  return MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) => SeriesBloc(SeriesRepository(Hive.box('series'))),
      ),
      BlocProvider(
        create: (context) => SettingsCubit(
          PreferencesRepository(Hive.box('preferences')),
        ),
      ),
    ],
    child: MaterialApp(
      title: 'ChronoSync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SeriesListScreen(),
    ),
  );
}
```

---

### Step 6: Create DismissibleEventItem Widget

**File**: `lib/presentation/widgets/dismissible_event_item.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/logic/settings_cubit/settings_cubit.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';

class DismissibleEventItem extends StatelessWidget {
  final Event event;
  final Series series;
  final int index;
  final VoidCallback onDismissed;

  const DismissibleEventItem({
    super.key,
    required this.event,
    required this.series,
    required this.index,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settingsState) {
        final direction = (settingsState as SettingsLoaded).swipeDirection;

        return Dismissible(
          key: Key(event.key.toString()),
          direction: direction.dismissDirection,
          confirmDismiss: (dismissDirection) async {
            // Check if event is in active timer
            final timerState = context.read<LiveTimerBloc>().state;
            if (timerState is LiveTimerRunning &&
                timerState.currentEvent.key == event.key) {
              _showActiveTimerDialog(context);
              return false;
            }
            return true;
          },
          onDismissed: (direction) => onDismissed(),
          background: Container(
            color: Colors.red,
            alignment: direction == SwipeDirection.ltr
                ? Alignment.centerLeft
                : Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: ListTile(
            title: Text(event.title),
            subtitle: Text(event.duration.toString()),
          ),
        );
      },
    );
  }

  void _showActiveTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot Delete'),
        content: const Text('Event is in use. Stop the timer first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to timer screen (implement navigation)
            },
            child: const Text('Go to Timer'),
          ),
        ],
      ),
    );
  }
}
```

---

### Step 7: Extend SeriesBloc for Deletion

**File**: `lib/logic/series_bloc/series_event.dart`

```dart
// Add new events
class DeleteEvent extends SeriesEvent {
  final Event event;
  final Series series;
  final int index;

  const DeleteEvent(this.event, this.series, this.index);

  @override
  List<Object> get props => [event, series, index];
}

class UndoDeletion extends SeriesEvent {
  final dynamic itemKey;

  const UndoDeletion(this.itemKey);

  @override
  List<Object> get props => [itemKey];
}
```

**File**: `lib/logic/series_bloc/series_bloc.dart`

```dart
// Add handler
on<DeleteEvent>(_onDeleteEvent);
on<UndoDeletion>(_onUndoDeletion);

// Add field
final Map<dynamic, Timer> _pendingDeletions = {};

Future<void> _onDeleteEvent(DeleteEvent event, Emitter<SeriesState> emit) async {
  // Remove from series.events
  event.series.events.remove(event.event);
  await event.series.save();

  // Start undo timer
  _pendingDeletions[event.event.key] = Timer(
    const Duration(seconds: 8),
    () async {
      await event.event.delete();
      _pendingDeletions.remove(event.event.key);
    },
  );

  add(LoadSeries());
}

Future<void> _onUndoDeletion(UndoDeletion event, Emitter<SeriesState> emit) async {
  final timer = _pendingDeletions[event.itemKey];
  if (timer != null) {
    timer.cancel();
    _pendingDeletions.remove(event.itemKey);
    // Event still in storage, just re-add to series
    add(LoadSeries());
  }
}

@override
Future<void> close() {
  // Cancel all pending timers
  for (final timer in _pendingDeletions.values) {
    timer.cancel();
  }
  return super.close();
}
```

---

### Step 8: Update EventListScreen

**File**: `lib/presentation/screens/event_list_screen.dart`

Replace ListView.builder body with:

```dart
body: BlocBuilder<SeriesBloc, SeriesState>(
  builder: (context, state) {
    // ... existing logic to get currentSeries ...

    return ListView.builder(
      itemCount: currentSeries.events.length,
      itemBuilder: (context, index) {
        final event = currentSeries.events[index];
        return DismissibleEventItem(
          event: event,
          series: currentSeries,
          index: index,
          onDismissed: () {
            context.read<SeriesBloc>().add(
              DeleteEvent(event, currentSeries, index),
            );

            // Show undo snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Event deleted'),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () {
                    context.read<SeriesBloc>().add(
                      UndoDeletion(event.key),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  },
),
```

---

### Step 9: Test Event Deletion

**Run App**: `flutter run`

**Test Sequence**:
1. Open a series with events
2. Swipe an event left-to-right
3. Verify event disappears and undo snackbar shows
4. Tap "Undo" → event reappears
5. Swipe again, wait 8 seconds → permanent delete
6. Verify event gone after reload

---

## Phase 2 & 3 Implementation

Follow similar patterns:
- **Series deletion**: Create `DismissibleSeriesItem`, add confirmation dialog
- **Settings screen**: Create `SettingsScreen` with radio buttons for swipe direction
- **App bar**: Add settings icon that navigates to SettingsScreen

See full implementation in `contracts/bloc-contracts.md` and `data-model.md`.

---

## Testing Checklist

### Basic Functionality
- [ ] Unit tests for SettingsCubit
- [ ] Unit tests for SeriesBloc deletion events
- [ ] Widget tests for DismissibleEventItem
- [ ] Widget tests for DismissibleSeriesItem
- [ ] Integration test for full swipe→undo flow
- [ ] Integration test for swipe→timer expiry→permanent delete
- [ ] Test event deletion blocked when in active timer
- [ ] Test series confirmation dialog

### Rapid Deletion & Data Consistency (Phase 7)
- [ ] Test rapid successive deletions of multiple events (3+ events within 2 seconds)
- [ ] Verify _pendingDeletions map correctly tracks all rapid deletions
- [ ] Test deleting same event multiple times rapidly (timer cancellation)
- [ ] Test rapid deletions with undo interspersed
- [ ] Verify data consistency: series.events HiveList matches events box after deletions
- [ ] Test consistency after rapid delete→undo→delete sequence
- [ ] Test consistency after cascade deletion of series with many events
- [ ] Verify no orphaned events in box after series deletion
- [ ] Test error recovery: manual retry after DeletionError state
- [ ] Verify error SnackBar shows with proper message and Retry action

---

## Common Issues & Solutions

### Issue: Dismissible not triggering
- **Solution**: Ensure unique Key() for each Dismissible based on item.key
- **Solution**: Check direction matches user preference

### Issue: Undo not working
- **Solution**: Verify Timer is cancelled in UndoDeletion handler
- **Solution**: Check item still in Hive box (soft delete, not hard delete)

### Issue: UI not updating after deletion
- **Solution**: Ensure SeriesBloc emits new state after deletion
- **Solution**: BlocBuilder should rebuild on state change

### Issue: Gesture conflicts with scroll
- **Solution**: Dismissible handles this automatically, but ensure direction is set

---

## Performance Optimization Tips

1. **Use const constructors** where possible (reduce widget rebuilds)
2. **Key widgets properly** (helps Flutter's reconciliation algorithm)
3. **Avoid rebuilding entire list** on single item deletion (BLoC should emit only changed data)
4. **Cancel timers** in BLoC close() to prevent memory leaks

---

## Next Steps After Implementation

1. Run full test suite: `flutter test`
2. Manual QA testing with spec acceptance scenarios
3. Performance profiling with Flutter DevTools
4. Code review against constitutional compliance
5. Update documentation with any implementation notes
6. Create pull request with link to spec and plan

---

## Resources

- **Spec**: `specs/002-swipe-delete-items/spec.md`
- **Data Model**: `specs/002-swipe-delete-items/data-model.md`
- **BLoC Contracts**: `specs/002-swipe-delete-items/contracts/bloc-contracts.md`
- **Flutter Dismissible Docs**: https://api.flutter.dev/flutter/widgets/Dismissible-class.html
- **BLoC Pattern Docs**: https://bloclibrary.dev/

---

## Estimated Completion Timeline

| Phase | Time | Cumulative |
|-------|------|------------|
| P1: Event deletion | 4-5 hours | 5 hours |
| P2: Series deletion | 2-3 hours | 8 hours |
| P3: Settings UI | 2-3 hours | 11 hours |
| Testing & QA | 2-3 hours | 14 hours |

**Total**: 11-14 hours for full feature with comprehensive testing.

---

## Acceptance Scenario Validation

### User Story 1: Event Deletion
**Scenario**: User swipes to delete an event from a series
1. Create series "Morning Routine" with 3 events
2. Swipe middle event left-to-right
3. ✓ Event disappears immediately (<1s)
4. ✓ Undo snackbar appears for 8 seconds
5. ✓ Tap "Undo" → event reappears in original position
6. Swipe same event again
7. Wait 8 seconds without undo
8. ✓ Event permanently deleted from storage
9. ✓ series.events HiveList no longer contains event
10. ✓ Event not in events box after deletion

**Scenario**: User tries to delete event in active timer
1. Create series with 2 events
2. Start timer with first event
3. Swipe to delete active event
4. ✓ Confirmation dialog shows "Cannot Delete"
5. ✓ Event not deleted
6. ✓ Option to navigate to timer screen

### User Story 2: Empty Series Deletion
**Scenario**: User swipes to delete an empty series
1. Create empty series "New Series"
2. Swipe series left-to-right
3. ✓ Series disappears immediately
4. ✓ Undo snackbar appears for 8 seconds
5. ✓ Tap "Undo" → series reappears
6. Swipe again, wait 8 seconds
7. ✓ Series permanently deleted

### User Story 3: Non-Empty Series Deletion
**Scenario**: User swipes to delete series with events
1. Create series "Workout" with 5 events
2. Swipe series left-to-right
3. ✓ Confirmation dialog shows: "Delete 'Workout' and its 5 events?"
4. ✓ Series title truncated at 50 chars if needed
5. Tap "Cancel"
6. ✓ Series not deleted, dialog dismissed
7. Swipe series again
8. Tap "Delete" in confirmation
9. ✓ Series and all events deleted immediately (cascade)
10. ✓ No orphaned events in events box
11. ✓ Data consistency validated

### User Story 4: Swipe Direction Settings
**Scenario**: User changes swipe direction preference
1. Open Settings from app bar icon
2. ✓ Current direction selected (default: left-to-right)
3. Select "Right-to-left"
4. ✓ Preference saved immediately
5. Navigate back to series list
6. Swipe series left-to-right
7. ✓ No deletion (wrong direction)
8. Swipe series right-to-left
9. ✓ Series deleted successfully

### Rapid Deletion Scenarios
**Scenario**: User rapidly deletes multiple events
1. Create series with 5 events
2. Quickly swipe 3 events within 2 seconds
3. ✓ All 3 events disappear immediately
4. ✓ _pendingDeletions map contains 3 entries
5. ✓ Undo snackbar for most recent deletion
6. Tap "Undo" for one event
7. ✓ That event reappears, other 2 remain deleted
8. Wait 8 seconds
9. ✓ Remaining 2 events permanently deleted
10. ✓ Data consistency validated (no orphaned events)

**Scenario**: User rapidly deletes and undoes same event
1. Create series with 1 event
2. Swipe event
3. Immediately tap "Undo"
4. Quickly swipe same event again
5. ✓ Previous timer cancelled properly
6. ✓ New 8-second timer started
7. ✓ No duplicate timers in _pendingDeletions
8. ✓ Event shows in list

### Error Recovery Scenarios
**Scenario**: Deletion fails after auto-retry
1. Simulate Hive delete failure (test with mock)
2. Swipe event to delete
3. ✓ Auto-retry attempted after 100ms
4. ✓ Auto-retry fails
5. ✓ DeletionError state emitted
6. ✓ Error SnackBar shows: "Failed to delete. Tap to retry."
7. Tap "Retry" action
8. ✓ DeleteSeries event dispatched again
9. ✓ Deletion succeeds on manual retry

---

## Success Criteria Verification

After implementation, verify against spec Success Criteria:
- ✓ SC-001: Event deletion <1 second (measure with stopwatch)
- ✓ SC-002: Series deletion <1 second
- ✓ SC-007: UI updates <500ms (use DevTools performance tab)
- ✓ SC-009: Undo within 5-10 seconds (test with 8-second timer)
- ✓ SC-010: Undo restores exact position (verify visually)

All criteria should pass before marking feature complete.
