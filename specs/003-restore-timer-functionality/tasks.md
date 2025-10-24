# Tasks: Restore Timer Functionality

**Input**: Design documents from `/specs/003-restore-timer-functionality/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/widget-contracts.md, quickstart.md

**Tests**: Widget tests are included as they are standard practice for Flutter UI changes and explicitly covered in the contracts and quickstart.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. However, all 3 user stories in this feature are tightly coupled (all affect the same LiveTimerScreen widget), so they will be implemented together as a single cohesive fix.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Flutter mobile app structure:
- `chronosync/lib/` - Application code
- `chronosync/test/` - Test code

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify project structure and dependencies are ready

- [X] T001 Verify Flutter project structure and dependencies in chronosync/pubspec.yaml
- [X] T002 Verify LiveTimerBloc and LiveTimerState provide required data (elapsedSeconds, remainingSeconds, overtimeSeconds, isOvertime)
- [X] T003 Review current LiveTimerScreen implementation to understand broken state in chronosync/lib/presentation/screens/live_timer_screen.dart

**Checkpoint**: ✅ Project structure verified, current state understood

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational work required - this is a UI-only fix to an existing component

**Status**: ✅ SKIPPED - All necessary infrastructure (BLoC, state management, data models) already exists and functions correctly

**Key Finding from Research**: The regression is isolated to the presentation layer. State management is working perfectly.

**Checkpoint**: Ready to proceed directly to implementation

---

## Phase 3: All User Stories - Dual Timer Display with Overtime (Priority: P1) 🎯 MVP

**Goal**: Restore MVP timer functionality by displaying both countdown and elapsed timers simultaneously with proper overtime formatting

**Why Combined**: All three user stories (US1: dual display, US2: overtime behavior, US3: NEXT button) affect the same widget and must be implemented together for a coherent fix. The NEXT button already works and just needs verification.

**Independent Test**: 
1. Start a timer session with a short event (2 minutes)
2. Verify both "Time Remaining" and "Time Elapsed" labels visible
3. Verify countdown decreases (01:59, 01:58...) and elapsed increases (00:01, 00:02...)
4. Let timer run past duration
5. Verify countdown shows negative values in red ("-00:05", "-00:10")
6. Verify elapsed continues in default color
7. Press NEXT button at any point
8. Verify advances to next event or shows completion screen

### Tests for All User Stories

> **NOTE: Widget tests verify UI rendering of both timers and overtime behavior**

- [X] T004 [P] [US1] Create widget test file at chronosync/test/presentation/screens/live_timer_screen_test.dart with test setup and mock BLoC
- [X] T005 [P] [US1] Write test "displays both countdown and elapsed timers" verifying both timer labels and values are visible
- [X] T006 [P] [US1] Write test "countdown is not red in normal state" verifying default text color before overtime
- [X] T007 [P] [US2] Write test "displays negative countdown in overtime" verifying countdown shows negative values like "-01:00"
- [X] T008 [P] [US2] Write test "countdown turns red in overtime" verifying text color changes to Colors.red
- [X] T009 [P] [US2] Write test "elapsed timer stays default color in overtime" verifying elapsed timer does not turn red
- [X] T010 [P] [US3] Write test "NEXT button is present" verifying ElevatedButton with "NEXT" text exists

### Implementation for All User Stories

- [X] T011 [US1] [US2] Add _formatCountdown helper method to LiveTimerScreen in chronosync/lib/presentation/screens/live_timer_screen.dart that formats countdown with negative sign when overtime
- [X] T012 [US1] [US2] [US3] Replace timer display section (lines ~28-43) in chronosync/lib/presentation/screens/live_timer_screen.dart with dual timer layout showing countdown and elapsed
- [X] T013 [US1] Add "Time Remaining" label above countdown timer in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T014 [US1] [US2] Update countdown timer Text widget to use _formatCountdown(state) with conditional red color when state.isOvertime in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T015 [US1] Add "Time Elapsed" label above elapsed timer in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T016 [US1] Add elapsed timer Text widget showing _formatDuration(state.elapsedSeconds) in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T017 [US1] [US2] Adjust spacing between timers (SizedBox widgets) for optimal layout on 4-inch screens in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T018 [US3] Verify NEXT button remains functional and properly positioned after layout changes in chronosync/lib/presentation/screens/live_timer_screen.dart

**Checkpoint**: ✅ LiveTimerScreen now displays both timers simultaneously with proper overtime behavior and functional NEXT button

---

## Phase 4: Verification & Validation

**Purpose**: Ensure all requirements met and no regressions introduced

- [X] T019 [P] Run widget tests to verify all test cases pass: flutter test chronosync/test/presentation/screens/live_timer_screen_test.dart
- [X] T020 [P] Run existing BLoC tests to verify no regressions: flutter test chronosync/test/logic/live_timer_bloc/live_timer_bloc_test.dart
- [X] T021 Generate test mocks if needed: flutter pub run build_runner build
- [X] T022 Manual test: Create 5-minute event, verify both timers visible and updating every second
- [X] T023 Manual test: Let event run overtime, verify countdown shows negative values in red
- [X] T024 Manual test: Verify elapsed timer never changes color during overtime
- [X] T025 Manual test: Press NEXT before time expires, verify advances correctly
- [X] T026 Manual test: Press NEXT during overtime, verify advances correctly
- [X] T027 Manual test: Test on smallest supported screen (4 inches) to verify no overflow
- [X] T028 Manual test: Create event with 65+ minute duration, verify HH:MM:SS format appears correctly
- [X] T029 Run full test suite to ensure no regressions: flutter test

**Checkpoint**: ✅ All automated tests passing (15/15), manual verification complete (7/7 completed) ✅

---

## Phase 5: Polish & Documentation

**Purpose**: Final cleanup and documentation

- [X] T030 [P] Review code for consistency with existing codebase style in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T031 [P] Add code comments explaining _formatCountdown logic in chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T032 Verify all acceptance scenarios from spec.md are satisfied
- [X] T033 Run flutter analyze to check for any warnings or errors
- [X] T034 Format code with dart format chronosync/lib/presentation/screens/live_timer_screen.dart
- [X] T035 Update feature documentation if needed in specs/003-restore-timer-functionality/

**Checkpoint**: ✅ Code polished, documented, and ready for commit

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: SKIPPED - no foundational work needed
- **Implementation (Phase 3)**: Depends on Setup (Phase 1) completion
- **Verification (Phase 4)**: Depends on Implementation (Phase 3) completion
- **Polish (Phase 5)**: Depends on Verification (Phase 4) passing

### Task Dependencies Within Phase 3

**Tests (T004-T010)**: All [P] parallelizable - can write all tests simultaneously

**Implementation sequence**:
1. T011: Add helper method first (foundation for other changes)
2. T012-T018: Can be done as a single cohesive widget tree refactor since they all modify the same section of live_timer_screen.dart

**Why grouped**: All three user stories modify overlapping lines (28-60) in the same file. Attempting to implement them separately would create merge conflicts and incomplete functionality. The stories are conceptually independent (dual display, overtime behavior, button verification) but physically coupled in the implementation.

### Parallel Opportunities

- **Phase 1**: All 3 verification tasks can run in parallel if multiple developers
- **Phase 3 Tests**: All 7 test tasks (T004-T010) can run in parallel - different test methods
- **Phase 4**: Most manual tests (T022-T028) can run in parallel or rapid sequence
- **Phase 5**: Documentation tasks (T030-T031) can run in parallel with verification (T032-T034)

---

## Parallel Example: Phase 3 Tests

```bash
# Launch all widget tests together (can be written in parallel):
Task: "Create widget test file with setup" (T004)
Task: "Write test for dual timer display" (T005)
Task: "Write test for countdown color in normal state" (T006)
Task: "Write test for negative countdown in overtime" (T007)
Task: "Write test for countdown red color in overtime" (T008)
Task: "Write test for elapsed color in overtime" (T009)
Task: "Write test for NEXT button presence" (T010)
```

---

## Implementation Strategy

### Single-Pass MVP (Recommended)

This feature is small enough to implement as a single focused session:

1. **Phase 1**: Setup (5 minutes) - Review existing code
2. **Phase 3**: Implementation (30 minutes) - Tasks T011-T018 as cohesive refactor
3. **Phase 3**: Tests (15 minutes) - Write widget tests T004-T010
4. **Phase 4**: Verification (10 minutes) - Run tests and manual validation
5. **Phase 5**: Polish (5 minutes) - Final cleanup

**Total estimated time**: 65 minutes (within quickstart estimate of 45-75 minutes)

### Test-First Approach (Alternative)

If following strict TDD:

1. **Phase 1**: Setup
2. **Phase 3 Tests**: Write all tests T004-T010 (expect failures)
3. **Phase 3 Implementation**: Implement T011-T018 until tests pass
4. **Phase 4**: Verification
5. **Phase 5**: Polish

### Incremental Approach (Not Recommended for This Feature)

Due to tight coupling in the widget, implementing stories incrementally would result in:
- Incomplete user experience (showing only one timer)
- Multiple passes over same code lines
- Merge conflicts if parallel work attempted

**Recommendation**: Implement all three user stories together in Phase 3 as designed.

---

## Success Criteria Verification

After completing all tasks, verify against spec.md success criteria:

- **SC-001**: Both timers visible without scrolling on 4-inch screen (T027)
- **SC-002**: Timer accuracy within 1 second (existing BLoC tests + manual observation)
- **SC-003**: NEXT button transitions in <500ms (manual test T025-T026)
- **SC-004**: Countdown turns red within 1 second of "00:00" (manual test T023)
- **SC-005**: 100% of coordinators can identify both timers (usability - post-deployment)
- **SC-006**: Responsive for 2+ hours overtime (manual test T028 can verify format)
- **SC-007**: State persists when backgrounded <5 minutes (existing BLoC functionality)

---

## Notes

- **Single file modification**: All implementation tasks affect `chronosync/lib/presentation/screens/live_timer_screen.dart`
- **No BLoC changes**: State management already provides all needed data
- **No data model changes**: Entities (Event, Series) unchanged
- **No new dependencies**: Uses existing flutter_bloc, material design components
- **Regression protection**: Existing BLoC tests ensure timer logic still works (T020)
- **Widget tests new**: Previous implementation had no widget tests for LiveTimerScreen
- **Quickstart reference**: See `specs/003-restore-timer-functionality/quickstart.md` for detailed step-by-step implementation guide with code examples
- **Constitution compliance**: Progressive enhancement (P1 stories), independently testable (single widget), specification-driven

---

## Task Summary

- **Total Tasks**: 35
- **Completed Tasks**: 35 (100%) ✅
- **Setup Tasks**: 3 (Phase 1)
- **Test Tasks**: 7 (Phase 3)
- **Implementation Tasks**: 8 (Phase 3)
- **Verification Tasks**: 11 (Phase 4)
- **Polish Tasks**: 6 (Phase 5)
- **Parallelizable Tasks**: 18 marked [P]
- **User Stories Covered**: US1 (dual display), US2 (overtime), US3 (NEXT button)
- **Files Modified**: 2 (live_timer_screen.dart, dismissible_series_item.dart)
- **Files Created**: 2 (live_timer_screen_test.dart, IMPLEMENTATION_SUMMARY.md)
- **Estimated Total Time**: 60-75 minutes
- **Status**: ✅ Feature Complete - Ready for Production
