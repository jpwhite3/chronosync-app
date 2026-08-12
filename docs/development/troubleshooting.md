# Developer Troubleshooting

Start with:

```sh
make doctor
make devices
make help
```

Use the smallest corrective action below. Preserve local plan/history data and
uncommitted source changes before cleaning or reinstalling anything.

## Flutter or CocoaPods Cannot Find Generated Configuration

Errors such as `Generated.xcconfig must exist` mean Flutter dependencies have
not prepared the platform workspace:

```sh
make app-deps
make generate
```

Then rerun the native recipe. Open `Runner.xcworkspace`, not `Runner.xcodeproj`,
when using Xcode.

## Generated Dart Conflicts or Is Stale

Do not edit generated files. Reset only build_runner's cache, then regenerate:

```sh
make clean-codegen
make generate
```

If CI reports a packaged-client mismatch, rebuild the specific artifact:

```sh
make nearby-client
make drift-worker
```

Review and commit the source and regenerated output together.

## No iPhone Simulator Is Available

Install an iOS runtime in Xcode's platform settings, then list devices:

```sh
make ios-simulators
```

Select one explicitly if automatic selection is wrong:

```sh
make ios-simulator IOS_SIMULATOR_ID=<udid>
make run-ios IOS_SIMULATOR_ID=<udid>
```

If Xcode has not completed first-launch setup, open it once and accept its
license/component prompts before retrying.

## Chrome Is Missing

Install Chrome and confirm Flutter recognizes it:

```sh
make devices
```

Both `make run-web` and `make test-browser` require Chrome. A different browser
can be used for manual acceptance but does not replace the automated suite.

## Online Hosting Is Unavailable

Check the compile-time configuration:

- web needs an HTTPS relay and must itself be served over HTTPS to create online
  invitations;
- native iPhone/Mac needs both `RELAY_URL` and `WEB_URL`;
- HTTP relay and online PWA join URLs are rejected intentionally.

Example:

```sh
make run-macos \
  RELAY_URL=https://relay.example.com \
  WEB_URL=https://app.example.com
```

Rebuild after changing defines; they are not runtime environment variables.

## Local HTTPS Relay Fails

Run Wrangler with HTTPS:

```sh
make relay-dev-https
```

Visit or otherwise trust `https://localhost:8787` if the development
certificate has not been accepted. The default `make run-web` page uses HTTP
and cannot create an online invitation because its guest join URL would not be
HTTPS. Use the local relay with tests, or serve a compiled ChronoSync web build
from a trusted HTTPS origin for end-to-end room testing.

If an HTTPS browser client reports CORS/403, ensure `ALLOWED_ORIGINS` matches
scheme, host, and port exactly. Restart Wrangler after editing `wrangler.toml`.

## A Physical Device Cannot Reach Local Services

`localhost` refers to the device itself. Use endpoints reachable from that
device, with valid HTTPS certificates for online rooms. Confirm both devices
use the same network and that firewalls, VPNs, captive portals, and client
isolation are not blocking traffic.

For nearby sessions, grant Local Network permission on iPhone and keep the host
foregrounded. The Simulator does not fully reproduce Bonjour and permission
behavior.

## A Guest Shows Connection Stale

This is expected when the guest cannot verify active host authority. Check that:

- the host app/page remains open and awake;
- the iPhone host was not backgrounded;
- both peers still have network connectivity;
- the online relay is healthy and the room has not expired;
- the invitation is current and was not revoked.

Guests intentionally freeze the last verified timer. Do not work around stale
state by advancing locally or promoting a guest to host.

## Web Plans or History Disappeared

Web data is local to the browser profile and origin. Private browsing, site-data
clearing, a different hostname/port, or browser storage eviction creates a
different or empty library. Import a prior `.chronosync` export if available.

Before clearing site data for diagnosis, export important plans. Session
history is not automatically synchronized between devices.

## Drift Web Worker or WASM Fails to Load

Confirm `chronosync/web/drift_worker.js` and `chronosync/web/sqlite3.wasm` are
served with the web build and are not intercepted by a misconfigured SPA
fallback. Rebuild and verify the release:

```sh
make drift-worker-check
make build-web
```

Inspect browser network and console output, but sanitize paths and data before
sharing it.

## Branding Asset Generation Fails

The branding script requires `rsvg-convert` from librsvg and `magick` from
ImageMagick. Install both with the package manager appropriate for your system,
then run:

```sh
make branding-assets
make branding-assets-check
```

Do not manually resize only one platform's icons; committed outputs must remain
derived from the shared source SVG.

## Mac Release Verification Fails

`make build-macos-release` checks code signing and sandbox entitlements. Confirm
the application sandbox, outbound network client, and user-selected file
read/write entitlements are present. Local development uses placeholder identity
and signing; distribution additionally needs final bundle/team configuration
and the chosen App Store or Developer ID/notarization workflow.

## Tests Pass Locally but Fail in CI

Compare against CI's pinned Flutter 3.41.9, Node.js 22, Chrome environment, and
macOS 15 runner. Run:

```sh
make ci
make ci-native   # macOS only
```

Look first for formatting, stale generated bundles, timezone/real-clock use,
unordered async behavior, platform assumptions, or an unlocked dependency.
Tests should use deterministic clocks and in-memory/contract transports where
possible.

## Request More Help

If the problem remains, follow [SUPPORT.md](../../SUPPORT.md) and file a minimal
sanitized reproduction. Use [SECURITY.md](../../SECURITY.md) instead for any
issue involving authorization, encryption, invitations, disclosure, or unsafe
parsing.
