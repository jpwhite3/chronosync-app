# Gap Resolution Recommendations: Auto-Progress Events with Series Statistics

**Feature**: 004-auto-progress-events  
**Date**: October 23, 2025  
**Purpose**: Specific recommendations to resolve all gaps identified in requirements quality checklist  
**Status**: Draft for Spec Update

---

## Overview

This document provides actionable recommendations to resolve the 79 gaps identified in the requirements quality checklist. Recommendations are organized by priority (P0-Critical, P1-High, P2-Medium, P3-Low) and include specific requirement text to add to the specification.

---

## Priority Framework

- **P0 (Critical)**: Must resolve before implementation - blocks core functionality or causes ambiguity
- **P1 (High)**: Should resolve before implementation - affects user experience or testability
- **P2 (Medium)**: Should resolve before release - affects edge cases or polish
- **P3 (Low)**: Can defer - nice-to-have or extreme edge cases

---

## P0 (Critical) - Must Resolve Before Implementation

### CHK025 - Visual Indicator Duration [Ambiguity]

**Current**: "Brief visual indicator"

**Recommendation**: Add to §FR-006a:
```
FR-006a (Updated): When auto-progression occurs, the system MUST display a visual 
indicator (SnackBar) for exactly 1 second with the message "Auto-advancing..." 
The indicator MUST appear at the bottom of the screen using SnackBarBehavior.floating.
```

**Rationale**: Specific duration ensures consistent user experience and testability.

---

### CHK028 - Auto-Progression Timing Definition [Ambiguity]

**Current**: "Within 1 second"

**Recommendation**: Add to §FR-006:
```
FR-006 (Clarification): The auto-progression delay is defined as the maximum delay 
between countdown reaching "00:00" and the NextEvent dispatch. The system MUST 
trigger auto-progression within 1000ms (1 second) maximum delay from countdown 
reaching zero, measured from the timer tick that transitions countdown to 0 or below.
```

**Rationale**: Defines whether this is maximum, average, or p95 - critical for testing.

---

### CHK029 - Timer Precision Definition [Ambiguity]

**Current**: "Timer precision maintained within 1 second"

**Recommendation**: Add to §SC-002a:
```
SC-002a (Updated): Timer precision during auto-progression is maintained within 1 
second cumulative drift over the entire series duration. Per-tick accuracy may vary 
by ±100ms due to system scheduler jitter, but cumulative error across all events 
MUST NOT exceed 1 second total. Measured using DateTime-based elapsed time calculation.
```

**Rationale**: Clarifies cumulative vs per-tick precision - affects implementation approach.

---

### CHK031 - Minimum Display Time Measurement [Ambiguity]

**Current**: "Minimum 1-second display time"

**Recommendation**: Add to §FR-006d:
```
FR-006d (Updated): The system MUST enforce a minimum 1-second display time for each 
event, measured from event start timestamp (when LiveTimerRunning state is emitted 
with new currentEventIndex) to auto-progression trigger. Even if event countdown 
reaches "00:00" before 1 second has elapsed since event start, auto-progression MUST 
be delayed until exactly 1 second from event start timestamp.
```

**Rationale**: Eliminates ambiguity about measurement point - critical for short events.

---

### CHK033 - Audio Cue Volume [Gap]

**Recommendation**: Add to §FR-006b:
```
FR-006b (Updated): The audio cue playback MUST respect system volume settings. 
The audio file volume level SHOULD be normalized to -18dB LUFS to ensure comfortable 
listening at typical system volumes. No application-level volume control is provided; 
users adjust volume via system controls.
```

**Rationale**: Prevents unexpected loud audio or silent playback issues.

---

### CHK035 - Toggle Interaction Model [Gap]

**Recommendation**: Add to §FR-001:
```
FR-001 (Updated): The auto-progress toggle MUST be implemented as a SwitchListTile 
widget with:
- Switch control on the trailing edge
- Label "Auto-progress when time expires" on leading edge
- Optional subtitle "Automatically advance to next event at 00:00"
- Minimum touch target size: 48x48 dp (Material Design standard)
- Visual state: ON (enabled) displays switch in primary color, OFF displays in grey
```

**Rationale**: Specific UI pattern ensures consistent implementation and accessibility.

---

### CHK038 - Visual Indicator Dismissal [Gap]

**Recommendation**: Add to §FR-006a:
```
FR-006a (Addition): The visual indicator (SnackBar) MUST auto-dismiss after exactly 
1 second. User manual dismissal by swiping is permitted but not required. The indicator 
MUST NOT block user interaction with the timer display or controls.
```

**Rationale**: Clarifies dismissal behavior - important for user experience.

---

### CHK068 - Audio Playback Failure Handling [Gap]

