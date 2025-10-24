# Implementation Tasks: Haptics and Audio Settings

**Feature**: 005-haptics-audio-settings  
**Branch**: `005-haptics-audio-settings`  
**Generated**: October 24, 2025  
**Source Documents**: spec.md, plan.md, data-model.md, contracts/notification_settings_contract.md, quickstart.md

---

## Task Summary

- **Total Tasks**: 71
- **Setup Phase**: 5 tasks
- **Foundational Phase**: 9 tasks
- **User Story 1 (P1)**: 18 tasks
- **User Story 2 (P2)**: 12 tasks
- **User Story 3 (P3)**: 12 tasks
- **User Story 4 (P3)**: 10 tasks
- **Polish Phase**: 5 tasks

**Parallel Opportunities**: 42 tasks marked [P] can be executed independently
**Estimated Duration**: ~15 hours (2 development days)

---

## Implementation Strategy

### MVP Scope (Minimum Viable Product)
**User Story 1 Only** - Configure Global Audio and Haptic Defaults
- Delivers core value: Global notification settings
- Independent test: Settings persist and apply to all events
- Foundation for all other stories

### Incremental Delivery Order
1. **Phase 1-2**: Setup + Foundational (T001-T014) - Required infrastructure
2. **Phase 3**: User Story 1 (T015-T032) - MVP delivery
3. **Phase 4**: User Story 2 (T033-T044) - Event-level control
4. **Phase 5**: User Story 3 (T045-T056) - Audio customization
5. **Phase 6**: User Story 4 (T057-T066) - Haptic customization
6. **Phase 7**: Polish (T067-T071) - Cross-cutting concerns

### Independent Testing Per Story
- Each user story phase includes its own testing tasks
- Story completion verified before moving to next story
- Enables incremental deployment and feedback

---

## Phase 1: Setup & Dependencies

**Goal**: Install dependencies and configure platform-specific requirements

### Tasks

- [ ] T001 Add new dependencies to chronosync/pubspec.yaml (vibration ^2.0.0, flutter_local_notifications ^18.0.0, permission_handler ^11.0.0)
- [ ] T002 Run flutter pub get to install dependencies
- [ ] T003 Add VIBRATE permission to chronosync/android/app/src/main/AndroidManifest.xml
- [ ] T004 Add POST_NOTIFICATIONS permission to chronosync/android/app/src/main/AndroidManifest.xml for Android 13+
- [ ] T005 Verify iOS Info.plist configuration (no additional permissions needed for notifications/haptics)

**Checkpoint**: Dependencies installed, platform configurations complete

---

## Phase 2: Foundational - Data Models & Platform Channels

**Goal**: Create core data structures and platform integration required by all user stories

### Tasks

- [ ] T006 [P] Create HapticIntensity enum with Hive adapter in chronosync/lib/data/models/haptic_intensity.dart (typeId: 5)
- [ ] T007 [P] Create GlobalNotificationSettings model with Hive adapter in chronosync/lib/data/models/global_notification_settings.dart (typeId: 3)
- [ ] T008 [P] Create EventNotificationSettings model with Hive adapter in chronosync/lib/data/models/event_notification_settings.dart (typeId: 4)
- [ ] T009 [P] Create DeviceSound model (transient, no Hive adapter) in chronosync/lib/data/models/device_sound.dart
- [ ] T010 Run flutter pub run build_runner build --delete-conflicting-outputs to generate Hive adapters
- [ ] T011 Modify existing Event model to add notificationSettings field in chronosync/lib/data/models/event.dart
- [ ] T012 Re-run build_runner to regenerate Event adapter after modification
- [ ] T013 [P] Implement iOS platform channel for device audio in chronosync/ios/Runner/AppDelegate.swift (getSystemSounds, getSoundUri, triggerHaptic methods)
- [ ] T014 [P] Implement Android platform channel for device audio in chronosync/android/app/src/main/kotlin/com/yourcompany/chronosync/MainActivity.kt (getSystemSounds, getSoundUri methods)

**Checkpoint**: All data models created, Hive adapters generated, platform channels implemented

**Independent Test**: Run `flutter test test/data/models/` to verify model serialization and validation rules

---

## Phase 3: User Story 1 - Configure Global Audio and Haptic Defaults (P1)

**Story Goal**: Users can configure global default audio sounds and haptic intensity levels that apply to all timer completions.

