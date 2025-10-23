# Feature Specification: Swipe-to-Delete Events and Series

**Feature Branch**: `002-swipe-delete-items`  
**Created**: October 23, 2025  
**Status**: Draft  
**Input**: User description: "Add the ability to delete events and series. I want the user to be able to swipe to delete an event, and a settings menu that will allow them to chose the swipe direction. When deleting a series, if it is empty of events then delete it immediatly (just like events), but if the series is not empty, prompt the user to confirm that all events within the series will be deleted, and give them an option to cancel the operation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Delete Single Event with Swipe (Priority: P1)

A user viewing a list of events within a series wants to remove an event they no longer need. They swipe the event in their configured direction (default: left-to-right) and the event is immediately deleted from the series.

**Why this priority**: Core deletion functionality that provides immediate value. Users need the ability to manage events within their series, and swipe-to-delete is the most intuitive mobile gesture for removal actions.

**Independent Test**: Can be fully tested by creating a series with multiple events, swiping on any event, and verifying it's removed from the list and permanently deleted from storage. Delivers immediate content management value.

**Acceptance Scenarios**:

1. **Given** a series with 3 events, **When** user swipes an event in the configured direction, **Then** the event is immediately removed from the list and permanently deleted
2. **Given** a series with 1 event, **When** user swipes the only event, **Then** the event is deleted and the series remains with zero events
3. **Given** user swipes an event, **When** deletion completes, **Then** the list updates to show remaining events in their original order
4. **Given** user swipes an event but doesn't complete the gesture (releases mid-swipe), **When** the swipe threshold isn't met, **Then** the event returns to its original position without deletion

---

### User Story 2 - Delete Empty Series with Swipe (Priority: P2)

A user viewing their list of series wants to remove a series that contains no events. They swipe the empty series in their configured direction and it is immediately deleted.

**Why this priority**: Natural extension of event deletion. Empty series don't provide value and should be easy to clean up, but this is secondary to managing event content.

**Independent Test**: Can be fully tested by creating an empty series, swiping on it in the series list, and verifying it's removed. Works independently of event deletion functionality.

**Acceptance Scenarios**:

1. **Given** a series list containing an empty series, **When** user swipes the empty series in the configured direction, **Then** the series is immediately removed from the list and permanently deleted
2. **Given** user swipes an empty series but doesn't complete the gesture, **When** the swipe threshold isn't met, **Then** the series returns to its original position without deletion

---

### User Story 3 - Delete Non-Empty Series with Confirmation (Priority: P2)

A user viewing their list of series wants to remove a series that contains events. They swipe the series, and a confirmation dialog appears warning that all events within will be deleted. The user can either confirm deletion (removing the series and all its events) or cancel the operation (keeping everything intact).

**Why this priority**: Critical safety feature to prevent accidental data loss. Same priority as P2 because series deletion is less frequent than event management, but confirmation prevents costly mistakes.

**Independent Test**: Can be fully tested by creating a series with events, swiping it, verifying the confirmation dialog appears with accurate information, and testing both confirm and cancel paths independently.

**Acceptance Scenarios**:

1. **Given** a series with 5 events, **When** user swipes the series in the configured direction, **Then** a confirmation dialog appears with message "Delete series '[Series Name]'? This will permanently delete 5 event(s)." and buttons "Cancel" and "Delete"
2. **Given** the confirmation dialog is displayed, **When** user selects "Delete", **Then** the series and all its events are removed from display and undo snackbar appears
3. **Given** the confirmation dialog is displayed, **When** user selects "Cancel", **Then** the dialog closes and the series remains in the list with all events intact
4. **Given** the confirmation dialog is displayed, **When** user taps outside the dialog or presses back, **Then** the dialog closes and the series remains unchanged (default to safe action)

---

### User Story 4 - Configure Swipe Direction (Priority: P3)

A user wants to customize which direction they swipe to delete items because they prefer right-to-left swipes or have accessibility needs. They open the settings menu, select their preferred swipe direction, and all future swipe-to-delete gestures use that direction.

