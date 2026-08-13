# Screenshot Maintenance

ChronoSync documentation screenshots are captured manually from the real app.
There is no screenshot test or seeded launch mode, so use the same fixture,
frame size, and clean-state process whenever an image is replaced.

## Frame Specifications

Keep replacement images at the dimensions and format already used by their
asset set:

| Asset set | Format | Pixel size | Capture frame |
| --- | --- | --- | --- |
| `docs/assets/tutorial/web/` | JPEG | 1280 x 900 | 1280 x 900 browser viewport |
| `docs/assets/tutorial/participant/` | JPEG | 1280 x 900 | 1280 x 900 browser viewport |
| `docs/assets/tutorial/iphone/` | PNG | 1206 x 2622 | 402 x 874 points at 3x |
| `docs/assets/tutorial/mac/` | PNG | 1824 x 1488 | 912 x 744 points at 2x |

Use light appearance, default text scaling, and a consistent system status bar.
Close menus, snackbars, software keyboards, and unrelated windows unless they
are the subject of the image. Keep the pointer outside the capture.

## Canonical Synthetic Fixture

Start with a clean library and capture the empty state before adding data. Then
select **Try a sample sequence**. The app creates the neutral **Shared rhythm**
Sequence and opens it in the editor with these Intervals:

1. **Gather** — 5 minutes
2. **Set the pace** — 30 minutes
3. **Focus time** — 10 minutes
4. **Wrap up** — 5 minutes

Use synthetic device names such as `Workshop lead` and `Training room`. Do not
substitute a real person's name, imported Sequence, or genuine Session history.
For the normal solo flow, return to the library, select **Start**, choose **Just
me**, start the Session, advance through the Intervals, and finish it to populate
the summary and History screens.

## Start Clean

- **Web:** use a dedicated temporary Chrome profile, or clear the site's storage
  in DevTools before launch. Reload after clearing it.
- **iPhone Simulator:** use a dedicated simulator. To remove only ChronoSync and
  its simulator data before reinstalling, run
  `xcrun simctl uninstall YOUR_UDID com.example.chronosync`. Do not use a
  simulator that contains data you need.
- **Mac:** use a dedicated macOS test account or fresh app container. ChronoSync
  has no reset flag; do not capture from a personal installation or delete an
  unverified path under `Library`.

## Capture by Platform

Run these commands from the repository root. Capture commands run in a second
terminal while the Flutter process remains active.

### Web

```sh
make run-web WEB_PORT=8080
```

In Chrome DevTools, enable the device toolbar, set a responsive viewport to
1280 x 900, and use **Capture screenshot**. DevTools saves PNG; convert the
selected capture to the repository's JPEG format without resizing it:

```sh
sips -s format jpeg /path/to/capture.png \
  --out "$PWD/docs/assets/tutorial/web/05-live-ready.jpg"
```

Use the same viewport and conversion for the browser-based Participant image.

### iPhone Simulator

```sh
make ios-simulators
make run-ios IOS_SIMULATOR_ID=YOUR_UDID
```

With the chosen 402 x 874-point simulator booted, capture its framebuffer:

```sh
xcrun simctl io YOUR_UDID screenshot \
  "$PWD/docs/assets/tutorial/iphone/03-live-session-ready.png"
```

Use the same simulator model, appearance, orientation, and status-bar treatment
for the full iPhone set.

### Mac

```sh
make run-macos
```

Size the app content to 912 x 744 points on a Retina display. In another
terminal, start an interactive capture, omit the window shadow, and select only
the app content:

```sh
screencapture -i -o "$PWD/docs/assets/tutorial/mac/live-session.png"
```

Confirm the saved result is exactly 1824 x 1488 pixels; crop or recapture rather
than scaling the app UI.

## Shared Sessions and Secrets

Solo captures are reproducible without a relay. Lobby, Participant, Display,
and Timekeeper states require multiple controlled clients. Online clients need
the literal `CHRONOSYNC_RELAY_URL` and `CHRONOSYNC_WEB_URL` build defines;
Nearby hosting needs a physical iPhone for reliable acceptance testing. Bring
all synthetic clients to the intended state before capturing.

Never capture a live invitation, QR code, URL fragment, token, relay log, or
other Session secret, even if the image will later be cropped or blurred. Keep
secret-bearing controls outside the original frame. Use only synthetic data in
an isolated test Session, and discard it after capture.

## Naming and Alt Text

Before committing an image:

- use a two-digit workflow prefix and lowercase kebab-case subject, such as
  `02-sequence-editor.jpg`;
- keep the existing filename when the documented state has not changed, so
  references remain stable;
- use **Sequence**, **Interval**, **Session**, **Host**, **Timekeeper**, and
  **Timing drift** consistently in filenames and surrounding copy;
- write alt text that identifies the platform or role, screen, and meaningful
  state or action; do not write only "screenshot" or repeat the filename;
- verify that visible names and history are synthetic and that no invitation or
  secret appears anywhere in the pixels; and
- update every Markdown reference when a filename changes, then remove the old
  asset in the same change.

## Verify the Change

Inspect every changed image at 100% for correct copy, focus state, clipping,
debug UI, pointer placement, and sensitive data. Then check dimensions,
references, and whitespace:

```sh
find docs/assets/tutorial -type f -print0 | sort -z | xargs -0 file
rg -n '!\[[^]]+\]\([^)]*assets/tutorial/' docs --glob '*.md'
git diff --check
```

Confirm that each reported Markdown path exists, every renamed image has no
remaining old reference, and each changed asset is used by at least one guide.
