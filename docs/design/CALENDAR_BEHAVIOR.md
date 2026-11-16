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
the task's own planned time and task-event context, not in
`calendar_events.event_type`.

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

An edit of the whole current series (`all_in_series`) keeps skipped
occurrences skipped and discards `replacement` decisions, so every remaining
occurrence follows the series values. An edit that changes the start date or
the recurrence grid (frequency, interval, week start, or any BY rule; `UNTIL`
and `COUNT` do not move the grid) starts a new generation and discards every
decision, skipped occurrences included.

Monthly recurrence distinguishes a literal day-of-month from a month-end
anchor. When a rule omits `BYMONTHDAY`, `BYDAY`, and `BYSETPOS`,
a series anchored on the last day of a month whose length that
anchor cannot exceed (the 29th of February in a leap year, the 30th of
April, the 31st of any month) recurs on each month's LAST day
(`BYMONTHDAY=-1`): February yields the 28th or 29th, April the 30th. A
series anchored on a literal mid-month day that some months lack (an
anchored 29th or 30th) SKIPS the months without that day rather than
sliding to a neighboring day.
An explicit positive `BYMONTHDAY` always remains literal: choosing day 31
skips months without a 31st, while `BYMONTHDAY=-1` always means the last day.
The shared summary names months, every month day (including days counted from
the end), weekday ordinals, matching-day positions, and an explicit week start.
Month names stay Gregorian even when the display locale uses another calendar.
The Mac's basic repeat picker presents patterns its weekday/month-day controls
cannot express as Custom. Adjusting the interval preserves all conditions;
choosing a basic repeat option deliberately replaces the pattern while keeping
the interval and ending condition. Rules containing unknown fields remain
opaque Custom values, preserved until explicitly replaced or cleared.

Occurrence timing resolves against the event's stored timezone. A
new wall-clock start erased by a DST spring-forward is rejected at write time
as validation. An occurrence inherited from a valid recurrence or an existing
stored row may retain its exact source start when edited, cancelled, restored,
or split into a following segment. This internal permission matches the full
source date, clock, zone, and all-day state; changing any of them still checks
the proposed start. A fall-back wall clock that occurs twice is accepted and
stored, with the ambiguity surfaced as a `CalendarDstGuard` warning beside
the persisted row. ICS export resolves stored wall clocks
deterministically: an ambiguous time exports as its earlier instant, and a
gap time (an inherited recurrence clock or legacy data)
as the first instant after the gap.

The timeline displays timed events in the product time zone. Its UI projection
retains the exact start and end instants separately from the displayed clock
fields and the event's source zone. Editing or dragging converts the selected
instants back into that source zone; unchanged editor endpoints retain their
original civil fields, including a recurrence's intended spring-gap clock.
Detail-only saves patch only changed fields and retain concurrent changes to
untouched fields. Changing the product zone never rewrites
the event's recurrence zone. Scoped edits compare source dates and spans before
deciding whether a series needs a new anchor. All-day dates and floating clocks
remain civil values. New-event forms pin their displayed zone through save.
A timed event without an end has no implicit persisted duration. Editors show
an Add end time action; removing an end also removes any extra end day. Grid
moves and their undo preserve missing ends, while an explicit resize can add
an end. Optional endpoint updates use nil to retain and an empty string to clear.
Creating an event refreshes the last requested calendar window with projected
occurrences and matching tasks. It never appends a raw mutation result, even
when the saved event falls outside that window or a post-commit read fails.
A page turn supersedes older loads; a mutation that starts during navigation
reloads the requested page, not the previously loaded page. Inclusive window
boundaries remain unchanged, including a window covering only one day.
Repeat defaults and automatically followed weekdays/month days read that same
storage frame using a Gregorian calendar. The Mac editor names the recurrence
zone when it differs from the Start/End display zone. An all-day repeat uses
its civil date, and opening a new event never inherits an edited event's zone.
The detail summary also names an implicit weekly day in the source frame,
using a UTC-midnight civil anchor for the shared recurrence formatter. Event
details name a differing recurrence zone; the iPhone edit form shows the
stored rule and that same note without changing the rule's editing contract.
Shared and copied text includes years, the displayed clock's zone, and a
differing recurrence-zone note. Zone offsets come from the event's instants,
not the time of sharing. A span crossing an offset change formats its endpoints
separately with their offsets: an interval formatter can collapse distinct
instants with equal fall-back wall clocks. Midnight ends name their endpoint
date even when the grid counts only one occupied day. All-day dates and floating
clocks are formatted as civil values without an inferred device zone.

An offset change never invalidates a positive instant span, even when its
displayed end clock is earlier than its start. Source timing stays validated
in its own frame. The 24-hour grids split occupied time at offset changes and
label each piece with its GMT offset. The pieces open the same event; editing
these events uses the event sheet, since dragging a piece cannot describe the
whole span. Details and agenda labels retain the true endpoints with both
offsets, including the two readings of an equal clock. Drawing minimums and
open-ended placeholders never become reported end times. Planning and load
statistics union the occupied civil-clock pieces, conservatively reserving a
minute when either reading is busy. Agendas order projected events by their
instants and use the real clock for completion state during a repeated hour.

