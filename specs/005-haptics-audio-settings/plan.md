````markdown
# Implementation Plan: Haptics and Audio Settings

**Branch**: `005-haptics-audio-settings` | **Date**: 2025-10-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-haptics-audio-settings/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature adds comprehensive haptic and audio notification settings to ChronoSync, allowing users to configure default notification preferences globally and customize them per event. Users can select from device built-in sounds, choose haptic intensity levels (light, medium, strong), and toggle a "chime" setting at the event level to control timer completion notifications. The implementation requires integration with platform-specific audio and haptic APIs (iOS and macOS), persistent storage of settings via Hive, and graceful fallback handling for unavailable sounds or unsupported devices.

## Technical Context

**Language/Version**: Dart 3.9.2 / Flutter SDK 3.35.7 (stable channel)  
**Primary Dependencies**: flutter_bloc ^9.1.1, hive ^2.2.3, hive_flutter ^1.1.0, just_audio ^0.10.5, vibration ^3.1.4, flutter_local_notifications ^19.5.0, permission_handler ^12.0.1, equatable ^2.0.7  
**Storage**: Hive (local NoSQL database) for settings and event configuration persistence  
**Testing**: flutter_test (SDK), bloc_test ^10.0.0, mockito ^5.4.4  
**Target Platform**: iOS 13.0+, macOS 10.15+ (Flutter multi-platform: mobile + desktop)
**Project Type**: Mobile/Desktop Flutter application - multi-platform with platform-specific audio/haptic implementations  
**Performance Goals**: <1 second notification delivery from timer completion, <30ms haptic feedback response, <100ms sound preview playback start  
**Constraints**: Must respect device silent/DND mode for audio while maintaining haptic functionality, must handle OS permission restrictions gracefully with retry mechanisms, offline-capable (no network required)  
**Scale/Scope**: ~15-20 screens/dialogs (settings screens, event creation/editing), 3 haptic intensity levels, support for device built-in sound library enumeration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Specification-Driven Development**: ✅ `spec.md` exists and is complete with comprehensive requirements, user stories, edge cases, and success criteria
- **II. Template-Driven Consistency**: ✅ This plan follows the standard template structure
- **III. Progressive Enhancement**: ✅ User stories are prioritized (P1-P3) and independently testable as defined in spec.md
- **IV. Quality Gates**: ✅ Spec has passed quality checklist review with comprehensive enhancements documented
- **V. Tool Integration**: ✅ Workflow supports automation via bash scripts and JSON output

## Project Structure

### Documentation (this feature)

```text
```text
specs/005-haptics-audio-settings/
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
│   │   │   ├── event.dart (existing - extend with notification settings)
│   │   │   ├── global_settings.dart (NEW - notification defaults)
│   │   │   └── device_sound.dart (NEW - sound reference model)
│   │   ├── repositories/
│   │   │   ├── settings_repository.dart (NEW - Hive persistence)
│   │   │   └── sound_repository.dart (NEW - platform sound access)
│   │   └── datasources/
│   │       ├── hive_settings_datasource.dart (NEW)
│   │       └── platform_sound_datasource.dart (NEW - platform channels)
│   ├── logic/
│   │   ├── blocs/
│   │   │   ├── settings_bloc/ (NEW - global settings state management)
│   │   │   ├── event_bloc/ (existing - extend for notification settings)
│   │   │   └── sound_picker_bloc/ (NEW - sound selection state)
│   │   └── services/
│   │       ├── notification_service.dart (NEW - audio + haptic orchestration)
│   │       ├── audio_service.dart (NEW - just_audio wrapper)
│   │       └── haptic_service.dart (NEW - vibration wrapper)
│   └── presentation/
│       ├── screens/
│       │   ├── settings_screen.dart (existing - extend with notification section)
│       │   ├── event_form_screen.dart (existing - extend with chime toggle)
│       │   └── sound_picker_screen.dart (NEW)
│       └── widgets/
│           ├── haptic_intensity_selector.dart (NEW)
│           ├── sound_preview_button.dart (NEW)
│           └── chime_toggle.dart (NEW)
├── test/
│   ├── data/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── datasources/
│   ├── logic/
│   │   ├── blocs/
│   │   └── services/
│   └── presentation/
│       ├── screens/
│       └── widgets/
├── ios/ (platform-specific configuration)
│   ├── Podfile (updated with iOS 13.0+ platform)
│   └── Runner/
│       └── Info.plist (updated with audio background mode + permissions)
├── macos/ (platform-specific configuration)
│   └── Podfile (existing - macOS 10.15+)
└── assets/
    └── audio/
        ├── auto_progress_beep.mp3 (existing fallback sound)
        └── preview_beep.mp3 (NEW - sound preview fallback)
```

**Structure Decision**: Mobile + Desktop Flutter application structure selected. The project follows Flutter's standard architecture with separation of concerns: `data/` for models and persistence (Hive), `logic/` for business logic (BLoC pattern), and `presentation/` for UI. Platform-specific implementations use platform channels for iOS/macOS audio and haptic APIs. This structure supports the multi-platform nature of the application while maintaining code reusability through shared Dart logic.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No constitutional violations identified. All gates passed.*

````
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