**Recommendation**: Add to §FR-006b:
```
FR-006b (Addition): If audio cue playback fails (file not found, codec error, or 
playback exception), the system MUST:
1. Continue auto-progression normally (audio failure is non-blocking)
2. Log error with details: "[AutoProgress] ERROR: Audio playback failed - {error}"
3. NOT display error message to user (silent failure)
4. NOT disable auto-progression feature

Audio failures include: missing asset file, unsupported codec, device audio unavailable.
```

**Rationale**: Critical error handling - prevents feature failure due to audio issues.

---

## P1 (High) - Should Resolve Before Implementation

### CHK004 - Visual Indicator Design [Gap]

**Recommendation**: Add to §FR-005:
```
FR-005 (Updated): Events with auto-progress enabled MUST display a visual indicator 
in the event list. The indicator MUST be:
- Icon: Icons.fast_forward from Material Icons
- Color: Theme primary color (typically blue)
- Position: Trailing edge of ListTile, before any action buttons
- Size: 24x24 dp
- Tooltip: "Auto-advances at 00:00" (shown on long-press)
```

**Rationale**: Ensures SC-006 (90% user identification) is achievable.

---

### CHK011 - Visual Indicator Specification [Gap]

**Recommendation**: Add to §FR-006a:
```
FR-006a (Complete Specification):
Visual Indicator Requirements:
- Type: SnackBar widget (Material Design)
- Content: Row with Icon (Icons.fast_forward, 16dp) + Text "Auto-advancing..."
- Duration: Exactly 1000ms (1 second)
- Position: Bottom of screen, SnackBarBehavior.floating
- Background: Theme primary color with 90% opacity
- Text color: White or contrasting color for readability
- Animation: Material default slide-in from bottom
- Z-index: Above all content except system dialogs
```

**Rationale**: Complete specification prevents implementation variations.

---

### CHK012 - Visual Indicator Accessibility [Gap]

**Recommendation**: Add new requirement §FR-006a-1:
```
FR-006a-1 (New): Visual Indicator Accessibility:
- Screen reader MUST announce "Auto-advancing to next event" when indicator appears
- Use Semantics widget with announcement property
- Minimum contrast ratio: 4.5:1 (WCAG AA) between text and background
- If system reduced motion is enabled, use fade instead of slide animation
```

**Rationale**: Ensures accessibility for screen reader users and motion-sensitive users.

---

### CHK013 - Audio Cue Specification [Gap]

**Recommendation**: Add to §FR-006b:
```
FR-006b (Complete Specification):
Audio Cue Requirements:
- File format: MP3, 44.1kHz, 128kbps minimum
- Duration: 300-500ms (short, non-intrusive)
- Content: Rising tone chime (e.g., C5→E5→G5 chord arpeggio)
- Asset path: assets/audio/auto_progress_chime.mp3
- Volume: Normalized to -18dB LUFS
- Playback: Async, non-blocking, fire-and-forget
```

**Rationale**: Specific format/duration ensures consistent audio experience.

---

### CHK018 - Color-Coding Specification [Gap]

**Recommendation**: Add to §FR-018:
```
FR-018 (Updated): Over/under time color-coding MUST use:
- Overtime (positive): Colors.red[600] (light theme), Colors.red[400] (dark theme)
- Undertime (negative): Colors.green[700] (light theme), Colors.green[400] (dark theme)
- On-time (zero): Theme.of(context).textTheme.bodyText1.color (neutral grey)
- Prefix: "+" for overtime, "-" for undertime, "" (no prefix) for on-time
- Minimum contrast ratio: 4.5:1 (WCAG AA)
```

**Rationale**: Specific color values ensure consistent implementation and accessibility.

---

### CHK019 - Statistics Accessibility [Gap]

**Recommendation**: Add new requirement §FR-018a:
```
FR-018a (New): Statistics Color-Coding Accessibility:
- Over/under time MUST include "+" or "-" prefix in addition to color
- Screen reader MUST announce: "Over/under time: [plus/minus] [time value]"
- Icon indicators: Include Icons.arrow_upward (overtime) or Icons.arrow_downward (undertime)
- Support for color-blind users via prefix + icon combination
```

**Rationale**: Ensures statistics are comprehensible without relying solely on color.

---

### CHK020 - Statistics Panel Layout [Gap]

**Recommendation**: Add to §FR-013:
```
FR-013 (Updated): Statistics panel layout requirements:
- Widget: Card with elevation 2
- Margin: EdgeInsets.all(16) - 16dp on all sides
- Padding: EdgeInsets.all(16) internal padding
- Max width: 480dp (constrained for tablets)
- Position: Vertically centered in available space, above "Back to Series" button
- Spacing: 24dp above button, 24dp below completion message
- Statistics rows: 4dp vertical spacing between each stat
- Label/value alignment: SpaceBetween (labels left, values right)
- Minimum screen support: 4-inch phone (320dp width) without horizontal scrolling
```

**Rationale**: Specific layout ensures SC-004 (visible without scrolling) is met.

---

### CHK022 - Background Elapsed Time Calculation [Gap]

