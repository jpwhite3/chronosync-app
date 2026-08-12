# Development Command Reference

Run these recipes from the repository root. `make help` is generated from the
`Makefile` and remains authoritative; this page adds context and requirements.

## Setup and Discovery

| Command | Purpose |
| --- | --- |
| `make help` | List recipes and common overrides. |
| `make makefile-check` | Dry-run primary recipes to catch Makefile wiring errors. |
| `make setup` / `make install` | Install Flutter packages and locked relay packages. |
| `make app-deps` | Run `flutter pub get` only. |
| `make relay-deps` | Run locked `npm ci` only. |
| `make doctor` | Report Flutter, Xcode, CocoaPods, Node, npm, and device health. |
| `make outdated` | Report available Flutter and npm dependency updates without applying them. |
| `make devices` | List Flutter-recognized devices. |
| `make emulators` | List Flutter-recognized emulators. |
| `make launch-emulator EMULATOR=<id>` | Start one Flutter emulator. |

## Run Applications and Services

| Command | Purpose |
| --- | --- |
| `make run` | Run Flutter interactively, or on `DEVICE=<id>`. |
| `make run-web` | Run Chrome on `WEB_PORT` (default `8080`). |
| `make run-macos` | Run the native Mac app. |
| `make run-ios` | Boot and run on `IOS_SIMULATOR_ID` or the first available iPhone. |
| `make ios-simulators` | List available iPhone Simulator UDIDs. |
| `make ios-simulator` / `make simulator` | Boot and open a simulator without launching the app. |
| `make relay-dev` | Start local Wrangler development over its default protocol. |
| `make relay-dev-https` | Start local Wrangler HTTPS for end-to-end rooms. |

Add `RELAY_URL=https://...` to enable online-room behavior. Native commands
also require `WEB_URL=https://...` to create guest invitations.

## Generate and Format

| Command | Purpose |
| --- | --- |
| `make generate` | Generate Drift and Mockito Dart sources once. |
| `make generate-watch` | Watch and regenerate Dart sources continuously. |
| `make nearby-client` | Compile the iPhone-hosted nearby browser client. |
| `make nearby-client-check` | Compare the committed nearby bundle with its source. |
| `make drift-worker` | Compile the browser Drift worker. |
| `make drift-worker-check` | Compare the committed worker with its source. |
| `make branding-assets` | Generate iOS, Mac, and web icons from the brand SVG. |
| `make branding-assets-check` | Compare committed icons byte-for-byte. |
| `make format` | Format Dart source, tests, and tools. |
| `make format-check` | Fail if those Dart files are not formatted. |

Branding generation additionally needs `rsvg-convert` and ImageMagick's
`magick`. Never hand-edit generated source or compiled bundles.

## Analyze and Test

| Command | Purpose |
| --- | --- |
| `make analyze` | Generate Dart sources and run `flutter analyze`. |
| `make lint` | Check Dart formatting/analyzer and relay TypeScript. |
| `make test-flutter` | Run the complete Flutter VM suite. |
| `make test-focus TEST=<path>` | Run one Flutter test. |
| `make tdd TEST=<path>` | Alias for the focused red–green–refactor loop. |
| `make test-coverage` | Write Flutter coverage to `chronosync/coverage/lcov.info`. |
| `make test-browser` | Run selected portability/fullscreen tests in Chrome. |
| `make test-ios-native` | Build and run iOS `RunnerTests` on a simulator. |
| `make macos-configure` | Configure the Mac Xcode workspace for native tests. |
| `make test-macos-native` | Run macOS `RunnerTests`. |
| `make test-native` | Run both Apple-native suites. |
| `make relay-test` | Run relay Vitest once. |
| `make relay-test-watch` | Run relay Vitest in watch mode. |
| `make relay-typecheck` | Run strict TypeScript checks without emit. |
| `make relay-check` | Audit, type-check, and test the relay. |
| `make test` | Run Flutter VM, selected Chrome, and relay suites. |
| `make test-all` | Run `make test` plus native Apple suites. |

Use `TEST_ARGS='--name "pattern"'` or other supported Flutter test arguments to
narrow a test. See [Testing](testing.md) for expected coverage and manual QA.

## Build and Verify Artifacts

| Command | Purpose |
| --- | --- |
| `make build-web` | Build, sanitize, and verify the release PWA. |
| `make sanitize-web-release` | Remove compiler metadata from an existing web build. |
| `make verify-web-release` | Reject source maps and local paths in a web build. |
| `make build-web-debug` | Build a debug web app. |
| `make build-ios-simulator` | Build the unsigned debug Simulator app. |
| `make build-ios-release` | Build iOS release with local Xcode signing. |
| `make build-macos-debug` | Build native Mac debug. |
| `make build-macos-release` | Build and verify native Mac release. |
| `make verify-macos-release` | Verify an existing Mac release signature and entitlements. |
| `make build-native` | Build iOS Simulator and Mac release. |
| `make build` | Build all MVP targets; requires macOS. |

Release output paths and signing constraints are documented in
[Local development](local-development.md#build-artifacts) and
[Release guide](release.md).

## Repository Quality Gates

| Command | Purpose |
| --- | --- |
| `make check-app` | Generate, format-check, verify bundles, analyze, and test Flutter/browser code. |
| `make check-relay` | Run all relay checks. |
| `make check` | Run normal non-native app and relay gates. |
| `make ci` | Install dependencies, run normal checks, and verify web release. |
| `make ci-native` | Run Apple-native tests and verify Mac release. |

## Deploy and Clean

| Command | Purpose |
| --- | --- |
| `make relay-deploy CONFIRM_DEPLOY=1` | Deploy the reviewed relay configuration. |
| `make clean` | Run `flutter clean` for build products and ephemeral metadata. |
| `make clean-codegen` | Remove build_runner's generated cache. |

Deployment changes external state. Review `relay/wrangler.toml` and follow
[Relay development](relay.md#production-configuration) before running it.

## Variables

| Variable | Default | Use |
| --- | --- | --- |
| `DEVICE` | empty | Flutter target selected by `make run`. |
| `EMULATOR` | empty | Flutter emulator selected by `make launch-emulator`. |
| `IOS_SIMULATOR_ID` | first available iPhone | Simulator for iOS run/test recipes. |
| `TEST` | empty | Flutter test path relative to `chronosync/`. |
| `TEST_ARGS` | empty | Additional Flutter test flags. |
| `RELAY_URL` | empty | HTTPS online relay URL compiled into the app. |
| `WEB_URL` | empty | HTTPS PWA URL compiled into native apps. |
| `WEB_PORT` | `8080` | Chrome development port. |
| `CONFIRM_DEPLOY` | `0` | Must be `1` for relay deployment. |
| `FLUTTER`, `DART`, `NPM` | command names on `PATH` | Advanced executable overrides. |
