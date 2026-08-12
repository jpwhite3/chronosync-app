# Contributing to ChronoSync

Thank you for helping improve ChronoSync. The project is in active development,
so early discussion is especially valuable for changes to protocols, storage,
permissions, or product scope.

## Before You Start

Search existing issues and `specs/` for related work. Open an issue before a
large change so maintainers can confirm the approach. For security reports,
follow [SECURITY.md](SECURITY.md) and establish a private channel before sharing
details.

The repository does not yet have an open-source license or defined inbound
contribution terms. External pull requests will not be merged until both are in
place; please contribute issues and design feedback in the meantime. The
workflow below applies to the owner's authorized collaborators now and to
external contributors after that policy is established.

## Set Up the Repository

Follow the [developer quick start](docs/development/quickstart.md). From the
repository root, the usual setup is:

```sh
make doctor
make setup
make check
```

`make help` is the authoritative command list. Flutter and Dart commands run
from `chronosync/`; relay commands run from `relay/`.

## Work Test First

Every behavior change follows red–green–refactor:

1. **Red:** Add the smallest test that demonstrates the desired observable
   behavior and confirm it fails for the expected reason.
2. **Green:** Make the smallest production change that passes the focused test.
3. **Refactor:** Improve the design while the focused test remains green, then
   run the broader relevant suite.

For a focused loop:

```sh
make tdd TEST=test/domain/session/live_session_test.dart
make tdd TEST=test/path/file_test.dart TEST_ARGS='--name "expected behavior"'
```

Bug fixes require a regression test. Do not remove or weaken assertions to make
a change pass. For native or visual behavior that cannot be fully automated,
add the closest contract, widget, or native test first and document the manual
acceptance check in the pull request.

## Respect the Architecture

- `presentation/` owns screens, responsive layouts, and reusable widgets.
- `logic/` coordinates use cases and maps domain state to the UI.
- `domain/` owns immutable models, commands, protocols, and reducer behavior.
- `data/` owns Drift repositories, transports, crypto, cues, and portability.
- `core/` contains shared clocks, serialization, and platform utilities.

`SessionReducer` is the only domain component that transitions live-session
state. Keep the host authoritative and derive timers from timestamps; do not
broadcast periodic timer ticks. The older `domain/run_session/`,
`logic/live_timer_bloc/`, and `logic/series_bloc/` paths exist for migration or
legacy coverage and should not receive new product behavior.

See [Architecture](docs/development/architecture.md) before changing these
contracts.

## Style and Generated Files

Dart uses two-space indentation and `dart format`. Name files and directories
`snake_case`, types `UpperCamelCase`, and members `lowerCamelCase`. Follow the
existing TypeScript style in `relay/` and keep its strict type checks passing.

Run `make generate` after changing Drift declarations or Mockito annotations.
Do not hand-edit `*.g.dart`, `*.mocks.dart`, or compiled bundles. Rebuild and
commit the appropriate artifact when its source changes:

```sh
make nearby-client     # assets/nearby_client/client.js
make drift-worker      # web/drift_worker.js
make branding-assets   # native and web app icons
```

## Verify the Change

During development, run the narrowest useful test. Before review, run:

```sh
make check
```

This includes `make workflow-check`, which lints Actions YAML and rejects
mutable action tags. GitHub's `CI required` check must pass before `main` can be
updated; do not bypass or weaken a gate to merge a change.

On a Mac with Xcode and an iOS Simulator, also run:

```sh
make ci-native
```

Use `make test-coverage` when inspecting coverage; no numeric threshold is
configured, but new behavior must be exercised. UI work should be checked at
compact, two-pane, and wide layouts, with keyboard navigation, screen readers,
large text, reduced motion, and non-color status cues considered.

## Commits and Pull Requests

Keep commits focused and use a concise imperative subject. Conventional Commit
prefixes are preferred, for example:

```text
feat(session): add controller acknowledgement status
fix(web): preserve plans after worker restart
test(relay): reject a duplicated command id
docs: clarify native signing setup
```

Pull requests should:

- explain the user-visible behavior and motivation;
- link the issue or relevant `specs/<number>-<feature>/` document;
- list the exact verification commands and manual checks performed;
- include screenshots or recordings for visible changes on each affected size;
- call out migrations, protocol changes, generated files, permissions, and
  platform-specific behavior;
- avoid unrelated formatting or cleanup.

Never include real invitations, capabilities, room secrets, private plan data,
or raw device identifiers in commits, logs, fixtures, screenshots, or issues.

## Documentation

Update user documentation when behavior changes and developer documentation
when commands, architecture, configuration, or release procedures change.
Screenshots belong under `docs/assets/` and must use fictional, non-sensitive
data. Add noteworthy user-facing changes to the `[Unreleased]` section of
[CHANGELOG.md](CHANGELOG.md).
