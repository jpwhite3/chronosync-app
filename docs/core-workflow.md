# Create, Run, and Review a Sequence

The Sequence editor and live Session controls work the same way on iPhone, web,
and Mac. Layouts adapt to the screen size, but labels and behavior stay
consistent.

## 1. Set the Device Name

1. Open **Settings** from the bottom navigation on iPhone or the navigation
   rail on a wide screen.
2. Enter a short **Display name**, such as `Workshop lead` or `Training room`.
3. Select **Save name**.

The name is stored only on this device and identifies its actions in shared
session history. No account is created.

## 2. Create a Sequence

For the fastest tour, open **Sequences** and select **Try a sample sequence**.
ChronoSync creates a **Shared rhythm** with four broadly useful sample
Intervals and opens it in the editor.

To start from scratch:

1. Select **Create a sequence** in an empty library or **New sequence** in a
   populated library.
2. Enter a **Sequence name**.
3. Select **Create**.

Each Sequence card shows its Interval count, total runtime, and scheduled
start. Use **Edit** to change it or **Start** to run it. The Sequence menu also
provides **Duplicate**, **Export**, and **Delete**. Deleting a Sequence does not
delete its past Session history.

## 3. Build the Sequence

In **Edit sequence**:

1. Change the title in **Sequence name** if needed.
2. Select **Add interval**.
3. Enter an **Interval title**, **Minutes**, and **Seconds**. An Interval must
   last from one second to 99 hours.
4. Enable **Auto-advance** if the next Interval should begin when this timer
   reaches zero.
5. Optionally enable **Custom timing cues** to override the Sequence defaults
   for this Interval.
6. Select **Add interval** or **Save interval**.
7. Repeat for the remaining Intervals.

Drag an Interval by its handle to reorder it. Its menu also offers **Move up**,
**Move down**, **Edit**, **Duplicate**, and **Delete**. The footer continuously
shows the Interval count and total scheduled runtime.

### Schedule a Start

Select **Scheduled start**, choose a date and time, and confirm. The active
Session can begin automatically at that time. Clear the schedule with the
close control beside it when the Sequence should instead start whenever the
Host is ready.

### Configure Timing Cues

Select **Timing cues** to set:

- the approaching threshold in seconds before zero;
- the overtime threshold in seconds after zero; and
- **Visual cue**, **Sound**, and **Haptic** delivery.

Defaults are an approaching cue at 60 seconds remaining, a due cue at zero,
and an overtime cue after 60 seconds. A short Interval skips the default
approaching cue when its entire duration is no longer than that threshold;
set a custom Interval cue when you need different behavior. Haptics play only
on supported mobile devices, while the setting remains portable with the
Sequence.

Select **Save** when editing is complete. If you go back with unsaved changes,
ChronoSync asks whether to **Keep editing** or **Discard changes**.

## 4. Preview It Solo

1. Select **Start live session** in the editor, or **Start** on the Sequence
   card.
2. On **How will everyone join?**, select **Just me**.
3. Review the first Interval and select **Start session**. A scheduled Session
   may begin automatically when its planned time arrives.

## 5. Operate the Live Session

The large timer is the current Interval's remaining time. **Elapsed** shows its
active elapsed time, and the timing status card reports **Ahead**, **Behind**,
or **On schedule** against the original Sequence. **Up next** previews the
following Interval.

Use the controls as follows:

- **Advance:** move immediately to the next Interval. On the final Interval this
  becomes **Finish session** and requires confirmation.
- **Got it:** record that this device acknowledged the current Interval. It
  never advances the Session.
- **Pause / Resume:** freeze or resume active timing. The original schedule
  remains fixed, so paused time can contribute to Timing drift.
- **−1 min / +1 min:** quickly adjust the current Interval's remaining time.
- **Custom:** enter a signed number of minutes; a negative value removes time.
- **Jump to interval:** choose another Interval and confirm the jump.
- **End session:** stop before completing the final Interval. This is a
  Host-only action in shared Sessions.

Auto-advance behaves like a system-issued Advance and is recorded in history.
Amber status indicates an approaching or due Interval; coral indicates
overtime.

## 6. Finish and Review

On the final Interval, select **Finish session**, review **Finish live
session?**, then select **Finish session** again. Use **End session** only when
the run is ending without completing the final Interval.

The summary compares every scheduled duration with actual timing and shows total
runtime, Timing drift, acknowledgements, and the activity count.

Select **Export CSV** or **Export activity as CSV** for the complete activity
record. Then close the summary. The session remains under **History**; select
its row to reopen the summary and export it later.

## 7. Reuse or Move the Sequence

- Start the same Sequence again from **Sequences** for another workshop,
  class, training session, ceremony, service shift, production, drill, workout,
  game, or anything else your group needs to time together.
- Use the Sequence menu's **Duplicate** action before making a variation.
- Use **Export** for one Sequence or **Export all sequences** from the library
  menu to create a `.chronosync` archive.
- On another device, open the library menu, select **Import .chronosync**,
  review the preview, and select **Import**.

Archives contain Sequences and Intervals only. They do not contain history,
device identities, or invitation secrets, and an import never silently
overwrites an existing Sequence.
