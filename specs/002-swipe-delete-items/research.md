# Research: Swipe-to-Delete Events and Series

**Feature**: 002-swipe-delete-items  
**Date**: October 23, 2025  
**Status**: Complete

## Overview

Research for implementing swipe-to-delete functionality in a Flutter mobile app using BLoC pattern and Hive storage. Focus areas: gesture handling, undo mechanisms, settings persistence, and state management.

## Technical Decisions

### 1. Swipe Gesture Implementation

**Decision**: Use Flutter's built-in `Dismissible` widget

**Rationale**:
- Native Flutter widget designed specifically for swipe-to-dismiss patterns
- Handles gesture recognition, thresholds, and animation automatically
- Supports directional configuration (left-to-right, right-to-left)
- Provides callbacks for confirmation before dismissal
- Well-tested and performant (60fps animations)
- Reduces custom gesture detection code

**Alternatives Considered**:
- **GestureDetector with custom logic**: Rejected because it requires manual threshold calculation, animation state management, and gesture conflict resolution. Dismissible handles all this out-of-the-box.
- **Third-party package (flutter_slidable)**: Rejected because Dismissible meets all requirements and avoids additional dependencies. Slidable is better for reveal-actions, not delete.

**Implementation Pattern**:
```dart
Dismissible(
  key: Key(item.key.toString()),
  direction: _getSwipeDirection(), // from user preference
  confirmDismiss: (direction) async {
    // Show confirmation for non-empty series
    // Block if event in active timer
    return await _confirmDeletion();
  },
  onDismissed: (direction) {
    // Trigger deletion with undo window
  },
  background: _buildSwipeBackground(), // Visual feedback
  child: ListTile(...)
)
```

---

### 2. Undo Mechanism

**Decision**: Soft deletion with Timer-based permanent deletion

**Rationale**:
- Matches FR-002, FR-028-030: temporary retention for undo window
- Hive supports soft delete by marking objects without physical removal
- Timer ensures automatic cleanup after 5-10 seconds
- ScaffoldMessenger.showSnackBar provides native undo UI
- State updates trigger UI refresh via BLoC pattern

**Alternatives Considered**:
- **Command pattern with undo stack**: Rejected as over-engineered for simple undo. Adds complexity without benefit for single-level undo.
- **Separate "trash" box in Hive**: Rejected because Timer + soft delete is simpler and doesn't require migration logic or UI for trash management.

**Implementation Pattern**:
```dart
class PendingDeletion {
  final HiveObject item;
  final int originalIndex;
  final Timer timer;
  
  PendingDeletion({
    required this.item,
    required this.originalIndex,
  }) : timer = Timer(Duration(seconds: 8), () {
    // Permanently delete after window
    item.delete();
  });
  
  void undo() {
    timer.cancel();
    // Restore to original position
  }
}
```

---

### 3. Settings Persistence

**Decision**: New Hive box for UserPreferences with TypeAdapter

**Rationale**:
- Consistent with existing app architecture (Hive for all persistence)
- FR-017: Must persist across app restarts
- Type-safe with generated adapter (hive_generator)
- Synchronous access (no async overhead for preference reads)
- Lightweight for single preference entity

**Alternatives Considered**:
- **SharedPreferences package**: Rejected because mixing storage solutions adds inconsistency. Hive already in use and handles this well.
- **In-memory only**: Rejected - violates FR-017 persistence requirement.

**Implementation Pattern**:
```dart
@HiveType(typeId: 2)
class UserPreferences extends HiveObject {
  @HiveField(0)
  String swipeDirection; // 'ltr' or 'rtl'
  
  UserPreferences({this.swipeDirection = 'ltr'});
}

// In main.dart
Hive.registerAdapter(UserPreferencesAdapter());
final prefsBox = await Hive.openBox<UserPreferences>('preferences');
```

---

### 4. State Management for Settings

**Decision**: New SettingsCubit (simplified BLoC) for preference management

**Rationale**:
- Follows existing app pattern (flutter_bloc)
- Settings are simple state (no complex event sequences) - Cubit is lighter than full Bloc
- Emits state changes for reactive UI updates
- Easy to test with bloc_test package

**Alternatives Considered**:
- **Provider**: Rejected to maintain consistency with existing BLoC pattern throughout app.
- **ValueNotifier**: Rejected - less testable than Cubit, no built-in testing utilities.

**Implementation Pattern**:
```dart
class SettingsCubit extends Cubit<SettingsState> {
  final PreferencesRepository _repository;
  
  SettingsCubit(this._repository) : super(SettingsLoaded(_repository.get()));
  
  void setSwipeDirection(SwipeDirection direction) {
    _repository.save(direction);
    emit(SettingsLoaded(direction));
  }
}
```

---

### 5. Active Timer Check

**Decision**: Query LiveTimerBloc state before allowing deletion

**Rationale**:
- FR-023-025: Must block deletion of events in active timer
- BLoC pattern provides centralized timer state
- Can check `LiveTimerState.currentEvent` before confirming dismissal
- Clean separation: deletion logic queries timer state, doesn't manage it

**Alternatives Considered**:
- **Event status flag**: Rejected - requires bidirectional state sync between timer and events, prone to inconsistency.
- **Global singleton**: Rejected - anti-pattern in Flutter, harder to test.

**Implementation Pattern**:
```dart
confirmDismiss: (direction) async {
  final timerBloc = context.read<LiveTimerBloc>();
  if (timerBloc.state is LiveTimerRunning) {
    final currentEvent = (timerBloc.state as LiveTimerRunning).currentEvent;
    if (currentEvent.key == event.key) {
      _showActiveTimerError(context);
      return false; // Block dismissal
    }
  }
  return true; // Allow dismissal
}
```

