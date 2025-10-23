# Data Model: Swipe-to-Delete Events and Series

**Feature**: 002-swipe-delete-items  
**Date**: October 23, 2025  
**Status**: Design Phase

## Entity Definitions

### UserPreferences

**Purpose**: Store user configuration settings that persist across app sessions

**Storage**: Hive box named 'preferences' with TypeAdapter (typeId: 2)

**Fields**:
| Field | Type | Required | Default | Validation | Description |
|-------|------|----------|---------|------------|-------------|
| swipeDirection | String | Yes | 'ltr' | Must be 'ltr' or 'rtl' | User's preferred swipe direction for delete gestures |

**Relationships**: None (singleton configuration entity)

**Lifecycle**:
- Created on first app launch if not exists
- Updated when user changes settings via SettingsScreen
- Never deleted (persists for app lifetime)

**HiveObject**: Yes (extends HiveObject for Hive integration)

**Key Generation**: Not required (single instance accessed by key '0' in box)

---

### PendingDeletion

**Purpose**: Track items in undo window before permanent deletion

**Storage**: In-memory only (managed by BLoC, not persisted to Hive)

**Fields**:
| Field | Type | Required | Default | Validation | Description |
|-------|------|----------|---------|------------|-------------|
| item | HiveObject | Yes | - | Must be Event or Series | The item marked for deletion |
| originalIndex | int | Yes | - | >= 0 | Position in list before deletion for restore |
| itemType | ItemType enum | Yes | - | 'event' or 'series' | Type of item for type-safe restoration |
| timer | Timer | Yes | - | 5-10 second duration | Countdown to permanent deletion |

**Relationships**: 
- References Event or Series (generic HiveObject)
- Managed by SeriesBloc

**Lifecycle**:
- Created when user dismisses item
- Destroyed after timer expires (item permanently deleted)
- Destroyed immediately on undo (item restored, timer cancelled)
- Destroyed on navigation away (timer expires early, permanent delete triggered)

**HiveObject**: No (transient state object)

---

### Event (Existing - Modifications)

**Purpose**: Represents a timed activity within a series

**Storage**: Hive box named 'events' with TypeAdapter (typeId: 1)

**Existing Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| title | String | Yes | Event name |
| durationInSeconds | int | Yes | Event duration in seconds |

**New Fields**: None

**Modified Behavior**:
- **Deletion**: Soft delete (removed from Series.events list but retained in events box during undo window)
- **Validation**: Check if event is in active timer before allowing deletion (via LiveTimerBloc query)

**Relationships**:
- Many-to-one with Series (via Series.events HiveList)
- Referenced by LiveTimerBloc when timer is active

**Lifecycle Changes**:
- Deletion now two-phase: remove from HiveList → undo window → permanent delete
- Protection: Cannot be deleted if currentEvent in LiveTimerRunning state

---

### Series (Existing - Modifications)

**Purpose**: Container for a collection of events

**Storage**: Hive box named 'series' with TypeAdapter (typeId: 0)

**Existing Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| title | String | Yes | Series name |
| events | HiveList<Event> | Yes | Ordered list of events in series |

**New Fields**: None

**Modified Behavior**:
- **Deletion Logic**: 
  - If `events.length == 0`: Immediate deletion with undo
  - If `events.length > 0`: Show confirmation dialog before deletion
- **Cascade Deletion**: When series deleted, all events in HiveList also deleted (existing behavior preserved)

**Relationships**:
- One-to-many with Event (owns events HiveList)
- No relationship with UserPreferences or PendingDeletion

**Lifecycle Changes**:
- Deletion now two-phase: remove from series box → undo window → permanent delete with cascade

---

## State Transitions

### Event Deletion Flow

```
[Event in List]
       ↓ (user swipes in configured direction)
[Check Active Timer] ← Query LiveTimerBloc.state
       ↓ (if not active)
[Dismiss Animation] ← Dismissible widget
       ↓
[Soft Delete] ← Remove from Series.events HiveList
       ↓
[Show Undo Snackbar] ← ScaffoldMessenger
       ↓
[PendingDeletion Created] ← Start 8-second timer
       ↓
    ┌──────┴──────┐
    ↓             ↓
[User Taps Undo]  [Timer Expires]
    ↓             ↓
[Cancel Timer]    [Permanent Delete] ← event.delete()
[Restore Event]   [Remove from events box]
[Re-insert List]
```

### Series Deletion Flow

```
[Series in List]
       ↓ (user swipes in configured direction)
[Check Event Count]
       ↓
    ┌──────┴──────┐
    ↓             ↓
[events.isEmpty]  [events.isNotEmpty]
    ↓             ↓
[Immediate       [Show Confirmation Dialog]
 Dismissal]              ↓
    ↓         ┌──────────┴──────────┐
    ↓         ↓                     ↓
    ↓    [User: Delete]        [User: Cancel]
    ↓         ↓                     ↓
    └─────────┴─────────┐      [Dialog Closes]
                        ↓      [Series Remains]
              [Soft Delete] ← Remove from series box
                        ↓
              [Show Undo Snackbar]
                        ↓
              [PendingDeletion Created]
                        ↓
                 ┌──────┴──────┐
                 ↓             ↓
            [Undo]        [Timer Expires]
                 ↓             ↓
            [Restore]     [Cascade Delete]
                          [Series + All Events]
```

### Settings Update Flow

