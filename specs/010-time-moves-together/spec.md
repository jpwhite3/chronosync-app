# Feature Specification: Time Moves Together

**Status**: Implemented language refresh
**Product**: ChronoSync

## Intent

ChronoSync is a local-first shared timer for groups moving through a sequence
together. It is not defined by one industry or activity: workshops, classes,
training, ceremonies, service teams, productions, drills, workouts, games, and
many other coordinated activities can all share the same timed flow.

The product voice is clear first and lightly time-themed second. It should feel
purposeful and memorable without forcing metaphor into controls where familiar
language is safer.

## Product Language

| Concept | User-facing term | Internal compatibility name |
| --- | --- | --- |
| Reusable ordered timer set | **Sequence** | `Plan` |
| One timed part | **Interval** | `Step` |
| One live execution | **Session** | `LiveSession` |
| Role that operates shared timing | **Timekeeper** | `SessionRole.controller` |
| Difference from the original timing | **Timing drift** | variance fields |
| Current and following parts | **Current interval** and **Up next** | current/next `Step` |

The tagline is **Time moves together.** Supporting copy may use words such as
rhythm, pace, moment, and sync when they remain accurate and easy to understand.

Product copy must not use **Plan**, **Step**, **Event**, **Runbook**, or
**run of show** as category nouns. Ordinary uses such as “planned duration,”
historical specifications, source identifiers, and platform programming events
are outside this rule.

## Compatibility Boundary

This is a presentation and positioning change, not a storage or protocol
migration. Existing Dart types, database tables, archive keys, MIME types,
encrypted session messages, legacy Hive `Series`/`Event` migration types, and
the `.chronosync` file format remain stable. Renaming those contracts requires
a separately versioned migration and cross-version compatibility design.

## Requirements

- The app navigation, library, editor, live views, summaries, settings,
  notifications, accessibility labels, dialogs, and errors use the product
  language consistently.
- The starter content is activity-neutral and demonstrates a Sequence of
  Intervals without implying that ChronoSync is primarily for live events.
- User documentation opens with the broad shared-timer value proposition and
  treats use cases as examples rather than boundaries.
- Developer documentation explicitly maps the product language to internal
  compatibility names so contributors do not rename serialized contracts by
  accident.
- Historical specifications retain their original terminology. Current release
  validation recruits representative groups across multiple use cases.

## Acceptance Criteria

- A new user can create a **Sequence**, add **Intervals**, and start a live
  **Session** without encountering the old product nouns in that journey.
- Shared-session controls and assistive technology identify the operating role
  as **Timekeeper** and timed parts as **Intervals**.
- Summaries explain ahead/behind results as **Timing drift**.
- Import/export remains backward compatible with existing `.chronosync`
  archives and connected clients.
- Automated widget tests cover the library, editor, navigation, and live-view
  terminology, and the complete analyzer/test suite remains green.
