# Feature Specification: Auto-Progress Events with Series Statistics

**Feature Branch**: `004-auto-progress-events`  
**Created**: October 23, 2025  
**Status**: Draft  
**Input**: User description: "When creating an event, add the option to auto progress once the countdown timer for that event reaches zero. Should all events in a series be set to auto progress, then starting a series would automatically progress through all the events in order without user intervention. At the end of a series, after the last event ends, show aggregate stats just above the button to go back to the series."

## Clarifications

### Session 2025-10-23

- Q: Should series statistics be persisted after completion or only displayed during the completion screen session? → A: Statistics are calculated at completion and displayed only during the completion screen session (not saved)
- Q: What visual/audio feedback should occur during auto-progression transitions? → A: Both visual indicator (toast/banner) and optional audio cue (toggleable in settings)
- Q: How should the system handle rapid auto-progression when events have very short durations? → A: System enforces minimum 1-second display time per event
- Q: What timer precision must be maintained during auto-progression? → A: Timer precision maintained within 1 second
- Q: What observability/logging is required for auto-progression events? → A: Log auto-progression events (start/complete) and any failures to app logs

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Auto-Progress on Individual Events (Priority: P1)

As an Event Coordinator setting up a series, I want to mark individual events with an auto-progress option when creating or editing them, so that those specific events will automatically advance to the next event when their time expires.

**Why this priority**: This is the foundational feature that enables automated event progression. Without the ability to configure auto-progress on events, none of the other features can function. This can be independently tested by creating/editing events and verifying the auto-progress setting is saved.

**Independent Test**: Can be fully tested by creating a new event or editing an existing event, toggling the auto-progress option, saving, and verifying the setting persists when viewing the event again. Delivers immediate value by establishing the configuration mechanism.

**Acceptance Scenarios**:

1. **Given** I am creating a new event, **When** I view the event creation form, **Then** I see an auto-progress toggle option clearly labeled (e.g., "Auto-progress when time expires")
2. **Given** the auto-progress toggle is visible, **When** I enable it and save the event, **Then** the event is saved with auto-progress enabled
3. **Given** an event has auto-progress enabled, **When** I edit that event, **Then** the auto-progress toggle reflects the enabled state
4. **Given** I am viewing the event list in a series, **When** I look at each event, **Then** I can visually identify which events have auto-progress enabled (e.g., via an icon, badge, or label)
5. **Given** an event has auto-progress disabled (default state), **When** I save the event, **Then** the event behaves as it did previously, requiring manual "NEXT" button press to advance

---

### User Story 2 - Auto-Progress Single Event During Live Timer (Priority: P1)

As an Event Coordinator running a live timer session, when an event with auto-progress enabled reaches zero on its countdown timer, I want it to automatically advance to the next event without requiring me to press "NEXT", so that the session flows continuously.

**Why this priority**: This is the core value proposition of the feature - automating the progression of individual events. It can be independently tested by creating a series with one auto-progress event followed by a manual event, and verifying automatic advancement occurs at the right moment.

**Independent Test**: Can be fully tested by creating a short-duration event (e.g., 30 seconds) with auto-progress enabled, starting the series, and observing that when the countdown reaches "00:00", the system automatically advances to the next event without user interaction.

**Acceptance Scenarios**:

1. **Given** an event with auto-progress enabled is running, **When** the countdown timer reaches "00:00", **Then** the system automatically advances to the next event within 1 second
2. **Given** an auto-progress event automatically advances, **When** the transition occurs, **Then** a brief visual indicator (e.g., "Auto-advancing...") is displayed
3. **Given** the audio cue setting is enabled and an auto-progress event advances, **When** the transition occurs, **Then** an audio cue plays
4. **Given** the audio cue setting is disabled and an auto-progress event advances, **When** the transition occurs, **Then** no audio cue plays
5. **Given** an auto-progress event automatically advances, **When** the transition occurs, **Then** both timers reset appropriately for the new event (countdown to new duration, elapsed to zero)
6. **Given** an event with auto-progress disabled is running, **When** the countdown timer reaches "00:00", **Then** the system does NOT automatically advance and the countdown continues into negative/overtime
7. **Given** an auto-progress event is running but has not yet reached "00:00", **When** I press the "NEXT" button manually, **Then** the system advances immediately without waiting for the timer to reach zero
8. **Given** an auto-progress event is the last event in a series, **When** the countdown timer reaches "00:00", **Then** the system automatically displays the series completion screen with statistics

---

### User Story 3 - Fully Automated Series Execution (Priority: P2)

As an Event Coordinator running a live timer session where all events have auto-progress enabled, I want the entire series to run from start to finish without any manual intervention, so that I can focus on facilitating the event rather than managing timers.

**Why this priority**: This enables the fully hands-free experience for coordinators. It depends on User Story 2 working correctly but adds the end-to-end automated flow. This can be independently tested by creating a multi-event series with all events set to auto-progress.