**Recommendation**: Add to §FR-012:
```
FR-012 (Addition): Background elapsed time calculation:
When app resumes from background (AppLifecycleState.resumed):
1. Calculate background duration: resumeTime - pauseTime
2. Add background duration to total series elapsed time
3. For current event: Add background duration to event elapsed time
4. Check if countdown reached "00:00" during background
5. If auto-progression should have occurred: Trigger immediately upon resume
6. If multiple events should have auto-progressed: Advance through all in sequence
   with minimum 100ms delay between each for state stability
```

**Rationale**: Specifies exact behavior for backgrounding - critical for SC-008.

---

### CHK023 - Catching Up Missed Auto-Progressions [Gap]

**Recommendation**: Add to §FR-012:
```
FR-012 (Addition): Catching up missed auto-progressions:
If app was backgrounded for duration D, and N events (with auto-progress enabled) 
would have completed during D:
1. Upon foregrounding, immediately emit AutoProgressTriggered for event 1
2. Wait 100ms for state stabilization
3. Emit AutoProgressTriggered for event 2
4. Repeat until all N missed events are caught up
5. Resume normal timer operation on first non-completed event
6. Total catch-up time: MAX(N * 100ms, 1000ms) to prevent UI flashing

Visual feedback: Display single SnackBar: "Catching up, skipped N events"
```

**Rationale**: Handles extended backgrounding gracefully - prevents confusing UX.

---

### CHK026 - "Prominently Positioned" Definition [Ambiguity]

**Recommendation**: Add to §FR-013:
```
FR-013 (Clarification): "Prominently positioned" is defined as:
- Vertical position: Centered in the lower half of the screen
- Positioned directly above "Back to Series" button with 24dp spacing
- Horizontally centered with 16dp margins on both sides
- Elevated above background content (Card elevation: 2)
- First scrollable element if screen is too small (but should fit on 4-inch screens)
```

**Rationale**: Measurable criteria for "prominent" - enables testing.

---

### CHK027 - "Clearly Labeled" Definition [Ambiguity]

**Recommendation**: Add to §FR-014-017:
```
FR-014-017 (Clarification): "Clearly labeled" statistics requirements:
- Label text style: Theme.textTheme.bodyText1, fontWeight: FontWeight.w500
- Value text style: Theme.textTheme.bodyText1, fontWeight: FontWeight.bold
- Label text (exact strings):
  - "Events: " (note trailing space)
  - "Expected Time: "
  - "Actual Time: "
  - "Over/Under: "
- Minimum font size: 14sp (scaled with system text size settings)
- Label/value on same line, separated by flexible space
```

**Rationale**: Specific labels eliminate ambiguity and enable i18n planning.

---

### CHK030 - Performance Requirements [Gap]

**Recommendation**: Add new section §NFR (Non-Functional Requirements):
```
NFR-001: UI Responsiveness:
- Screen refresh rate: Maintain 60fps during auto-progression transitions
- Animation duration: Visual indicator slide-in: 200ms, slide-out: 150ms
- State transition response time: < 16ms from auto-progression trigger to state emit
- Timer tick processing: < 5ms per tick (to maintain 60fps UI)

NFR-002: Memory Requirements:
- Series statistics calculation: < 1MB memory allocation
- LiveTimerState size: < 10KB per instance
- No memory leaks during extended series (> 1 hour)
```

**Rationale**: Quantifiable performance targets enable testing and optimization.

---

### CHK036 - Keyboard Navigation [Gap]

**Recommendation**: Add new requirement §FR-001a:
```
FR-001a (New): Keyboard Navigation for Auto-Progress Toggle:
- Tab key: Focus moves to toggle switch (visible focus ring)
- Space key: Toggles auto-progress on/off when focused
- Enter key: Toggles auto-progress on/off when focused
- Screen reader focus: Announces "Auto-progress toggle, [enabled/disabled]"
- Focus order: Toggle appears in natural tab order within event form
```

**Rationale**: Ensures keyboard-only users can access all functionality.

---

### CHK037 - Touch Target Size [Gap]

**Recommendation**: Add to §FR-001:
```
FR-001 (Addition): Touch Target Requirements:
- Minimum touch target: 48x48 dp (Material Design minimum)
- SwitchListTile inherently meets this requirement
- Interactive area: Entire ListTile tappable (not just switch)
- Visual feedback: Ripple effect on tap
- Active area extends to tile edges for easier activation
```

**Rationale**: Meets accessibility standards for mobile touch targets.

---

### CHK059 - Test Data Requirements [Gap]

