# Feature Specification: ChronoSync MVP - Live Event Coordinator

**Feature Branch**: `001-chronosync-mvp`  
**Created**: 2025-10-22  
**Status**: Draft  
**Input**: User description: "Generate initial specifications for a new mobile application for a 'Live Event Coordinator' use case."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Series Management (Priority: P1)

As an Event Coordinator, I want to create and manage a series of timed events so that I can build and review the agenda for a live event.

**Why this priority**: This is the foundational feature. Without the ability to create an agenda, the live timer has no content to display.

**Independent Test**: The coordinator can create a new series, add multiple events with titles and durations, and see them listed in the correct order. This can be fully tested without the live timer screen.

**Acceptance Scenarios**:

1. **Given** I am on the main screen, **When** I tap "Create Series", **Then** I am prompted to enter a title for the new series.
2. **Given** I have created a series, **When** I enter a title and tap "Save", **Then** a new, empty series with that title appears in my list of series.
3. **Given** I am viewing a series, **When** I tap "Add Event", **Then** I am prompted to enter a title and a duration in minutes for a new event.
4. **Given** I have entered a title and duration for a new event, **When** I tap "Save", **Then** the new event appears at the end of the event list for the current series.
5. **Given** a series contains multiple events, **When** I view the series, **Then** all events are displayed in the order they were added.

---

### User Story 2 - Live Timer Screen (Priority: P2)

As an Event Coordinator, I want to run a live timer for a selected series, with clear visual cues for the current event, its timing, and its status.

**Why this priority**: This is the core value proposition of the MVP, providing the live-tracking functionality for the event. It depends on User Story 1.

**Independent Test**: The coordinator can select a pre-populated series, start the live timer, and see the first event's title and timers. The "NEXT" button should advance to the next event. This can be tested with mock data.

**Acceptance Scenarios**:

1. **Given** I am viewing a list of my series, **When** I select a series and tap "Start", **Then** the Live Timer Screen appears, displaying the first event of the series.
2. **Given** the Live Timer Screen is active, **When** an event is running, **Then** the event's title is prominently displayed at the top of the screen.
3. **Given** an event is running, **When** I look at the timers, **Then** I see a countdown timer showing remaining time and a count-up timer showing elapsed time, both updating every second.
4. **Given** an event's countdown timer reaches "00:00", **When** time continues to pass, **Then** the timer's color changes to red and it begins to count into negative values (e.g., "-00:01").
5. **Given** an event is running, **When** I tap the "NEXT" button, **Then** the current event is marked as complete and the next event in the series immediately begins, with its own title and timers.
6. **Given** the last event in a series is running, **When** I tap the "NEXT" button, **Then** a summary screen is displayed, indicating the series is complete.

---

### Edge Cases

- **No Events in Series**: What happens if a user tries to start a series with no events? The "Start" button should be disabled or a message should appear.
- **Device Interruption**: How does the system handle the app being backgrounded or the device being locked during a live timer session? The timer state should be preserved and resume when the app is foregrounded.
- **Invalid Input**: The duration for an event must be a positive integer. The app should prevent non-numeric or zero/negative input.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow users to create a named Series.
- **FR-002**: The system MUST allow users to add an Event with a title and a duration in minutes to a Series.
- **FR-003**: The system MUST display the list of Events within a Series in the order they were added.
- **FR-004**: Users MUST be able to select a Series and start a live timer session.
- **FR-005**: The live timer screen MUST display the current event's title.
- **FR-006**: The live timer screen MUST display a countdown timer and a count-up timer for the current event.
- **FR-007**: The countdown timer MUST turn red and show negative time if the event duration is exceeded.
- **FR-008**: Users MUST be able to manually advance to the next event in the series using a "NEXT" button.
- **FR-009**: The system MUST persist all created Series and their Events locally on the device.

### Key Entities *(include if feature involves data)*

- **Series**: Represents a collection of events for a single agenda.
  - `title`: String (e.g., "Q3 All-Hands Meeting")
  - `events`: An ordered list of Event objects.
- **Event**: Represents a single timed item within a Series.
  - `title`: String (e.g., "Welcome & Intro")
  - `duration`: Integer (in minutes)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An Event Coordinator can create a 10-item series and start the live timer in under 90 seconds.
- **SC-002**: During a live session, the timers on the screen must be accurate to within 1 second of the device's system clock.
- **SC-003**: 95% of first-time users can successfully start and advance through a 3-event series without assistance.
- **SC-004**: The application must successfully resume its timer state after being backgrounded and then foregrounded within 5 minutes.
