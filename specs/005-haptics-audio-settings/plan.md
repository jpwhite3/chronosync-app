# Implementation Plan: Haptics and Audio Settings

**Branch**: `005-haptics-audio-settings` | **Date**: October 24, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-haptics-audio-settings/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Add comprehensive audio and haptic notification settings to ChronoSync timer app. Users can configure global default audio sounds (from device built-in sounds) and haptic intensity levels (light, medium, strong). Each event can override these defaults with custom settings via a "chime" toggle. The feature includes sound preview, graceful permission handling, device capability detection, and OS notification integration for reliable notifications when app is backgrounded or device is locked.

## Technical Context

**Language/Version**: Dart 3.9.2 / Flutter SDK (latest stable)  
**Primary Dependencies**: flutter_bloc ^9.1.1, hive ^2.2.3, hive_flutter ^1.1.0, just_audio ^0.9.36, vibration ^2.0.0 (NEW), flutter_local_notifications ^18.0.0 (NEW), permission_handler ^11.0.0 (NEW)  
**Storage**: Hive (local NoSQL database) for settings persistence  
**Testing**: flutter_test, mockito ^5.4.4, bloc_test ^10.0.0  
**Target Platform**: iOS and Android (cross-platform mobile)
**Project Type**: Mobile (Flutter) - feature modules within existing app structure  
**Performance Goals**: <1 second notification delivery after timer completion, <200ms UI response for settings changes  
**Constraints**: Must work offline, respect device permissions, graceful degradation on unsupported hardware  
**Scale/Scope**: Single-user local app, ~3 new screens/widgets, integration with existing Event entity

**Note**: All NEEDS CLARIFICATION items resolved in research.md

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Specification-Driven Development**: ✅ PASS - spec.md exists and is complete with all mandatory sections
- **II. Template-Driven Consistency**: ✅ PASS - This plan follows the standard template structure
- **III. Progressive Enhancement**: ✅ PASS - User stories are prioritized (P1-P3) and independently testable
- **IV. Quality Gates**: ✅ PASS - Spec passed quality checklist validation (see checklists/requirements.md)
- **V. Tool Integration**: ✅ PASS - Workflow supports automation via JSON output and follows template-driven approach

**Gate Status**: ✅ ALL CHECKS PASSED - Proceeding to Phase 0 research

## Project Structure

### Documentation (this feature)

```text
specs/005-haptics-audio-settings/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── notification_settings_contract.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
chronosync/
├── lib/
│   ├── data/
│   │   ├── models/
│   │   │   ├── global_notification_settings.dart       # NEW: Global settings model
│   │   │   ├── event_notification_settings.dart        # NEW: Event-level settings model
│   │   │   └── device_sound.dart                       # NEW: Device sound reference model
│   │   └── repositories/
│   │       ├── notification_settings_repository.dart   # NEW: Settings persistence
│   │       └── device_audio_repository.dart            # NEW: Device sound/haptic access
│   ├── logic/
│   │   └── blocs/
│   │       ├── notification_settings_bloc/             # NEW: Settings state management
│   │       │   ├── notification_settings_bloc.dart
│   │       │   ├── notification_settings_event.dart
│   │       │   └── notification_settings_state.dart
│   │       └── timer_notification_bloc/                # NEW: Timer completion notifications
│   │           ├── timer_notification_bloc.dart
│   │           ├── timer_notification_event.dart
│   │           └── timer_notification_state.dart
│   └── presentation/
│       ├── screens/
│       │   └── settings/
│       │       ├── notification_settings_screen.dart   # NEW: Global settings UI
│       │       └── widgets/
│       │           ├── sound_picker_widget.dart        # NEW: Sound selection
│       │           ├── haptic_intensity_picker.dart    # NEW: Haptic intensity selector
│       │           └── sound_preview_button.dart       # NEW: Sound preview
│       └── widgets/
│           └── event_form/
│               └── chime_settings_widget.dart          # NEW: Event chime toggle & custom settings
└── test/
    ├── data/
    │   ├── models/
    │   │   ├── global_notification_settings_test.dart
    │   │   ├── event_notification_settings_test.dart
    │   │   └── device_sound_test.dart
    │   └── repositories/
    │       ├── notification_settings_repository_test.dart
    │       └── device_audio_repository_test.dart
    ├── logic/
    │   └── blocs/
    │       ├── notification_settings_bloc_test.dart
    │       └── timer_notification_bloc_test.dart
    └── presentation/
        └── widgets/
            ├── sound_picker_widget_test.dart
            ├── haptic_intensity_picker_test.dart
            └── chime_settings_widget_test.dart
```

**Structure Decision**: Flutter mobile app with BLoC pattern architecture. Following existing project structure with separation of concerns: data layer (models, repositories), logic layer (BLoCs for state management), and presentation layer (screens, widgets). Hive for local persistence, existing pattern established in the app.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitutional violations - all quality gates passed. No additional complexity introduced beyond standard Flutter/BLoC architecture patterns already established in the project.

---

## Phase Completion Status

### Phase 0: Research ✅ COMPLETE
**Output**: `research.md` - 8 research questions resolved
- Audio picker approach: Platform channels (no package solution)
- Vibration package: vibration ^2.0.0 with intensity mapping
- Notification integration: flutter_local_notifications ^18.0.0
- Sound preview: just_audio ^0.9.36
- Hive models: Type adapters with typeId 3-5
- Permission handling: permission_handler ^11.0.0 with retry logic
- BLoC architecture: Two separate BLoCs (settings vs notifications)
- UI patterns: Material Design 3 with ExpansionTile, bottom sheets

### Phase 1: Design & Contracts ✅ COMPLETE
**Outputs**:
- `data-model.md` - 5 entities defined with validation rules and relationships
- `contracts/notification_settings_contract.md` - 9 interfaces (repositories, BLoCs, widgets, platform channels)
- `quickstart.md` - Developer guide with 5 implementation phases, testing strategy, troubleshooting
- Agent context updated via `update-agent-context.sh copilot`

**Re-evaluation**: Constitution Check remains PASSED after design phase completion.

### Phase 2: Task Generation ⏳ PENDING
**Instruction**: Run separate command `/speckit.tasks` to generate tasks.md

**Rationale**: Per workflow design, task generation is intentionally separated from planning to allow review of research, data models, and contracts before committing to specific implementation tasks. This gate ensures architectural decisions are validated before breaking down into granular work items.

---

## Next Steps

1. ✅ Phase 0 Research completed
2. ✅ Phase 1 Design artifacts completed
3. ⏳ **ACTION REQUIRED**: Review the following artifacts before proceeding:
   - `research.md` - Validate technology decisions
   - `data-model.md` - Validate entity structure and validation rules
   - `contracts/notification_settings_contract.md` - Validate interface contracts
   - `quickstart.md` - Validate implementation approach
4. ⏳ **NEXT COMMAND**: Run `/speckit.tasks` to generate implementation tasks (Phase 2)
5. ⏳ Begin implementation following quickstart.md phases
6. ⏳ Use generated tasks.md for progress tracking

**Current Status**: ✅ Phase 1 complete - ready for task generation
