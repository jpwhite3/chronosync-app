# Tasks: Swipe-to-Delete Events and Series

**Input**: Design documents from `/specs/002-swipe-delete-items/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/bloc-contracts.md, quickstart.md

**Tests**: Not explicitly requested in feature specification - focusing on implementation tasks

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Flutter mobile app structure:
- Source: `chronosync/lib/`
- Tests: `chronosync/test/`
- Models: `chronosync/lib/data/models/`
- Repositories: `chronosync/lib/data/repositories/`
- BLoCs: `chronosync/lib/logic/`
- Screens: `chronosync/lib/presentation/screens/`
- Widgets: `chronosync/lib/presentation/widgets/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create new data model and generate Hive adapters

- [X] T001 Create UserPreferences model in chronosync/lib/data/models/user_preferences.dart with swipeDirection field (typeId: 2)
- [X] T002 Generate Hive TypeAdapter for UserPreferences using build_runner
- [X] T003 Register UserPreferencesAdapter in chronosync/lib/main.dart
- [X] T004 Open 'preferences' Hive box in chronosync/lib/main.dart and initialize default UserPreferences if empty

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core repositories and state management infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create PreferencesRepository in chronosync/lib/data/repositories/preferences_repository.dart with getPreferences(), saveSwipeDirection(), and getSwipeDirection() methods
- [X] T006 Create SettingsCubit in chronosync/lib/logic/settings_cubit/settings_cubit.dart with setSwipeDirection() and getSwipeDirection() methods
- [X] T007 Create SettingsState in chronosync/lib/logic/settings_cubit/settings_state.dart with SettingsLoaded state containing swipeDirection
- [X] T008 Provide SettingsCubit in MultiBlocProvider in chronosync/lib/main.dart

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Delete Single Event with Swipe (Priority: P1) 🎯 MVP

**Goal**: Users can swipe to delete events from a series with undo capability

**Independent Test**: Create a series with multiple events, swipe any event in the configured direction, verify it's removed from the list and undo snackbar appears. Tap undo to restore, or wait 8 seconds for permanent deletion.

### Implementation for User Story 1

- [X] T009 [P] [US1] Add DeleteEvent class to chronosync/lib/logic/series_bloc/series_event.dart with event, series, and index fields
- [X] T010 [P] [US1] Add UndoDeletion class to chronosync/lib/logic/series_bloc/series_event.dart with itemKey field
- [X] T011 [P] [US1] Add ConfirmPermanentDeletion class to chronosync/lib/logic/series_bloc/series_event.dart with itemKey field
- [X] T012 [P] [US1] Add SeriesDeletionPending state to chronosync/lib/logic/series_bloc/series_state.dart with series list and pendingDeletions map
- [X] T013 [P] [US1] Add DeletionError state to chronosync/lib/logic/series_bloc/series_state.dart with message and series fields
- [X] T014 [US1] Add _pendingDeletions map field to SeriesBloc in chronosync/lib/logic/series_bloc/series_bloc.dart
- [X] T015 [US1] Implement _onDeleteEvent handler in chronosync/lib/logic/series_bloc/series_bloc.dart with active timer check, remove from HiveList, create PendingDeletion with 8-second timer
- [X] T016 [US1] Implement _onUndoDeletion handler in chronosync/lib/logic/series_bloc/series_bloc.dart to cancel timer and restore event to original position
- [X] T017 [US1] Implement _onConfirmPermanentDeletion handler in chronosync/lib/logic/series_bloc/series_bloc.dart to permanently delete from Hive box
- [X] T018 [US1] Add timer cleanup logic in SeriesBloc close() method in chronosync/lib/logic/series_bloc/series_bloc.dart
- [X] T019 [US1] Create DismissibleEventItem widget in chronosync/lib/presentation/widgets/dismissible_event_item.dart with confirmDismiss callback for active timer check
- [X] T020 [US1] Add _showActiveTimerDialog method to DismissibleEventItem in chronosync/lib/presentation/widgets/dismissible_event_item.dart with message "Event is in use. Stop the timer first." and navigation option
- [X] T021 [US1] Update EventListScreen in chronosync/lib/presentation/screens/event_list_screen.dart to use DismissibleEventItem and dispatch DeleteEvent on dismissal
- [X] T022 [US1] Add undo SnackBar display in EventListScreen in chronosync/lib/presentation/screens/event_list_screen.dart with 8-second duration and UndoDeletion action

**Checkpoint**: At this point, User Story 1 should be fully functional - users can swipe to delete events with undo capability

---

## Phase 4: User Story 2 - Delete Empty Series with Swipe (Priority: P2)