**Independent Test**: Can be fully tested by creating a series with 3-5 short events (e.g., 15-30 seconds each), enabling auto-progress on all events, starting the series, and observing that all events advance automatically without any button presses until the completion screen appears.

**Acceptance Scenarios**:

1. **Given** a series where all events have auto-progress enabled, **When** I start the live timer session, **Then** the first event begins normally
2. **Given** the first event in a fully automated series reaches "00:00", **When** auto-progression occurs, **Then** the second event starts automatically with fresh timers
3. **Given** a fully automated series is running, **When** each subsequent event reaches "00:00", **Then** the next event starts automatically until the final event is reached
4. **Given** the final event in a fully automated series reaches "00:00", **When** auto-progression occurs, **Then** the series completion screen is displayed automatically with aggregate statistics
5. **Given** a fully automated series is running, **When** I press the "NEXT" button manually at any point, **Then** the system advances to the next event immediately, overriding the auto-progress timing

---

### User Story 4 - Display Aggregate Series Statistics at Completion (Priority: P2)

As an Event Coordinator who has just completed a series, I want to see aggregate statistics about the entire session (number of events, expected vs. actual elapsed time, total over/under time) displayed prominently just above the button to return to the series list, so that I can evaluate how well the session adhered to the planned schedule.

**Why this priority**: Provides valuable post-session insights for coordinators to improve future planning. This can be independently tested by completing any series (manually or via auto-progress) and verifying the statistics are calculated and displayed correctly.

**Independent Test**: Can be fully tested by running a series to completion (with some events going overtime and some ending early via manual advancement), and verifying that the completion screen displays: (1) correct event count, (2) correct expected total time (sum of all durations), (3) correct actual elapsed time (including overtime), and (4) correct over/under time calculation.

**Acceptance Scenarios**:

1. **Given** I have completed a series, **When** the completion screen appears, **Then** I see a statistics panel displayed prominently above the "Back to Series" button
2. **Given** the statistics panel is displayed, **When** I view it, **Then** I see the total number of events in the series clearly labeled (e.g., "Events: 5")
3. **Given** the statistics panel is displayed, **When** I view it, **Then** I see the expected elapsed time (sum of all event durations) clearly labeled (e.g., "Expected Time: 15:00")
4. **Given** the statistics panel is displayed, **When** I view it, **Then** I see the actual elapsed time (total time including overtime/undertime) clearly labeled (e.g., "Actual Time: 16:45")
5. **Given** the statistics panel is displayed, **When** I view it, **Then** I see the total over/under time (difference between actual and expected) clearly labeled and color-coded (e.g., "+01:45" in red for over, "-02:30" in green for under)
6. **Given** a series ran exactly on schedule with no overtime or early finishes, **When** I view the statistics panel, **Then** the over/under time shows "00:00" in neutral color
7. **Given** some events ran overtime and others ended early, **When** I view the statistics panel, **Then** the actual elapsed time and over/under time reflect the cumulative net difference

---

### Edge Cases

- What happens if an event with auto-progress enabled is manually advanced before reaching "00:00"? The system should advance immediately and treat it as if the event ended early (contributing to under-time in statistics).
- What happens if the app is backgrounded during an auto-progress event? Upon foregrounding, the system should evaluate the timer state and trigger auto-progression if the event has passed "00:00" while backgrounded.
- What happens if a series has only one event with auto-progress enabled? It should auto-progress directly to the completion screen when the countdown reaches "00:00".
- What happens if a series is a mix of auto-progress and manual events? The auto-progress events advance automatically; manual events require the "NEXT" button press.
- What happens if an auto-progress event has a very short duration (e.g., 5 seconds or less)? The system enforces a minimum 1-second display time to ensure readable transitions and prevent UI flashing.
- What happens to statistics if I manually advance through all events before any timers reach zero? All events would contribute to under-time, resulting in negative over/under time value.
- What happens if the final event in a series does NOT have auto-progress enabled? The user must manually press "NEXT" to see the completion screen with statistics.

## Requirements *(mandatory)*

### Functional Requirements

#### Event Configuration

- **FR-001**: The event creation form MUST include an auto-progress toggle option that is OFF by default
- **FR-002**: The auto-progress toggle MUST be clearly labeled to indicate its purpose (e.g., "Auto-progress when time expires")
- **FR-003**: The event edit form MUST display the current auto-progress setting for the event being edited
- **FR-004**: The system MUST persist the auto-progress setting as part of the event's data
- **FR-005**: The event list view within a series MUST visually indicate which events have auto-progress enabled (e.g., icon, badge, or label)

#### Auto-Progression Behavior

