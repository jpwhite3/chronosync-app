# Peer Session Protocol

## Transport Boundary

The protocol is transport independent. iOS and Android nearby adapters send the
same versioned messages; QR bootstraps a session and export files carry a final
snapshot. The protocol never assumes Internet access.

## Join Invitation

The host QR code contains a version, session ID, transport service identifier,
host public key, random session secret, and expiry. It is encoded as a
`chronosync://join` payload. The secret is never displayed separately or reused
for another session.

## Messages

| Type | Direction | Meaning |
|---|---|---|
| `joinRequest` | Participant → host | Requests entry with peer ID and display name. |
| `sessionSnapshot` | Host → participant | Full runbook and authoritative session state. |
| `revisionRequest` | Participant → host | Requests activities after a revision. |
| `activityBatch` | Host → participant | Ordered changes after a revision. |
| `acknowledgement` | Participant → host | Requests a current-step acknowledgement. |
| `heartbeat` | Both | Maintains presence and measures clock offset. |
| `sessionEnded` | Host → participant | Closes the shared session. |

Every payload includes `protocolVersion`, `sessionId`, `messageId`, and an
authenticated envelope. Receivers reject expired invitations, an unknown
session, duplicate `messageId` values, and unexpected revisions.

## Authoritative Write Flow

1. A participant sends an acknowledgement request.
2. The host validates that the session is running and the step is current.
3. The host appends a `RunActivity`, increments the session revision, persists
   both locally, and broadcasts the activity.
4. Clients apply only consecutive revisions. A gap triggers `revisionRequest`;
   the host falls back to `sessionSnapshot` when its activity history is absent.

## Reconnect and Failure

- The participant retries nearby discovery only for the saved session ID while
  the invitation remains valid.
- A reconnecting participant never advances state from its cached copy.
- If the host ends or loses the session, connected peers retain their last
  verified snapshot and state that the session is no longer live.
- Host migration is out of scope for the MVP; it needs a separate quorum and
  conflict model.