**Goal**: Users can swipe to delete empty series (no events) with undo capability

**Independent Test**: Create an empty series (zero events), swipe it in the configured direction on the series list screen, verify it's removed and undo snackbar appears. Tap undo to restore, or wait 8 seconds for permanent deletion.

### Implementation for User Story 2

- [X] T023 [US2] Add DeleteSeries class to chronosync/lib/logic/series_bloc/series_event.dart with series and index fields
- [X] T024 [US2] Implement _onDeleteSeries handler in chronosync/lib/logic/series_bloc/series_bloc.dart with remove from repository, create PendingDeletion with 8-second timer
- [X] T025 [US2] Create DismissibleSeriesItem widget in chronosync/lib/presentation/widgets/dismissible_series_item.dart with empty series check (no confirmation dialog if events.isEmpty)
- [X] T026 [US2] Update SeriesListScreen in chronosync/lib/presentation/screens/series_list_screen.dart to use DismissibleSeriesItem and dispatch DeleteSeries on dismissal for empty series
- [X] T027 [US2] Add undo SnackBar display for series in SeriesListScreen in chronosync/lib/presentation/screens/series_list_screen.dart with 8-second duration and UndoDeletion action

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - users can delete events and empty series

---

## Phase 5: User Story 3 - Delete Non-Empty Series with Confirmation (Priority: P2)

**Goal**: Users can swipe to delete series containing events with confirmation dialog to prevent accidental data loss

**Independent Test**: Create a series with events, swipe it in the configured direction, verify confirmation dialog appears with accurate message showing series name and event count. Test both "Confirm" (deletes series and events with undo) and "Cancel" (keeps everything) paths.

### Implementation for User Story 3

- [X] T028 [US3] Create DeletionConfirmationDialog widget in chronosync/lib/presentation/widgets/deletion_confirmation_dialog.dart with series name, event count, and Cancel/Delete buttons
- [X] T029 [US3] Update DismissibleSeriesItem confirmDismiss callback in chronosync/lib/presentation/widgets/dismissible_series_item.dart to show confirmation dialog when series.events.isNotEmpty
- [X] T030 [US3] Implement series title truncation in DeletionConfirmationDialog in chronosync/lib/presentation/widgets/deletion_confirmation_dialog.dart for long titles (ellipsis at 50 chars)
- [X] T031 [US3] Configure barrierDismissible: true in DeletionConfirmationDialog in chronosync/lib/presentation/widgets/deletion_confirmation_dialog.dart to treat outside tap as cancel
- [X] T032 [US3] Update SeriesListScreen in chronosync/lib/presentation/screens/series_list_screen.dart to handle confirmation result and only dispatch DeleteSeries if confirmed
- [X] T033 [US3] Update _onConfirmPermanentDeletion handler in chronosync/lib/logic/series_bloc/series_bloc.dart to cascade delete all events when series is permanently deleted

**Checkpoint**: All deletion flows (events, empty series, non-empty series) should now work with proper safeguards

---

## Phase 6: User Story 4 - Configure Swipe Direction (Priority: P3)

**Goal**: Users can customize swipe direction preference (left-to-right or right-to-left) via settings screen, with preference persisting across app restarts

**Independent Test**: Open settings from app bar, change swipe direction preference from left-to-right to right-to-left, verify that subsequent swipe gestures only work in the new direction. Restart app and verify preference persists.

### Implementation for User Story 4

- [X] T034 [US4] Create SettingsScreen in chronosync/lib/presentation/screens/settings_screen.dart with radio buttons for swipe direction options
- [X] T035 [US4] Add BlocBuilder for SettingsCubit in SettingsScreen in chronosync/lib/presentation/screens/settings_screen.dart to display current swipe direction
- [X] T036 [US4] Wire up radio button onChanged callbacks in SettingsScreen in chronosync/lib/presentation/screens/settings_screen.dart to call SettingsCubit.setSwipeDirection()
- [X] T037 [US4] Add settings icon to app bar in chronosync/lib/presentation/screens/series_list_screen.dart with navigation to SettingsScreen
- [X] T038 [US4] Add settings icon to app bar in chronosync/lib/presentation/screens/event_list_screen.dart with navigation to SettingsScreen
- [X] T039 [US4] Update DismissibleEventItem in chronosync/lib/presentation/widgets/dismissible_event_item.dart to read swipe direction from SettingsCubit state
- [X] T040 [US4] Update DismissibleSeriesItem in chronosync/lib/presentation/widgets/dismissible_series_item.dart to read swipe direction from SettingsCubit state
- [X] T041 [US4] Add route for SettingsScreen in chronosync/lib/main.dart MaterialApp routes

