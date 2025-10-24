# Feature Specification: Restore Timer Functionality

**Feature Branch**: `003-restore-timer-functionality`  
**Created**: October 23, 2025  
**Status**: Draft  
**Input**: User description: "Reimplement the working timers from 001-chronosync-mvp, in completing 002-swipe-delete-items there has been some regression in functionality. Specifically, the 001 all the timers worked, displayed time remaining and time over, with the option to progress to the next event."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Display Both Countdown and Count-up Timers (Priority: P1)

As an Event Coordinator running a live timer session, I want to see both a countdown timer (remaining time) and a count-up timer (elapsed time) simultaneously, so that I can track both how much time is left and how long the event has been running.

**Why this priority**: This is the core MVP functionality that was lost during feature 002 implementation. The timer display is the primary value proposition of the app, and coordinators need both pieces of information to effectively manage live events.

**Independent Test**: Can be fully tested by starting any series with events, observing that both countdown (remaining) and count-up (elapsed) timers are displayed simultaneously and update every second. Delivers immediate value for event coordination.

**Acceptance Scenarios**:

1. **Given** a live timer session is running, **When** I view the timer screen, **Then** I see both a countdown timer showing remaining time and a count-up timer showing elapsed time displayed prominently
2. **Given** an event with 5 minute duration is running, **When** 2 minutes have elapsed, **Then** the countdown shows "03:00" (remaining) and the count-up shows "02:00" (elapsed)
3. **Given** both timers are displayed, **When** time passes, **Then** both timers update every second in sync (countdown decreasing, count-up increasing)
4. **Given** an event is running, **When** I observe the timer labels, **Then** the countdown timer is clearly labeled as "Remaining" or "Time Left" and the count-up timer is labeled as "Elapsed" or "Time Passed"

---

### User Story 2 - Countdown Timer Turns Red and Goes Negative at Zero (Priority: P1)

As an Event Coordinator, when an event runs over its allocated time, I want the countdown timer to turn red and display negative time (e.g., "-01:30"), so that I can clearly see how far over schedule the event is running.

**Why this priority**: Critical visual feedback for managing events that run over time. This was part of the MVP requirement (FR-007) and provides essential at-a-glance status information for coordinators.

**Independent Test**: Can be fully tested by creating an event with a short duration (e.g., 1 minute), letting it run past zero, and verifying the countdown timer turns red and displays negative values like "-00:05", "-01:30", etc.

**Acceptance Scenarios**:

1. **Given** an event's countdown timer reaches "00:00", **When** time continues to pass, **Then** the countdown timer changes color to red
2. **Given** an event has been overtime for 1 minute and 30 seconds, **When** I view the countdown timer, **Then** it displays "-01:30" in red
3. **Given** the countdown timer is showing negative time, **When** each second passes, **Then** the negative value increases (e.g., "-00:05" becomes "-00:06")
4. **Given** the countdown timer is in overtime (red and negative), **When** I observe the count-up timer, **Then** it continues to count up normally without color change

---

### User Story 3 - Progress to Next Event (Priority: P1)

As an Event Coordinator, I want to manually advance to the next event in the series at any time by pressing a "NEXT" button, regardless of whether the current event's time has expired, so that I can maintain control over the event flow.

**Why this priority**: Essential control mechanism from the MVP. Coordinators must be able to advance the agenda even if an event finishes early or runs long. This was a core requirement (FR-008).

**Independent Test**: Can be fully tested by starting a series with multiple events, pressing the "NEXT" button at various points (before time expires, after time expires, during overtime), and verifying that each press immediately advances to the next event with fresh timers.

**Acceptance Scenarios**:

1. **Given** a live timer session is running with multiple events remaining, **When** I press the "NEXT" button, **Then** the current event immediately ends and the next event begins with both timers reset to zero
2. **Given** an event is in overtime (countdown showing negative time), **When** I press "NEXT", **Then** I progress to the next event normally without any error or warning
3. **Given** the last event in a series is running, **When** I press "NEXT", **Then** a completion screen appears indicating the series is finished
4. **Given** the "NEXT" button is displayed, **When** I view the timer screen, **Then** the button is prominently visible and clearly labeled as "NEXT"

---

### Edge Cases

