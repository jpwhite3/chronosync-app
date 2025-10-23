# Implementation Plan: Swipe-to-Delete Events and Series

**Branch**: `002-swipe-delete-items` | **Date**: October 23, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-swipe-delete-items/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Add swipe-to-delete functionality for events and series with configurable swipe direction, undo capability, confirmation dialogs for non-empty series, and protection for events in active timer sessions. Technical approach uses Flutter's Dismissible widget for swipe gestures, flutter_bloc for state management, and Hive for persisting user preferences and managing soft deletion with undo windows.

## Technical Context

**Language/Version**: Dart 3.9.2 / Flutter (from pubspec.yaml)
**Primary Dependencies**: flutter_bloc ^9.1.1, hive ^2.2.3, hive_flutter ^1.1.0, equatable ^2.0.7
**Storage**: Hive (local NoSQL database) with boxes for 'series' and 'events'
**Testing**: flutter_test, mockito ^5.4.4, bloc_test ^10.0.0
**Target Platform**: Cross-platform mobile (iOS, Android, macOS based on workspace structure)
**Project Type**: Mobile application with BLoC pattern architecture
**Performance Goals**: <500ms UI updates (SC-007), 60 fps animations for swipe gestures, <100ms storage operations
**Constraints**: Offline-capable (Hive is local-first), undo window 5-10 seconds, gesture threshold 30-40% of item width
**Scale/Scope**: Single-user local app, ~5 main screens currently (series list, event list, timer, settings to be added), small data volume (dozens of series/events per user)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Specification-Driven Development**: ✅ `spec.md` exists and is complete with 33 functional requirements, 10 success criteria, and 5 clarifications
- **II. Template-Driven Consistency**: ✅ This plan follows the standard template structure
- **III. Progressive Enhancement**: ✅ User stories are prioritized P1-P3 and each is independently testable
- **IV. Quality Gates**: ✅ Spec passed quality checklist with all 16 items validated (see checklists/requirements.md)
- **V. Tool Integration**: ✅ Workflow supports JSON output and automation

**Gate Status**: ✅ PASSED - Proceeding to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
chronosync/
├── lib/
│   ├── data/
│   │   ├── models/
│   │   │   ├── event.dart (existing)
│   │   │   ├── series.dart (existing)
│   │   │   ├── user_preferences.dart (NEW - for swipe direction)
│   │   │   └── pending_deletion.dart (NEW - for undo tracking)
│   │   └── repositories/
│   │       ├── series_repository.dart (existing - MODIFY)
│   │       ├── event_repository.dart (NEW)
│   │       └── preferences_repository.dart (NEW)
│   ├── logic/
│   │   ├── series_bloc/ (existing - MODIFY for deletion)
│   │   ├── live_timer_bloc/ (existing - CHECK for active events)
│   │   └── settings_bloc/ (NEW - for preferences)
│   ├── presentation/
│   │   ├── screens/
│   │   │   ├── series_list_screen.dart (existing - MODIFY for swipe)
│   │   │   ├── event_list_screen.dart (existing - MODIFY for swipe)
│   │   │   ├── settings_screen.dart (NEW)
│   │   │   └── live_timer_screen.dart (existing - reference only)
│   │   └── widgets/
│   │       ├── dismissible_series_item.dart (NEW)
│   │       ├── dismissible_event_item.dart (NEW)
│   │       ├── deletion_confirmation_dialog.dart (NEW)
│   │       └── undo_snackbar.dart (NEW)
│   └── main.dart (existing - MODIFY for settings route)
└── test/
    ├── data/
    │   ├── models/ (NEW tests for preferences, pending_deletion)
    │   └── repositories/ (NEW tests for new repositories)
    ├── logic/
    │   └── settings_bloc/ (NEW tests)
    └── presentation/
        └── widgets/ (NEW tests for dismissible items)
```

**Structure Decision**: Using existing Flutter BLoC architecture pattern. New feature adds:
- User preferences model/repository for settings persistence
- Pending deletion tracking for undo functionality
- Settings BLoC for preference management
- Dismissible wrapper widgets for reusable swipe-to-delete behavior
- Settings screen accessible from app bar
- Confirmation dialog component for series deletion

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

### Principle III Exception: User Story 2 & 3 Dependency

**Violation**: Tasks.md Phase 5 states "User Story 3: Requires User Story 2 completion"

**Justification**: 
- US2 and US3 share the `DismissibleSeriesItem` widget infrastructure
- Dependency is at the *widget implementation* level, not *feature* level
- US3 can be independently tested: Create series with events → swipe → verify confirmation dialog → test both paths
- US3 delivers independent value: Safety mechanism preventing accidental data loss
- Shared widget factoring is a technical optimization, not a feature coupling

**Mitigation**:
- US3 can be implemented by different developer than US2 after widget interface is defined
- US3 test scenarios are fully independent (confirmation dialog behavior)
- If US2 is skipped, US3 can implement full widget from scratch (6 tasks become 8 tasks)

**Approved**: This is a pragmatic dependency that maintains independent testing and value delivery while optimizing implementation efficiency.

---

## Phase Completion Status

### Phase 0: Research ✅ COMPLETE

**Artifacts Generated**:
- `research.md` - Technical decisions documented

**Key Decisions**:
1. Use Flutter's Dismissible widget for swipe gestures
2. Soft deletion with Timer-based permanent deletion for undo
3. New Hive box for UserPreferences persistence
4. SettingsCubit for preference management
5. Query LiveTimerBloc state for active timer check
6. AlertDialog for confirmation dialogs
7. Try-catch with auto-retry for storage failures
8. Optimistic UI updates with rollback

**All NEEDS CLARIFICATION resolved**: Yes

---

### Phase 1: Design & Contracts ✅ COMPLETE

**Artifacts Generated**:
- `data-model.md` - Entity definitions, state transitions, validation rules
- `contracts/bloc-contracts.md` - BLoC events/states/methods, repository contracts, widget contracts
- `quickstart.md` - Developer implementation guide

**Key Design Elements**:
1. **New Entities**: UserPreferences (Hive typeId: 2), PendingDeletion (in-memory)
2. **Modified Entities**: Event and Series with soft delete behavior
3. **New BLoC**: SettingsCubit with SettingsLoaded state
4. **Extended BLoC**: SeriesBloc with DeleteEvent, DeleteSeries, UndoDeletion, ConfirmPermanentDeletion events
5. **New Repositories**: PreferencesRepository
6. **New Widgets**: DismissibleEventItem, DismissibleSeriesItem
7. **State Transitions**: Documented for event deletion, series deletion, settings update
8. **Validation Rules**: Active timer check, confirmation logic, swipe direction validation

**Constitution Check Re-validation**:
- ✅ All specifications still complete and valid
- ✅ Design maintains template consistency
- ✅ Progressive enhancement preserved (P1→P2→P3 implementation order)
- ✅ Quality gates defined in contracts (unit, widget, integration tests)
- ✅ Tool integration maintained (no blocking dependencies)

**Post-Design Gate Status**: ✅ PASSED

---

## Next Steps

1. **Phase 2**: Run `/speckit.tasks` to generate task breakdown (tasks.md)
2. **Implementation**: Follow quickstart.md for step-by-step development
3. **Testing**: Implement tests as defined in contracts/bloc-contracts.md
4. **Validation**: Verify success criteria from spec.md after completion

**Estimated Implementation Time**: 11-14 hours (see quickstart.md)

---

## Planning Complete

All phases of planning (Phase 0: Research, Phase 1: Design & Contracts) are complete. Ready for task breakdown and implementation.