**Checkpoint**: Complete feature - all user stories are independently functional with full configuration capability

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Error handling, visual feedback, and refinements that affect multiple user stories

- [X] T042 [P] Add swipe background widget (red background with delete icon) to DismissibleEventItem in chronosync/lib/presentation/widgets/dismissible_event_item.dart
- [X] T043 [P] Add swipe background widget (red background with delete icon) to DismissibleSeriesItem in chronosync/lib/presentation/widgets/dismissible_series_item.dart
- [X] T044 Implement error recovery with auto-retry in _onDeleteEvent in chronosync/lib/logic/series_bloc/series_bloc.dart with try-catch and DeletionError state emission
- [X] T045 Implement error recovery with auto-retry in _onDeleteSeries in chronosync/lib/logic/series_bloc/series_bloc.dart with try-catch and DeletionError state emission
- [X] T046 [P] Add manual retry SnackBar for DeletionError state in EventListScreen in chronosync/lib/presentation/screens/event_list_screen.dart
- [X] T047 [P] Add manual retry SnackBar for DeletionError state in SeriesListScreen in chronosync/lib/presentation/screens/series_list_screen.dart
- [X] T048 Add rapid deletion handling in SeriesBloc in chronosync/lib/logic/series_bloc/series_bloc.dart to prevent queue overflow (verify _pendingDeletions map)
- [X] T049 Add data consistency validation in SeriesBloc in chronosync/lib/logic/series_bloc/series_bloc.dart to verify series.events HiveList matches events box after deletions
- [X] T050 Update quickstart.md validation: test all acceptance scenarios from spec.md including rapid successive deletions and data consistency checks

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion (T001-T004) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase (T005-T008) - Core MVP functionality
- **User Story 2 (Phase 4)**: Depends on Foundational phase (T005-T008) - Can start after Foundation, uses US1 infrastructure
- **User Story 3 (Phase 5)**: Depends on Foundational phase (T005-T008) AND User Story 2 (T023-T027) - Extends series deletion with confirmation
- **User Story 4 (Phase 6)**: Depends on Foundational phase (T005-T008) AND User Story 1 (T009-T022) - Adds configuration UI
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - **MVP target**
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent but uses same SeriesBloc infrastructure as US1
- **User Story 3 (P2)**: Requires User Story 2 completion (extends series deletion) - Adds confirmation dialog to US2 flow
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Requires US1 widgets exist to read settings

### Within Each User Story

**User Story 1 Flow**:
1. T009-T013 [P] - Event/State definitions (can run in parallel)
2. T014 - Add field to SeriesBloc (depends on T009-T013)
3. T015-T018 - Implement handlers (depends on T014)
4. T019-T020 [P] - Create widget (can run in parallel with handlers if interfaces defined)
5. T021-T022 - Wire up screen (depends on T015-T020)

**User Story 2 Flow**:
1. T023 - Add DeleteSeries event (independent)
2. T024 - Implement handler (depends on T023)
3. T025 - Create widget (can run in parallel with T024)
4. T026-T027 - Wire up screen (depends on T024-T025)

**User Story 3 Flow**:
1. T028 - Create confirmation dialog (independent)
2. T029-T031 - Update widget with confirmation (depends on T028 and US2 T025)
3. T032 - Wire up confirmation result (depends on T029-T031)
4. T033 - Add cascade delete logic (depends on US2 T024)

**User Story 4 Flow**:
1. T034-T036 - Create settings screen (depends on T006-T007 from Foundation)
2. T037-T038 [P] - Add settings icons (can run in parallel)
3. T039-T040 [P] - Update widgets to read settings (depends on US1 T019 and US2 T025)
4. T041 - Add route (depends on T034)

### Parallel Opportunities

**Setup Phase**:
- T001 and T002 can run concurrently (model creation and adapter generation can be done together)

**Foundational Phase**:
- T005, T006-T007 can run in parallel (repository and cubit/state are independent)

**User Story 1**:
- T009, T010, T011 (events) can run in parallel
- T012, T013 (states) can run in parallel
- T019-T020 (widget) can run in parallel with T015-T018 (handlers) if interfaces are defined

**User Story 2**:
- T025 (widget) can run in parallel with T024 (handler)

**User Story 4**:
- T037-T038 (app bar icons) can run in parallel
- T039-T040 (update widgets) can run in parallel

