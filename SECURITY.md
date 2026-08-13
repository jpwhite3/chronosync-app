# Security Policy

## Supported Versions

ChronoSync is under active development and has no tagged public release. Only
the current `main` branch is evaluated for security fixes. This policy will be
revised when supported release lines exist.

## Report a Vulnerability

Do not disclose a suspected vulnerability in a public issue, discussion, pull
request, log, or screenshot.

GitHub private vulnerability reporting and a public security email are not yet
confirmed for this repository. If **Report a vulnerability** is available on
the repository's **Security** tab, use it. If you already have a verified
private channel to the repository owner, use that instead.

If neither route is available, open a minimal public issue titled **Private
security contact requested**. Include no vulnerability details, reproduction
steps, affected components, credentials, active invitation links, capabilities,
room secrets, or personal data. A maintainer can then establish a private
channel before disclosure. This temporary bootstrap is not a place to submit
the report itself.

Include only the information needed to reproduce and assess the report:

- affected commit and platform;
- impact and prerequisites;
- minimal reproduction steps or proof of concept;
- whether the issue is already public;
- a safe way to contact you.

There is currently no bug-bounty program or guaranteed response SLA. Please
allow time to validate, coordinate, and test a fix before public disclosure.

## Relevant Security Boundaries

Reports are especially useful when they involve:

- invitation, capability, or room-secret disclosure;
- role escalation or unauthorized session commands;
- failures in encryption, authentication, replay protection, or revision checks;
- relay behavior that exposes or logs decrypted session content;
- unsafe `.chronosync` or CSV import/export handling;
- local-network permission or nearby-session access issues;
- unintended persistence or disclosure of Sequence, history, or device data.

Online payloads are encrypted by the application; the relay should only handle
opaque room state. Nearby sessions use application-layer authenticated
encryption but are designed for trusted local networks. Invitation links are
bearer capabilities and must be handled as secrets.

For the intended design and trust boundaries, see
[Architecture](docs/development/architecture.md#security-and-trust-boundaries)
and [Relay development](docs/development/relay.md).

General hardening suggestions that do not reveal an exploitable weakness may be
filed as normal issues. When uncertain, report privately.
