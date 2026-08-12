# Implementation Plan: Local-First Runbooks

## Delivery Order

1. **Session core**: Introduce serializable `RunSession`, activity, revision,
   and clock abstractions with unit tests. Refactor the timer to derive elapsed
   time from timestamps.
2. **Host experience**: Add a session lobby, host controls, local activity log,
   and presentation mode backed by the session core.
3. **Peer protocol**: Implement QR invitation encoding and a fake in-memory
   transport for deterministic tests.
4. **Native nearby adapters**: Add Swift/iOS and Kotlin/Android adapters behind
   the transport boundary. Verify host/join/reconnect with physical devices.
5. **Watch companion**: Mirror the phone's local session state to the paired
   watch and provide acknowledgement controls.
6. **Hardening**: Exercise background/resume, radio loss, duplicate messages,
   invalid invitations, and local export/import paths.

## Architecture Guardrails

- Do not add a cloud dependency, account model, or server-generated identifier.
- Do not let a transport callback change UI state directly; it must pass through
  the session domain and revision checks.
- Do not make a client timer authoritative. Only the host may mutate session
  progression.
- Keep native nearby code behind a Dart interface so iOS and Android use the
  same wire protocol and deterministic fakes remain available to tests.
