# ChronoSync

ChronoSync is an account-free shared runbook for live event teams. Create a
timed plan, run it from iPhone, Mac, or the web, and keep hosts, controllers,
participants, and displays aligned on the current step and schedule variance.

## Supported targets

| Target | MVP capabilities | Nearby sessions |
| --- | --- | --- |
| iPhone | Full app and every live role | Host or join |
| Mac | Full app, native fullscreen Display, and every live role | Join by invitation |
| Web/PWA | Full app and every live role while the page is open | Join by QR/link |
| Apple Watch | Post-MVP companion | Through paired iPhone |

Nearby hosting from Mac and web is deferred.

## Run locally

From the repository root, `make help` lists the supported development tasks.
Typical workflows are `make setup`, `make run-ios`, `make run-web`,
`make test`, and `make check`. Compile-time service URLs can be supplied with
`RELAY_URL=https://...` and `WEB_URL=https://...`; simulator and focused-test
overrides are documented by the help target.

`make run-web` uses port 8080 for local-only browser workflows. Online
invitations require the web app and relay to use HTTPS, including on loopback;
use a trusted HTTPS web origin or a staging deployment for end-to-end rooms.
`make relay-dev-https` runs the relay locally for relay tests or such a client.

The equivalent Flutter commands, run from `chronosync/`, are:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
flutter run -d macos
```

The web app persists plans and session history locally with Drift and ships the
SQLite WASM worker required for offline use. Build the installable PWA with:

```sh
flutter build web --release
```

Anonymous online rooms are optional. Deploy the Worker in `../relay/`, then
build the web app with its HTTPS endpoint:

```sh
flutter build web --release \
  --dart-define=CHRONOSYNC_RELAY_URL=https://relay.example.com
```

Web builds use their current HTTPS origin as the QR/link destination. The
default loopback HTTP development server supports local-only workflows, not
online invitations. Native iPhone and Mac builds also need the public
ChronoSync PWA URL:

```sh
flutter build ios --release \
  --dart-define=CHRONOSYNC_RELAY_URL=https://relay.example.com \
  --dart-define=CHRONOSYNC_WEB_URL=https://app.example.com

flutter build macos --release \
  --dart-define=CHRONOSYNC_RELAY_URL=https://relay.example.com \
  --dart-define=CHRONOSYNC_WEB_URL=https://app.example.com
```

The repository’s Mac target uses a placeholder bundle identifier and ad-hoc
signing for local builds. Before distribution, choose the final bundle ID and
Apple team, then configure either App Store signing or Developer ID signing
with Hardened Runtime and notarization.

Shared links open `CHRONOSYNC_WEB_URL`; the invitation fragment carries the
separate relay endpoint used for the WebSocket connection. Online hosting stays
disabled when the relay URL or a secure PWA join URL is missing or invalid.

The native Mac app includes the full editor, solo and online hosting, all
shared-session roles, fullscreen Display, local history, and import/export.
Paste a shared invitation into **Join session** to participate natively.
Mac uses visual and audio cues; haptic preferences remain portable for plans
that will also run on supported mobile devices.

Nearby hosting is iPhone-only. It advertises a Bonjour service and hosts an
authenticated local WebSocket while the app remains awake and in the
foreground. Browsers and the Mac app can join nearby sessions from an
invitation.

## Architecture

- `lib/domain/`: immutable plans, live-session state, reducer, and protocol.
- `lib/data/`: Drift repositories, migration, portability, cues, and transports.
- `lib/logic/`: host-authoritative live-session coordination.
- `lib/presentation/`: responsive editor, lobby, role views, and summaries.
- `test/`: unit, transport, migration, BLoC, widget, and responsive coverage.

Plans and histories remain on-device unless explicitly exported. The versioned
`.chronosync` archive supports portable plan exchange; activity history exports
as CSV.

## Verify changes

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --release
flutter build macos --release
```

After changing `tool/nearby_client/`, rebuild the browser bundle with:

```sh
dart compile js tool/nearby_client/main.dart -O4 \
  -o assets/nearby_client/client.js
```
