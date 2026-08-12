# Data Model: Local-First Runbook Sessions

## Existing Data

`Series` and `Event` remain the persisted runbook template and step entities in
the first migration. A future naming migration can rename them without changing
the session protocol.

## New Session Entities

### RunSession

An active or completed execution of one runbook.

| Field | Purpose |
|---|---|
| `id` | Random local session identifier. |
| `runbookId` | Local identifier of the source `Series`. |
| `hostPeerId` | Ephemeral identifier of the authoritative host. |
| `status` | Lobby, running, completed, or ended. |
| `currentStepIndex` | Active step in the source runbook. |
| `startedAt` | Host-issued UTC timestamp for the first step. |
| `currentStepStartedAt` | Host-issued UTC timestamp for the active step. |
| `revision` | Strictly increasing host revision. |

### RunActivity

An append-only record created by the host.

| Field | Purpose |
|---|---|
| `id` | Globally unique action identifier. |
| `sessionId` | Session that owns the activity. |
| `revision` | Host-issued ordering value. |
| `type` | Started, advanced, auto-advanced, acknowledged, completed, or ended. |
| `stepIndex` | Step affected by the action. |
| `actorPeerId` | Host or participant that initiated the action. |
| `occurredAt` | Host-issued UTC timestamp. |

### PeerIdentity

An ephemeral, local identity consisting of a random peer ID and chosen display
name. It is not an account and does not identify a person outside the device.

## Clock Rule

The host publishes `currentStepStartedAt`. A client calculates elapsed time as
its current wall-clock time minus that timestamp after applying a measured host
clock offset. Timer ticks redraw the display only; they never mutate session
time. The host alone mutates step progression.

## Persistence

Runbook templates, active sessions, and activity logs are stored locally. An
implementation may use Hive for the first MVP, but the session domain must not
depend on Hive so it can be serialized to a QR bundle, a nearby transport, or an
export file.
