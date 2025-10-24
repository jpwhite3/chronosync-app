# Tasks: Auto-Progress Events with Series Statistics

**Input**: Design documents from `/Users/jpwhite/Code/cronos-app/specs/004-auto-progress-events/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: Unit tests and widget tests included per quickstart.md guidance

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a Flutter mobile application with the following structure:
- **Source**: `chronosync/lib/`
- **Tests**: `chronosync/test/`
- **Assets**: `chronosync/assets/`

---

## Phase 1: Setup (1-2 hours)

**Purpose**: Project initialization and data model preparation for auto-progress feature

- [X] T001 Add just_audio dependency (^0.9.36) to chronosync/pubspec.yaml
- [X] T002 Create assets/audio/ directory and add auto_progress_beep.mp3 audio file
- [X] T003 Update chronosync/pubspec.yaml to include audio asset (assets/audio/auto_progress_beep.mp3)
- [X] T004 Run `flutter pub get` to fetch new dependencies
- [X] T005 Create lib/data/models/series_statistics.dart with SeriesStatistics class (transient model)

**Checkpoint**: Dependencies installed, assets configured, base statistics model created ✅

---

## Phase 2: Foundational (Blocking Prerequisites) (1-2 hours)

**Purpose**: Core data model updates that MUST be complete before ANY user story implementation

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Add autoProgress field (bool, default false) to Event model in lib/data/models/event.dart
- [X] T007 Add autoProgressAudioEnabled field (bool, default true) to UserPreferences model in lib/data/models/user_preferences.dart
- [X] T008 Run `flutter packages pub run build_runner build --delete-conflicting-outputs` to regenerate type adapters
- [X] T009 Create unit test for Event.autoProgress default value in test/data/models/event_test.dart
- [X] T010 Create unit test for UserPreferences.autoProgressAudioEnabled default in test/data/models/user_preferences_test.dart
- [X] T011 Create unit tests for SeriesStatistics computed properties in test/data/models/series_statistics_test.dart
- [X] T012 Run `flutter test` to verify data model tests pass

**Checkpoint**: Foundation ready - all data models updated and tested, user story implementation can now begin ✅

---

## Phase 3: User Story 1 - Enable Auto-Progress on Individual Events (Priority: P1) 🎯 MVP (1-2 hours)

**Goal**: Allow users to toggle auto-progress setting when creating or editing events, with visual indication in event list

**Independent Test**: Create a new event with auto-progress enabled, save it, edit the event, verify toggle state persists, and check that the event list shows an auto-progress indicator icon

### Implementation for User Story 1

- [X] T013 [P] [US1] Add SwitchListTile for auto-progress toggle in event creation dialog in lib/presentation/screens/event_list_screen.dart
- [X] T014 [P] [US1] Add SwitchListTile for auto-progress toggle in event edit dialog in lib/presentation/screens/event_list_screen.dart
- [X] T015 [US1] Update event save logic to persist autoProgress field in lib/presentation/screens/event_list_screen.dart
- [X] T016 [US1] Add visual indicator (icon) for auto-progress enabled events in event list tiles in lib/presentation/screens/event_list_screen.dart
- [X] T017 [US1] Add tooltip or subtitle text "Auto-progress when time expires" to toggle in lib/presentation/screens/event_list_screen.dart

**Manual Test Checkpoint**: 
1. Create new event with auto-progress ON → Save → Edit → Verify toggle shows ON
2. Create new event with auto-progress OFF → Save → Edit → Verify toggle shows OFF (default)
3. View event list → Verify events with auto-progress show icon indicator
4. Success criteria: SC-001 (toggle and save in under 5 seconds), SC-006 (90% can identify auto-progress events) ✅

---

## Phase 4: User Story 2 - Auto-Progress Single Event During Live Timer (Priority: P1) (2-3 hours)

**Goal**: Automatically advance to next event when countdown reaches "00:00" on auto-progress enabled events, with visual/audio feedback

**Independent Test**: Create a series with a 30-second event (auto-progress ON) followed by another event. Start the series, observe automatic advancement at "00:00" with visual indicator and optional audio cue.

### BLoC Layer Updates for User Story 2

- [X] T018 [US2] Add eventStartTime, seriesStartTime, and totalSeriesElapsedSeconds fields to LiveTimerRunning state in lib/logic/live_timer_bloc/live_timer_state.dart
- [X] T019 [US2] Add shouldAutoProgress computed property to LiveTimerRunning state in lib/logic/live_timer_bloc/live_timer_state.dart
- [X] T020 [US2] Update LiveTimerComplete state to include SeriesStatistics field in lib/logic/live_timer_bloc/live_timer_state.dart
- [X] T021 [US2] Add AutoProgressTriggered event class to lib/logic/live_timer_bloc/live_timer_event.dart
- [X] T022 [US2] Update LiveTimerStarted handler in LiveTimerBloc to initialize eventStartTime and seriesStartTime in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [X] T023 [US2] Update LiveTimerTicked handler in LiveTimerBloc to check shouldAutoProgress and dispatch AutoProgressTriggered in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [X] T024 [US2] Add AudioPlayer field and initialize in LiveTimerBloc constructor in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [X] T025 [US2] Load audio asset (assets/audio/auto_progress_beep.mp3) in LiveTimerBloc in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [X] T026 [US2] Implement AutoProgressTriggered event handler in LiveTimerBloc (play audio, advance event, calculate statistics) in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [X] T027 [US2] Add _calculateStatistics helper method to LiveTimerBloc in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [X] T028 [US2] Update LiveTimerBloc.close() to dispose AudioPlayer in lib/logic/live_timer_bloc/live_timer_bloc.dart

### Settings Layer Updates for User Story 2

- [X] T029 [P] [US2] Add autoProgressAudioEnabled field to SettingsState in lib/logic/settings_cubit/settings_state.dart
- [X] T030 [P] [US2] Update SettingsState.copyWith to include autoProgressAudioEnabled parameter in lib/logic/settings_cubit/settings_state.dart
- [X] T031 [US2] Add toggleAutoProgressAudio method to SettingsCubit in lib/logic/settings_cubit/settings_cubit.dart
- [X] T032 [US2] Add SwitchListTile for "Auto-Progress Audio" toggle in lib/presentation/screens/settings_screen.dart

### UI Layer Updates for User Story 2

- [X] T033 [P] [US2] Create AutoProgressIndicator widget (SnackBar) in lib/presentation/widgets/auto_progress_indicator.dart
- [X] T034 [US2] Add BlocListener for AutoProgressTriggered in LiveTimerScreen to show visual indicator in lib/presentation/screens/live_timer_screen.dart
- [X] T035 [US2] Update LiveTimerScreen to detect auto-progression and call AutoProgressIndicator.show() in lib/presentation/screens/live_timer_screen.dart

### Tests for User Story 2

- [ ] T036 [P] [US2] Create bloc_test for AutoProgressTriggered advancing to next event in test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [ ] T037 [P] [US2] Create bloc_test for AutoProgressTriggered completing series on last event in test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [ ] T038 [P] [US2] Create bloc_test for LiveTimerTicked dispatching AutoProgressTriggered when countdown reaches 00:00 in test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [ ] T039 [P] [US2] Create bloc_test for LiveTimerTicked NOT dispatching AutoProgressTriggered when autoProgress is false in test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [ ] T040 [P] [US2] Create widget test for AutoProgressIndicator SnackBar display in test/presentation/widgets/auto_progress_indicator_test.dart
- [ ] T041 [US2] Run `flutter test` to verify User Story 2 tests pass

**Manual Test Checkpoint**: 
1. Create series: Event A (30s, auto-progress ON) → Event B (30s, manual)
2. Start series → Wait for Event A countdown to reach 00:00
3. Verify: Visual indicator "Auto-advancing..." appears
4. Verify: Audio cue plays (if settings enabled)
5. Verify: Event B starts automatically with fresh timers
6. Verify: Manual "NEXT" button still works during auto-progress event
7. Success criteria: SC-002 (auto-progress within 1 second), SC-002a (timer precision within 1 second), SC-007 (manual NEXT overrides) ✅ MVP COMPLETE

---

## Phase 5: User Story 3 - Fully Automated Series Execution (Priority: P2) (30 minutes)

**Goal**: Enable hands-free execution when all events in a series have auto-progress enabled

**Independent Test**: Create a series with 3-5 events (15-30 seconds each), all with auto-progress ON. Start the series and observe it progress automatically from start to completion without any manual intervention.

**Note**: This user story is primarily enabled by User Story 2 implementation - no additional code changes required, but testing validates the end-to-end flow.

### Implementation for User Story 3

- [ ] T042 [US3] Verify existing LiveTimerBloc logic supports chaining multiple auto-progress events in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T043 [US3] Add debug logging for series completion when all events auto-progressed in lib/logic/live_timer_bloc/live_timer_bloc.dart

### Tests for User Story 3

- [ ] T044 [P] [US3] Create integration test for fully automated 5-event series in test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [ ] T045 [US3] Run `flutter test` to verify User Story 3 test passes

**Manual Test Checkpoint**: 
1. Create series with 5 events: all 20 seconds, all auto-progress ON
2. Start series → Hands off (do not touch any buttons)
3. Verify: All 5 events advance automatically
4. Verify: Visual indicators appear on each transition
5. Verify: Completion screen displays after final event
6. Success criteria: SC-003 (fully automated series runs smoothly)

---

## Phase 6: User Story 4 - Display Aggregate Series Statistics at Completion (Priority: P2) (1-2 hours)

**Goal**: Show statistics panel (event count, expected time, actual time, over/under time) on series completion screen

**Independent Test**: Run any series to completion (manual or auto-progress), verify statistics panel displays above "Back to Series" button with all four statistics calculated correctly and color-coded.

### Implementation for User Story 4

- [ ] T046 [P] [US4] Create SeriesStatisticsPanel widget in lib/presentation/widgets/series_statistics_panel.dart
- [ ] T047 [US4] Implement _buildStatRow helper method in SeriesStatisticsPanel in lib/presentation/widgets/series_statistics_panel.dart
- [ ] T048 [US4] Implement _getOverUnderColor helper method (red for overtime, green for undertime, neutral for on-time) in lib/presentation/widgets/series_statistics_panel.dart
- [ ] T049 [US4] Add formatted time string methods (expectedTimeFormatted, actualTimeFormatted, overUnderTimeFormatted) to SeriesStatistics model in lib/data/models/series_statistics.dart
- [ ] T050 [US4] Update LiveTimerScreen completion UI to include SeriesStatisticsPanel above "Back to Series" button in lib/presentation/screens/live_timer_screen.dart
- [ ] T051 [US4] Verify statistics panel positioning and layout on small screens (4-inch minimum) in lib/presentation/screens/live_timer_screen.dart

### Tests for User Story 4

- [ ] T052 [P] [US4] Create widget test for SeriesStatisticsPanel display and formatting in test/presentation/widgets/series_statistics_panel_test.dart
- [ ] T053 [P] [US4] Create widget test for SeriesStatisticsPanel color coding (overtime red, undertime green, on-time neutral) in test/presentation/widgets/series_statistics_panel_test.dart
- [ ] T054 [US4] Create unit test for SeriesStatistics formatted string methods in test/data/models/series_statistics_test.dart
- [ ] T055 [US4] Run `flutter test` to verify User Story 4 tests pass

**Manual Test Checkpoint**: 
1. Create series: Event A (1 min), Event B (1 min), Event C (1 min)
2. Scenario 1: Complete all events on time → Verify over/under shows "00:00" neutral color
3. Scenario 2: Let Event A run 30s overtime → Verify over/under shows "+00:30" in red
4. Scenario 3: Press NEXT early on Event B (20s remaining) → Verify over/under shows "-00:20" in green
5. Scenario 4: Mixed (overtime on A, undertime on B) → Verify cumulative over/under calculation
6. Success criteria: SC-004 (panel visible without scrolling), SC-005 (statistics calculate within 1 second)

---

## Phase 7: Background/Foreground Handling (1 hour)

**Purpose**: Ensure auto-progression works correctly when app is backgrounded and foregrounded

**Note**: This is a cross-cutting concern that enhances User Story 2 behavior

### Implementation

- [ ] T056 Add AppLifecycleObserver mixin to LiveTimerBloc in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T057 Implement didChangeAppLifecycleState to track background/foreground transitions in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T058 Add logic to check if auto-progression should have occurred during background period in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T059 Dispatch AutoProgressTriggered on app resume if countdown reached 00:00 while backgrounded in lib/logic/live_timer_bloc/live_timer_bloc.dart

### Tests

- [ ] T060 [P] Create bloc_test for background auto-progression scenario in test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [ ] T061 Run `flutter test` to verify background handling tests pass

**Manual Test Checkpoint**: 
1. Start series with 1-minute auto-progress event
2. Wait 30 seconds → Background the app (press home button)
3. Wait 40 seconds (total 70 seconds, event should have auto-progressed at 60s)
4. Foreground the app → Verify auto-progression triggers within 2 seconds
5. Success criteria: SC-008 (auto-progression triggers within 2 seconds of foregrounding)

---

## Phase 8: Edge Cases & Polish (1 hour)

**Purpose**: Handle edge cases and improve user experience across all user stories

### Edge Case Implementation

- [ ] T062 [P] Add validation to prevent event duration < 1 second during event creation in lib/presentation/screens/event_list_screen.dart
- [ ] T063 [P] Verify minimum 1-second display time enforcement in LiveTimerBloc shouldAutoProgress logic in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T064 Add error handling for audio playback failures (log error, continue) in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T065 Add logging for auto-progression start, completion, and errors in lib/logic/live_timer_bloc/live_timer_bloc.dart
- [ ] T066 Test single-event series with auto-progress (should go directly to completion screen)
- [ ] T067 Test series with mix of auto-progress and manual events
- [ ] T068 Test very short event duration (< 1 second) enforces minimum display time

### Documentation & Cleanup

- [ ] T069 [P] Add code comments to AutoProgressTriggered handler explaining logic
- [ ] T070 [P] Add code comments to SeriesStatistics calculations
- [ ] T071 Update README.md or CHANGELOG.md with feature summary
- [ ] T072 Run `flutter analyze` to check for code quality issues
- [ ] T073 Run `flutter test --coverage` to verify test coverage
- [ ] T074 Run quickstart.md manual testing checklist validation

**Final Checkpoint**: All edge cases handled, documentation complete, tests passing

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) - Independent of US1 but may benefit from US1 for testing
- **User Story 3 (Phase 5)**: Depends on User Story 2 completion (auto-progression logic required)
- **User Story 4 (Phase 6)**: Depends on Foundational (Phase 2) - Independent of US1/US2/US3, can run in parallel with US2
- **Background Handling (Phase 7)**: Depends on User Story 2 completion (enhances auto-progression)
- **Edge Cases & Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

```
Foundational (Phase 2) [BLOCKING]
    ↓
    ├─→ User Story 1 (Phase 3) [INDEPENDENT] ← MVP
    ├─→ User Story 2 (Phase 4) [INDEPENDENT]
    │       ↓
    │       └─→ User Story 3 (Phase 5) [DEPENDS ON US2]
    │       └─→ Background Handling (Phase 7) [DEPENDS ON US2]
    └─→ User Story 4 (Phase 6) [INDEPENDENT, can parallel with US2]
    