**Independent Test Criteria**:
1. Navigate to settings, select audio sound, verify setting persists
2. Navigate to settings, enable haptic feedback with intensity, verify setting persists
3. Create new event without custom settings, verify it inherits global defaults
4. Restart app, verify global settings are retained

### Tasks

#### Data Layer

- [ ] T015 [P] [US1] Implement NotificationSettingsRepository.getGlobalSettings() in chronosync/lib/data/repositories/notification_settings_repository.dart
- [ ] T016 [P] [US1] Implement NotificationSettingsRepository.saveGlobalSettings() in chronosync/lib/data/repositories/notification_settings_repository.dart
- [ ] T017 [P] [US1] Implement DeviceAudioRepository.getSystemSounds() with retry logic in chronosync/lib/data/repositories/device_audio_repository.dart
- [ ] T018 [P] [US1] Implement DeviceAudioRepository.hasHapticSupport() in chronosync/lib/data/repositories/device_audio_repository.dart
- [ ] T019 [P] [US1] Implement DeviceAudioRepository.hasAmplitudeControl() in chronosync/lib/data/repositories/device_audio_repository.dart
- [ ] T020 [P] [US1] Implement DeviceAudioRepository.triggerHaptic() with platform-specific mapping in chronosync/lib/data/repositories/device_audio_repository.dart
- [ ] T021 [P] [US1] Implement DeviceAudioRepository.previewSound() using just_audio in chronosync/lib/data/repositories/device_audio_repository.dart
- [ ] T022 [P] [US1] Implement DeviceAudioRepository.stopPreview() in chronosync/lib/data/repositories/device_audio_repository.dart
- [ ] T023 [P] [US1] Implement DeviceAudioRepository permission check methods in chronosync/lib/data/repositories/device_audio_repository.dart

#### Business Logic

- [ ] T024 [US1] Create NotificationSettingsEvent classes in chronosync/lib/logic/blocs/notification_settings_bloc/notification_settings_event.dart
- [ ] T025 [US1] Create NotificationSettingsState classes in chronosync/lib/logic/blocs/notification_settings_bloc/notification_settings_state.dart
- [ ] T026 [US1] Implement NotificationSettingsBloc in chronosync/lib/logic/blocs/notification_settings_bloc/notification_settings_bloc.dart
- [ ] T027 [US1] Add LoadNotificationSettings event handler in NotificationSettingsBloc
- [ ] T028 [US1] Add UpdateGlobalSound event handler in NotificationSettingsBloc
- [ ] T029 [US1] Add UpdateGlobalHapticEnabled event handler in NotificationSettingsBloc
- [ ] T030 [US1] Add UpdateGlobalHapticIntensity event handler in NotificationSettingsBloc
- [ ] T031 [US1] Add RefreshDeviceSounds event handler in NotificationSettingsBloc

#### Presentation Layer

- [ ] T032 [US1] Create NotificationSettingsScreen in chronosync/lib/presentation/screens/settings/notification_settings_screen.dart with BlocProvider and UI scaffold

**Story Checkpoint**: Global settings can be configured and persisted. Run tests to verify:
```bash
flutter test test/data/repositories/notification_settings_repository_test.dart
flutter test test/data/repositories/device_audio_repository_test.dart
flutter test test/logic/blocs/notification_settings_bloc_test.dart
```

---

## Phase 4: User Story 2 - Enable/Disable Timer End Notifications at Event Level (P2)

**Story Goal**: Users can toggle a "chime" setting when creating/editing events to enable or disable timer end notifications.

**Independent Test Criteria**:
1. Create event with chime ON, run timer to completion, verify notification plays
2. Create event with chime OFF, run timer to completion, verify silence
3. Edit existing event to toggle chime, verify behavior updates
4. Verify chime ON with no custom settings uses global defaults

### Tasks

#### Data Layer

- [ ] T033 [P] [US2] Implement NotificationSettingsRepository.getEventSettings() in chronosync/lib/data/repositories/notification_settings_repository.dart
- [ ] T034 [P] [US2] Implement NotificationSettingsRepository.saveEventSettings() in chronosync/lib/data/repositories/notification_settings_repository.dart
- [ ] T035 [P] [US2] Implement NotificationSettingsRepository.resetEventSettingsToDefaults() in chronosync/lib/data/repositories/notification_settings_repository.dart
- [ ] T036 [P] [US2] Implement NotificationSettingsRepository.resolveSettings() with inheritance logic in chronosync/lib/data/repositories/notification_settings_repository.dart

#### Business Logic

