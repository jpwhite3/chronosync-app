# Feature Specification: Haptics and Audio Settings

**Feature Branch**: `005-haptics-audio-settings`  
**Created**: October 24, 2025  
**Status**: Draft  
**Input**: User description: "I want to add haptics and audio settings into the app; allowing users to choose from the built-in sounds on their device and the audio cue when a timer ends. I would also like them to be able to choose haptic cues (vibrate) as well. A user can choose audio, haptics, or both. In the main application settings, a user can pick a defualt sound (from the ones already on device), and at the event level choose a different sound. When create an event, an option to toggle a \"chime\" setting (play a sound at the end). If toggle ON, the user can choose what sounds will be played, but the default selected in the main settings will be the default sounds played if the user does not choose something else. Haptics would work the same way; a default setting and an event level setting."

## Clarifications

### Session 2025-10-24

- Q: What haptic pattern options should users be able to select at both global and event levels? → A: Multiple intensity levels (light, medium, strong) - allows users to differentiate events by vibration strength
- Q: When the app fails to access device sounds due to OS permission restrictions, what should happen? → A: Retry 2-3 times then show user-friendly error message - attempts to recover, informs user if it fails
- Q: How should the system handle haptic feedback on devices that don't support vibration? → A: Disable haptic features gracefully with visual indicator - shows options grayed out with "Not supported on this device" message
- Q: What happens when the user is editing an event's audio/haptic settings while a timer for that event is actively running? → A: Changes take effect for next timer run, current timer uses original settings, and show warning "Timer is running, changes will apply next time"
- Q: How should the system behave if the app is backgrounded or device is locked when the timer ends? → A: Use OS notification system with sound/haptic - most reliable, works in all states, standard pattern for timer apps

### Specification Enhancements (Post-Checklist Review)

Following comprehensive requirements quality review (see `checklists/comprehensive.md`), the following clarifications and enhancements were added:

- **First-run initialization**: Explicitly defined default values on first launch (FR-001a)
- **Built-in sounds scope**: Clarified to include all platform-accessible sounds including custom ringtones (FR-002)
- **Haptic preview**: Added tap-to-preview functionality for intensity selection (FR-003b)
- **Empty sound list handling**: Defined graceful degradation with retry mechanism (FR-023a, FR-023b)
- **Sound preview controls**: Specified stop/cancel functionality and visual feedback (FR-024a, FR-024b, FR-024c)
- **Retry mechanism**: Specified exact retry count (3), intervals (exponential backoff), and UX feedback (FR-026, FR-026a)
- **Error message content**: Defined 4 required components for user-friendly error messages (FR-026)
- **Data validation**: Added requirement for validation according to data model constraints (FR-028)
- **Configuration conflict warning**: Added warning when chime ON but both notification types disabled (FR-029)
- **Accessibility**: Added comprehensive accessibility requirements for screen readers, keyboard navigation, contrast, and assistive technology announcements (FR-030 through FR-033)
- **Measurable outcomes**: Enhanced success criteria with specific test methodologies, sample sizes, and pass/fail criteria (SC-001, SC-004, SC-005, SC-006, SC-007, SC-008)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure Global Audio and Haptic Defaults (Priority: P1)

A user opens the main application settings to configure their preferred notification style. They want to set default audio and haptic feedback that will apply to all timer completions unless overridden at the event level.

**Why this priority**: This establishes the foundation for all notification behavior. Without global defaults, users would need to configure every single event individually, creating friction and poor user experience.

**Independent Test**: Can be fully tested by navigating to settings, selecting audio/haptic preferences, and verifying that newly created events inherit these defaults. Delivers immediate value by providing consistent notification behavior across the app.

**Acceptance Scenarios**:

1. **Given** the user is in the main application settings, **When** they select an audio sound from the device's built-in sounds, **Then** the selected sound is saved as the default audio cue for timer completions
2. **Given** the user is in the main application settings, **When** they enable haptic feedback, **Then** haptic feedback is enabled by default for all timer completions
3. **Given** the user is in the main application settings, **When** they enable both audio and haptic feedback, **Then** both notification types are saved as defaults
4. **Given** the user has set global defaults, **When** they create a new event without specifying custom settings, **Then** the event inherits the global audio and haptic settings

---

### User Story 2 - Enable/Disable Timer End Notifications at Event Level (Priority: P2)

When creating or editing an event, a user wants to control whether any notification (audio or haptic) plays when the timer completes. They toggle a "chime" setting to enable or disable end-of-timer notifications for that specific event.

