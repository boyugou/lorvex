# Calendar Behavior

This document is the canonical reference for calendar ownership and
interaction rules across Lorvex surfaces: Week Grid, Month Grid, Day
Timeline, Day Panel, Today, Upcoming, MCP calendar tools, and planning
schedule generation. It exists so future UX or product churn does not
collapse Lorvex-owned calendar events and external provider mirrors into
one ambiguous event model.

## Ownership Model

Calendar surfaces render three families of time-aware items:

- **Tasks** - created, owned, mutated, scheduled, and synced by Lorvex.
  Drag-reschedule, in-place edits, completion toggles, and snooze are
  valid because Lorvex is the canonical owner.
- **`calendar_events` are Lorvex-owned canonical events.** Human users
  can create, edit, delete, link, and export canonical events from
  Lorvex surfaces; AI assistants can do the same through MCP calendar
  tools. These rows are synced Lorvex truth, carry HLC versions, support
  deterministic per-occurrence decisions, and participate in native
  backup/restore.
- **`provider_calendar_events` are read-only external provider mirrors.**
  EventKit, Windows calendar, Linux/ICS, and subscribed feed readers
  mirror external source data into provider tables for display,
  planning, and task association. The source of truth remains the
  external calendar/feed/provider.

`task_calendar_event_links` connects tasks to canonical Lorvex events.
`task_provider_event_links` connects tasks to provider mirrors and is
local-only because provider identity is device/source-specific.

## Canonical Events

Canonical events are editable Lorvex data. The Calendar view and MCP
calendar tools may:

- create, update, and delete `calendar_events`
- replace, cancel, or restore individual recurring occurrences, or edit/delete
  the current and following occurrences as a new series
- link and unlink tasks through `task_calendar_event_links`
- export canonical events to ICS
- export and restore final-state native backups

These operations write Lorvex-owned rows and sync envelopes. Meetings
are ordinary canonical events with attendee, URL, description, and task
link context; they are not a separate `event_type`. Task blocks live in
focus schedules and task-event context, not in `calendar_events.event_type`.

A recurring series separates mutable state into two independently ordered
registers. Content owns title, description, location, URL, color, event type,
person, and attendees; topology owns timing, timezone, recurrence, and the
recurrence generation. This prevents concurrent edits on different devices
from making a title change erase a timing change, or vice versa.

An occurrence decision is addressed by the deterministic tuple
`(series_id, recurrence_generation, recurrence_instance_date)` and has one of
three states: `replacement`, `cancelled`, or `inherit`. The generation prevents
old decisions from reviving after an all-series recurrence reset. These rows
are synced final state, not an undo history.

Monthly recurrence distinguishes a literal day-of-month from a month-end
anchor. A series anchored on the last day of a month whose length that
anchor cannot exceed (the 29th of February in a leap year, the 30th of
April, the 31st of any month) recurs on each month's LAST day
(`BYMONTHDAY=-1`): February yields the 28th or 29th, April the 30th. A
series anchored on a literal mid-month day that some months lack (an
anchored 29th or 30th) SKIPS the months without that day rather than
sliding to a neighboring day.

Occurrence timing resolves against the event's stored timezone. A
wall-clock start erased by a DST spring-forward is rejected at write time
as validation; a fall-back wall clock that occurs twice is accepted and
stored, with the ambiguity surfaced as a `CalendarDstGuard` warning beside
the persisted row. ICS export resolves stored wall clocks
deterministically: an ambiguous time exports as its earlier instant, and a
gap time (reachable only through data that predates the write-time guard)
as the first instant after the gap.

## Provider Mirrors

Provider events stay read-only. Lorvex may render, search, fence, and
use provider mirrors as scheduling constraints, but it does not mutate
the external source through these rows. Users should reschedule, rename,
or cancel provider-owned events in the source calendar app or feed.

This applies to every calendar surface:

- Provider event blocks do not expose Lorvex edit, delete, drag-resize,
  or drag-reschedule handlers.
- Provider rows may expose source/diagnostic context when available.
- Task links to provider events go through `task_provider_event_links`;
  they do not convert the provider event into canonical synced truth.
- Refresh/reconciliation is owned by the provider adapter. A later
  provider refresh may update, hide, or remove the mirror row.

## Drag And Edit Affordances

Task pills support drag-reschedule through the task workflow contract.
Canonical calendar events support Lorvex event edit/delete flows. Provider
event mirrors remain visual/planning context and task-link targets only.

When adding a calendar affordance, first ask which owner receives the
write:

- Task write: use task mutation paths.
- Canonical event write: use calendar event mutation paths.
- Provider event write: do not write through Lorvex; route the user to
  the source provider or keep the affordance read-only.

The boundary protects round-trip integrity. A local edit to an external
mirror would be overwritten by the next provider refresh or create a
false synced fact on devices that cannot write that provider.