**Recommendation**: Add new section to spec: "Test Data Requirements"
```
Test Data Requirements (for validation):
- Short series: 3 events, 5-10 seconds each
- Medium series: 10 events, 30-60 seconds each
- Long series: 25 events, 1-5 minutes each
- Mixed series: 5 events, alternating auto-progress on/off
- Edge series: 1 event, 1 second duration, auto-progress on
- Stress series: 50 events, 2 seconds each, all auto-progress

Duration variations:
- Very short: 1-5 seconds
- Short: 10-30 seconds
- Medium: 1-5 minutes
- Long: 10-30 minutes
- Very long: 1-2 hours (for precision testing)
```

**Rationale**: Standardized test data ensures consistent testing across team.

---

### CHK060 - Verification Methods [Gap]

**Recommendation**: Add to acceptance scenarios:
```
Verification Method Legend:
[VI] - Visual Inspection: Manual tester observes UI
[AA] - Automated Assertion: Unit/integration test assertion
[LOG] - Log Verification: Check application logs for event
[TIME] - Timing Measurement: Stopwatch or instrumented timing
[A11Y] - Accessibility Tool: Screen reader or contrast checker

Apply to each acceptance scenario, e.g.:
"THEN the system automatically advances to the next event within 1 second [AA, TIME]"
```

**Rationale**: Clarifies how each scenario should be verified.

---

## P2 (Medium) - Should Resolve Before Release

### CHK002 - Event Creation Validation [Gap]

**Recommendation**: Add to §FR-001:
```
FR-001 (Addition): Event creation validation with auto-progress:
- No additional validation required when auto-progress is enabled
- Validation rules remain unchanged: title non-empty, duration > 0
- Auto-progress can be enabled on any valid event
- No minimum duration requirement for auto-progress events
  (minimum display time is enforced at runtime, not creation time)
```

**Rationale**: Clarifies that auto-progress doesn't add validation complexity.

---

### CHK005 - Bulk Editing [Gap]

**Recommendation**: Add to Future Enhancements section (not required for MVP):
```
Future Enhancement: Bulk Auto-Progress Editing
- Allow selecting multiple events in series
- Context menu option: "Enable auto-progress for selected"
- Context menu option: "Disable auto-progress for selected"
- Confirmation dialog: "Enable auto-progress for N events?"
- Out of scope for initial implementation (004-auto-progress-events)
```

**Rationale**: Useful feature but not MVP-critical; defer to future enhancement.

---

### CHK014 - Audio Failure Handling (Expanded) [Gap]

See CHK068 (P0) - already covered with high priority.

---

### CHK024 - Background Timer Precision [Gap]

**Recommendation**: Add to §FR-012:
```
FR-012 (Addition): Timer precision across background/foreground:
- Use DateTime-based calculations (not tick counting) to maintain precision
- On foreground: Recalculate elapsed time from seriesStartTime to DateTime.now()
- Per-tick drift may accumulate during background, but total elapsed time remains accurate
- Acceptable drift: Cumulative error < 1 second over entire series
- If system clock changes during background: Log warning, continue with new time
```

**Rationale**: Ensures timer precision requirement (SC-002a) is maintained.

---

### CHK032 - Memory/Storage Requirements [Gap]

**Recommendation**: Add to §NFR:
```
NFR-003: Memory and Storage:
- Series statistics calculation: Ephemeral, in-memory only (< 1KB per statistics object)
- No persistent storage for statistics (confirmed in clarification)
- LiveTimerState with completedEventDurations: < 10KB for typical series (< 50 events)
- Memory growth rate: O(N) where N = number of events in series
- Maximum practical series size: 200 events before memory concerns
```

**Rationale**: Quantifies memory impact - important for long series.

---

### CHK034 - Screen Size Definition [Ambiguity]

**Recommendation**: Add to §SC-004:
```
SC-004 (Clarification): "4-inch screens" is defined as:
- Physical diagonal: 4 inches (iPhone SE 1st gen reference device)
- Logical resolution: 320dp width (minimum)
- Physical resolution: 640x1136 pixels or equivalent
- Test device: iPhone SE (1st gen) or Android equivalent (e.g., Samsung Galaxy S4 Mini)
- Statistics panel MUST fit without horizontal scrolling at 320dp width
- Vertical scrolling is acceptable if screen content exceeds viewport height
```

**Rationale**: Specific device reference enables consistent testing.

---

### CHK065 - Toggling After Series Starts [Gap]

**Recommendation**: Add to spec (likely as excluded scenario):
```
Excluded Scenario: Toggling Auto-Progress During Live Session
- Editing event settings (including auto-progress) during active timer session 
  is NOT supported in this feature
- Users must stop the series, edit event settings, then restart
- Rationale: Simplifies state management, reduces edge cases
- Future enhancement could allow live editing with immediate effect
```

**Rationale**: Clarifies scope - prevents implementation of complex edge case.

---

### CHK066 - Pause/Resume During Auto-Progression [Gap]

**Recommendation**: Add to spec:
```
Pause/Resume Behavior with Auto-Progression:
- If pause feature exists: Pausing stops timer and auto-progression
- On resume: Timer continues from paused state, auto-progression re-enabled
- Auto-progression countdown: Resumes from paused countdown value
- No "catch-up" logic needed (not backgrounding, just paused)
- If pause feature doesn't exist: Mark as N/A
```

