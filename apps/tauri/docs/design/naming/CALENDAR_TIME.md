# Calendar and Time Naming

## Scope

This document defines naming for:

- canonical calendar events
- provider calendar mirrors
- timeline and blocking ranges
- working hours
- day/time anchors
- schedule blocks vs calendar events

## Current State In Code

Observed in:

- `lorvex-store/src/calendar_timeline/queries/`
- `mcp-server/src/calendar/`
- planning schedule code that consumes blocking ranges

Current code reality:

- `calendar_events` are canonical Lorvex-owned events
- `provider_calendar_events` are local mirror rows
- `get_calendar_timeline` returns projected occurrences
- `get_day_blocking_ranges` derives planning constraints from that timeline
- `focus_schedule` uses calendar blocking ranges as constraints, not as identity source

## Canonical Distinctions

### Canonical Calendar Event

Canonical name:

- `calendar_event`

Meaning:

- Lorvex-owned, synced calendar event

### Provider Calendar Event

Canonical name:

- `provider_calendar_event`

Meaning:

- device-local mirrored external calendar event

This is not synced truth.

### Calendar Timeline

Canonical name:

- `calendar_timeline`

Meaning:

- projected occurrence stream for display/query

### Blocking Range

Canonical name:

- `blocking_range`

Meaning:

- a schedulable-time constraint derived from calendar occurrences

This is what planning code should consume.

### Working Hours

Canonical name:

- `working_hours`

Meaning:

- planning boundary preferences used by focus scheduling

### Focus Schedule Blocks

Canonical names:

- `task block`
- `buffer block`
- `event block`

Meaning:

- planning output blocks
- not raw calendar event rows

## Day and Time Anchors

Current code already distinguishes:

- anchored timezone
- active timezone
- date-scoped aggregates

Naming rule:

- use `today` only when explicitly anchored to canonical day-boundary logic
- use `date` for neutral persisted keys
- use `start_date` / `start_time` for event fields
- use `planned_date` and `due_date` for task planning/lifecycle, not calendar events

## Avoided Confusions

Do not conflate:

- calendar event and schedule block
- provider event and canonical event
- timeline and blocking range
- working hours and focus schedule

The word `schedule` should be reserved for planning output, not generic calendar data.

## Final Decision

The calendar/time naming system should be treated as:

- `calendar_event` = canonical synced event
- `provider_calendar_event` = local mirror event
- `calendar_timeline` = occurrence stream for display/query
- `blocking_range` = planning constraint derived from calendar data
- `working_hours` = planning preference boundary
- `focus_schedule` = planning output over focus tasks, not calendar truth