- What happens if a series has only one event and "NEXT" is pressed? The completion screen should appear.
- What happens if an event has a very long duration (e.g., 2 hours) and runs overtime for 30 minutes? Both timers should continue to display correctly (countdown showing "-30:00", count-up showing "02:30:00").
- What happens when the app is backgrounded mid-timer and then foregrounded? The timer state should be preserved and both timers should reflect the correct elapsed time.
- What happens if an event has a very short duration (e.g., 10 seconds)? Both timers should update smoothly without UI glitches.
- What happens when the count-up timer reaches hours (e.g., "01:23:45")? It should display in HH:MM:SS format automatically.

## Requirements *(mandatory)*

### Functional Requirements

#### Timer Display

- **FR-001**: The live timer screen MUST simultaneously display both a countdown timer (remaining time) and a count-up timer (elapsed time) for the current event
- **FR-002**: The countdown timer MUST show the time remaining until the event's duration is reached (e.g., "05:30" for 5 minutes 30 seconds remaining)
- **FR-003**: The count-up timer MUST show the total elapsed time since the current event started (e.g., "02:15" for 2 minutes 15 seconds elapsed)
- **FR-004**: Both timers MUST update simultaneously every second
- **FR-005**: The countdown timer MUST have a clear label such as "Remaining", "Time Left", or similar
- **FR-006**: The count-up timer MUST have a clear label such as "Elapsed", "Time Passed", or similar

#### Overtime Behavior

- **FR-007**: When the countdown timer reaches "00:00", it MUST change color to red
- **FR-008**: After reaching "00:00", the countdown timer MUST continue counting into negative values (e.g., "-00:01", "-00:02", "-01:30")
- **FR-009**: The countdown timer MUST remain red and display negative values for as long as the event continues in overtime
- **FR-010**: The count-up timer MUST continue counting normally (without color change) when the event goes into overtime

#### Event Progression

- **FR-011**: A "NEXT" button MUST be displayed prominently on the live timer screen at all times during event execution
- **FR-012**: Users MUST be able to press "NEXT" at any point during an event (before, during, or after the scheduled duration expires)
- **FR-013**: Pressing "NEXT" MUST immediately advance to the next event in the series, resetting both timers to their starting values (countdown to event duration, count-up to zero)
- **FR-014**: Pressing "NEXT" on the final event MUST display a completion screen indicating the series has finished
- **FR-015**: The completion screen MUST provide a way to exit back to the series list

#### Timer Format

- **FR-016**: Timers MUST display in MM:SS format for durations under one hour (e.g., "05:30")
- **FR-017**: Timers MUST display in HH:MM:SS format when the elapsed time reaches or exceeds one hour (e.g., "01:23:45")
- **FR-018**: Negative countdown values MUST include a minus sign prefix (e.g., "-01:30")

### Key Entities

- **Event**: Represents a timed activity with a title and duration. The current event drives both timer displays.
- **Series**: Container for multiple events. Provides the sequence of events for the live timer session.
- **Timer State**: Tracks the current event index and elapsed seconds, which are used to calculate both countdown (remaining) and count-up (elapsed) timer values.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Both countdown and count-up timers are displayed simultaneously and visible without scrolling on screens as small as 4 inches
- **SC-002**: Timer accuracy is maintained within 1 second of the device system clock throughout a 30-minute session
- **SC-003**: Users can progress through a 5-event series using the "NEXT" button with all timer transitions completing in under 500ms
- **SC-004**: The countdown timer turns red and displays negative time within 1 second of reaching "00:00"
- **SC-005**: 100% of event coordinators can identify both remaining and elapsed time at a glance during usability testing
- **SC-006**: The timer display remains responsive and updates smoothly even when events run 2+ hours overtime
- **SC-007**: App state including timer values persists correctly when backgrounded and foregrounded within 5 minutes

## Assumptions

- The LiveTimerBloc already exists and manages timer state with elapsed seconds
- The LiveTimerState already calculates remainingSeconds and overtimeSeconds from elapsed time
- Timer ticks are triggered by a Timer.periodic every second
- The UI layer (LiveTimerScreen) is responsible for formatting and displaying timer values
- The current implementation shows either countdown OR overtime, not both timers simultaneously
- The count-up (elapsed) timer was part of the original MVP but was removed or hidden during the 002-swipe-delete-items implementation
- Event duration is stored as a Duration object and can be converted to seconds for calculations
- The "NEXT" button functionality already exists but may have been affected by changes in feature 002
- The completion screen exists and displays when the final event's "NEXT" button is pressed