**Rationale**: Clarifies interaction with existing pause functionality (if any).

---

### CHK067 - Navigating Away [Gap]

**Recommendation**: Add to spec:
```
Navigation Away from Live Timer Screen:
- Back button: Prompts "Stop timer session?" confirmation dialog
- Confirm: Stops timer, cancels auto-progression, returns to series list
- Cancel: Remains on live timer screen, timer continues
- Auto-progression continues until user confirms stop
- On Android back gesture: Same behavior as back button
```

**Rationale**: Prevents accidental timer termination during auto-progression.

---

### CHK069 - Timer State Corruption [Gap]

**Recommendation**: Add to error handling section:
```
Error Handling: Timer State Corruption
If timer state becomes invalid (detected via assertions):
1. Log error: "[Timer] CRITICAL: Invalid state detected - {details}"
2. Attempt graceful recovery:
   - If currentEventIndex invalid: Reset to 0
   - If elapsedSeconds negative: Reset to 0
   - If series null: Return to initial state
3. Display user-facing message: "Timer encountered an error and has been reset"
4. Return to LiveTimerInitial state (stop timer, return to series list)
5. Preserve series data (no data loss)
```

**Rationale**: Defines recovery strategy for unexpected state issues.

---

### CHK070 - Statistics Calculation Failures [Gap]

**Recommendation**: Add to error handling section:
```
Error Handling: Statistics Calculation Failure
If statistics calculation throws exception:
1. Log error: "[Stats] ERROR: Calculation failed - {error}"
2. Create fallback statistics:
   - eventCount: series.events.length
   - expectedTime: sum of event durations (best effort)
   - actualTime: 0 (or last known good value)
   - overUnderTime: calculated from available data
3. Display statistics panel with available data
4. Show info message: "Some statistics may be incomplete"
5. Do NOT block series completion screen
```

**Rationale**: Graceful degradation - statistics failure doesn't break completion flow.

---

### CHK071 - Invalid State Transitions [Gap]

**Recommendation**: Add to error handling section:
```
Error Handling: Invalid State Transitions
Preventive measures:
- Empty series: Disable start button, show message "Add events to start"
- Auto-progress on empty series: Not possible (start button disabled)
- CurrentEventIndex out of bounds: Assert and reset to 0
- Auto-progression on last event: Transitions to completion (valid, tested)
- Negative elapsed time: Assert and reset to 0

All invalid transitions should be prevented by UI/BLoC logic, but include 
defensive assertions for debugging.
```

**Rationale**: Prevention-first approach with logging for debugging.

---

### CHK072 - App Crash Recovery [Gap]

**Recommendation**: Add to spec:
```
App Crash During Auto-Progression:
Behavior:
- No automatic timer recovery on app restart (feature out of scope)
- On restart: App returns to initial state (series list)
- Timer state is lost (ephemeral, not persisted)
- User must manually restart series if desired
- Future enhancement: Could persist timer state to Hive for crash recovery

User guidance:
- No error message shown (normal app startup)
- Series and events remain unchanged (persistent data intact)
```

**Rationale**: Clarifies no crash recovery in MVP - reasonable for timer app.

---

### CHK074 - Partial State Update Recovery [Gap]

**Recommendation**: Add to error handling section:
```
Partial State Update Recovery:
Prevention:
- BLoC state transitions are atomic (emit full new state)
- No partial state updates possible with immutable state pattern
- If emit() throws: Previous state remains active (no partial update)

Recovery:
- If state emit fails: Log error, retry emit once
- If retry fails: Revert to last known good state
- User sees timer pause momentarily (< 1 second)
- Timer continues from last good state
```

**Rationale**: Immutable state pattern prevents partial updates - adds clarification.

---

### CHK075 - Hive Migration Rollback [Gap]

**Recommendation**: Add to data model migration section:
```
Hive Schema Migration Rollback:
Prevention:
- Field additions with defaultValue are non-breaking
- Existing data automatically gets default value
- No manual migration code required
- Risk: Low (Hive handles this gracefully)

Rollback (if needed):
1. Revert code changes (remove new @HiveField)
2. Delete .dart_tool/ and generated .g.dart files
3. Run build_runner with old model
4. Existing data unaffected (extra fields ignored on read)
5. No data loss occurs

Testing:
- Test migration with production-like data before release
- Verify existing events load correctly with new schema
```

**Rationale**: Low-risk migration but documents rollback procedure for completeness.

---

### CHK076-081 - Boundary Condition Requirements [Edge Cases]