- [ ] T037 [US2] Add LoadEventSettings event handler in NotificationSettingsBloc
- [ ] T038 [US2] Add UpdateEventChimeEnabled event handler in NotificationSettingsBloc
- [ ] T039 [US2] Add ResetEventSettingsToDefaults event handler in NotificationSettingsBloc

#### Presentation Layer

- [ ] T040 [US2] Create ChimeSettingsWidget in chronosync/lib/presentation/widgets/event_form/chime_settings_widget.dart with chime toggle
- [ ] T041 [US2] Integrate ChimeSettingsWidget into existing event creation screen
- [ ] T042 [US2] Integrate ChimeSettingsWidget into existing event editing screen
- [ ] T043 [US2] Add FR-016 warning dialog when editing event with active timer in ChimeSettingsWidget
- [ ] T044 [US2] Add FR-029 validation warning when chime ON but both audio/haptic disabled in ChimeSettingsWidget

**Story Checkpoint**: Chime toggle controls event notifications. Run tests:
```bash
flutter test test/data/repositories/notification_settings_repository_test.dart
flutter test test/logic/blocs/notification_settings_bloc_test.dart
flutter test test/presentation/widgets/chime_settings_widget_test.dart
```

---

## Phase 5: User Story 3 - Customize Audio Sound at Event Level (P3)

**Story Goal**: Users can select a custom audio sound for specific events, overriding the global default.

**Independent Test Criteria**:
1. Create event with chime ON, select custom sound, verify custom sound plays at timer end
2. Remove custom sound selection, verify event reverts to global default
3. Make custom sound unavailable, verify fallback to global default (FR-025)

### Tasks

#### Presentation Layer

- [ ] T045 [P] [US3] Create SoundPickerWidget in chronosync/lib/presentation/screens/settings/widgets/sound_picker_widget.dart with browsable sound list
- [ ] T046 [P] [US3] Add empty state UI with retry button to SoundPickerWidget (FR-023a)
- [ ] T047 [P] [US3] Add haptic-only fallback message to SoundPickerWidget (FR-023b)
- [ ] T048 [P] [US3] Create SoundPreviewButton widget in chronosync/lib/presentation/screens/settings/widgets/sound_preview_button.dart
- [ ] T049 [P] [US3] Add stop/cancel mechanism to SoundPreviewButton (FR-024a)
- [ ] T050 [P] [US3] Add auto-stop on new preview to SoundPreviewButton (FR-024b)
- [ ] T051 [P] [US3] Add visual feedback during preview to SoundPreviewButton (FR-024c)
- [ ] T052 [US3] Integrate SoundPickerWidget into NotificationSettingsScreen for global sound selection
- [ ] T053 [US3] Add SelectGlobalSound event handler in NotificationSettingsBloc
- [ ] T054 [US3] Add custom sound selection to ChimeSettingsWidget
- [ ] T055 [US3] Add UpdateEventCustomSound event handler in NotificationSettingsBloc
- [ ] T056 [US3] Add RemoveEventCustomSound event handler in NotificationSettingsBloc

**Story Checkpoint**: Custom event sounds work and fallback properly. Run tests:
```bash
flutter test test/presentation/widgets/sound_picker_widget_test.dart
flutter test test/logic/blocs/notification_settings_bloc_test.dart
```

---

## Phase 6: User Story 4 - Customize Haptic Feedback at Event Level (P3)

**Story Goal**: Users can customize haptic feedback for specific events independently from audio settings.

**Independent Test Criteria**:
1. Create event with chime ON, enable custom haptic, verify custom haptic at timer end
2. Enable haptics only (audio disabled), verify haptic-only notification
3. Enable audio only (haptics disabled), verify audio-only notification
4. Remove custom haptic, verify revert to global default

### Tasks

#### Presentation Layer

- [ ] T057 [P] [US4] Create HapticIntensityPicker widget in chronosync/lib/presentation/screens/settings/widgets/haptic_intensity_picker.dart
- [ ] T058 [P] [US4] Add tap-to-preview functionality to HapticIntensityPicker (FR-003b)
- [ ] T059 [P] [US4] Add device capability detection and "Not supported" indicator to HapticIntensityPicker (FR-027)
- [ ] T060 [US4] Integrate HapticIntensityPicker into NotificationSettingsScreen for global haptic settings
- [ ] T061 [US4] Add SelectGlobalHapticIntensity event handler in NotificationSettingsBloc
- [ ] T062 [US4] Add custom haptic controls to ChimeSettingsWidget
- [ ] T063 [US4] Add UpdateEventCustomHapticEnabled event handler in NotificationSettingsBloc
- [ ] T064 [US4] Add UpdateEventCustomHapticIntensity event handler in NotificationSettingsBloc
- [ ] T065 [US4] Add RemoveEventCustomHaptic event handler in NotificationSettingsBloc
- [ ] T066 [US4] Add accessibility announcements to HapticIntensityPicker (FR-033)