**Why this priority**: This provides essential control over individual event behavior. Some timers need silent operation (meetings, meditation) while others benefit from alerts. This is the second most critical feature as it enables per-event customization.

**Independent Test**: Can be tested by creating an event, toggling the chime setting on/off, running the timer to completion, and verifying notification behavior matches the toggle state. Works independently of custom sound selection.

**Acceptance Scenarios**:

1. **Given** the user is creating a new event, **When** they toggle the chime setting ON, **Then** the event is configured to play notifications when the timer ends
2. **Given** the user is creating a new event, **When** they toggle the chime setting OFF, **Then** the event is configured to remain silent when the timer ends (no audio or haptic feedback)
3. **Given** the user is editing an existing event, **When** they toggle the chime setting, **Then** the notification behavior for that event is updated accordingly
4. **Given** the chime setting is ON and no custom sound is selected, **When** the timer ends, **Then** the global default audio and haptic settings are applied

---

### User Story 3 - Customize Audio Sound at Event Level (Priority: P3)

For a specific event with the chime setting enabled, a user wants to select a different audio sound from the device's built-in sounds instead of using the global default. This allows them to differentiate between different types of events (work timer vs. break timer).

**Why this priority**: This enhances personalization but is not essential for core functionality. Users can still use the app effectively with only global defaults.

**Independent Test**: Can be tested by creating an event with chime enabled, selecting a custom sound different from the global default, running the timer to completion, and verifying the custom sound plays instead of the default.

**Acceptance Scenarios**:

1. **Given** the user is creating/editing an event with chime setting ON, **When** they select a custom audio sound from the device's built-in sounds, **Then** that sound is saved as the event-specific audio cue
2. **Given** an event has a custom audio sound configured, **When** the timer ends, **Then** the custom sound plays instead of the global default sound
3. **Given** an event has a custom audio sound, **When** the user removes the custom selection, **Then** the event reverts to using the global default sound

---

### User Story 4 - Customize Haptic Feedback at Event Level (Priority: P3)

For a specific event with the chime setting enabled, a user wants to customize the haptic feedback separately from the audio setting. They can enable haptics even if audio is disabled, or vice versa, providing flexible notification combinations for different event types.

**Why this priority**: This provides advanced customization for power users but is not essential for basic functionality. Most users will be satisfied with consistent audio/haptic behavior from global defaults.

**Independent Test**: Can be tested by creating an event with chime enabled, customizing haptic settings independent of audio settings, running the timer to completion, and verifying the haptic behavior matches the custom configuration.

**Acceptance Scenarios**:

1. **Given** the user is creating/editing an event with chime setting ON, **When** they enable custom haptic feedback, **Then** that setting is saved as the event-specific haptic preference
2. **Given** an event has custom haptic settings, **When** the timer ends, **Then** the custom haptic feedback is applied instead of the global default
3. **Given** an event with chime ON, **When** the user enables audio but disables haptics, **Then** only audio plays when the timer ends
4. **Given** an event with chime ON, **When** the user enables haptics but disables audio, **Then** only haptic feedback occurs when the timer ends
5. **Given** an event has custom haptic settings, **When** the user removes the custom configuration, **Then** the event reverts to using the global default haptic setting

---

### Edge Cases

- What happens when the device has no built-in sounds available or sound access is restricted by OS permissions? System will retry access 3 times with exponential backoff (FR-026, FR-026a), then display an error message with steps to grant permissions and action button to open system settings. If sounds remain unavailable, haptic-only mode is enabled (FR-023a, FR-023b).
- What happens when a user selects a sound that becomes unavailable (deleted or moved) before the timer ends? System falls back to the global default sound to ensure notification delivery (FR-025).
- How does the system handle haptic feedback on devices that don't support vibration? Haptic settings are disabled with a visual indicator ("Not supported on this device") to inform users.
- What happens when the device is in silent/do-not-disturb mode - should audio still play or respect system settings? Audio respects silent/DND mode (no audio plays), but haptics still function if enabled.
- What happens when the user is editing an event's audio/haptic settings while a timer for that event is actively running? Changes apply to the next timer run only (not current), and a warning message appears: "Timer is running, changes will apply next time" (FR-016).
- How does the system behave if the app is backgrounded or device is locked when the timer ends? System uses the OS notification system to deliver audio and haptic feedback reliably regardless of app state (FR-022a).
- What happens when chime setting is ON but both audio and haptic notifications are explicitly disabled or unavailable? System displays a warning message explaining that no notifications will occur and suggests enabling at least one notification type (FR-029).

