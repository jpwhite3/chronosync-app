# Relay Development and Operations

The optional `relay/` package provides anonymous online room coordination with
a Cloudflare Worker and one Durable Object per room. It is not a timer authority
and never decrypts application payloads. The active ChronoSync host validates
commands, advances state, and publishes canonical encrypted snapshots.

The protocol details and frame examples in `relay/README.md` are canonical;
this guide focuses on contributor and operator workflows.

## Prerequisites

- Node.js 22 and npm;
- dependencies installed with `make relay-deps` or `npm ci` in `relay/`;
- a Cloudflare account and Wrangler authentication for deployment;
- an HTTPS ChronoSync PWA origin for production.

Locked tools and scripts are declared in `relay/package.json`.

## Run Locally

For relay-only development:

```sh
make relay-dev
```

Run Wrangler over HTTPS when exercising it from ChronoSync because the app
rejects insecure relay URLs:

```sh
make relay-dev-https
```

Trust Wrangler's local certificate if necessary. The default `make run-web`
origin is HTTP and therefore cannot produce an online invitation: online join
URLs require HTTPS even on loopback. Use Vitest for relay-only work, or serve a
ChronoSync build from a trusted HTTPS origin in `ALLOWED_ORIGINS` for complete
room testing. See [Local development](local-development.md#develop-online-rooms).

## Test and Type-Check

```sh
make relay-test            # Vitest once
make relay-test-watch      # Vitest watch mode
make relay-typecheck       # TypeScript without emit
make relay-check           # npm audit, type-check, and tests
```

Add tests before implementation. Use the Cloudflare Vitest pool for Durable
Object behavior, and exercise malformed frames, roles, revisions, duplicate
messages, connection leases, retention bounds, expiry, and CORS. Tests must not
depend on a deployed Worker or real secrets.

## Request and Room Model

- `GET /health` returns a content-free health response.
- `POST /v1/rooms` creates a room and role capabilities.
- WebSocket connections provide protocol, role, capability, and opaque device
  token through subprotocols.
- A room accepts one active host, up to 50 guests, and up to 10 Timekeepers
  (`controller` in the protocol).
- The latest accepted encrypted snapshot is retained for reconnecting guests.
- Capabilities expire 24 hours after creation; storage also expires after 24
  hours without activity.
- Application heartbeats maintain a 30-second socket lease.

The host creates the application encryption key locally. It belongs in the
invitation fragment and is never returned to or stored by the relay.

## Logging and Data Handling

Do not add logging for:

- HTTP request bodies;
- WebSocket frames or ciphertext;
- capabilities, invitation fragments, or session keys;
- opaque device tokens or raw device IDs;
- Sequence titles, Intervals, participant names, or activity content.

Safe operational telemetry should be aggregate and content-free, such as
status codes, bounded counters, or latency distributions. Review any new
telemetry as a privacy and abuse-resistance change.

## Production Configuration

Before deployment:

1. Replace `ALLOWED_ORIGINS` in `relay/wrangler.toml` with the exact deployed
   HTTPS PWA origin. Scheme, host, and port must match.
2. Authenticate Wrangler to the intended Cloudflare account and verify the
   Worker name and Durable Object binding.
3. Configure Cloudflare edge rate limiting for `POST /v1/rooms`; in-room limits
   do not replace endpoint abuse protection.
4. Run `make relay-check` and the relevant app transport tests.
5. Review compatibility with the deployed PWA and native protocol version.

Deployment is intentionally guarded:

```sh
make relay-deploy CONFIRM_DEPLOY=1
```

Afterward, verify the deployed `GET /health`, create a disposable room from the
production PWA, join from a second platform, and exercise host loss/reconnect.
The Flutter client does not currently expose the relay's host-only `end_room`
operator frame; rely on fixed capability expiry and inactivity cleanup unless
you are deliberately testing that raw protocol with disposable credentials.
Do not paste the invitation into tickets or chat logs.

## Source Map

- `relay/src/index.ts` — health, room creation, WebSocket upgrade, and CORS.
- `relay/src/room.ts` — Durable Object state, authority, presence, limits,
  retention, role changes, revocation, and expiry.
- `relay/src/protocol.ts` — strict frame and credential validation.
- `relay/src/constants.ts` — shared bounds and time-to-live values.
- `relay/test/` — Vitest behavior and regression coverage.
- `chronosync/lib/data/transports/online_room_service.dart` — room creation and
  local encryption-key generation.
- `chronosync/lib/data/transports/online_relay_transport.dart` — client
  WebSocket, encrypted messaging, heartbeat, and reconnection.

Changes to a limit or frame are protocol changes. Update Dart and TypeScript
tests, `relay/README.md`, this guide, and the relevant `specs/` contract in the
same pull request.
