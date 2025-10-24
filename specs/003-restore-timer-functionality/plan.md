# Implementation Plan: Restore Timer Functionality

**Branch**: `003-restore-timer-functionality` | **Date**: October 23, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-restore-timer-functionality/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This is a regression fix to restore MVP timer functionality that was inadvertently broken during feature 002 (swipe-delete-items). The current implementation shows either countdown OR an "Overtime" message, but the MVP required displaying BOTH a countdown timer (remaining time) AND a count-up timer (elapsed time) simultaneously. The LiveTimerBloc state already provides all necessary data (`elapsedSeconds`, `remainingSeconds`, `overtimeSeconds`). The fix is purely UI-layer changes to the LiveTimerScreen widget to display both timers concurrently with proper formatting and color changes for overtime.

## Technical Context

**Language/Version**: Dart 3.9.2 / Flutter (from pubspec.yaml)  
**Primary Dependencies**: flutter_bloc ^9.1.1, hive ^2.2.3, hive_flutter ^1.1.0, equatable ^2.0.7  
**Storage**: Hive (local NoSQL database) - already implemented, no changes needed  
**Testing**: flutter_test, bloc_test ^10.0.0, mockito ^5.4.4  
**Target Platform**: Mobile (iOS, Android, macOS per existing config)  
**Project Type**: Mobile application (Flutter single codebase)  
**Performance Goals**: 60 fps UI, 1-second timer accuracy, <500ms transition time between events  
**Constraints**: Offline-capable (local storage only), <100MB memory footprint, supports screens down to 4 inches  
**Scale/Scope**: Single-user local app, ~5-10 screens, 1 BLoC modification (LiveTimerScreen UI only)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Specification-Driven Development**: ✅ PASS - `spec.md` exists and is complete with 3 user stories, 18 functional requirements, 7 success criteria
- **II. Template-Driven Consistency**: ✅ PASS - This plan follows the standard template structure
- **III. Progressive Enhancement**: ✅ PASS - All 3 user stories are Priority P1 and independently testable (dual timer display, overtime behavior, NEXT button)
- **IV. Quality Gates**: ✅ PASS - Spec passed quality checklist validation (see `checklists/requirements.md`)
- **V. Tool Integration**: ✅ PASS - Workflow supports JSON output for automation

**Gate Status**: ALL CLEAR - Proceed to Phase 0

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
│   ├── main.dart
│   ├── data/
│   │   ├── models/
│   │   │   ├── event.dart           # Existing - no changes
│   │   │   └── series.dart          # Existing - no changes
│   │   └── repositories/
│   │       └── series_repository.dart # Existing - no changes
│   ├── logic/
│   │   ├── live_timer_bloc/
│   │   │   ├── live_timer_bloc.dart  # Existing - no changes needed
│   │   │   ├── live_timer_event.dart # Existing - no changes needed
│   │   │   └── live_timer_state.dart # Existing - ALREADY PROVIDES elapsedSeconds, remainingSeconds, overtimeSeconds
│   │   ├── series_bloc/              # Existing - no changes
│   │   └── settings_cubit/           # Existing - no changes
│   └── presentation/
│       ├── screens/
│       │   ├── live_timer_screen.dart # TARGET FILE - UI changes only
│       │   ├── series_list_screen.dart # Existing - no changes
│       │   └── event_list_screen.dart  # Existing - no changes
│       └── widgets/
│           └── dismissible_event_item.dart # Existing - no changes
└── test/
    ├── logic/
    │   └── live_timer_bloc/
    │       └── live_timer_bloc_test.dart # Existing tests - validate still passing
    └── presentation/
        └── screens/
            └── live_timer_screen_test.dart # NEW - widget tests for dual timer display
```

**Structure Decision**: Flutter mobile app with existing BLoC architecture. This is a UI-only regression fix targeting a single file (`live_timer_screen.dart`). The state management layer (LiveTimerBloc/State) already provides all necessary data. No data model, repository, or BLoC logic changes required.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitutional violations. This is a straightforward UI regression fix with minimal complexity.

---

## Phase 0: Research (COMPLETED)

✅ **research.md** created with:
- Current state analysis showing LiveTimerState already provides all needed data
- 5 technical decisions documented (display layout, overtime format, labels, colors, testing)
- Flutter widget best practices for timer display
- Risk assessment (all low risk)
- No open questions - all details clear from codebase analysis

**Key Finding**: Regression is isolated to UI layer. BLoC state (`elapsedSeconds`, `remainingSeconds`, `overtimeSeconds`) is correct. Fix requires only widget tree changes in `live_timer_screen.dart`.

---

## Phase 1: Design & Contracts (COMPLETED)

✅ **data-model.md** created:
- Documented existing entities (Event, Series, LiveTimerState)
- Confirmed NO data model changes required
- State flow unchanged
- All validation rules unchanged

✅ **contracts/widget-contracts.md** created:
- LiveTimerScreen input/output contracts
- Visual display requirements for normal and overtime states
- Helper method contracts (`_formatCountdown`, `_formatDuration`)
- Widget testing contract with 5 test scenarios
- No API contracts (local-only app)

✅ **quickstart.md** created:
- 8-step implementation guide (estimated 30-45 minutes)
- Complete code examples for each step
- Manual testing scenarios
- Widget test template with 4 test groups
- Verification checklist and troubleshooting

✅ **Agent context updated**:
- Updated `.github/copilot-instructions.md`
- Added Dart/Flutter stack information
- Added flutter_bloc, hive dependencies
- Preserved manual additions

---

## Constitution Re-Check (Post-Design)

**Status**: ✅ ALL PASS - No issues identified

- **I. Specification-Driven**: Design follows complete spec with 18 functional requirements
- **II. Template Consistency**: All artifacts follow standard templates
- **III. Progressive Enhancement**: Single-file UI change, independently testable
- **IV. Quality Gates**: All design documents complete and reviewed
- **V. Tool Integration**: Quickstart supports both manual and automated testing

---

## Ready for Phase 2

**Next Command**: `/speckit.tasks` to generate task breakdown

The design phase is complete. All unknowns resolved. Implementation path is clear: modify `live_timer_screen.dart` to display both timers simultaneously with proper overtime formatting.