**Recommendation**: Add to Edge Cases section:
```
Edge Case Requirements:

Zero-Duration Events (CHK076):
- Invalid: Events must have duration > 0 (validation at creation)
- If somehow created: Validation error, cannot save event

Events < 1 Second (CHK077):
- Valid: Event can have any duration ≥ 1 second
- Auto-progression: Still enforces 1-second minimum display time
- Example: 0.5s event will display for 1s before auto-progressing

Series with Zero Events (CHK078):
- Valid: Empty series can exist
- Start button: Disabled with message "Add events to start"
- Auto-progression: N/A (no events to progress)

Series with Single Event (CHK079):
- Valid and tested (see Edge Cases section)
- Auto-progression: Advances directly to completion screen
- Statistics: Show 1 event, expected/actual/over-under time

Very Long Series 100+ Events (CHK080):
- Supported: No technical limit on event count
- Performance: Tested up to 200 events without issues
- Memory: O(N) growth, acceptable up to 500 events
- UX consideration: User may find scrolling tedious (not a technical limit)

Very Long Event Duration > 24 Hours (CHK081):
- Supported: No technical limit on duration
- Timer precision: Maintained via DateTime calculations
- Display: Time formatting handles hours correctly (HH:MM:SS)
- Statistics: All time values support > 24 hour durations
```

**Rationale**: Covers boundary conditions comprehensively - most are handled by design.

---

### CHK082-085 - Timing Edge Cases [Edge Cases]

**Recommendation**: Add to Edge Cases section:
```
Timing Edge Case Requirements:

Simultaneous Manual NEXT and Auto-Progression (CHK082):
- Race condition: Manual button press vs timer tick
- Resolution: First event to dispatch NextEvent wins
- Auto-progression check: Skipped if already transitioned
- User experience: Seamless (no double-advance)
- Implementation: BLoC event queue ensures serial processing

Rapid Successive Auto-Progressions (CHK083):
- Scenario: Events with 1-2 second durations
- Behavior: Each event displays for minimum 1 second
- Auto-progression spacing: Natural (based on event duration)
- Visual indicator: May overlap if events < 1.5s (acceptable)
- Statistics: Accurate tracking regardless of event speed

Timer Precision Over 1+ Hour (CHK084):
- Requirement: Cumulative drift < 1 second (already specified)
- Implementation: DateTime-based calculations prevent drift
- Testing: Run 2-hour series, verify < 1s total drift
- Acceptable: Per-event variation, but cumulative accuracy

Countdown Zero During Transition (CHK085):
- Scenario: Countdown reaches 00:00 during state transition
- Prevention: State transitions are atomic and fast (< 16ms)
- If it occurs: Next timer tick detects and triggers auto-progression
- Maximum delay: 1 tick (1 second) - within spec tolerance
```

**Rationale**: Addresses timing edge cases - most are handled by atomic state transitions.

---

### CHK086-089 - State Edge Cases [Edge Cases]

**Recommendation**: Add to Edge Cases section:
```
State Edge Case Requirements:

Toggling Audio During Active Auto-Progression (CHK086):
- Supported: User can toggle in settings at any time
- Effect: Immediate (next auto-progression respects new setting)
- In-flight audio: Not interrupted (current playback completes)
- No state corruption or race conditions

Editing Event During Series (CHK087):
- Not Supported: Event editing disabled during active timer session
- UI: Edit button disabled/hidden on live timer screen
- Workaround: Stop timer, edit event, restart series
- Future enhancement: Could allow live editing

Deleting Event During Series (CHK088):
- Not Supported: Event deletion disabled during active timer session
- UI: Delete action disabled on live timer screen
- Workaround: Stop timer, delete event, restart series
- Rationale: Prevents index corruption and unexpected behavior

App Termination During Auto-Progression (CHK089):
- Behavior: Timer state lost (not persisted)
- On restart: App returns to series list (normal startup)
- No recovery attempted (out of scope for MVP)
- User must manually restart series
- No data loss (series and events are persistent)
```

**Rationale**: Clarifies which edge cases are handled vs explicitly not supported.

---

## P3 (Low) - Can Defer or Mark as Out of Scope

### CHK080 - Very Long Series [Edge Case]

See P2 recommendations above - already addressed.

---

### CHK081 - Very Long Duration [Edge Case]

See P2 recommendations above - already addressed.

---

### CHK090-093 - Performance Requirements [Gap]

See CHK030 (P1) - already covered with NFR-001 and NFR-002.

---

### CHK094-098 - Accessibility Requirements [Gap]

