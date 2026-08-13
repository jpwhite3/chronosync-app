# Local Development

The root `Makefile` gives consistent entry points across the Flutter app and
Cloudflare relay. Run `make help` whenever the command surface changes.

## Repository Working Directories

- Run `make ...` from the repository root.
- Run direct `flutter` and `dart` commands from `chronosync/`.
- Run direct `npm` commands from `relay/`; invoke the locally installed Wrangler
  through `npm run` or `npm exec wrangler`.

Prefer the Make recipes in documentation and CI reproduction because they also
perform required code generation and artifact checks.

## Runtime Configuration

ChronoSync uses compile-time Dart defines, not a committed `.env` file.

| Make override | Purpose |
| --- | --- |
| `RELAY_URL` | Sets `CHRONOSYNC_RELAY_URL`, an HTTPS relay base URL. |
| `WEB_URL` | Sets `CHRONOSYNC_WEB_URL`, the public HTTPS PWA URL used in native invitations. |
| `WEB_PORT` | Chrome development port; defaults to `8080`. |
| `DEVICE` | Flutter device ID used by `make run`. |
| `EMULATOR` | Flutter emulator ID used by `make launch-emulator`. |
| `IOS_SIMULATOR_ID` | iPhone Simulator UDID used by run/test recipes. |
| `TEST` | Focused Flutter test path relative to `chronosync/`. |
| `TEST_ARGS` | Additional `flutter test` arguments. |
| `CONFIRM_DEPLOY=1` | Explicit guard required for relay deployment. |

Do not commit production secrets. Relay and PWA endpoints are public
configuration, but invitation capabilities, encryption keys, and device tokens
are secrets and must never appear in source, logs, or fixtures.

## Run Offline and Solo Workflows

No service configuration is required for Sequence editing, local history, solo
sessions, imports, or exports:

```sh
make run-web
make run-macos
make run-ios
```

The web app persists through browser storage. Clearing site data removes local
Sequences and history, so export important Sequences before resetting it.

## Develop Online Rooms

Wrangler can run the relay locally over HTTPS:

```sh
make relay-dev-https
```

Use this for relay tests or with a ChronoSync web build served from a trusted
HTTPS origin. Accept or trust Wrangler's development certificate before a
browser connects, and set `ALLOWED_ORIGINS` to the web origin exactly.

The default `make run-web` server is `http://localhost:8080`. That is suitable
for Sequence, solo, and offline browser development, but it cannot create a
valid online invitation because online join URLs require HTTPS. For end-to-end
online testing, use a trusted local HTTPS web server or staging PWA and compile
it with the reachable HTTPS relay URL:

```sh
make build-web RELAY_URL=https://relay.example.com
```

Serve `chronosync/build/web/` from the HTTPS origin in the relay allowlist. The
web app derives its invitation URL from that origin.

Native iPhone and Mac hosts require both an HTTPS relay and an HTTPS PWA URL
that guests can reach:

```sh
make run-macos \
  RELAY_URL=https://relay.example.com \
  WEB_URL=https://app.example.com
```

Use the same overrides with `make run-ios`. `localhost` on a physical phone is
the phone itself, not the development Mac; use reachable HTTPS endpoints for
cross-device testing.

## Nearby Session Development

Only a foreground iPhone hosts nearby sessions. It advertises Bonjour service
`_chronosync._tcp`, serves a small browser client, and keeps the display awake.
The host must remain open; backgrounding freezes guest state until authority is
restored.

Use a physical iPhone and a second device on the same trusted Wi-Fi network.
Verify local-network permission, QR join, host backgrounding, Wi-Fi
interruption, reconnection, audio, haptics, and VoiceOver. Local browser traffic
uses HTTP/WS with application-layer authenticated encryption; do not represent
it as transport security for hostile networks.

## Code Generation and Committed Bundles

Generate Drift and Mockito sources after annotations or database declarations
change:

```sh
make generate
make generate-watch
```

Never hand-edit `*.g.dart`, `*.mocks.dart`, or compiled JavaScript. Regenerate
the checked-in browser assets from their Dart sources:

```sh
make nearby-client       # chronosync/assets/nearby_client/client.js
make drift-worker        # chronosync/web/drift_worker.js
```

CI verifies both outputs byte-for-byte. If branding SVGs change, install
`rsvg-convert` and ImageMagick's `magick`, then run:

```sh
make branding-assets
make branding-assets-check
```

## Build Artifacts

| Target | Command | Output |
| --- | --- | --- |
| Web release | `make build-web` | `chronosync/build/web/` |
| Web debug | `make build-web-debug` | `chronosync/build/web/` |
| iOS Simulator | `make build-ios-simulator` | `chronosync/build/ios/iphonesimulator/Runner.app` |
| Signed local iOS release | `make build-ios-release` | Flutter/Xcode iOS build output |
| Mac debug | `make build-macos-debug` | `chronosync/build/macos/Build/Products/Debug/ChronoSync.app` |
| Mac release | `make build-macos-release` | `chronosync/build/macos/Build/Products/Release/ChronoSync.app` |

`make build` builds web, iOS Simulator, and Mac release, so it requires macOS.
Web release builds are sanitized and rejected if source maps or local build
paths remain. Mac release builds are checked for valid signing and required
sandbox entitlements.

`make build-ios-release` uses local Xcode signing; it does not create an
App Store-ready IPA. Current Apple bundle identifiers are placeholders and must
be replaced before distribution.

## Useful Maintenance Commands

```sh
make format              # Format Dart app, tests, and tools
make lint                # Formatting, Dart analyzer, TypeScript checks
make outdated            # Report app and relay dependency updates
make clean               # Remove Flutter build products
make clean-codegen       # Reset build_runner's generated cache
make makefile-check      # Dry-run primary Make recipes
```

`make clean` removes build products, not local application data. Avoid broad or
manual deletion of browser/native databases; export anything important first.