---

### 6. Confirmation Dialog

**Decision**: Use `showDialog` with `AlertDialog` widget

**Rationale**:
- Native Material Design pattern
- Blocks interaction with background (modal)
- FR-011: Barrier dismiss defaults to cancel (safe action)
- Simple to customize message with series name and count
- Returns Future<bool> for async confirmation

**Alternatives Considered**:
- **Bottom sheet**: Rejected - less emphatic for destructive action, not standard for confirmations.
- **Custom modal**: Rejected - AlertDialog provides all needed functionality.

**Implementation Pattern**:
```dart
Future<bool?> showDeleteConfirmation(Series series) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true, // FR-011: dismiss = cancel
    builder: (context) => AlertDialog(
      title: Text('Delete series "${series.title}"?'),
      content: Text('This will permanently delete ${series.events.length} event(s).'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
```

---

### 7. Error Recovery for Storage Failures

**Decision**: Try-catch with automatic retry + manual retry snackbar

**Rationale**:
- FR-022, FR-026: Auto-retry once, then show error with manual option
- Hive exceptions are rare (local storage) but possible (disk full, permission issues)
- SnackBar with action button provides inline retry without navigation
- Revert UI optimistic update on failure

**Alternatives Considered**:
- **No retry**: Rejected - poor UX for transient failures like temp filesystem lock.
- **Infinite retry**: Rejected - can hang UI, no escape for persistent failures.

**Implementation Pattern**:
```dart
Future<bool> deleteWithRetry(HiveObject item) async {
  for (int attempt = 0; attempt < 2; attempt++) {
    try {
      await item.delete();
      return true;
    } catch (e) {
      if (attempt == 1) {
        _showErrorWithRetry(e);
        return false;
      }
      await Future.delayed(Duration(milliseconds: 100)); // Brief delay
    }
  }
  return false;
}
```

---

### 8. UI Responsiveness (SC-007)

**Decision**: Optimistic UI updates with rollback on failure

**Rationale**:
- SC-007: <500ms display updates
- Hive operations typically <10ms (local)
- Remove from list immediately, show undo snackbar
- If deletion fails, restore to list with error message
- Provides instant feedback while maintaining data integrity

**Alternatives Considered**:
- **Wait for confirmation**: Rejected - adds 10-100ms delay, violates SC-007 perception of responsiveness.
- **No rollback**: Rejected - leaves UI inconsistent on rare failures.

**Implementation Pattern**:
```dart
onDismissed: (direction) {
  final item = items[index];
  items.removeAt(index); // Optimistic
  emit(UpdatedListState(items));
  
  deleteWithRetry(item).then((success) {
    if (!success) {
      items.insert(index, item); // Rollback
      emit(UpdatedListState(items));
    }
  });
}
```

---

## Flutter Best Practices Applied

### Widget Composition
- Create reusable `DismissibleSeriesItem` and `DismissibleEventItem` widgets
- Extract confirmation dialog to separate widget
- Extract undo snackbar to separate widget
- Improves testability and reusability

### State Management
- Use BLoC for complex state (series/events list)
- Use Cubit for simple state (settings)
- Keep widgets stateless where possible
- Single source of truth for each state slice

### Testing Strategy
- Widget tests for dismissible behavior
- BLoC tests for deletion logic
- Repository tests for storage operations
- Integration tests for full swipe-to-delete flow

### Performance
- Use `const` constructors where possible
- Unique keys for Dismissible (required by framework)
- Avoid rebuilding entire list on single item deletion
- Timer cleanup in dispose methods

---

## Dependencies Required

**New**: None - all functionality achievable with existing dependencies:
- `flutter`: Dismissible, AlertDialog, SnackBar
- `flutter_bloc`: Cubit/BLoC for state
- `hive/hive_flutter`: Storage and persistence
- `hive_generator`: Type adapters for new models

**Existing**: No version changes needed

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Gesture conflicts with list scrolling | Dismissible handles this automatically with directional constraints |
| Race condition: undo during permanent deletion | Timer.cancel() in undo prevents race |
| Event in timer deleted while timer running | Check LiveTimerBloc state in confirmDismiss callback (FR-023-025) |
| Storage failure during deletion | Try-catch with auto-retry + manual retry UI (FR-022, FR-026) |
| Undo timeout too short for user | 8 seconds (mid-range of 5-10) provides comfortable window |
| Long series title overflow in dialog | Use ellipsis overflow in Text widget (edge case documented) |

All risks have clear mitigation strategies. No blockers identified.

---

## Performance Targets Validation

| Success Criteria | Technical Approach | Expected Performance |
|------------------|-------------------|---------------------|
| SC-001: Delete event <1s | Dismissible gesture + Hive delete | ~200-300ms total (gesture + storage) |
| SC-002: Delete series <1s | Same as above | ~200-300ms (empty), ~400-600ms (confirmation) |
| SC-007: UI update <500ms | Optimistic update + BLoC emit | ~16-50ms (1-3 frames at 60fps) |
| SC-005: 95% gestures succeed | Dismissible threshold tuning | Framework handles threshold, should exceed 95% |

All targets achievable with proposed implementation.

---

## Conclusion

All technical unknowns resolved. Implementation uses proven Flutter patterns and existing dependencies. No new external packages required. Architecture aligns with existing codebase structure (BLoC + Hive). Ready to proceed to Phase 1 (Design & Contracts).