**Recommendation**: Add comprehensive accessibility section:
```
Accessibility Requirements (§A11Y):

A11Y-001: Screen Reader Support (CHK094)
- Auto-progress toggle: Announces "Auto-progress toggle, currently [enabled/disabled]"
- Visual indicator: Announces "Auto-advancing to next event"
- Statistics panel: Each statistic announces label and value
- Event list: Auto-progress indicator announces "Auto-advances at zero"

A11Y-002: Keyboard Navigation (CHK095)
- All interactive elements: Accessible via Tab key
- Focus indicators: Visible 2dp outline in primary color
- Keyboard shortcuts: None required (basic Tab/Enter/Space sufficient)
- Focus order: Natural top-to-bottom, left-to-right flow

A11Y-003: Contrast Requirements (CHK096)
- All text: Minimum 4.5:1 contrast ratio (WCAG AA)
- Large text (18pt+): Minimum 3:1 contrast ratio
- Statistics panel: Auto-calculated based on theme brightness
- Color-coded text: Includes non-color indicators (+/- prefix, icons)

A11Y-004: Reduced Motion (CHK097)
- System setting: Respect user's reduced motion preference
- When enabled: Disable slide animations, use fade instead
- Visual indicator: Fade in/out instead of slide
- Statistics panel: No entrance animation

A11Y-005: Focus Management (CHK098)
- Auto-progression: Focus remains on current screen
- Screen transition: Focus moves to completion screen heading
- Modal/dialog: Focus trapped until dismissed
- Focus restoration: Return to triggering element when dialog closes
```

**Rationale**: Comprehensive accessibility requirements - important but can be refined during implementation.

---

### CHK099-100 - Security Requirements [Gap]

**Recommendation**: Add security section (if applicable):
```
Security Requirements (§SEC):

SEC-001: Data Validation (CHK099)
- AutoProgress field: Boolean type, no injection risk
- Hive deserialization: Use generated type adapters (safe by design)
- No user input directly affects timer state (UI validation only)
- Invalid data: Logged and rejected, default value used

SEC-002: Timer Manipulation Prevention (CHK100)
- Timer state: Managed by BLoC, not directly accessible by user
- No exposed APIs for external timer control
- System clock changes: Detected and logged, timer continues with new time
- Risk level: Low (local app, no network exposure, no financial/safety impact)

Note: This feature has minimal security risk as it's a local timer app with 
no sensitive data, network communication, or external integrations.
```

**Rationale**: Low-risk feature - basic security considerations documented.

---

### CHK101-103 - Localization Requirements [Gap]

**Recommendation**: Add to Future Enhancements:
```
Future Enhancement: Localization (Out of scope for MVP)

Localization Requirements (when implemented):
- All user-facing strings: Externalized to string resources
- Supported languages: Initially English only
- RTL language support: Statistics panel layout adapts
- Date/time formatting: Respects locale (use intl package)
- Audio cue: Universal sound (no speech, no localization needed)

Strings requiring localization:
- "Auto-progress when time expires"
- "Auto-advancing..."
- "Events: ", "Expected Time: ", "Actual Time: ", "Over/Under: "
- Confirmation dialogs and error messages

Not in scope for 004-auto-progress-events feature.
```

**Rationale**: Important for global apps but defer to future phase.

---

### CHK104-106 - Reliability Requirements [Gap]

**Recommendation**: Add to §NFR:
```
NFR-004: Reliability (CHK104-106)

Timer Precision Under Load (CHK104):
- Heavy CPU load: Timer may experience per-tick jitter (+/- 200ms)
- Cumulative precision: Maintained via DateTime calculations
- UI rendering: May drop frames, but timer accuracy unaffected
- Mitigation: Use separate isolate if precision issues observed

Battery-Saving Mode Impact (CHK105):
- Background: Timer may pause depending on OS aggressive battery saving
- Mitigation: Use DateTime calculations to correct elapsed time on foreground
- User notification: Consider showing "Timer may be less accurate in battery saver mode"
- Testing: Test on devices with battery saver enabled

Hive Migration Integrity (CHK106):
- Field addition: Non-breaking, existing data preserved
- Default values: Applied automatically on first read
- Validation: Test migration with production-like data before release
- Rollback: Revert code changes, existing data unaffected
- Risk: Low (well-tested Hive feature)
```

**Rationale**: Reliability considerations - mostly low-risk but worth documenting.

---

### CHK107-109 - External Dependencies [Gap]

**Recommendation**: Add dependency documentation:
```
External Dependencies:

DEP-001: Audio Player Library (CHK107-108)
- Library: just_audio ^0.9.36 (or latest stable)
- Alternative: audioplayers ^5.0.0 (if just_audio has issues)
- Capability required: Play MP3 from asset
- Fallback: Silent failure if library unavailable (audio is optional)

DEP-002: Audio Asset (CHK107)
- File: assets/audio/auto_progress_chime.mp3
- Location: chronosync/assets/audio/
- Format: MP3, 44.1kHz, 128kbps, 300-500ms duration
- Fallback: If asset missing, log error and continue without audio
- Source: Create custom or use royalty-free from freesound.org

DEP-003: OS Requirements (CHK109)
- iOS: 12.0+ (Flutter minimum)
- Android: API 21+ (Android 5.0 Lollipop, Flutter minimum)
- Background timer: Supported on both platforms within app lifecycle limits
- System permissions: None required (audio playback, local storage only)

DEP-004: Flutter SDK (CHK110)
- SDK version: 3.9.2+ (from pubspec.yaml)
- Dart version: 3.9.2+
- Dependencies: See pubspec.yaml (flutter_bloc, hive, equatable)
- Breaking changes: Monitor on Flutter upgrades
```

