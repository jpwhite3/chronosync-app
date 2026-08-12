# Repository Guidelines

## Project Structure & Module Organization

The Flutter application lives in `chronosync/`; run Flutter and Dart commands from that directory:

- `lib/presentation/` contains screens and reusable widgets.
- `lib/logic/` contains BLoCs, Cubits, events, and states.
- `lib/domain/` defines core runtime behavior and protocols.
- `lib/data/` contains models, repositories, services, and platform channels.
- `lib/core/` holds shared infrastructure such as clock abstractions.
- `test/` mirrors `lib/` for unit, BLoC, repository, and widget tests.
- `assets/audio/` contains bundled sounds; platform runners live in `android/`, `ios/`, `macos/`, `linux/`, and `windows/`.
- `relay/` contains the TypeScript Cloudflare Worker, Durable Object, and Vitest suite.

Feature requirements, plans, contracts, and task lists belong in `specs/<number>-<feature-name>/`.

## Build, Test, and Development Commands

From `chronosync/`, use:

```sh
flutter pub get                         # Install dependencies
flutter run                             # Run on a selected device
flutter analyze                         # Apply analyzer and lint rules
flutter test                            # Run the complete test suite
flutter test test/logic/live_timer_bloc # Run a focused test directory
dart format lib test                    # Format Dart sources and tests
dart run build_runner build --delete-conflicting-outputs
```

Run code generation after changing Mockito annotations or Drift database declarations. Do not manually edit `*.mocks.dart`, `*.g.dart`, or other generated files.

From `relay/`, use `npm ci`, `npm run typecheck`, and `npm test`.

## Coding Style & Naming Conventions

Use Dart’s standard two-space indentation and keep code `dart format` compliant. The analyzer enforces `flutter_lints`, explicit types, final locals where possible, const constructors, and camel-case type names. Name files and directories `snake_case`, types `UpperCamelCase`, and members `lowerCamelCase`. Keep presentation, state management, domain logic, and persistence concerns in their existing layers.

## Testing Guidelines

Use test-driven development for every behavior change:

1. **Red:** Write the smallest test that describes the intended observable behavior and confirm it fails for the expected reason.
2. **Green:** Implement only enough production code to make that test pass.
3. **Refactor:** Improve the design while keeping the focused test green, then run the broader relevant suite.

Bug fixes must begin with a reproducing regression test. Do not weaken or remove assertions merely to make a change pass. For native integrations or visual behavior that cannot be fully automated, add the closest contract, widget, or native test first and document the remaining manual acceptance check.

Flutter tests use `flutter_test`, `bloc_test`, and Mockito; relay tests use Vitest. Name files `<subject>_test.dart`, mirror the production path, and group cases by observable behavior. Exercise BLoC state transitions, repository persistence, transport contracts, and widget interactions as appropriate. Run the focused test during the red–green loop, then finish with `flutter analyze` and `flutter test`. No numeric coverage threshold is configured; new behavior must still be covered before review.

## Commit & Pull Request Guidelines

History favors concise, imperative subjects and Conventional Commit prefixes such as `feat:`, `fix:`, `test:`, and `docs:`; optional scopes are welcome (for example, `feat(native): ...`). Keep each commit focused.

Pull requests should summarize behavior changes, link the relevant issue or `specs/` feature, list verification commands, and note platform-specific impact. Include screenshots or recordings for visible UI changes and call out migrations, generated files, or new permissions explicitly.
