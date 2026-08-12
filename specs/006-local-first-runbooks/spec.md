# Feature Specification: Local-First Runbooks for In-Person Event Teams

**Status**: Superseded by `specs/007-shared-runbook-mvp/`
**Product**: ChronoSync

## Product Intent

ChronoSync coordinates an event team that is physically together. One host starts
an ordered runbook; nearby team devices join with a QR code and see the same
current step, countdown, elapsed time, and activity feed. The product works with
no account, Internet connection, or hosted service.

The host device is the temporary source of truth for an active session. Every
participant retains an encrypted local copy of the runbook and session activity.

## MVP Users

- **Host**: Builds a runbook, opens the nearby session, and advances it.
- **Operator**: Joins a session, sees the live state, and acknowledges a step.
- **Display operator**: Joins an iPad as a large, read-only operations display.

## MVP User Flows

### Host a runbook

1. The host selects an existing runbook and taps **Host live runbook**.
2. ChronoSync creates a local session, shows a QR join code, and lists nearby
   team members as they join.
3. The host starts the first step. Only the host can start, advance, or finish
   the shared session.

### Join a runbook

1. An operator opens ChronoSync and taps **Join live runbook**.
2. They scan the host's QR code, choose a display name, and accept the nearby
   connection prompt.
3. They receive the session snapshot, then see the current and next steps.

### Run the event

1. All participants see the current instruction, a countdown, elapsed time, and
   overtime state.
2. The host advances manually or uses the existing auto-advance option.
3. Operators can acknowledge the current step; the host and displays see who
   acknowledged it and when.
4. On completion, every device retains the same local activity export.

### Reconnect

1. A disconnected participant keeps the last verified state and sees
   **Reconnecting nearby**.
2. While the host remains available, the participant reconnects using the saved
   session invitation and requests all changes after its last revision.
3. If the host cannot provide the requested history, it sends a fresh snapshot.
4. Host loss ends shared control for the MVP. Participants retain a read-only
   cached session and can export it; host failover is deliberately deferred.

## Functional Requirements

- A runbook is an ordered list of titled, timed steps.
- Live state always shows the current step, next step, countdown, elapsed time,
  and clear overtime treatment.
- The host is the only authoritative source of progression. Participant actions
  are acknowledgements, never conflicting advances.
- A QR invitation transfers only the details necessary to join one local
  session; it must expire when the host ends the session.
- Joining, synchronizing, and running a session must work without Internet
  access.
- Participants receive a full snapshot when joining and revisioned changes while
  connected.
- A participant may reconnect without rescanning while the host session is open.
- Each activity record includes the actor, action, step, host-issued timestamp,
  and session revision.
- The iPad display can join as display-only and must expose no progression
  controls.
- Phone and paired watch notifications remain local to the device. No remote
  notification delivery is promised.

## Non-Goals

- Accounts, remote sharing, cloud backups, browser-to-browser live sessions,
  remote push notifications, and recovery after device loss.
- Medication, caregiver, or emergency workflows.
- Host election, multi-host editing, and automatic conflict resolution.
- Analytics beyond a locally exportable activity log.

## Experience Rules

- The main action is always large, explicit, and reachable in one tap.
- Status uses both text and color; red means overtime, never the only signal.
- All live timing derives from timestamps, not from a counter that pauses when
  the app is backgrounded.
- The app must present a clear disconnected state instead of implying live sync.

## Success Criteria

- A host can create a five-step runbook, open a session, and start it in under
  two minutes.
- A nearby participant can join by QR and receive the live state without
  Internet access.
- The countdown remains accurate after backgrounding and resuming a device.
- A completed session can be exported from every participating device.
