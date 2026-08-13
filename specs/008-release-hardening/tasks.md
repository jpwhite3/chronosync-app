# Release Hardening Tasks

## Crash-Recovery Slice — Complete

- [x] T001 Write repository tests for solo selection, shared cleanup, device
  ownership, deletion, and ended-history retention.
- [x] T002 Persist explicit solo, shared-host, and shared-participant recovery
  metadata transactionally with session snapshots.
- [x] T003 Select only the newest authoritative solo snapshot and purge all
  non-resumable unfinished snapshots at startup.
- [x] T004 Write controller tests for running downtime, paused freezing, and
  invalid recovery authority.
- [x] T005 Add safe `LiveSessionController.recoverSolo` restoration without a
  synthetic activity, new ID, or revision, including cleanup on failed
  preparation.
- [x] T006 Write widget tests for Resume, Discard, audio preparation,
  persistence, recovered live navigation, compact-height layout, and system
  Back.
- [x] T007 Implement the non-dismissible recovery dialog with retryable failure
  handling and destructive-action copy.
- [x] T008 Serialize startup routing so invitation handling precedes recovery.
- [x] T009 Write and implement a generic, retryable bootstrap error state that
  does not expose storage internals.
- [x] T010 Verify recovered waiting sessions open in the solo live experience.
- [x] Verify analyzer, 257 Flutter tests, 17 browser tests, iOS/macOS native
  tests, release web, iOS Simulator, and signed Mac release builds.

## Release Validation — Pending

- [ ] T011 Complete TestFlight coverage on physical current and previous-major
  iPhones, including termination during running and paused solo sessions.
- [ ] T012 Validate native Mac sleep/wake, termination recovery, fullscreen
  Display, online hosting, import/export, and sound cues.
- [ ] T013 Exercise production PWA and relay origins, invitation precedence,
  reconnect, revocation, expiry, Wi-Fi interruption, and host backgrounding.
- [ ] T014 Run representative beta sessions across workshops, classes,
  training, ceremonies, service teams, productions, drills, workouts, and
  games; record defects and acceptance results.

## Accessibility and Localization — Pending

- [ ] T015 Test all roles and breakpoints with keyboard-only navigation,
  screen readers, visible focus, reduced motion, and non-color status cues.
- [ ] T016 Test Dynamic Type/text scaling through at least 200–300 percent and
  resolve overflow without reducing the 44-point target size.
- [ ] T017 Recheck WCAG 2.2 AA contrast, semantics, and responsive golden tests.
- [ ] T018 Add generated Flutter localization and extract core Sequence,
  lobby, live-session, recovery, history, and error strings.

## Privacy, Performance, and Release — Pending

- [ ] T019 Add and validate Apple privacy manifests, privacy disclosures, data
  retention language, and account-free product policy.
- [ ] T020 Finalize bundle identifiers, signing, versions, production relay/PWA
  configuration, App Store metadata, and web release assets; recapture product
  and tutorial screenshots with Sequence, Interval, and Timekeeper language.
- [ ] T021 Qualify 250-Interval Sequences, 50 connected devices, eight-hour
  sessions, and LAN/online update latency targets with deterministic tests and
  profiling.
- [ ] T022 Run final format, analyze, Flutter/relay/native tests, release builds,
  signing checks, and manual acceptance checklist before release approval.