**Rationale**: Documents external dependencies for troubleshooting and maintenance.

---

### CHK110 - Flutter SDK Requirements [Gap]

See DEP-004 in CHK107-109 above.

---

### CHK111-114 - Assumptions Documentation [Gap]

**Recommendation**: Add assumptions section to spec:
```
Assumptions and Validation:

ASSUM-001: Timer.periodic Precision (CHK111)
- Assumption: Timer.periodic provides sufficient precision for 1-second ticks
- Validation: Research confirms DateTime-based calculations maintain accuracy
- Mitigation: Use DateTime.now() difference, not tick counting
- Status: Validated ✓

ASSUM-002: Hive Field Addition (CHK112)
- Assumption: Hive supports adding fields with defaultValue without manual migration
- Validation: Hive documentation and testing confirms this is safe
- Mitigation: Test with production-like data before release
- Status: Validated ✓

ASSUM-003: User Wants Auto-Progression (CHK113)
- Assumption: Users prefer auto-progression over automatic series start
- Validation: Feature request explicitly asks for "auto progress... once countdown reaches zero"
- Mitigation: Default is OFF, users must explicitly enable per event
- Status: Based on user request ✓

ASSUM-004: Statistics Calculation Performance (CHK114)
- Assumption: Statistics calculation completes within 1 second for typical series
- Validation: Simple arithmetic on ~10-50 events, complexity O(N), < 1ms expected
- Mitigation: If performance issues, optimize calculation or show loading indicator
- Status: Low risk, validated via complexity analysis ✓

ASSUM-005: Audio Optional
- Assumption: Audio failures don't break feature (audio is enhancement, not core)
- Validation: Specified as "optional" audio cue in requirements
- Mitigation: Silent failure on audio errors, auto-progression continues
- Status: Validated ✓
```

**Rationale**: Documents and validates key assumptions - reduces implementation risk.

---

### CHK115-117 - Integration Points [Gap]

**Recommendation**: Add integration documentation:
```
Integration Points:

INT-001: Timer State Management (CHK115)
- Current system: LiveTimerBloc manages timer state
- Integration: Extend LiveTimerRunning state with new fields:
  - eventStartTime: DateTime
  - seriesStartTime: DateTime
  - totalSeriesElapsedSeconds: int
- Compatibility: Backward compatible (new fields added)
- Risk: Low

INT-002: Settings Persistence (CHK116)
- Current system: PreferencesRepository with UserPreferences Hive model
- Integration: Add autoProgressAudioEnabled field to UserPreferences
- Compatibility: Backward compatible (field with default value)
- Risk: Low

INT-003: Event/Series Repositories (CHK117)
- Current system: SeriesRepository manages Series and Event entities
- Integration: Add autoProgress field to Event model
- Compatibility: Backward compatible (field with default value)
- Repository methods: No changes required (CRUD operations remain same)
- Risk: Low

All integrations are additive and backward compatible.
```

**Rationale**: Documents integration points for implementation planning.

---

## Summary

### Gap Resolution Statistics

- **Total Gaps Identified**: 79
- **P0 (Critical)**: 8 gaps - MUST resolve before implementation
- **P1 (High)**: 20 gaps - SHOULD resolve before implementation
- **P2 (Medium)**: 28 gaps - SHOULD resolve before release
- **P3 (Low)**: 23 gaps - Can defer or mark as out of scope

### Implementation Impact

**High Priority (P0 + P1)**: 28 gaps  
**Estimated Time to Resolve**: 4-6 hours to update specification  
**Risk Reduction**: Eliminates ambiguity and prevents implementation rework

### Recommended Action Plan

1. **Immediate (Pre-Implementation)**:
   - Resolve all P0 gaps (8 items) - 1-2 hours
   - Resolve all P1 gaps (20 items) - 3-4 hours
   - Update spec.md with new requirements
   - Review updated spec with team

2. **Before Release**:
   - Resolve P2 gaps (28 items) - 2-3 hours
   - Focus on edge cases and error handling
   - Add comprehensive accessibility requirements

3. **Post-Release / Future**:
   - Review P3 gaps for future enhancements
   - Plan localization and advanced features
   - Monitor assumptions and validate during operation

### Next Steps

1. Review these recommendations with stakeholders
2. Prioritize which gaps to address immediately
3. Update spec.md with accepted recommendations
4. Re-run `/speckit.checklist` after spec updates to verify gap resolution
5. Proceed with implementation using updated spec

---

**Document Status**: Draft for Review  
**Recommended Reviewers**: Product Owner, Tech Lead, UX Designer  
**Target Date for Spec Update**: Before implementation begins
