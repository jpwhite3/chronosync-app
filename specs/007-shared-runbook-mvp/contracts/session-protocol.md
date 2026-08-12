# Session Protocol Contract

Every encrypted envelope includes `protocolVersion`, `sessionId`, `messageId`,
`senderDeviceId`, `baseRevision`, `sentAt`, `kind`, and authenticated payload.
The invitation supplies a random room capability, encryption secret, role,
transport endpoint, browser join URL, and fixed expiry.

## Authority and Identity

- Participant connections may submit encrypted commands; Displays cannot.
- The transport attaches an opaque authenticated connection ID and capability
  role. The host binds that connection to a device only after validating its
  encrypted join credential.
- Every WebSocket presents a room-scoped HMAC device token. Transports can
  revoke this opaque token without exposing the underlying device ID. The host
  verifies that it matches the HMAC derived from the encrypted join device ID
  and session secret before binding the connection.
- A reconnect must prove the stable, device-local per-session credential.
- Hosts retain the device-to-token binding after a socket disconnect so an
  offline participant can still be removed safely. The packaged nearby client
  uses browser local storage so ordinary new tabs reuse the same anonymous
  device identity. In this account-free bearer-invitation model, deliberately
  clearing site data creates a new participant identity.
- Controller authority exists only after a host-issued role-change revision.

## Ordering and Recovery

- The host reducer accepts a command only at the current revision and records
  its message ID for idempotency.
- Accepted commands increment the session revision and publish a complete
  encrypted snapshot.
- The online relay accepts any strictly newer authoritative snapshot, allowing
  recovery after a dropped revision, while rejecting equal or rollback state.
- On reconnect the host republishes its latest snapshot. Clients replace only
  with an equal-or-newer authenticated host snapshot.

## Liveness

Online and nearby connections exchange application-level ping/pong frames.
Silence beyond the bounded timeout marks the connection stale, freezes client
timing, and starts reconnect. Host presence deltas update lobby and People
views; presence never grants a session role.

The relay rejects new WebSocket upgrades after fixed capability expiry and
deletes retained encrypted state after its independent inactivity window.
Host removal installs a token tombstone before returning a correlated
acknowledgement, closes every live or handshaking socket sharing that token,
and only then records the participant as removed. Missing live sockets still
produce a successful acknowledgement because the tombstone is authoritative.
Failed or timed-out acknowledgements do not remove the participant locally and
the transport retries the tombstone after reconnect. Revoked reconnects close
with code `4003` before any retained snapshot is sent. Clients treat `4003`,
and replaced relay hosts treat `4001`, as terminal.