**Polish Phase**:
- T042-T043 (background widgets) can run in parallel
- T046-T047 (error snackbars) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch event and state definitions together:
Task T009: "Add DeleteEvent class to chronosync/lib/logic/series_bloc/series_event.dart"
Task T010: "Add UndoDeletion class to chronosync/lib/logic/series_bloc/series_event.dart"
Task T011: "Add ConfirmPermanentDeletion class to chronosync/lib/logic/series_bloc/series_event.dart"
Task T012: "Add SeriesDeletionPending state to chronosync/lib/logic/series_bloc/series_state.dart"
Task T013: "Add DeletionError state to chronosync/lib/logic/series_bloc/series_state.dart"

# After interfaces are defined, widget and handlers can proceed in parallel:
Task T015: "Implement _onDeleteEvent handler in chronosync/lib/logic/series_bloc/series_bloc.dart"
Task T016: "Implement _onUndoDeletion handler in chronosync/lib/logic/series_bloc/series_bloc.dart"
Task T017: "Implement _onConfirmPermanentDeletion handler in chronosync/lib/logic/series_bloc/series_bloc.dart"
Task T019: "Create DismissibleEventItem widget in chronosync/lib/presentation/widgets/dismissible_event_item.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004) - ~1 hour
2. Complete Phase 2: Foundational (T005-T008) - ~1.5 hours ⚠️ CRITICAL GATE
3. Complete Phase 3: User Story 1 (T009-T022) - ~4-5 hours
4. **STOP and VALIDATE**: Test event deletion with swipe and undo independently
5. Deploy/demo if ready - **This is a complete, usable feature**

**MVP Milestone**: Users can manage events with swipe-to-delete and undo (total ~6.5-7.5 hours)

### Incremental Delivery

1. Complete Setup (T001-T004) + Foundational (T005-T008) → Foundation ready (~2.5 hours)
2. Add User Story 1 (T009-T022) → Test independently → Deploy/Demo (**MVP!** at ~7 hours)
3. Add User Story 2 (T023-T027) → Test independently → Deploy/Demo (~2 hours, cumulative ~9 hours)
4. Add User Story 3 (T028-T033) → Test independently → Deploy/Demo (~1.5 hours, cumulative ~10.5 hours)
5. Add User Story 4 (T034-T041) → Test independently → Deploy/Demo (~2.5 hours, cumulative ~13 hours)
6. Polish (T042-T048) → Final touches (~1.5 hours, total ~14.5 hours)

Each story adds value without breaking previous stories.

### Parallel Team Strategy

With multiple developers (after Foundational phase T005-T008 complete):

**Scenario 1: Two developers**
- Developer A: User Story 1 (T009-T022) - MVP focus
- Developer B: User Story 2 + 3 (T023-T033) - Series deletion

**Scenario 2: Three developers**
- Developer A: User Story 1 (T009-T022) - MVP focus
- Developer B: User Story 2 + 3 (T023-T033) - Series deletion
- Developer C: User Story 4 (T034-T041) - Settings UI

Stories complete and integrate independently with minimal merge conflicts.

---

## Task Summary

**Total Tasks**: 50 tasks across 7 phases

**Task Count by Phase**:
- Phase 1 (Setup): 4 tasks
- Phase 2 (Foundational): 4 tasks ⚠️ BLOCKS all stories
- Phase 3 (User Story 1): 14 tasks 🎯 MVP
- Phase 4 (User Story 2): 5 tasks
- Phase 5 (User Story 3): 6 tasks
- Phase 6 (User Story 4): 8 tasks
- Phase 7 (Polish): 9 tasks

**Parallel Opportunities Identified**: 15 tasks marked [P] can run in parallel within their phase

**Independent Test Criteria**:
- User Story 1: Swipe event → verify removal → tap undo → verify restore
- User Story 2: Swipe empty series → verify removal → tap undo → verify restore
- User Story 3: Swipe non-empty series → verify confirmation → test both paths
- User Story 4: Change setting → verify gestures use new direction → restart → verify persistence

**Suggested MVP Scope**: Phases 1-3 (T001-T022) = User Story 1 only
- Delivers core value: event deletion with swipe and undo
- Independently testable and deployable
- Estimated time: 6.5-7.5 hours

**Format Validation**: ✅ All tasks follow checklist format with:
- Checkbox prefix: `- [ ]`
- Sequential task ID: T001-T050
- [P] marker for parallelizable tasks
- [Story] label for user story phases (US1, US2, US3, US4)
- Clear description with exact file path

---

## Notes

- [P] tasks = different files, no dependencies within phase
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group of parallel tasks
- Stop at any checkpoint to validate story independently
- Tests not included as they were not explicitly requested in spec
- Follow quickstart.md for detailed code examples and implementation guidance
- Reference contracts/bloc-contracts.md for exact API signatures
