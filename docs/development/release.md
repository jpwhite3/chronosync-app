# Release Guide

ChronoSync has no tagged public release yet. This checklist documents the
intended development release process without implying production readiness or
automated distribution.

## Release Readiness

Before creating the first public release, the project owner must:

- select and add an open-source license;
- replace `com.example.chronosync` with final iOS and Mac bundle identifiers;
- configure Apple developer teams, signing, capabilities, and distribution;
- configure production PWA and relay HTTPS endpoints and exact relay origins;
- enable a private security-reporting channel and choose policy contacts;
- complete physical-device, accessibility, localization, privacy, performance,
  beta, and store-review qualification.

Do not publish artifacts that still contain placeholder identifiers or URLs.

## 1. Choose Scope and Version

Confirm that the target changes are complete, documented in `specs/`, and
merged to the release branch. Update:

- `chronosync/pubspec.yaml` version and build number;
- `[Unreleased]` in `CHANGELOG.md`, moving entries under the new version/date;
- user and developer documentation;
- protocol documentation if compatibility changed.

Confirm and document the versioning policy before the first public release.
Treat persistence, `.chronosync` archives, invitation envelopes, and relay
frames as compatibility surfaces regardless of the chosen policy.

## 2. Freeze Configuration

Record the exact production values without committing secrets:

- `CHRONOSYNC_RELAY_URL` — deployed HTTPS Worker base URL;
- `CHRONOSYNC_WEB_URL` — deployed HTTPS PWA URL used by native invitations;
- relay `ALLOWED_ORIGINS` — exact PWA origin;
- final Apple bundle IDs, signing team, entitlements, and privacy metadata.

The endpoint URLs are compile-time configuration. Invitation capabilities and
encryption keys are runtime secrets and must never enter build scripts or CI
logs.

## 3. Run Automated Qualification

From a clean checkout of the candidate commit:

```sh
make doctor
make ci
make ci-native
```

`make ci` installs locked dependencies, runs normal app/relay checks, and
builds a sanitized, verified web release. `make ci-native` runs iOS/macOS
XCTest, builds the Mac release, and verifies its signature and sandbox
entitlements. Confirm all GitHub Actions jobs pass for the same commit.

Review dependency-audit results instead of bypassing them. Regenerate and
commit any derived artifact from its source; never patch compiled output.

## 4. Build Candidate Artifacts

### Web/PWA

```sh
make build-web RELAY_URL=https://relay.example.com
```

The verified output is `chronosync/build/web/`. Deploy it to an HTTPS origin
with correct MIME types, caching rules, and SPA fallback behavior. The web app
derives invitation links from that serving origin; `WEB_URL` is used only by
native builds. Verify the service worker, offline reload, Drift WASM worker,
invitation bootstrap, and fullscreen Display on current Safari, Chrome, and
Edge.

### Relay

Update and review `relay/wrangler.toml`, then follow
[Relay development](relay.md#production-configuration):

```sh
make relay-deploy CONFIRM_DEPLOY=1
```

Deployment is not performed by CI. Verify `/health` and a disposable end-to-end
room after deployment.

### iPhone

For a signed local release build:

```sh
make build-ios-release \
  RELAY_URL=https://relay.example.com \
  WEB_URL=https://app.example.com
```

This does not produce an App Store-ready IPA automatically. Open
`chronosync/ios/Runner.xcworkspace` in Xcode, select the final team and bundle
ID, review permissions/privacy manifests, archive, validate, and distribute
through the chosen App Store Connect/TestFlight workflow.

### Native Mac

```sh
make build-macos-release \
  RELAY_URL=https://relay.example.com \
  WEB_URL=https://app.example.com
```

The local output is
`chronosync/build/macos/Build/Products/Release/ChronoSync.app`. The Make recipe
verifies its signature and sandbox entitlements, but production distribution
still requires the chosen App Store or Developer ID workflow. Developer ID
distribution additionally requires Hardened Runtime and notarization.

## 5. Run Manual Acceptance

Use fictional Sequences and fresh anonymous rooms. At minimum verify:

- create, edit, reorder, duplicate, import, export, delete, and recover;
- scheduled/instant starts, pause/resume, adjust, jump, auto-advance, cues, end,
  summary, and CSV;
- all roles on iPhone, Mac, and web at compact/two-pane/wide layouts;
- nearby join with no Internet, host backgrounding, Wi-Fi loss, and reconnect;
- online join, simultaneous commands, host loss, role promotion/revocation,
  expired invitations, and relay-driven expiry/cleanup;
- keyboard, VoiceOver/screen reader, large text, contrast, reduced motion, and
  fullscreen exit;
- eight-hour timing accuracy and expected behavior around sleep/wake.

Record the tested OS/browser/device matrix and any accepted limitations in the
release notes.

## 6. Publish and Observe

Only after artifacts and deployed services match the candidate commit:

1. create the signed version tag;
2. publish GitHub release notes from `CHANGELOG.md`;
3. attach or link only approved distribution artifacts;
4. verify fresh-install and upgrade paths from public endpoints;
5. monitor content-free health, crashes, and support reports without collecting
   session content or secrets.

Keep the previous compatible PWA/relay/native artifacts available for rollback.
If a release has a security problem, follow `SECURITY.md` and coordinate fixes
before public detail.
