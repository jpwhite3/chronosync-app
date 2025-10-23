# BLoC Contracts: Swipe-to-Delete Feature

**Feature**: 002-swipe-delete-items  
**Date**: October 23, 2025  
**Type**: Flutter BLoC Pattern API Contracts

## Overview

This document defines the contracts (events, states, and methods) for the BLoCs managing the swipe-to-delete feature. These are internal API contracts for state management, not external REST/GraphQL APIs.

---

## SettingsCubit

**Purpose**: Manage user preference settings (swipe direction)

**File**: `lib/logic/settings_cubit/settings_cubit.dart`

### States

#### SettingsLoaded
```dart
class SettingsLoaded extends SettingsState {
  final SwipeDirection swipeDirection;
  
  const SettingsLoaded(this.swipeDirection);
  
  @override
  List<Object> get props => [swipeDirection];
}
```

**Properties**:
- `swipeDirection`: Enum('ltr', 'rtl') - Current user preference

**When Emitted**: 
- On cubit initialization (loads from repository)
- After user changes preference

---

### Methods

#### setSwipeDirection
```dart
void setSwipeDirection(SwipeDirection direction)
```

**Parameters**:
- `direction`: SwipeDirection enum ('ltr' or 'rtl')

**Behavior**:
1. Validate direction enum value
2. Save to PreferencesRepository
3. Emit SettingsLoaded(direction)

**Side Effects**: Persists preference to Hive 'preferences' box

**Performance**: Synchronous (Hive write <5ms)

---

#### getSwipeDirection
```dart
SwipeDirection getSwipeDirection()
```

**Returns**: Current SwipeDirection from state

**Use Case**: Called by Dismissible widgets to determine gesture direction

---

## SeriesBloc (Modifications)

**Purpose**: Extended to handle series and event deletion with undo

**File**: `lib/logic/series_bloc/series_bloc.dart`

### New Events

#### DeleteEvent
```dart
class DeleteEvent extends SeriesEvent {
  final Event event;
  final Series series;
  final int index;
  
  const DeleteEvent(this.event, this.series, this.index);
  
  @override
  List<Object> get props => [event, series, index];
}
```

**Triggers**: User dismisses event item

**Parameters**:
- `event`: Event to delete
- `series`: Parent series containing event
- `index`: Original position in list (for undo)

---

#### DeleteSeries
```dart
class DeleteSeries extends SeriesEvent {
  final Series series;
  final int index;
  
  const DeleteSeries(this.series, this.index);
  
  @override
  List<Object> get props => [series, index];
}
```

**Triggers**: User dismisses series item (after confirmation if non-empty)

**Parameters**:
- `series`: Series to delete
- `index`: Original position in list (for undo)

---

#### UndoDeletion
```dart
class UndoDeletion extends SeriesEvent {
  final dynamic itemKey; // HiveObject key
  
  const UndoDeletion(this.itemKey);
  
  @override
  List<Object> get props => [itemKey];
}
```

**Triggers**: User taps "Undo" in snackbar

**Parameters**:
- `itemKey`: Key of item to restore (Event or Series)

---

#### ConfirmPermanentDeletion
```dart
class ConfirmPermanentDeletion extends SeriesEvent {
  final dynamic itemKey;
  
  const ConfirmPermanentDeletion(this.itemKey);
  
  @override
  List<Object> get props => [itemKey];
}
```

**Triggers**: Timer expiry (8 seconds after deletion)

**Parameters**:
- `itemKey`: Key of item to permanently delete

---

### New States

#### SeriesDeletionPending
```dart
class SeriesDeletionPending extends SeriesState {
  final List<Series> series;
  final Map<dynamic, PendingDeletion> pendingDeletions;
  
  const SeriesDeletionPending(this.series, this.pendingDeletions);
  
  @override
  List<Object> get props => [series, pendingDeletions];
}
```

**Properties**:
- `series`: Current list of series (with soft-deleted items removed)
- `pendingDeletions`: Map of itemKey → PendingDeletion objects

**When Emitted**: After deletion initiated, during undo window