All above → Edge Cases & Polish (Phase 8)
```

### Parallel Opportunities

**Phase 1 (Setup)**:
- T001-T005 can run sequentially (fast, ~15 minutes total)

**Phase 2 (Foundational)**:
- T006-T007 (model updates) can run in parallel
- T009-T011 (test creation) can run in parallel after T008
- Must complete before any user story work

**Phase 3 (User Story 1)**:
- T013-T014 (toggle in create/edit dialogs) can run in parallel
- T016-T017 (visual indicator + tooltip) can run in parallel after T015

**Phase 4 (User Story 2)**:
- T018-T021 (state/event updates) can run in parallel
- T029-T030 (settings state) can run in parallel with T018-T021
- T033 (AutoProgressIndicator widget) can run in parallel with BLoC work
- T036-T040 (all tests) can run in parallel after implementation

**Phase 6 (User Story 4)**:
- T046 (SeriesStatisticsPanel widget) can run in parallel with T049 (formatted time methods)
- T052-T054 (all tests) can run in parallel after implementation

**Phase 8 (Edge Cases & Polish)**:
- T062-T063 (validation/display time) can run in parallel
- T069-T070 (documentation) can run in parallel with testing
- T072-T073 (analysis/coverage) can run in parallel

### Parallel Example: User Story 2 BLoC Layer

```bash
# Launch these tasks together:
Task T018: "Add fields to LiveTimerRunning state"
Task T019: "Add shouldAutoProgress computed property"
Task T020: "Update LiveTimerComplete state"
Task T021: "Add AutoProgressTriggered event class"

