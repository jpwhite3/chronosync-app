# Developer Quick Start

This guide gets the web, native Mac, or iPhone Simulator app running from a
fresh checkout.

## 1. Install Prerequisites

All contributors need:

- Git and GNU-compatible `make`;
- Flutter **3.41.9** on the stable channel;
- a Dart SDK compatible with **`^3.11.5`** (included with Flutter);
- Node.js **22** and npm;
- Chrome for web development and browser tests.

iPhone and Mac development additionally require:

- macOS with Xcode and its command-line tools;
- an iOS Simulator runtime installed through Xcode;
- CocoaPods;
- iOS 13/macOS 10.15 or newer as deployment targets.

The CI workflow pins Flutter and Node. If a newer local toolchain behaves
differently, reproduce the failure with the pinned versions before changing
project code.

## 2. Clone and Install

```sh
git clone https://github.com/jpwhite3/chronosync-app.git
cd chronosync-app
make doctor
make setup
```

`make doctor` reports Flutter, Xcode, CocoaPods, Node, and connected-device
health. Resolve relevant errors before proceeding. `make setup` runs
`flutter pub get` for the app and locked `npm ci` for the relay.

## 3. Launch a Target

### Web/PWA

```sh
make run-web
```

Chrome opens the development server on `http://localhost:8080`. Sequences and
history persist in the browser's local Drift SQLite/WASM database.

### Native Mac

```sh
make run-macos
```

The first build may take longer while CocoaPods and Xcode prepare native
artifacts.

### iPhone Simulator

```sh
make ios-simulators
make run-ios
```

The recipe selects and boots the first available iPhone. To choose one:

```sh
make run-ios IOS_SIMULATOR_ID=<simulator-udid>
```

### Physical iPhone or Another Flutter Device

```sh
make devices
make run DEVICE=<flutter-device-id>
```

A physical iPhone requires normal Apple signing and trust configuration.
Nearby hosting must be validated on physical hardware; the simulator is not a
substitute for Bonjour, local-network permission, haptics, or backgrounding.

## 4. Run the Quality Gates

```sh
make check
```

This generates Dart sources, checks formatting and generated browser bundles,
runs the analyzer, executes Flutter VM and Chrome tests, audits and type-checks
the relay, and runs Vitest. On a configured Mac, add:

```sh
make ci-native
```

That command runs iOS and macOS XCTest and verifies a sandboxed Mac release.

## 5. Make a Test-Driven Change

Choose a test path relative to `chronosync/`:

```sh
make tdd TEST=test/domain/session/live_session_test.dart
```

Write the failing test, make it pass with the smallest implementation, then
refactor. Finish with the broader relevant suite and `make check`. Read
[Testing](testing.md) and [Contributing](../../CONTRIBUTING.md) before opening a
pull request.

## Next Steps

- Configure anonymous online rooms in [Local development](local-development.md).
- Understand state ownership in [Architecture](architecture.md).
- Read [Troubleshooting](troubleshooting.md) when a prerequisite or build fails.