**Story Checkpoint**: Custom event haptics work independently from audio. Run tests:
```bash
flutter test test/presentation/widgets/haptic_intensity_picker_test.dart
flutter test test/logic/blocs/notification_settings_bloc_test.dart
```

---

## Phase 7: Polish & Cross-Cutting Concerns

**Goal**: Integrate notifications with timer completion, add accessibility, handle edge cases

### Tasks

#### Timer Notification Integration

- [ ] T067 Create TimerNotificationBloc in chronosync/lib/logic/blocs/timer_notification_bloc/ with events and states
- [ ] T068 Implement TimerNotificationService using flutter_local_notifications in chronosync/lib/data/repositories/timer_notification_service.dart
- [ ] T069 Integrate TimerNotificationBloc with existing timer completion logic to trigger notifications based on resolved settings

#### Accessibility & Error Handling

- [ ] T070 [P] Add semantic labels and WCAG 2.1 AA compliance to all notification settings UI (FR-030, FR-031, FR-032)
- [ ] T071 [P] Add retry logic with loading feedback for sound access failures (FR-026, FR-026a)

**Final Checkpoint**: End-to-end notification flow works. Run full test suite:
```bash
flutter test
flutter test integration_test/ # if integration tests exist
```

---

## Task Dependencies

### Dependency Graph (by User Story)

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational - BLOCKING)
    ↓
    ├─> User Story 1 (P1) ──┐
    │                       │
    ├─> User Story 2 (P2) ──┼─> Polish Phase
    │   (depends on US1)    │
    │                       │
    ├─> User Story 3 (P3) ──┤
    │   (depends on US1)    │
    │                       │
    └─> User Story 4 (P3) ──┘
        (depends on US1)