# These can also run in parallel with above:
Task T029: "Add autoProgressAudioEnabled to SettingsState"
Task T030: "Update SettingsState.copyWith"
Task T033: "Create AutoProgressIndicator widget"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

**Estimated Time**: 4-6 hours

1. Complete Phase 1: Setup (1-2 hours)
2. Complete Phase 2: Foundational (1-2 hours) - CRITICAL GATE
3. Complete Phase 3: User Story 1 (1-2 hours) - Configuration UI
4. Complete Phase 4: User Story 2 (2-3 hours) - Core auto-progression
5. **STOP and VALIDATE**: Test independently, demo to stakeholders
6. Deploy/demo if ready

**MVP Delivers**:
- ✅ Users can toggle auto-progress on individual events
- ✅ Events auto-advance when countdown reaches zero
- ✅ Visual and audio feedback on auto-progression
- ✅ Manual NEXT button still works (overrides auto-progression)

### Incremental Delivery (All User Stories)

**Estimated Time**: 6-8 hours

1. Complete MVP (Phases 1-4) → 4-6 hours
2. Add User Story 3 (Phase 5) → +30 minutes → Test fully automated series
3. Add User Story 4 (Phase 6) → +1-2 hours → Test statistics display
4. Add Background Handling (Phase 7) → +1 hour → Test app backgrounding
5. Polish & Edge Cases (Phase 8) → +1 hour → Final validation

