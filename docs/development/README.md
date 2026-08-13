# Developer Handbook

This handbook is the source of truth for building, testing, and maintaining
ChronoSync. Run commands from the repository root unless a guide explicitly
says otherwise.

## Start Here

1. [Quick start](quickstart.md) — install prerequisites, clone, verify the
   toolchain, and launch each supported app.
2. [Local development](local-development.md) — configuration, generated code,
   online rooms, build outputs, and common workflows.
3. [Command reference](commands.md) — every Make recipe, variable, and artifact
   workflow in one place.
4. [Testing](testing.md) — the required TDD cycle and complete test matrix.
5. [Screenshot maintenance](screenshots.md) — canonical fixtures, capture sizes,
   platform commands, and documentation image checks.
6. [Architecture](architecture.md) — layers, domain contracts, persistence,
   synchronization, and security boundaries.
7. [Continuous integration](continuous-integration.md) — GitHub Actions jobs,
   security automation, artifacts, permissions, and failure diagnosis.

## Operate and Ship

- [Relay development](relay.md) — run, test, configure, and deploy the
  Cloudflare Worker and Durable Object.
- [Release guide](release.md) — development release checklist for web, iPhone,
  and Mac.
- [Troubleshooting](troubleshooting.md) — fixes for toolchain, simulator,
  generated-code, database, and connectivity failures.

## Project Policies

- [Contributing](../../CONTRIBUTING.md)
- [Security](../../SECURITY.md)
- [Support](../../SUPPORT.md)
- [Changelog](../../CHANGELOG.md)
- [Repository agent guidance](../../AGENTS.md)

## Command Map

| Goal | Command |
| --- | --- |
| Show every recipe | `make help` |
| Check the toolchain | `make doctor` |
| Install all dependencies | `make setup` |
| Run web, Mac, or iPhone | `make run-web`, `make run-macos`, `make run-ios` |
| Run a focused TDD test | `make tdd TEST=test/path/file_test.dart` |
| Run normal quality gates | `make check` |
| Reproduce cross-platform CI | `make ci` |
| Run Apple-native gates | `make ci-native` |
| Build all MVP targets | `make build` |

The root `Makefile` is authoritative. Direct Flutter/Dart commands run from
`chronosync/`; direct npm commands run from `relay/`.
