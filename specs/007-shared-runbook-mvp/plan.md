# Implementation Plan: Shared Runbook MVP

## Architecture

- Immutable `Plan`, `Step`, `PlanSnapshot`, `LiveSession`, `Participant`,
  `Activity`, and `Invitation` models define versioned JSON contracts.
- Drift owns Plans, history, metadata, and transactional legacy Hive migration.
- `SessionReducer` is the only authority for revisioned session behavior.
- `LiveSessionController` derives time, persists snapshots, emits cues, binds
  authenticated transport connections to device identities, and serializes
  host commands.
- `SessionTransport` has in-memory, nearby LAN, and online relay
  implementations with the same encrypted envelope contract.

## Delivery

1. Establish timestamp-derived domain behavior, automated checks, responsive
   design tokens, and user terminology.
2. Deliver local Plans, solo sessions, history, `.chronosync` portability, CSV,
   and browser persistence.
3. Add iPhone Bonjour/Network.framework hosting and a packaged offline browser
   client over authenticated WebSockets.
4. Add the full PWA and a Cloudflare Durable Object relay for anonymous rooms.
5. Ship a native Mac target with the full local and online experience, native
   invitation entry, nearby joining, sandboxed network/file access, and an
   automated release build. Nearby hosting remains iPhone-only.
6. Harden migration fidelity, accessibility, clock correction, heartbeat
   timeouts, reconnect credentials, presence, invitation expiry, and snapshot
   recovery.

## Configuration

Online hosting is enabled only with `CHRONOSYNC_RELAY_URL`. Native invitation
links additionally require `CHRONOSYNC_WEB_URL`. Both must be HTTPS outside
loopback development. The host remains authoritative; the relay stores only
encrypted snapshots and expires connection capabilities after 24 hours.
macOS release builds enable sandboxed outbound networking and user-selected
file access for shared sessions and portable exports.

## Post-MVP

Build the Apple Watch companion in SwiftUI with WatchConnectivity. It will show
current/next Steps, timers, haptics, Got it, and a small Controller action set.
Role management, jumps, and ending remain on iPhone.