**Why this priority**: Quality-of-life enhancement that improves user experience but isn't critical for core functionality. Users can use the default setting effectively, making this a nice-to-have feature.

**Independent Test**: Can be fully tested independently by opening settings, changing the swipe direction preference, and verifying that subsequent swipe gestures only work in the newly configured direction.

**Acceptance Scenarios**:

1. **Given** user is on any screen in the app, **When** user taps the settings icon in the app bar, **Then** they see swipe direction options (left-to-right, right-to-left)
2. **Given** the settings menu is open, **When** user selects "Right-to-left", **Then** the setting is saved and all swipe-to-delete gestures require right-to-left swipes
3. **Given** the settings menu is open, **When** user selects "Left-to-right", **Then** the setting is saved and all swipe-to-delete gestures require left-to-right swipes
4. **Given** user has configured a swipe direction, **When** they swipe in the opposite direction, **Then** no delete action occurs
5. **Given** user has configured a swipe direction, **When** they restart the app, **Then** their swipe direction preference persists

---

### Edge Cases

- What happens when a user deletes the last event in a series while viewing that series' event list?
- When user attempts to delete an event in an active timer session, system blocks deletion and shows "Event is in use. Stop the timer first." with navigation option to timer
- What happens if a user quickly swipes multiple items in succession?
- When deletion fails due to storage error, system automatically retries once, then shows error message with manual retry option if still failing
- What happens when a user swipes to delete but the network/storage is unavailable? (Same recovery as above)
- Confirmation dialog truncates extremely long series titles with ellipsis (e.g., "Delete series 'Very Long Series Na...'?")
- What happens if a user navigates away or closes the app while the confirmation dialog is open?

## Requirements *(mandatory)*

### Functional Requirements

#### Event Deletion

- **FR-001**: System MUST allow users to delete individual events by swiping them in the configured direction
- **FR-002**: System MUST remove deleted events from the list display immediately but retain in storage temporarily for undo
- **FR-003**: System MUST update the event list display immediately when an event is deleted, showing remaining events
- **FR-004**: System MUST require a swipe gesture to meet a minimum threshold distance of 30-40% of the item width before triggering deletion (prevent accidental deletions from unintended touches)
- **FR-005**: System MUST provide visual feedback during the swipe gesture showing the action that will occur (e.g., revealing delete icon or changing background color)
- **FR-023**: System MUST prevent deletion of events that are currently being used in an active timer session
- **FR-024**: System MUST display message "Event is in use. Stop the timer first." when user attempts to delete an event in an active timer
- **FR-025**: System MUST provide option to navigate to the active timer from the blocked deletion message
- **FR-028**: System MUST display an "Undo" snackbar/toast notification for 8 seconds after deletion
- **FR-029**: System MUST restore deleted event to its original position if user taps "Undo" within the time window
- **FR-030**: System MUST permanently remove deleted events from storage after undo window expires or user navigates away

#### Series Deletion

- **FR-006**: System MUST allow users to delete series by swiping them in the configured direction
- **FR-007**: System MUST immediately delete empty series (containing zero events) without showing a confirmation dialog and display undo snackbar
- **FR-008**: System MUST display a confirmation dialog when user attempts to delete a non-empty series
- **FR-009**: Confirmation dialog MUST display message "Delete series '[Series Name]'? This will permanently delete [N] event(s)." where [Series Name] is the actual series title and [N] is the count of events
- **FR-010**: System MUST provide "Cancel" and "Delete" buttons in the confirmation dialog
- **FR-011**: System MUST treat dismissing the confirmation dialog (back button, outside tap) as a cancel action
- **FR-012**: System MUST remove the series from display but retain in storage temporarily for undo after deletion is confirmed
- **FR-013**: System MUST update the series list display immediately when a series is deleted
- **FR-031**: System MUST display an "Undo" snackbar/toast notification for 8 seconds after series deletion
- **FR-032**: System MUST restore deleted series and all its events to original position if user taps "Undo" within time window
- **FR-033**: System MUST permanently remove the series and all its contained events from storage after undo window expires

