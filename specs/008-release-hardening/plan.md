# Implementation Plan: Release Hardening

## Completed Slice: Startup and Solo Recovery

The recovery design keeps the existing version-1 Drift schema. Recovery kinds
are stored in `AppMetadataRecords` beside each unfinished session and updated in
the same transaction as its session snapshot and activity rows.

`DriftSessionHistoryRepository.prepareStartupRecovery` selects the newest safe
solo snapshot for the current host device and removes other unfinished rows.
`LiveSessionController.recoverSolo` restores local authority only when the host
device matches, no participants are present, and activity history is complete.
Timestamp-derived calculations preserve running downtime and paused freezing.

Bootstrap loads the candidate after device identity, exposes a generic retry
state for initialization failures, and runs one ordered startup flow. A deep
link invitation is handled first. The recovery dialog then prepares audio and
controller state from the Resume gesture, or deletes the candidate on Discard.
The existing `SessionFlowScreen` renders the recovered controller from its
embedded `PlanSnapshot`.

## TDD Evidence

Behavior was driven and retained by focused tests:

- `test/data/repositories/session_history_repository_test.dart`: newest safe
  solo selection, shared/foreign snapshot cleanup, deletion, and ended-history
  retention.
- `test/logic/live_session/live_session_controller_test.dart`: running downtime,
  paused freezing, local-only recovery, authority rejection, and cleanup after
  failed initialization.
- `test/app_recovery_test.dart`: explicit Resume/Discard UI, audio preparation,
  persistence, live-view navigation, compact-height layout, and confirmed
  system-Back handling.
- `test/presentation/screens/session_flow_screen_test.dart`: a recovered waiting
  solo session opens live rather than entering a shared lobby.
- `test/bootstrap_test.dart`: sanitized initialization failure and retry.

Run each focused test during red-green-refactor, then finish with:

```sh
cd chronosync
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Remaining Delivery Order

1. Complete the accessibility and responsive-layout matrix.
2. Establish generated localization and extract core workflow copy.
3. Add deterministic scale, duration, and reconnect acceptance tests.
4. Finish privacy manifests, disclosures, signing, production origins, and
   store assets.
5. Run physical-device, browser, relay, and representative-team beta scenarios.