---

#### DeletionError
```dart
class DeletionError extends SeriesState {
  final String message;
  final List<Series> series;
  
  const DeletionError(this.message, this.series);
  
  @override
  List<Object> get props => [message, series];
}
```

**Properties**:
- `message`: Error description for user display
- `series`: Reverted list (item restored to original position)

**When Emitted**: Storage error after retry attempts exhausted

---

### Event Handlers

#### _onDeleteEvent
```dart
Future<void> _onDeleteEvent(DeleteEvent event, Emitter<SeriesState> emit)
```

**Flow**:
1. Check if event is in active timer (query LiveTimerBloc)
2. If active, emit DeletionError with FR-024 message, return
3. Remove event from series.events HiveList
4. Create PendingDeletion with 8-second timer
5. Emit SeriesDeletionPending with updated list
6. Show undo snackbar (side effect in UI layer)
7. Timer callback: dispatch ConfirmPermanentDeletion

**Error Handling**: Try-catch with auto-retry, emit DeletionError on failure

---

#### _onDeleteSeries
```dart
Future<void> _onDeleteSeries(DeleteSeries event, Emitter<SeriesState> emit)
```

**Flow**:
1. Remove series from repository
2. Create PendingDeletion with 8-second timer
3. Emit SeriesDeletionPending with updated list
4. Show undo snackbar (side effect in UI layer)
5. Timer callback: dispatch ConfirmPermanentDeletion (cascade deletes events)

**Error Handling**: Try-catch with auto-retry, emit DeletionError on failure

---

#### _onUndoDeletion
```dart
Future<void> _onUndoDeletion(UndoDeletion event, Emitter<SeriesState> emit)
```

**Flow**:
1. Lookup PendingDeletion by itemKey
2. Cancel timer
3. Restore item to original index
4. Remove from pendingDeletions map
5. Emit SeriesLoaded with updated list

**Error Handling**: If item not found, log warning and no-op

---

#### _onConfirmPermanentDeletion
```dart
Future<void> _onConfirmPermanentDeletion(ConfirmPermanentDeletion event, Emitter<SeriesState> emit)
```

**Flow**:
1. Lookup PendingDeletion by itemKey
2. If Series: cascade delete all events in series.events HiveList
3. Call item.delete() to remove from Hive
4. Remove from pendingDeletions map
5. Emit SeriesLoaded (item already removed from list)

**Error Handling**: Log error if delete fails, but remove from pendingDeletions (prevent zombie state)

---

## Repository Contracts

### PreferencesRepository

**File**: `lib/data/repositories/preferences_repository.dart`

```dart
class PreferencesRepository {
  final Box<UserPreferences> _box;
  
  PreferencesRepository(this._box);
  
  // Get current preferences (creates default if not exists)
  UserPreferences getPreferences() {
    return _box.get('0') ?? UserPreferences(swipeDirection: 'ltr');
  }
  
  // Save preferences
  Future<void> savePreferences(UserPreferences prefs) async {
    await _box.put('0', prefs);
  }
  
  // Get specific preference
  SwipeDirection getSwipeDirection() {
    return getPreferences().swipeDirectionEnum;
  }
  
  // Save specific preference
  Future<void> saveSwipeDirection(SwipeDirection direction) async {
    final prefs = getPreferences();
    prefs.swipeDirection = direction.value;
    await savePreferences(prefs);
  }
}
```

---

### SeriesRepository (Modifications)

**File**: `lib/data/repositories/series_repository.dart`

**New Methods**:

```dart
class SeriesRepository {
  // ... existing methods ...
  
  // Soft delete: remove from list but keep in box temporarily
  void removeSeries(Series series) {
    // Series already has HiveObject methods
    // Just remove reference, don't call delete() yet
    // BLoC manages PendingDeletion and permanent delete
  }
  
  // Restore series to box
  Future<void> restoreSeries(Series series) async {
    // Re-add to box if removed (shouldn't happen - soft delete keeps it)
    // Mainly ensures consistency
  }
  
  // Check if event is in active timer
  bool isEventInActiveTimer(Event event, LiveTimerState timerState) {
    if (timerState is! LiveTimerRunning) return false;
    return timerState.currentEvent.key == event.key;
  }
}
```