## Requirements *(mandatory)*

### Functional Requirements

**Global Settings**

- **FR-001**: System MUST provide a settings section where users can configure global default audio and haptic preferences
- **FR-001a**: On first app launch, System MUST initialize global notification settings using default values (haptic enabled, medium intensity, no sound selected) without requiring user input
- **FR-002**: System MUST allow users to select an audio sound from the device's built-in/system sounds as the global default, where "built-in/system sounds" includes all sounds accessible via the platform's notification sound APIs (RingtoneManager on Android, system sound IDs on iOS), including both pre-installed OS sounds and user-added custom ringtones
- **FR-003**: System MUST allow users to enable or disable haptic feedback as the global default
- **FR-003a**: System MUST allow users to select a haptic intensity level (light, medium, or strong) as the global default when haptic feedback is enabled
- **FR-003b**: System MUST trigger haptic feedback at the selected intensity level when user taps a haptic intensity option, providing immediate preview feedback
- **FR-004**: System MUST allow users to enable audio only, haptics only, or both as global defaults
- **FR-005**: System MUST persist global audio and haptic settings across app sessions
- **FR-006**: System MUST display the currently selected global default sound and haptic setting in the settings interface

**Event-Level Settings**

- **FR-007**: System MUST provide a "chime" toggle when creating or editing an event to enable/disable timer end notifications
- **FR-008**: System MUST default the chime setting to ON when creating new events (to use global defaults)
- **FR-009**: When chime setting is OFF, System MUST not play any audio or haptic feedback when the timer ends, regardless of other settings
- **FR-010**: When chime setting is ON, System MUST allow users to optionally select a custom audio sound from device's built-in sounds
- **FR-011**: When chime setting is ON with no custom sound selected, System MUST use the global default audio setting
- **FR-012**: When chime setting is ON, System MUST allow users to optionally customize haptic feedback (enable/disable independently from audio)
- **FR-012a**: When chime setting is ON and custom haptic feedback is enabled, System MUST allow users to select a haptic intensity level (light, medium, or strong) for that event
- **FR-013**: When chime setting is ON with no custom haptic setting, System MUST use the global default haptic setting
- **FR-014**: System MUST persist event-level audio and haptic settings with the event data
- **FR-015**: System MUST allow users to remove custom event-level settings and revert to global defaults
- **FR-016**: When a user edits an event's audio/haptic settings while a timer for that event is actively running, System MUST apply the changes only to the next timer run (not the current running timer) and MUST display a warning message informing the user that "Timer is running, changes will apply next time"

**Timer Completion Behavior**

- **FR-017**: When a timer ends with chime ON, System MUST play the appropriate audio sound based on event-specific or global default settings
- **FR-018**: When a timer ends with chime ON, System MUST trigger the appropriate haptic feedback based on event-specific or global default settings
- **FR-019**: System MUST support playing audio and haptic feedback simultaneously if both are enabled
- **FR-020**: System MUST support playing only audio if audio is enabled and haptics are disabled
- **FR-021**: System MUST support playing only haptics if haptics are enabled and audio is disabled
- **FR-022**: System MUST honor device silent/do-not-disturb mode for audio notifications (no audio plays when device is silenced), but MUST still provide haptic feedback if haptics are enabled
- **FR-022a**: When the app is backgrounded or the device is locked and a timer ends, System MUST use the operating system's notification system to deliver audio and haptic feedback according to the configured settings, ensuring notifications work reliably regardless of app state

**Sound Selection**

