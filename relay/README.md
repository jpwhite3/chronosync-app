# ChronoSync Relay

Anonymous, ephemeral WebSocket coordination for ChronoSync online live
sessions. A Cloudflare Durable Object represents one room and serializes its
connections and authoritative revisions.

The relay never decrypts application payloads. It stores only capability
hashes, the latest encrypted snapshot, its revision, room activity timestamps,
transient connection IDs/roles, bounded host-managed device-role overrides,
and opaque room-scoped device tokens blocked by the host. Do not add
request-body, WebSocket-frame, capability, device-token, or ciphertext logging.

## Local development

```sh
npm install
npm run dev
npm run typecheck
npm test
```

Before deployment, replace `ALLOWED_ORIGINS` in `wrangler.toml` with the exact
HTTPS origin of the ChronoSync web app. Configure Cloudflare rate limiting for
`POST /v1/rooms`; the Worker also enforces per-room connection, controller,
message-size, and per-connection message-rate limits.

Deploy with:

```sh
npm run deploy
```

`GET /health` provides a content-free health check.

## Room lifecycle

Create an anonymous room:

```http
POST /v1/rooms
```

The response contains a random room ID and separate `host`, `controller`,
`participant`, and `display` capabilities. It does **not** contain an
application encryption key. The host must generate that key locally and share
it inside the invitation fragment or another channel that is never sent to the
relay.

Connect using the returned `websocketPath` and four WebSocket subprotocols:

```text
chronosync.v1
role.participant
cap.<participant capability>
device.<room-scoped device token>
```

For example:

```ts
const socket = new WebSocket(url, [
  "chronosync.v1",
  "role.participant",
  `cap.${participantCapability}`,
  `device.${deviceToken}`,
]);
```

Capabilities deliberately use WebSocket subprotocol headers instead of URL
query parameters, which are more commonly retained in access logs. Treat every
capability as a bearer secret. The device token is an opaque HMAC derived
locally from the session secret and device ID; it never contains the raw device
ID. Only one host connection is active; a new valid host connection replaces
the previous one.

Room capabilities have a fixed expiry 24 hours after room creation. The relay
stores that deadline and rejects every new WebSocket upgrade after it, even if
room activity continued; sockets that connected before the deadline may remain
active. Independently, every valid connection or message extends the storage
inactivity deadline by 24 hours. The alarm closes connections and deletes all
room storage after that inactivity deadline. An authenticated host may send
`{"type":"end_room"}` for immediate deletion.

## Version 1 WebSocket protocol

All encrypted fields are base64url strings; optional terminal `=` padding is
accepted for compatibility with standard encoders. Clients must encrypt and
authenticate payloads themselves, including the room ID, protocol version,
message metadata, and intended action as associated data.

Host snapshots are the only authoritative state:

```json
{
  "type": "snapshot",
  "messageId": "snapshot_001",
  "revision": 0,
  "sentAt": "2026-07-28T12:00:00.000Z",
  "nonce": "base64url_nonce",
  "ciphertext": "base64url_ciphertext"
}
```

The relay accepts an active host snapshot whose revision is equal to or newer
than the retained revision. Newer revisions let the host recover when
intermediate snapshots were dropped; a new equal-revision message refreshes
and broadcasts connection-scoped state such as participant rebind
confirmation. Lower revisions are rejected, while a repeated accepted
`messageId` is acknowledged as an idempotent duplicate. The relay retains the
latest accepted snapshot and sends it to reconnecting clients.

Host-only presence entries and command sender metadata include the sender's
opaque `deviceToken`; guest presence never exposes tokens. A host can durably
remove a device with a correlated request:

```json
{
  "type": "disconnect_peer",
  "requestId": "disconnect_001",
  "deviceToken": "opaque_room_scoped_token"
}
```

The relay commits the token tombstone before replying, closes every current
socket sharing that token, and rejects future connections with code `4003`
before a welcome or retained snapshot. A `not_found` result still means the
absent token was tombstoned. To reject only one unauthenticated or superseded
socket without blocking its device, use `disconnect_connection` with
`requestId` and `connectionId`.

Both operations reply with a correlated result:

```json
{
  "type": "peer_disconnect_result",
  "requestId": "disconnect_001",
  "deviceToken": "opaque_room_scoped_token",
  "status": "disconnected",
  "disconnectedConnections": 2
}
```

`status` is `disconnected`, `not_found`, or `failed`. Failed results also
include an `errorCode`; connection-only results echo `connectionId` instead of
`deviceToken`.

The active host promotes or demotes an authenticated device without sharing a
Controller bearer secret:

```json
{
  "type": "set_peer_role",
  "requestId": "role_001",
  "deviceToken": "opaque_room_scoped_token",
  "role": "controller"
}
```

The relay commits the room-scoped override before returning
`peer_role_result`, applies it to every live socket for that device, and reuses
it when the device reconnects. Roles may be `participant`, `controller`, or
`display`; host authority cannot be granted. Revocation and room expiry delete
the override. Role overrides and blocked-device tombstones are each capped at
250 entries; new entries beyond that bound return a correlated
`retained_device_limit` failure.

Controllers and participants can submit encrypted requests to the host:

```json
{
  "type": "command",
  "messageId": "command_001",
  "baseRevision": 0,
  "sentAt": "2026-07-28T12:00:00.000Z",
  "nonce": "base64url_nonce",
  "ciphertext": "base64url_ciphertext"
}
```

The relay requires `baseRevision` to match its latest snapshot and adds only an
ephemeral sender connection ID and role before forwarding. The host still
decrypts, authorizes, validates, reduces, and publishes the resulting snapshot.
Display connections cannot submit commands.

Relay-originated messages include `welcome`, aggregate `presence`, `pong`,
`command_forwarded`, `snapshot_accepted`, `peer_disconnect_result`,
`peer_role_result`, `room_closed`, and structured `error` messages. Presence contains only
ephemeral connection IDs, roles, connection timestamps, and—only for the
active host—opaque device tokens; never display names or plan content.

## Host liveness

All clients send `{"type":"ping"}` every 10 seconds because browser WebSockets
do not expose control-frame pings. Any valid frame refreshes that socket's
30-second application lease. Normal room traffic and new joins sweep expired
sockets: stale participants, controllers, and displays are closed and excluded
from presence, routing, role limits, and room capacity. A frame arriving after
its sender's lease expired is rejected before it can refresh the lease.

The host uses the same lease, with additional authority semantics. When it
expires, the relay clears the active-host identity and reports
`hostConnected: false` in `presence` and `pong` frames. Guests must freeze live
state while that assertion is false; a replacement or reconnected host restores
`hostConnected: true`. This distinguishes a healthy guest-to-relay connection
from a healthy guest-to-host session.

## Operational limits

- 50 simultaneous guest connections per room, plus one authoritative host.
- 10 Controller connections per room.
- 250 retained device-role overrides and 250 blocked-device tombstones.
- 256 KiB of encrypted application payload per message, with a 320 KiB limit
  for the complete WebSocket frame including protocol metadata.
- 120 messages per connection per 10 seconds.
- Capabilities expire 24 hours after room creation.
- Room storage expires 24 hours after the most recent activity.

Timer ticks should be derived locally from authenticated timestamps, not sent
through the relay. This keeps traffic and Durable Object writes bounded.
