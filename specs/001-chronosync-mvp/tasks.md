---
description: "Task list for ChronoSync MVP implementation"
---

# Tasks: ChronoSync MVP - Live Event Coordinator

**Input**: Design documents from `/specs/001-chronosync-mvp/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: TDD is not explicitly requested, so test tasks are focused on unit and widget testing as per Flutter best practices.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- **Mobile App**: `lib/` for source, `test/` for tests.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure.

- [X] T001 Create new Flutter project named 'chronosync'
- [X] T002 [P] Add required dependencies to `pubspec.yaml`: `flutter_bloc` for state management, `hive` and `hive_flutter` for local storage.
- [X] T003 [P] Configure linting rules in `analysis_options.yaml` for strict type checking and code style.
- [X] T004 Create the basic directory structure inside `lib/`: `data/`, `logic/`, `presentation/`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented.

- [X] T005 Initialize Hive for local storage in `main.dart`.
- [X] T006 [P] Define the `Series` and `Event` data models in `lib/data/models/series.dart` and `lib/data/models/event.dart`. Register them with Hive.
- [X] T007 [P] Create a `SeriesRepository` in `lib/data/repositories/series_repository.dart` to handle CRUD operations for Series and Events using Hive.
- [X] T008 [P] Set up the basic BLoC for Series management in `lib/logic/series_bloc/series_bloc.dart`.

---

## Phase 3: User Story 1 - Series Management (Priority: P1) 🎯 MVP

**Goal**: Allow an Event Coordinator to create and manage a series of timed events.

**Independent Test**: The user can create a series, add events to it, and see the updated list on the screen.

### Implementation for User Story 1

- [X] T009 [US1] Create the UI for the Series list screen in `lib/presentation/screens/series_list_screen.dart`. This screen should display a list of all created series.
- [X] T010 [US1] Implement the "Create Series" functionality, showing a dialog to get the series title and triggering the BLoC event to save it.
- [ ] T011 [US1] Create the UI for the Event list screen in `lib/presentation/screens/event_list_screen.dart`. This screen should display the events for a selected series.
- [ ] T012 [US1] Implement the "Add Event" functionality on the Event list screen, showing a dialog to get the event title and duration.
- [ ] T013 [US1] Connect the UI to the `SeriesBloc` to display real data and handle state changes.
- [ ] T014 [P] [US1] Write unit tests for the `SeriesRepository` in `test/data/repositories/series_repository_test.dart`.
- [ ] T015 [P] [US1] Write unit tests for the `SeriesBloc` in `test/logic/series_bloc/series_bloc_test.dart`.

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently.

---

## Phase 4: User Story 2 - Live Timer Screen (Priority: P2)

**Goal**: Provide a live timer screen for running an event series.

**Independent Test**: The user can start a series and see the live timer screen with the correct data. The timers should update, and the "NEXT" button should function.

### Implementation for User Story 2

- [ ] T016 [US2] Create the `LiveTimerBloc` in `lib/logic/live_timer_bloc/live_timer_bloc.dart` to manage the state of the live timer screen (current event, timers, etc.).
- [ ] T017 [US2] Create the UI for the Live Timer screen in `lib/presentation/screens/live_timer_screen.dart`.
- [ ] T018 [US2] Implement the "Start" button on the Series list screen to navigate to the Live Timer screen and initialize the `LiveTimerBloc` with the selected series.
- [ ] T019 [US2] Implement the display of the current event's title.
- [ ] T020 [US2] Implement the countdown and count-up timers using a `Timer.periodic`.
- [ ] T021 [US2] Implement the logic for the countdown timer turning red and showing negative time when the duration is exceeded.
- [ ] T022 [US2] Implement the "NEXT" button to advance to the next event, updating the BLoC state.
- [ ] T023 [US2] Implement the summary screen when the last event is completed.
- [ ] T024 [P] [US2] Write unit tests for the `LiveTimerBloc` in `test/logic/live_timer_bloc/live_timer_bloc_test.dart`.
- [ ] T025 [P] [US2] Write widget tests for the `LiveTimerScreen` in `test/presentation/screens/live_timer_screen_test.dart` to verify UI updates.

**Checkpoint**: All user stories should now be independently functional.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories.

- [ ] T026 [P] Add basic error handling and user feedback for all interactions.
- [ ] T027 [P] Refine the UI/UX for a more polished look and feel.
- [ ] T028 [P] Write documentation for the main BLoCs and Repositories.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Must be completed first.
- **Foundational (Phase 2)**: Depends on Setup. Blocks all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational.
- **User Story 2 (Phase 4)**: Depends on User Story 1.
- **Polish (Phase 5)**: Can be done after all user stories are complete.

### Parallel Opportunities

- Within Phase 1, T002, T003, and T004 can be done in parallel.
- Within Phase 2, T006, T007, and T008 can be done in parallel.
- Unit tests (T014, T015, T024, T025) can often be written in parallel with UI development.

---

## Implementation Strategy

### Incremental Delivery

1.  Complete Setup + Foundational.
2.  Implement User Story 1 fully. At this point, the app allows creating and managing agendas.
3.  Implement User Story 2. This adds the live timer functionality.
4.  Final polish.

This approach ensures that the core data management is solid before building the live functionality on top of it.