- **FR-023**: System MUST present a browsable list of device's built-in sounds when user selects audio settings
- **FR-023a**: When device sound list is empty or returns no results, System MUST display an empty state message ("No sounds available") with a "Retry" button to attempt fetching sounds again
- **FR-023b**: When device sound list remains empty after retry attempts, System MUST inform user that haptic-only notifications will be used and disable audio selection controls
- **FR-024**: System MUST allow users to preview/test sounds before selecting them in global settings
- **FR-024a**: System MUST provide a mechanism to stop sound preview playback before completion (e.g., stop button or tap-to-stop)
- **FR-024b**: System MUST automatically stop any playing sound preview when a different sound is selected for preview
- **FR-024c**: System MUST display visual feedback during sound preview (e.g., playing indicator, stop button visible)
- **FR-025**: System MUST fall back to the global default sound when a selected custom sound becomes unavailable (deleted/moved)
- **FR-026**: When unable to access device sounds due to OS permission restrictions, System MUST retry access exactly 3 times with exponential backoff intervals (100ms, 200ms, 400ms), and if unsuccessful, display a user-friendly error message that includes: 1) what failed ("Cannot access device sounds"), 2) why it matters (context), 3) how to fix it (platform-specific permission path), and 4) an action button to open system settings
- **FR-026a**: During retry attempts to access device sounds, System MUST display loading feedback (e.g., spinner with "Accessing device sounds..." message) to inform user that the operation is in progress
- **FR-027**: On devices that do not support vibration/haptic feedback, System MUST disable haptic settings controls and display a visual indicator (e.g., grayed out with "Not supported on this device" message) to inform users of the limitation
- **FR-028**: System MUST validate all notification settings according to data model constraints (as defined in data-model.md §Validation Rules) before persisting to storage, and MUST display appropriate validation error messages for invalid inputs
- **FR-029**: When chime setting is ON but both audio and haptic are explicitly disabled (or unavailable), System MUST display a warning message to the user explaining that no notifications will occur and suggest enabling at least one notification type

### Accessibility Requirements

- **FR-030**: All interactive elements in notification settings UI (toggles, buttons, pickers) MUST have semantic labels for screen readers that clearly describe their purpose and current state
- **FR-031**: Settings UI MUST be fully navigable via keyboard and switch control, with logical tab order and focus indicators meeting WCAG 2.1 AA standards
- **FR-032**: All visual indicators and text in notification settings MUST meet WCAG 2.1 AA contrast ratio requirements (minimum 4.5:1 for normal text, 3:1 for large text and UI components)
- **FR-033**: When haptic intensity level changes or settings are saved, System MUST announce the change to assistive technologies (e.g., "Haptic intensity set to strong", "Settings saved successfully")

### Key Entities

## Requirements *(mandatory)*

### Key Entities

- **Global Settings**: Represents user's default preferences for audio and haptic notifications across the application
  - Default audio sound selection (reference to device's built-in sound)
  - Default haptic enabled/disabled state
  - Default haptic intensity level (light, medium, strong) when haptic feedback is enabled
  
- **Event Notification Settings**: Represents notification configuration specific to an individual event
  - Chime enabled/disabled toggle
  - Custom audio sound selection (optional override of global default)
  - Custom haptic enabled/disabled state (optional override of global default)
  - Custom haptic intensity level (light, medium, strong) when custom haptic feedback is enabled
  - Relationship to parent Event entity

- **Device Sound Reference**: Represents a built-in sound available on the user's device
  - Sound identifier/name
  - Sound availability status

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can configure global audio and haptic defaults in ≤5 taps/interactions with ≤30 seconds elapsed time from opening the settings screen
- **SC-002**: Users can enable/disable chime setting for an event in under 10 seconds during event creation
- **SC-003**: Users can select a custom sound for an event in under 20 seconds
- **SC-004**: 90% of users (minimum sample size: 20 test users across iOS and Android) successfully hear/feel their configured notification when a timer ends on first attempt
- **SC-005**: System plays timer completion notifications within 1 second of timer reaching zero (measured from timer expiration to notification delivery attempt)
- **SC-006**: Users can differentiate between at least 3 different event types using custom audio sounds, verified through user testing where participants correctly identify event type by sound alone with ≥80% accuracy
- **SC-007**: Event-level custom settings correctly override global defaults in 100% of test cases (enumerated test scenarios include: custom sound overrides default, custom haptic overrides default, chime OFF overrides all defaults, all combinations of audio/haptic enabled states)
- **SC-008**: System gracefully handles unavailable sounds without crashing or freezing the app, verified by: 1) app continues running, 2) fallback sound plays or haptic-only mode activates, 3) user receives notification of the issue
- **SC-009**: Settings persist correctly across app restarts in 100% of cases

## Assumptions

- The device operating system provides access to a collection of built-in/system sounds that the application can enumerate and play
- The device supports standard haptic feedback APIs (vibration)
- Users are familiar with the concept of global defaults vs. per-item settings from other applications
- The existing event creation/editing interface can accommodate additional toggle and selection controls
- Sound preview functionality is provided in global settings to allow users to make informed sound selections
- The app honors device silent/do-not-disturb mode for audio notifications but continues to provide haptic feedback when haptics are enabled, as haptics are often expected even when audio is silenced
- When a selected sound becomes unavailable, the system falls back to the global default sound to ensure users still receive notifications rather than silently failing
- If both custom and global default sounds are unavailable, the system uses a device fallback beep to ensure notification delivery