- **FR-006**: When an event with auto-progress enabled reaches "00:00" on its countdown timer during a live session, the system MUST automatically advance to the next event within 1 second
- **FR-006a**: When auto-progression occurs, the system MUST display a brief visual indicator (e.g., toast or banner message such as "Auto-advancing...") during the transition
- **FR-006b**: When auto-progression occurs, the system MUST play an optional audio cue if enabled in application settings
- **FR-006c**: The application settings MUST include a toggle to enable or disable the auto-progression audio cue (default: enabled)
- **FR-006d**: The system MUST enforce a minimum 1-second display time for each event, even if the event duration is shorter, to ensure readable transitions and prevent UI flashing
- **FR-007**: When auto-progression occurs, both timers MUST reset appropriately (countdown to the new event's duration, elapsed to zero)
- **FR-008**: When an event with auto-progress disabled reaches "00:00", the system MUST NOT automatically advance and MUST continue displaying overtime as per existing behavior
- **FR-009**: The manual "NEXT" button MUST remain functional at all times, allowing users to manually advance even during auto-progress events
- **FR-010**: Manual advancement via "NEXT" MUST immediately override any pending auto-progression timing
- **FR-011**: When the final event in a series with auto-progress enabled reaches "00:00", the system MUST automatically display the series completion screen
- **FR-012**: If the app is backgrounded during an auto-progress event and the countdown reaches "00:00" while backgrounded, the system MUST trigger auto-progression upon foregrounding

#### Observability

- **FR-012a**: The system MUST log auto-progression start events to application logs with event details (event title, duration, timestamp)
- **FR-012b**: The system MUST log auto-progression completion events to application logs with timing information
- **FR-012c**: The system MUST log any auto-progression failures or errors to application logs with context for debugging

#### Series Statistics

- **FR-013**: The series completion screen MUST display an aggregate statistics panel prominently positioned above the "Back to Series" button
- **FR-013a**: Series statistics are calculated and displayed only during the completion screen session and MUST NOT be persisted to storage
- **FR-014**: The statistics panel MUST display the total number of events in the completed series, labeled clearly (e.g., "Events: 5")
- **FR-015**: The statistics panel MUST display the expected elapsed time, calculated as the sum of all event durations in the series, formatted as HH:MM:SS or MM:SS, and labeled clearly (e.g., "Expected Time: 15:00")
- **FR-016**: The statistics panel MUST display the actual elapsed time, calculated as the total time from series start to series end including all overtime and undertime, formatted as HH:MM:SS or MM:SS, and labeled clearly (e.g., "Actual Time: 16:45")
- **FR-017**: The statistics panel MUST display the total over/under time, calculated as the difference between actual elapsed time and expected elapsed time, formatted as ±HH:MM:SS or ±MM:SS with a "+" or "-" prefix, and labeled clearly (e.g., "Over/Under: +01:45")
- **FR-018**: The over/under time value MUST be color-coded: red for positive (overtime), green for negative (undertime), and neutral for zero (exactly on time)
- **FR-019**: All time values in the statistics panel MUST use consistent formatting (MM:SS for times under one hour, HH:MM:SS for times one hour or longer)

### Key Entities

- **Event**: Represents a timed activity with a title and duration. Now includes an `autoProgress` boolean property indicating whether the event should automatically advance when its countdown reaches zero.
- **Series**: Container for multiple events. Provides the sequence of events for the live timer session.
- **Timer State**: Tracks the current event index and elapsed seconds. Used to determine when auto-progression should trigger and to calculate aggregate statistics.
- **Series Statistics**: A calculated summary displayed at series completion, including event count, expected time (sum of durations), actual time (total elapsed including overtime/undertime), and over/under time (difference). Statistics are computed in-memory and not persisted after the completion screen is dismissed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can enable or disable auto-progress on an event and save the setting in under 5 seconds
- **SC-002**: Auto-progression from one event to the next completes within 1 second of the countdown reaching "00:00"
- **SC-002a**: Timer precision during auto-progression is maintained within 1 second across all events in a series
- **SC-003**: A fully automated series of 5 events progresses from start to completion screen without user interaction, with timer transitions completing smoothly
- **SC-004**: The series completion statistics panel is visible without scrolling on screens as small as 4 inches
- **SC-005**: All four statistics (event count, expected time, actual time, over/under time) are displayed clearly and accurately calculate within 1 second of the series ending
- **SC-006**: 90% of users can identify which events in a series have auto-progress enabled when viewing the event list
- **SC-007**: Manual "NEXT" button presses successfully interrupt auto-progression at any point during an event, with immediate advancement
- **SC-008**: If the app is backgrounded during auto-progression and foregrounded after the countdown reaches zero, auto-progression triggers within 2 seconds of foregrounding

## Assumptions

- The Event entity can be extended to include an `autoProgress` boolean field (defaulting to `false`)
- The Timer State already tracks elapsed seconds and can be used to calculate when "00:00" is reached
- The existing "NEXT" button mechanism can be reused/invoked programmatically for auto-progression
- The series completion screen already exists and can be enhanced with a statistics panel
- The app already persists Series and Event data locally using Hive, and the schema can be updated to include the `autoProgress` field
- The timer logic already handles background/foreground transitions, and this mechanism can be extended to evaluate auto-progression upon foregrounding
- The system can calculate actual elapsed time for the entire series by summing up the actual runtime of all events (including overtime and undertime)
- Events that are manually advanced before reaching "00:00" contribute their actual runtime (less than duration) to the series actual elapsed time
