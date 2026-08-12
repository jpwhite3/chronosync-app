# Feature Specification: Shared Runbook MVP

**Status**: Implemented MVP
**Product**: ChronoSync

## Product Intent

ChronoSync is an account-free shared runbook for coordinated groups, initially
live event teams, on iPhone, Mac, and the web. A host creates a timed plan and
runs an authoritative live session. Teammates join as Participants or Displays
using an expiring QR/link over nearby Wi-Fi or an anonymous online relay.

## Required Experiences

- **Library and editor**: Create, duplicate, reorder, import, and export Plans
  containing titled, timed Steps, cue settings, auto-advance, and an optional
  scheduled start.
- **Lobby**: Share Participant and Display invitations, show authenticated
  connection presence, and let the host promote Participants to Controllers.
- **Live session**: Show current/next Steps, elapsed and remaining time,
  variance, pause/resume, advance, jump, adjustment, acknowledgement, and
  confirmed ending according to role.
- **Display**: Present a high-contrast fullscreen read-only view.
- **Summary**: Compare planned and actual timing, identify acknowledgements,
  retain local history, and export CSV.

## Behavioral Requirements

- The active host is authoritative; all commands are authenticated,
  idempotent, role-checked, revisioned, and serialized.
- Timers derive from host timestamps and measured clock offset.
- Host loss or a heartbeat timeout freezes the last verified client state.
- Reconnection reauthenticates the same local device and receives a fresh
  snapshot. There is no host election.
- Nearby hosting works without Internet from an awake, foreground iPhone.
- The native Mac app supports local authoring, solo sessions, online hosting,
  every shared-session role, fullscreen Display, and nearby joining by pasted
  invitation. Nearby hosting remains iPhone-only.
- Web supports the full editor, host, Participant, Controller, and Display
  experiences. Sound and visual alerts require the page to remain open.
- Plans, history, device identity, and rejoin credentials remain local unless
  explicitly exported. No account or automatic cross-device sync exists.

## Quality Bar

The responsive UI uses compact, two-pane, and expanded layouts; WCAG 2.2 AA
contrast; 44-point targets; keyboard and screen-reader support; visible focus;
reduced motion; and non-color status labels. Sessions support at least 250
Steps, 50 connections, and eight hours of timestamp-derived timing.

## Deferred

Apple Watch is the first post-MVP platform expansion. Nearby hosting from Mac,
accounts, collaborative editing, automatic library sync, host failover,
spreadsheet import, advanced analytics, medical/caregiver workflows, and Apple
Health require later product, privacy, and safety phases.