```
[User Opens Settings] ← Tap settings icon in app bar
       ↓
[SettingsScreen Displayed] ← BlocBuilder<SettingsCubit>
       ↓
[User Selects Direction] ← Radio buttons
       ↓
[SettingsCubit.setSwipeDirection()] ← User action
       ↓
[PreferencesRepository.save()] ← Persist to Hive
       ↓
[Emit SettingsLoaded State] ← Notify listeners
       ↓
[UI Updates] ← All Dismissible widgets read new direction
```

---

## Validation Rules

### UserPreferences
- `swipeDirection` MUST be exactly 'ltr' or 'rtl'
- If invalid value read from Hive, reset to default 'ltr' and log warning

### Event Deletion
- Event MUST NOT be the currentEvent in LiveTimerRunning state
- If validation fails, show error dialog (FR-024) and block dismissal

### Series Deletion
- If `events.length > 0`, MUST show confirmation dialog
- If `events.length == 0`, proceed directly to soft delete
- Confirmation dialog MUST show actual series title (truncated if >50 chars)
- Confirmation dialog MUST show actual event count

### PendingDeletion
- Timer duration MUST be 8 seconds (middle of 5-10 second range from spec)
- Only one PendingDeletion per item allowed (keyed by item.key)
- Attempting to delete item already in undo window replaces existing PendingDeletion

---

## Data Consistency Rules

### Rule 1: Cascade Integrity
When series deleted permanently:
1. Delete series from series box
2. For each event in series.events:
   - event.delete() from events box
3. HiveList maintains referential integrity automatically

### Rule 2: Undo Atomicity
When user taps undo:
1. Cancel timer (prevents permanent delete)
2. Restore item to original index
3. Re-add to Hive box if already removed (should not be - soft delete keeps it)
4. Remove PendingDeletion from tracking

### Rule 3: Navigation Cleanup
When user navigates away during undo window:
1. All active PendingDeletion timers expire immediately
2. Permanent deletions executed before navigation completes
3. Prevents orphaned items in limbo state

### Rule 4: Swipe Direction Consistency
When user changes swipe direction:
1. Change applies immediately to all Dismissible widgets
2. No in-flight dismissals interrupted (gesture already started completes with old direction)
3. New preference persisted before SettingsCubit emits state

---

## Storage Schema

### Hive Box: 'preferences'
```dart
// Box contains single UserPreferences instance at key '0'
{
  '0': UserPreferences(swipeDirection: 'ltr')
}
```

### Hive Box: 'events'
```dart
// Existing structure - no changes
{
  'event_key_1': Event(title: '...', durationInSeconds: 300),
  'event_key_2': Event(title: '...', durationInSeconds: 600),
  ...
}
```

### Hive Box: 'series'
```dart
// Existing structure - no changes
{
  'series_key_1': Series(
    title: '...',
    events: HiveList(['event_key_1', 'event_key_2'])
  ),
  ...
}
```

---

## Migration Plan

**From**: Existing schema (Event, Series boxes)

**To**: Add UserPreferences box

**Steps**:
1. Register `UserPreferencesAdapter` in main.dart
2. Open 'preferences' box on app init
3. Create default UserPreferences if box empty
4. No data migration needed (new entity, no conflicts)

**Backward Compatibility**: 
- Existing Event and Series objects unchanged
- Old app versions cannot read preferences (graceful: will use hard-coded defaults)
- Rolling back code safe: preferences box ignored by old versions

**Code Changes**:
```dart
// main.dart additions
Hive.registerAdapter(UserPreferencesAdapter());
final prefsBox = await Hive.openBox<UserPreferences>('preferences');
if (prefsBox.isEmpty) {
  prefsBox.put('0', UserPreferences(swipeDirection: 'ltr'));
}
```

---

## Indexing & Performance

### Hive Performance Characteristics
- **Reads**: O(1) lookups by key
- **List scans**: O(n) for series/events lists (acceptable for small datasets)
- **Writes**: O(1) puts and deletes

### No Indexing Required
- User preferences: Single object, no search needed
- Events/Series: Already keyed by Hive, lists stay small (<100 items)
- PendingDeletion: In-memory map, O(1) lookup by item key

### Performance Targets Met
- Storage operations <10ms (local disk, small objects)
- UI updates <50ms (1-3 frames)
- Well within SC-007 requirement of <500ms

---

## Testing Scenarios

### Data Integrity Tests
1. Delete event → verify removed from Series.events HiveList
2. Delete series → verify all events cascade deleted
3. Undo event → verify restored to exact original position and state
4. Undo series → verify series + all events restored
5. Timer expiry → verify permanent deletion from Hive boxes

### Validation Tests
1. Attempt delete event in active timer → verify blocked with error
2. Delete empty series → verify no confirmation shown
3. Delete non-empty series → verify confirmation with correct count
4. Invalid swipe direction in Hive → verify reset to 'ltr' default

### Consistency Tests
1. Rapid successive deletes → verify each gets unique PendingDeletion
2. Navigate away during undo → verify timer cleanup and permanent delete
3. Change swipe direction during active gesture → verify completes with old direction
4. Storage error during delete → verify UI revert and error shown

### Edge Cases
1. Delete all events in series → verify series becomes empty (not auto-deleted)
2. Long series title → verify truncation in confirmation dialog
3. Delete last series → verify app handles empty state gracefully
4. Undo after navigating back to same screen → verify item restored in correct position

---

## Conclusion

Data model extends existing entities (Event, Series) with new UserPreferences entity and transient PendingDeletion tracking. No breaking changes to existing schema. State transitions clearly defined for all deletion and undo flows. Validation rules enforce spec requirements (FR-023-025, FR-008-009). Data consistency maintained through cascade rules and atomic undo operations. Ready to generate API contracts.
