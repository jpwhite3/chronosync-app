# Testing and Quality Gates

ChronoSync uses test-driven development for every behavior change. Tests are
part of the design: they define observable contracts across timing, storage,
transport, native integration, and responsive UI.

## Red–Green–Refactor

1. **Red:** Write the smallest test for the intended behavior. Run it and
   confirm it fails for the expected reason—not because setup is broken.
2. **Green:** Implement only enough production code to pass that test.
3. **Refactor:** Improve names and structure while the focused test stays green.
4. Run the containing suite, then repository-wide gates before review.

Select a Flutter test relative to `chronosync/`:

```sh
make tdd TEST=test/domain/session/live_session_test.dart
make tdd TEST=test/path/file_test.dart TEST_ARGS='--name "observable behavior"'
```

For relay changes, keep Vitest running:

```sh
make relay-test-watch
```

Bug fixes must begin with a reproducing regression test. Never delete, skip, or
weaken a valid assertion simply to turn the build green.

## Test Suites

| Command | Coverage |
| --- | --- |
| `make test-flutter` | Complete Flutter VM suite after code generation. |
| `make test-browser` | Chrome-only archive, portability, and fullscreen behavior. |
| `make relay-test` | Cloudflare Worker/Durable Object Vitest suite. |
| `make test-ios-native` | `RunnerTests` on an available iPhone Simulator. |
| `make test-macos-native` | macOS `RunnerTests` through Xcode. |
| `make test` | Flutter VM, selected Chrome tests, and relay Vitest. |
| `make test-all` | Normal suites plus both Apple-native XCTest suites. |
| `make test-coverage` | Flutter suite with `chronosync/coverage/lcov.info`. |

Pass `IOS_SIMULATOR_ID=<udid>` to select the simulator used by iOS XCTest.
Native test recipes disable code signing.

## What to Test

Match tests to the boundary being changed:

- **Domain:** reducer transitions, roles, revisions, idempotency, timer
  derivation, pause accounting, adjustments, auto-advance, and cue decisions.
- **Data:** Drift transactions, migrations, recovery policy, serialization,
  import collision handling, bounded archive parsing, and export round trips.
- **Transport:** the in-memory contract tests plus the targeted LAN and online
  transport suites; cover reconnects, duplicate/reordered/delayed messages,
  stale-host behavior, role changes, and revocation.
- **Logic:** controller orchestration, serialized host commands, scheduled
  starts, persistence, cues, and clock offsets.
- **Presentation:** widget interactions, semantic labels, keyboard navigation,
  responsive widths, focus visibility, reduced motion, and layout overflow.
- **Native:** method/event channels, nearby host lifecycle, fullscreen, sleep
  prevention, permissions, and quit/background behavior.
- **Relay:** CORS, credentials, schema validation, room capacity, rate limits,
  host leases, revisions, retention, role overrides, revocation, and expiry.

Use deterministic clocks and transports instead of real time or network access
where possible. Assert public behavior rather than private implementation
details.

## UI and Accessibility Verification

Automate widget, semantic, and golden checks where stable. For visible changes,
also inspect:

- compact layouts below 600 px;
- two-pane layouts from 600–1023 px;
- wide layouts at 1024 px and above;
- 44-point minimum touch targets and large Dynamic Type;
- VoiceOver/screen-reader names, roles, values, and traversal order;
- keyboard-only operation and visible focus;
- contrast, reduced motion, and status cues that do not rely only on color;
- Host, Controller, Participant, and Display roles.

Attach screenshots or recordings for affected form factors to the pull request.

## Physical-Device Acceptance

Simulator and widget success do not qualify the complete nearby workflow. Test
on a physical iPhone and at least one guest device for:

- Internet unavailable but same Wi-Fi available;
- local-network permission and QR/link join;
- host foreground/background transitions and screen-awake behavior;
- Wi-Fi interruption and automatic reconnect;
- simultaneous controller commands and role revocation;
- invitation expiry, audio, native haptics, and VoiceOver;
- long-running sessions and device sleep/thermal behavior.

Sanitize all screenshots and logs. Never capture a real invitation or token.

## Pre-Review Gates

Run the normal repository gate on every platform:

```sh
make check
```

On a configured Mac, run the native gate too:

```sh
make ci-native
```

`make ci` installs locked dependencies, runs normal checks, and verifies a web
release. CI separately runs Flutter checks on Linux, Apple builds/tests on
macOS, and relay checks with Node.js 22.

There is no numeric coverage threshold. That is not permission to leave new
behavior untested: coverage should follow risk, branches, and contracts.

## Test File Conventions

Mirror the production path under `chronosync/test/`, name files
`<subject>_test.dart`, and group cases by observable behavior. Relay tests live
under `relay/test/` and use `*.test.ts`. Keep fixtures fictional, minimal, and
free of credentials or private event data.