**Full Feature Delivers**:
- ✅ All MVP features
- ✅ Fully hands-free series execution
- ✅ Series statistics at completion
- ✅ Background/foreground handling
- ✅ Edge cases covered

### Parallel Team Strategy

With 2-3 developers:

1. **Team completes Phase 1 & 2 together** (1-2 hours)
2. **Once Foundational is done, split**:
   - Developer A: User Story 1 (Phase 3) → 1-2 hours
   - Developer B: User Story 2 (Phase 4) → 2-3 hours
   - Developer C: User Story 4 (Phase 6) → 1-2 hours (can parallel with US2)
3. **Reconverge**:
   - Developer A: User Story 3 (Phase 5) after US2 done → 30 minutes
   - Developer B: Background Handling (Phase 7) → 1 hour
   - Developer C: Polish & Edge Cases (Phase 8) → 1 hour

**Team Completion Time**: ~4-5 hours (vs 6-8 hours sequential)

---

## Task Summary

- **Total Tasks**: 74
- **Phase 1 (Setup)**: 5 tasks
- **Phase 2 (Foundational)**: 7 tasks [BLOCKING]
- **Phase 3 (User Story 1 - P1)**: 5 tasks [MVP]
- **Phase 4 (User Story 2 - P1)**: 24 tasks [MVP]
- **Phase 5 (User Story 3 - P2)**: 4 tasks
- **Phase 6 (User Story 4 - P2)**: 10 tasks
- **Phase 7 (Background Handling)**: 6 tasks
- **Phase 8 (Edge Cases & Polish)**: 13 tasks

**Parallelizable Tasks**: 28 tasks marked [P]

**Story-Mapped Tasks**:
- User Story 1: 5 tasks
- User Story 2: 24 tasks
- User Story 3: 4 tasks
- User Story 4: 10 tasks

---

## Notes

- [P] tasks = different files, no dependencies within phase
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Run `flutter test` frequently to catch issues early
- Use `flutter analyze` to maintain code quality
- Follow Flutter/Dart style guide and BLoC patterns

---

## Success Criteria Validation

After implementation, verify all success criteria from spec.md:

- **SC-001**: Users enable/disable auto-progress in < 5 seconds → Validate in US1
- **SC-002**: Auto-progression completes within 1 second → Validate in US2
- **SC-002a**: Timer precision within 1 second → Validate in US2/US3
- **SC-003**: Fully automated series runs smoothly → Validate in US3
- **SC-004**: Statistics panel visible without scrolling → Validate in US4
- **SC-005**: Statistics calculate within 1 second → Validate in US4
- **SC-006**: 90% can identify auto-progress events → Validate in US1
- **SC-007**: Manual NEXT interrupts auto-progression → Validate in US2
- **SC-008**: Background/foreground auto-progression works → Validate in Phase 7

**All success criteria must pass before marking feature complete.**