#### Swipe Direction Settings

- **FR-014**: System MUST provide a settings icon/button in the app bar accessible from all screens
- **FR-015**: Settings menu MUST include a swipe direction preference with options: "Left-to-right" and "Right-to-left"
- **FR-016**: System MUST use "Left-to-right" as the default swipe direction if no preference is set
- **FR-017**: System MUST persist the user's swipe direction preference across app restarts
- **FR-018**: System MUST apply the configured swipe direction to both event and series deletion gestures
- **FR-019**: System MUST ignore swipe gestures in the opposite direction of the configured preference (no deletion action)

#### General

- **FR-020**: System MUST maintain data consistency between the series and events storage when deletions occur
- **FR-021**: System MUST handle rapid successive deletion attempts gracefully without corruption or crashes
- **FR-022**: System MUST automatically retry deletion once after a 100ms delay if a storage error occurs
- **FR-026**: System MUST show an error message with manual retry option if deletion fails after one automatic retry attempt
- **FR-027**: System MUST revert UI to pre-deletion state when deletion fails and cannot be completed

### Key Entities

- **Event**: Represents a timed activity within a series. Has a title and duration. Can be independently deleted without affecting other events or the parent series structure.
- **Series**: Container for a collection of events. Has a title and a list of events. Can be deleted, which cascades to remove all contained events. State (empty vs non-empty) determines deletion behavior.
- **User Preferences**: Stores user configuration settings including swipe direction preference. Persists across sessions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can delete an event with a single swipe gesture in under 1 second
- **SC-002**: Users can delete an empty series with a single swipe gesture in under 1 second
- **SC-003**: System prevents accidental deletion of non-empty series by requiring explicit confirmation
- **SC-009**: Users can undo any deletion within 8 seconds by tapping the undo notification
- **SC-010**: Undo action restores deleted items to their exact original position and state
- **SC-004**: Users can change swipe direction preference and have it apply immediately to all deletion gestures
- **SC-005**: 95% of swipe gestures that meet the threshold distance successfully trigger the intended action
- **SC-006**: User swipe direction preferences persist across 100% of app restarts
- **SC-007**: List displays update within 500ms after deletion to provide responsive feedback
- **SC-008**: Zero data inconsistencies occur between series and events after deletion operations

## Clarifications

### Session 2025-10-23

- Q: When a user attempts to delete an event that is currently being used in an active timer session, what should happen? → A: Block deletion and show message "Event is in use. Stop the timer first." with option to navigate to timer
- Q: Where should the settings menu be accessed from to configure swipe direction? → A: Add settings icon/button in the app bar (visible from all screens)
- Q: When a deletion operation fails due to storage errors, how should the system recover? → A: Automatically retry once, then show error with manual retry option
- Q: Should users be able to undo a deletion after it's been completed? → A: Show "Undo" snackbar/toast for 5-10 seconds after deletion
- Q: What exact message and button labels should appear in the confirmation dialog for deleting a non-empty series? → A: "Delete series '[Series Name]'? This will permanently delete [N] event(s)." with buttons "Cancel" and "Delete"

## Assumptions

- Users are familiar with swipe-to-delete gestures from common mobile applications (email clients, messaging apps)
- Left-to-right swipe is more natural for left-handed users and right-to-left for right-handed users, though individual preferences vary
- The swipe threshold distance should be approximately 30-40% of the item width to balance ease of use with prevention of accidental triggers
- Visual feedback during swipe (such as a red background or delete icon) is important for user confidence but specific styling is an implementation detail
- Deletion operations complete quickly enough (under 100ms) that offline/sync handling is not required for the MVP
- The settings menu will be a new addition to the app navigation structure
- Users will access settings infrequently after initial configuration, so it doesn't need to be prominently placed in primary navigation
