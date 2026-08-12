# Data, Recovery, and Troubleshooting

## Where ChronoSync Stores Data

ChronoSync has no accounts and no automatic cross-device sync.

- iPhone and Mac store Plans, identity, and History in the app's local data.
- Web stores them in browser storage for the current site and browser profile.
- A shared-room service routes encrypted live state; it is not a Plan library.
- Plans and History leave the device only when you explicitly share a Live
  session or export a file.

## Move Plans Between Devices

### Export

1. Open **Plans**.
2. For one Plan, open **Plan actions** and select **Export**.
3. For the whole library, open **Plan library actions** and select **Export all
   plans**.
4. Save or share the resulting `.chronosync` file.

A single archive uses the Plan title for its filename; a full-library export
uses `chronosync-plans.chronosync`.

### Import

1. Open **Plan library actions** and select **Import .chronosync**.
2. Choose an archive of no more than 10 MB.
3. Review **Import plans?**, including its Plan and Step counts.
4. Select **Import**.

Imports generate new IDs when necessary and never silently overwrite existing
Plans. Archives exclude History, device names, and Live session secrets.

## Export Session Activity

Open a completed summary directly or through **History**, then select **Export
CSV** or **Export activity as CSV**. The CSV records the session, Plan, revision,
Step, actor, role, action, planned and actual timestamps, duration, and variance.

The Host has the authoritative complete activity record. A guest that joined
late can show **Incomplete activity history**; export from the Host instead.

## Recover an Interrupted Solo Session

At startup, ChronoSync can recover the newest unfinished solo session created
on that device.

1. In **Resume solo session?**, review the Plan and current Step.
2. Select **Resume** to continue, or **Discard session** to remove the recovery.

A running session accounts for time while the app was closed. A paused session
remains paused. Waiting sessions reopen on the first Step. Shared Host and guest
sessions are intentionally not recoverable after the app closes.

## Common Problems

| Symptom | What to do |
| --- | --- |
| **Online team** is locked | Use solo/nearby, or install a build configured with the online service. |
| **Nearby team** is locked on Mac/web | Host from the iPhone app; Mac and web can only join nearby. |
| Nearby QR will not open | Confirm same Wi-Fi, foreground Host iPhone, Local Network permission, and an unexpired invitation. |
| Guest shows **Connection stale** | Restore the Host and network; keep the guest page open while it reconnects. |
| No browser sound | Interact with **Start** or **Join**, unmute the tab/device, and keep the page open. |
| No iPhone haptic | Enable Haptic in **Timing cues** and check device/system haptic settings. |
| **Start session** is disabled in the lobby | The Host must enable **I'm ready**. Guests do not have a readiness control. |
| Cannot join with the displayed code | Join by QR or full link; code entry is not implemented. |
| Mac/iPhone link opened in a browser | Copy the full invitation and paste it into the native app's **Join session** dialog. |
| CSV export is disabled | This device has incomplete activity; export from the Host. |
| Web Plans disappeared | Check the exact site, browser profile, and private-browsing state; restore from a `.chronosync` export if available. |
| App cannot open storage | Select **Retry**. Do not clear app/site data unless you have exports. |

## Safe Operating Checklist

Before a real event:

1. Rehearse the Plan in **Just me** mode.
2. Confirm every Step duration, auto-advance choice, and cue threshold.
3. Charge the Host device and disable disruptive power-saving behavior.
4. Test the actual Wi-Fi and every QR/link.
5. Join one Participant and one Display, then verify role controls.
6. Confirm sound, haptics, projector fullscreen, and accessibility settings.
7. Export an up-to-date Plan archive.
8. Keep the Host open for the entire session and export the Host CSV afterward.

## Current Limitations

Apple Watch is planned after MVP but is not implemented. Also unavailable are
accounts and automatic library sync, collaborative Plan editing, nearby hosting
from Mac or web, automatic Host failover, spreadsheet import, advanced
analytics, and medical, Apple Health, or caregiver workflows.