---

## Widget Contracts

### DismissibleSeriesItem

**File**: `lib/presentation/widgets/dismissible_series_item.dart`

**Props**:
```dart
final Series series;
final int index;
final SwipeDirection swipeDirection;
final VoidCallback onDismissed;
```

**Callbacks**:
- `onDismissed`: Called after dismissal confirmed

**Internal Behavior**:
- Shows confirmation dialog if series.events.isNotEmpty
- Blocks dismissal if user cancels
- Triggers onDismissed callback if confirmed

---

### DismissibleEventItem

**File**: `lib/presentation/widgets/dismissible_event_item.dart`

**Props**:
```dart
final Event event;
final Series parentSeries;
final int index;
final SwipeDirection swipeDirection;
final VoidCallback onDismissed;
```

**Callbacks**:
- `onDismissed`: Called after dismissal (if not blocked by active timer)

**Internal Behavior**:
- Checks LiveTimerBloc state
- Blocks dismissal and shows error if event in active timer
- Triggers onDismissed callback if allowed

---

## Error Codes

| Code | Message | Trigger |
|------|---------|---------|
| DEL_001 | "Event is in use. Stop the timer first." | Attempt to delete event in active timer (FR-024) |
| DEL_002 | "Failed to delete. Tap to retry." | Storage error after auto-retry (FR-026) |
| DEL_003 | "Failed to restore item." | Undo operation encounters storage error |

---

## Performance Contracts

| Operation | Target | Measured By |
|-----------|--------|-------------|
| Dismissible gesture | <16ms per frame (60fps) | Flutter DevTools timeline |
| Hive write (preference) | <10ms | Stopwatch in repository |
| Hive delete (event/series) | <10ms | Stopwatch in repository |
| UI state update | <50ms (3 frames) | BLoC emit to widget rebuild |
| Confirmation dialog show | <100ms | User-perceived responsiveness |
| Undo snackbar show | <50ms | ScaffoldMessenger display time |

All targets align with SC-007 (<500ms UI updates).

---

## Testing Contracts

### Unit Tests Required

**SettingsCubit**:
- Test setSwipeDirection updates state and calls repository
- Test getSwipeDirection returns current state value
- Test initialization loads from repository

**SeriesBloc**:
- Test DeleteEvent creates PendingDeletion and emits correct state
- Test DeleteSeries creates PendingDeletion and emits correct state
- Test UndoDeletion cancels timer and restores item
- Test ConfirmPermanentDeletion removes from Hive
- Test DeleteEvent blocked when event in active timer
- Test deletion error handling and retry logic

**PreferencesRepository**:
- Test getPreferences creates default if not exists
- Test saveSwipeDirection persists to Hive
- Test getSwipeDirection returns correct enum

---

### Widget Tests Required

**DismissibleSeriesItem**:
- Test swipe gesture in correct direction dismisses
- Test swipe in wrong direction does not dismiss
- Test confirmation dialog shows for non-empty series
- Test confirmation dialog not shown for empty series
- Test cancel in dialog prevents dismissal

**DismissibleEventItem**:
- Test swipe gesture in correct direction dismisses
- Test swipe blocked when event in active timer
- Test error dialog shows when blocked
- Test navigation to timer from error dialog

---

### Integration Tests Required

**Full Deletion Flow**:
- Test swipe → undo → restore complete flow
- Test swipe → timer expiry → permanent delete
- Test swipe direction change applies to subsequent gestures
- Test deletion during active timer blocked
- Test storage error recovery with retry

---

## Conclusion

BLoC contracts defined for SettingsCubit (new) and SeriesBloc (extended). Repository contracts specify persistence operations. Widget contracts define reusable dismissible components. Error codes standardized for user messaging. Performance contracts set measurable targets. Testing contracts ensure comprehensive coverage. Ready to generate quickstart guide.