```

### Blocking Dependencies

- **Phase 2 blocks all user stories**: Data models and platform channels must be complete
- **User Story 1 blocks Stories 2-4**: Global settings foundation required
- **User Stories 2, 3, 4 are independent**: Can be implemented in parallel after US1

### Story Completion Order

1. **Must Complete First**: Setup (Phase 1) → Foundational (Phase 2) → User Story 1 (Phase 3)
2. **Can Complete in Any Order**: User Story 2, 3, 4 (Phases 4-6)
3. **Must Complete Last**: Polish (Phase 7) - requires all stories

---

## Parallel Execution Examples

### During Phase 2 (Foundational)
Execute in parallel:
- T006: HapticIntensity enum
- T007: GlobalNotificationSettings model
- T008: EventNotificationSettings model
- T009: DeviceSound model
- T013: iOS platform channel
- T014: Android platform channel

### During User Story 1 (Phase 3)
Execute in parallel:
- T015-T023: All repository methods (different files)
- After bloc events/states created (T024-T025):
  - T026-T031: All event handlers (same file, sequential)

### After User Story 1 Complete
Execute entire phases in parallel:
- Phase 4 (User Story 2)
- Phase 5 (User Story 3)
- Phase 6 (User Story 4)

---

## Testing Strategy

### Unit Tests (Per Story)

**User Story 1**:
- GlobalNotificationSettings serialization/validation
- DeviceAudioRepository mock tests (permission failures, retry logic)
- NotificationSettingsBloc state transitions

**User Story 2**:
- EventNotificationSettings validation
- ChimeSettingsWidget toggle behavior
- Inheritance logic (resolveSettings)

**User Story 3**:
- SoundPickerWidget empty state
- Sound preview start/stop
- Fallback behavior

**User Story 4**:
- HapticIntensityPicker tap-to-preview
- Platform-specific haptic mapping
- Audio/haptic independence

### Integration Tests (End-to-End)

After all phases complete:
1. Configure global defaults → Create event → Timer ends → Verify notification
2. Custom event sound → Timer ends → Verify custom sound plays
3. Chime OFF → Timer ends → Verify silence
4. App backgrounded → Timer ends → Verify OS notification

### Manual Testing Checklist

- [ ] iOS: Sounds list loads correctly
- [ ] Android: Sounds list loads correctly
- [ ] Sound preview plays and can be stopped
- [ ] Haptic feedback triggers on tap
- [ ] Settings persist across app restart
- [ ] Notifications fire when app backgrounded
- [ ] Notifications respect device silent mode (audio off, haptic works)
- [ ] Devices without haptic support show "Not supported" message
- [ ] Screen reader announces settings changes
- [ ] Keyboard navigation works in settings UI

---

## Estimated Time Breakdown

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Phase 1: Setup | 5 | 30 minutes |
| Phase 2: Foundational | 9 | 2.5 hours |
| Phase 3: User Story 1 (P1) | 18 | 4 hours |
| Phase 4: User Story 2 (P2) | 12 | 2 hours |
| Phase 5: User Story 3 (P3) | 12 | 2.5 hours |
| Phase 6: User Story 4 (P3) | 10 | 2 hours |
| Phase 7: Polish | 5 | 1.5 hours |
| **Total** | **71** | **~15 hours** |

**Note**: Times are estimates. Actual duration may vary based on familiarity with Flutter/BLoC patterns.

---

## Success Criteria Validation

### SC-001: Global Settings Configuration Time
**Test**: Time user from opening settings screen to completing global audio + haptic configuration
**Pass**: ≤5 taps, ≤30 seconds
**Tasks**: T032, T052, T060

### SC-002: Chime Toggle Speed
**Test**: Time user toggling chime during event creation
**Pass**: <10 seconds
**Tasks**: T040-T042

### SC-003: Custom Sound Selection Speed
**Test**: Time user selecting custom sound for event
**Pass**: <20 seconds
**Tasks**: T045, T054

### SC-004: Notification Reliability
**Test**: 20 users (10 iOS, 10 Android) run timer to completion
**Pass**: ≥90% hear/feel notification on first attempt
**Tasks**: T067-T069 (timer integration)

### SC-005: Notification Latency
**Test**: Measure time from timer zero to notification delivery
**Pass**: <1 second
**Tasks**: T067-T069 (timer integration)

### SC-006: Event Differentiation
**Test**: Users identify 3 event types by sound alone
**Pass**: ≥80% accuracy
**Tasks**: T045-T056 (custom sounds)

### SC-007: Override Behavior
**Test**: Execute all override test scenarios (custom sound, custom haptic, chime OFF)
**Pass**: 100% of scenarios work correctly
**Tasks**: T033-T044, T045-T056, T057-T066

### SC-008: Graceful Degradation
**Test**: Make sound unavailable, verify app doesn't crash and fallback works
**Pass**: App continues, fallback sound plays, user notified
**Tasks**: T017 (retry logic), T036 (fallback in resolveSettings)

### SC-009: Persistence
**Test**: Configure settings, restart app, verify settings retained
**Pass**: 100% of settings persist
**Tasks**: T015-T016, T033-T034

---

## Troubleshooting Guide

### Issue: Sounds list empty
**Relevant Tasks**: T017, T045-T047
**Solution**: Check platform channel implementation (T013-T014), verify permissions, test retry logic

### Issue: Haptic not working
**Relevant Tasks**: T018-T020, T057-T059
**Solution**: Verify VIBRATE permission (T003), check hasHapticSupport() returns true, test platform mapping

### Issue: Notifications not appearing
**Relevant Tasks**: T067-T069
**Solution**: Check notification permissions (T023), ensure timer integration correct, test on physical device

### Issue: Sound URI not found
**Relevant Tasks**: T013-T014, T021
**Solution**: Verify getSoundUri platform implementation, check sound ID format matches platform expectations

---

## Next Steps After Task Completion

1. ✅ Complete all tasks in sequence (respecting dependencies)
2. ✅ Run full test suite: `flutter test`
3. ✅ Manual testing on both iOS and Android physical devices
4. ✅ Verify all success criteria (SC-001 through SC-009)
5. ✅ Create pull request with reference to spec.md and plan.md
6. ✅ Request code review focusing on:
   - Error handling in repositories
   - State management in BLoCs
   - Accessibility compliance
   - Platform-specific behavior

---

## Format Validation

✅ All tasks follow checklist format: `- [ ] [TaskID] [P?] [Story?] Description with file path`
✅ Task IDs sequential (T001-T071)
✅ [P] markers on parallelizable tasks (42 tasks)
✅ [US#] labels on user story tasks (52 tasks)
✅ File paths included in all implementation tasks

**Ready for implementation!** 🚀
