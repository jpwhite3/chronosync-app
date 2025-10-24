````markdown
# Implementation Plan: Auto-Progress Events with Series Statistics

**Branch**: `004-auto-progress-events` | **Date**: October 23, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-auto-progress-events/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature adds optional automatic progression for events when their countdown timers reach zero, enabling hands-free series execution. When all events in a series have auto-progress enabled, the entire series runs without manual intervention. Upon completion, aggregate statistics (event count, expected vs actual time, over/under time) are displayed. The implementation extends the existing Event model with an autoProgress field, enhances LiveTimerBloc to detect timer completion and trigger progression, and adds a completion statistics panel to the UI.

## Technical Context

**Language/Version**: Dart 3.9.2 / Flutter SDK (latest stable)  
**Primary Dependencies**: flutter_bloc ^9.1.1, hive ^2.2.3, hive_flutter ^1.1.0, equatable ^2.0.7  
**Storage**: Hive (local NoSQL database) for Event and Series persistence  
**Testing**: flutter_test (unit tests), mockito ^5.4.4, bloc_test ^10.0.0  
**Target Platform**: iOS, Android, macOS, Linux, Windows, Web (Flutter multi-platform)  
**Project Type**: Mobile (Flutter application with BLoC architecture)  
**Performance Goals**: 60 fps UI, <1 second auto-progression delay, <1 second timer precision  
**Constraints**: Offline-capable, must handle backgrounding/foregrounding, minimum 1-second event display time  
**Scale/Scope**: Single-user local app, ~10-50 series typical, ~5-20 events per series typical

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Pre-Phase 0 Check (✅ PASSED)**:
- **I. Specification-Driven Development**: ✅ `spec.md` exists and is complete with user scenarios, functional requirements, and success criteria
- **II. Template-Driven Consistency**: ✅ This plan follows the standard template structure
- **III. Progressive Enhancement**: ✅ User stories are prioritized (P1, P2) and each is independently testable as documented
- **IV. Quality Gates**: ✅ Spec includes comprehensive acceptance scenarios, edge cases, and measurable success criteria
- **V. Tool Integration**: ✅ Workflow supports automation via JSON output and standard tooling

**Post-Phase 1 Check (✅ PASSED)**:
- **I. Specification-Driven Development**: ✅ All design artifacts (research.md, data-model.md, contracts/, quickstart.md) completed
- **II. Template-Driven Consistency**: ✅ All artifacts follow standard templates and structure
- **III. Progressive Enhancement**: ✅ Implementation phases are incremental and independently testable
- **IV. Quality Gates**: ✅ Data model includes validation rules, contracts define clear interfaces, quickstart provides step-by-step guide
- **V. Tool Integration**: ✅ Agent context updated via automation, all paths absolute, supports CI/CD integration

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
│   │   │   ├── event.dart              # Extend with autoProgress field
│   │   │   ├── series.dart             # No changes needed
│   │   │   └── user_preferences.dart   # Add audio cue toggle
│   │   └── repositories/
│   │       ├── series_repository.dart  # No changes needed
│   │       └── preferences_repository.dart # Handle new setting
│   ├── logic/
│   │   ├── live_timer_bloc/
│   │   │   ├── live_timer_bloc.dart    # Add auto-progression logic
│   │   │   ├── live_timer_event.dart   # Add auto-progress trigger event
│   │   │   └── live_timer_state.dart   # Add completion statistics state
│   │   └── settings_cubit/
│   │       └── settings_state.dart     # Add audio cue setting
│   ├── presentation/
│   │   ├── screens/
│   │   │   ├── event_list_screen.dart  # Add auto-progress toggle UI
│   │   │   ├── live_timer_screen.dart  # Add stats panel, toast notifications
│   │   │   └── settings_screen.dart    # Add audio cue toggle
│   │   └── widgets/
│   │       └── series_stats_panel.dart # New widget for completion stats
│   └── main.dart                        # No changes needed
└── test/
    ├── data/
    │   └── models/
    │       └── event_test.dart          # Test autoProgress field
    ├── logic/
    │   └── live_timer_bloc/
    │       └── live_timer_bloc_test.dart # Test auto-progression logic
    └── presentation/
        └── widgets/
            └── series_stats_panel_test.dart # Test statistics calculations
```

**Structure Decision**: This is a Flutter mobile application using the BLoC (Business Logic Component) pattern with Hive for local persistence. The architecture separates data models, business logic (BLoCs), and presentation layers. All feature additions integrate into this existing structure without introducing new architectural patterns.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitutional violations identified. All complexity is inherent to the feature requirements:
- Auto-progression logic naturally fits within existing LiveTimerBloc
- Statistics calculations are ephemeral (not persisted), reducing complexity
- Event model extension follows established Hive patterns
- No new architectural patterns or dependencies introduced

````
