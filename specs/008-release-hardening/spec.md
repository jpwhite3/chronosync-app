# Feature Specification: Release Hardening

**Status**: Phase 4 in progress; crash-recovery slice complete
**Product**: ChronoSync

## Intent

Phase 4 turns the implemented MVP into a release-ready iPhone, Mac, and web
product. The first completed slice protects local work when startup or a live
solo session is interrupted, without weakening shared-session authority.

## Completed Crash-Recovery Requirements

- Persist each session with an explicit recovery kind: solo, shared host, or
  shared participant. Never infer a solo session from an empty participant
  list.
- At startup, offer only the newest non-ended solo session owned by the current
  device and retaining complete local history. Preserve its ID, revision,
  embedded Plan snapshot, activities, and current Step.
- Require an explicit, non-dismissible **Resume** or **Discard session** choice.
  Discard removes the unfinished session and its recovery metadata.
- A recovered running session derives elapsed and remaining time from its
  original UTC timestamps, so downtime counts as running time. A recovered
  paused session remains frozen until the user resumes it from the live view.
  A waiting solo session reopens at its first Step.
- Do not synthesize a recovery activity or silently overwrite the original
  Plan. Recovery is process restoration, not a runbook state transition.
- Purge unfinished shared-host and shared-participant snapshots during startup.
  They are not resumable because transport credentials, encryption context,
  and host authority are intentionally ephemeral. Ended history remains.
- Process an invitation link before presenting local recovery, preventing two
  startup routes from competing.
- If dependency initialization fails, hide internal error details and present a
  generic **Retry** action. A failed Resume or Discard keeps the saved session
  available and offers another attempt.
- Release timers, binding observers, and cue subscriptions if recovery
  preparation fails or the startup route disappears before ownership transfers
  to the live screen.
- Route system Back through the confirmed end/disconnect flow while a session
  is unfinished; never leave an inaccessible active snapshot in-process.

## Acceptance Criteria

- Recovery never grants authority to another device or converts shared state
  into a solo session.
- Resume and Discard work on iPhone, Mac, and web-local persistence.
- Running and paused timing behavior is deterministic under a controlled clock.
- Existing ended history and normal invitation joining remain unchanged.
- Short-height empty-library and recovery layouts remain scrollable and free of
  render overflow.

## Remaining Phase 4 Scope

Physical-device and production-environment validation, the full accessibility
matrix, localization infrastructure, privacy and store-release artifacts, and
250-Step/50-connection/eight-hour performance qualification remain pending.
