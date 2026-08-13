# Shared Sessions and Roles

A shared Session has one authoritative Host and one or more Timekeepers,
Participants, or Displays. Create role-specific invitations so every device
gets only the controls it needs.

## Choose Nearby or Online

| Mode | Host | Guests | Internet | Invitation lifetime |
| --- | --- | --- | --- | --- |
| **Nearby** | Foreground iPhone app | Same Wi-Fi; browser, iPhone, Mac, or web | Not required | 8 hours |
| **Online** | iPhone, web, or Mac when configured | Any supported device with Internet | Required | 24 hours |

The Host app or page must remain open in either mode. There is no automatic
Host failover.

## 1. Prepare the Lobby

1. Start a Sequence and choose **Nearby** or **Online**.
2. In **Session lobby**, use **Join as participant** for people who should
   follow and acknowledge Intervals.
3. Use **Open display** for a projector or read-only status screen.
4. Ask guests to scan the appropriate QR code or select **Copy link** / **Share**.
5. Watch **People** for connected devices.
6. Before starting, use a person's role menu to change them to **Timekeeper**,
   **Participant**, or **Display**. Use the remove action to revoke that
   device's access.
7. Enable the Host-only **I'm ready** checkbox, then select **Start session**.

The lobby's short session code helps people visually confirm that they are
looking at the same room. There is no join-by-code form in the current app, so
always share the QR code or full invitation link.

Role management is available in the pre-session lobby. During the run, the
Host's **Connected people** view is read-only.

## 2. Join as a Teammate

### Full iPhone, Web, or Mac App

1. Select **Join session**.
2. Paste the complete invitation or select **Paste from clipboard**.
3. Confirm that the form says **Invitation ready** and shows the intended role.
4. Enter **Name for this session** for a Participant invitation.
5. Select **Join session** and wait for the Host's encrypted snapshot.

### Nearby Browser Page

1. Scan the Host's QR code while connected to the same Wi-Fi.
2. For a Participant invitation, enter **Your name** and select **Join live
   session**.
3. For a Display invitation, select **Open display**; no name is required.
4. Keep the page open. If needed, select **Reconnect** after the Host or Wi-Fi
   becomes available again.

The lightweight nearby page is deliberately smaller than the full app. If the
Host promotes it to Timekeeper, it provides **Pause / Resume**, **−1 min**,
**+1 min**, and **Advance**, but not Custom adjustment, Jump, or End.

## 3. Understand the Roles

| Action | Host | Timekeeper | Participant | Display |
| --- | :---: | :---: | :---: | :---: |
| See current/next Interval and timing | Yes | Yes | Yes | Yes |
| Tap **Got it** | Yes | Yes | Yes | No |
| Pause/resume and Advance | Yes | Yes | No | No |
| Adjust remaining time | Yes | Yes | No | No |
| Jump to another Interval | Yes | Yes in full app | No | No |
| Finish the final Interval | Yes | Yes | No | No |
| End the session early | **Yes** | No | No | No |
| Change roles or remove devices | **Yes, in lobby** | No | No | No |

### Participant

The Participant view emphasizes the current Interval, remaining time, Timing
drift, next Interval, and one large **Got it** action.

**Got it is not Advance.** It records one acknowledgement for the current
Interval so the Host and Timekeepers can see who confirmed it and when. It
never advances the Sequence, even if everyone acknowledges.

### Timekeeper

A Timekeeper can run the timing workflow without getting Host authority. In
the full app it can pause/resume, Advance, use quick or Custom adjustments,
Jump to an Interval, acknowledge, and finish the final Interval. It cannot end
the room, change roles, or remove people.

### Display

The Display is a control-free, high-contrast view intended for a projector,
classroom screen, training station, service counter, production monitor, or
shared status board.

On web and Mac, use the fullscreen icon. The Display cannot send commands or
acknowledgements.

## 4. Handle Connection Problems

If a guest can reach the relay or Wi-Fi but no longer has a verified Host, it
shows **Connection stale**. ChronoSync freezes its timer and disables commands
rather than guessing. Keep the app/page open, restore the original connection,
and allow automatic reconnection. There is no leader election.

For nearby sessions, verify that the Host iPhone is unlocked, ChronoSync is in
the foreground, Local Network access is allowed, and every device remains on
the same Wi-Fi. For online sessions, verify Internet access and keep the Host
page or app open.

## 5. Finish the Room

On the final Interval, a Host or Timekeeper selects **Finish session**, confirms
**Finish live session?**, and opens the summary for everyone. Only the Host can
use **End session** to stop early. Ending also revokes the active invitation.

Export the complete CSV from the Host. A late joiner may have only recent
activity, display **Incomplete activity history**, and have CSV export disabled.