Calendar headers and month cells mark the loaded product day as Today. The
now indicator and initial time-axis scroll read wall minutes in the product
zone, not the device zone; a stale logical day has no now indicator until its
snapshot refreshes. All-day task overdue status uses the same logical day as
Today. Day coordinates remain civil labels, and clock ticks neither repack
event lanes nor reset a person's manual scroll position.

## MCP Time Context

`get_calendar_timeline` returns the display `timezone` alongside its inclusive
`from` and `to` day keys, even for an empty window. Each row's `timezone`
interprets that row's clock fields. Zoned timeline rows therefore name the
product zone; source-definition reads such as canonical search and write echoes
name the stored source zone. All-day/date-only rows have no clock zone, and
floating clocks never acquire an inferred absolute instant.

Response-only `time_context` accompanies temporal/recurrence fields:

- `kind`: `zoned`, `floating`, `all_day`, `date_only`, or `unresolved`.
- `clock_basis`: `display` for projected instants, `source` for unprojected
  source clocks, or `civil` for floating/all-day/date-only values.
- `source_timezone`: the stored source and recurrence zone, when present.
- `start_at` / `end_at`: known UTC instants in ISO 8601 with milliseconds.
  They accompany the corresponding selected clock fields. No end is invented
  for an event without an end, and source-only definitions do not guess instants.
- `source_timing`: original canonical civil fields for editing, included with
  `shape=full` or `include=["time"]` when `fields` is absent. A projected
  occurrence retains its intended source clock even on a spring gap. Provider
  rows are read-only and omit this editing payload.

Explicit `fields` selection still limits returned event data. Selected clocks
receive `timezone` and time context automatically; date-only selections do not
reveal clock values through instants, and title-only selections have no time
context. Null policy applies inside the context and source timing; a selected
clock's absent timezone is explicit. The input field enums remain unchanged.

Use canonical `event_id` for mutations, keeping `occurrence_date` as the
original source slot for scoped edits even when the displayed date differs.
The source timing of an expanded occurrence is suitable for that occurrence;
whole-series updates use the stored master returned by search, so a later
occurrence does not silently become the series anchor. Omitting timing fields
when editing only content preserves the schedule. Recurrence remains in its
stored source frame when the product display zone changes.

Timeline paging orders rows by displayed start day, actual start instant, title
and stable row id. Times precede missing times. Floating clocks use the display
zone's earlier reading (or snapped gap) solely as a sort coordinate; returned
values remain floating. Search and task links return source definitions or a
provider series' first cached observation under its stable source identity,
not expanded date-range occurrences. Linked provider reads use the same exact
instant decoder as timeline/search while retaining their limited-detail and
privacy-tier contract.

## Provider Mirrors

Provider events stay read-only. Lorvex may render, search, fence, and
use provider mirrors as scheduling constraints, but it does not mutate
the external source through these rows. Users should reschedule, rename,
or cancel provider-owned events in the source calendar app or feed.

Timed EventKit observations with a source time zone retain their absolute
start/end instants. The Mac keeps one series row with its source rule, zone,
and observed occurrence set; iOS keeps its existing occurrence rows. These
observations drive display and occupancy, including the two readings of a
fall-back hour. The source rule is metadata, not a reason to invent unseen or
cancelled occurrences beyond the fetched cache. Floating and all-day events
keep civil-time semantics; legacy caches use their previous projection until
refreshed. An in-window refresh replaces that window's observations and keeps
other cached weeks, including stable provider task-link identities. The exact
occupancy survives busy-only redaction without carrying event details.

This applies to every calendar surface:

- Provider event blocks do not expose Lorvex edit, delete, drag-resize,
  or drag-reschedule handlers.
- Provider rows may expose source/diagnostic context when available.
- Task links to provider events go through `task_provider_event_links`;
  they do not convert the provider event into canonical synced truth.
- Refresh/reconciliation is owned by the provider adapter. A later
  provider refresh may update, hide, or remove the mirror row.

## Duplicate Display Groups

The main macOS and iOS app surfaces share `CalendarDuplicateGrouping`: off,
strict (default), and title plus exact start/end times. Grouping is a display
projection over the raw timeline and calendar search; MCP reads, provider rows,
links, notifications and sync records retain every source event. A selected
copy determines the details and sharing target. Imported events stay read-only.

Only fully readable provider events with known, distinct origin calendars can
combine. Strict also compares location, notes, URL, organizer, attendees and
response states, source timezone and recurrence context, including source rules
and alarms that an expanded occurrence cannot reconstruct. Calendar color and
participant ordering do not distinguish event content. A candidate set with
two matching events in the same calendar stays separate in its entirety.
Titles are exact, never fuzzy; overlapping ranges do not qualify. Timed zoned
events compare exact instants (including the repeated hour), floating clocks
stay distinct, and all-day events compare inclusive civil spans.

EventKit imported identities qualify the server UID by source calendar. A
single UID can name several copies, so it cannot alone identify a source.
Migration 006 adds full-detail origin metadata and rebuilds only the disposable
EventKit mirror. It preserves owned events, task links and sync data. Verified
unambiguous legacy links are reassociated at ingest; ambiguous UIDs remain
unresolved rather than silently selecting a different calendar.

## Drag And Edit Affordances

Task pills support drag-reschedule through the task workflow contract.
Plan blocks (a task's saved planned time, drawn on the time axis of
the macOS day and week grids and the iPhone day grid) open their task and
carry no drag or resize handlers:
the schedule owns the time, and it is proposed, saved, and cleared on Today.
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
