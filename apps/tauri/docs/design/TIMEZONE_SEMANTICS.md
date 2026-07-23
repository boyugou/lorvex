# Timezone Semantics

This document defines the canonical date/time model for MCP tools and app behavior.

## Decision Summary

1. Task deadlines (`tasks.due_date`) are floating local-calendar dates (`YYYY-MM-DD`).
2. Calendar events (`calendar_events`) are absolute-time commitments with explicit timezone context.
3. "Today" task operations must use local-calendar day boundaries, not UTC date slicing.

## Data Model Semantics

### Tasks: floating local dates

- `due_date` is a calendar date without timezone.
- Interpretation: "this is due on this local day for the user."
- `due_time` is optional wall-clock time, still local-context (no timezone field on tasks).
- MCP queries comparing `due_date` (`<`, `=`, `>=`) are date-only local-calendar comparisons.
- Task sorting (priority + due_date) and Eisenhower urgency classification (deadline proximity) use the same local-calendar day boundary.

Examples:
- `due_date = 2026-03-04` means due on March 4 in the user's local day context.
- If the user travels, the calendar date remains `2026-03-04`; it does not shift like a UTC instant.
- If an API accepts a timestamp-like due-date input (for example RFC3339), the timestamp must be converted into the user's local calendar day before storing `YYYY-MM-DD`. Do not persist the source timestamp's own calendar date verbatim.

### Calendar events: absolute-time commitments

- `calendar_events.timezone` stores IANA timezone context for the event.
- Start/end date-time fields model fixed-time commitments (meetings, appointments, travel blocks).
- These are not interchangeable with floating task deadlines.

### Reminder timestamps

- Instant timestamps such as `reminder_at` remain ISO 8601 UTC timestamps.
- They model exact moments, not floating dates.

## MCP Behavior Rules

### Local "today" operations

For MCP paths that define "today" or date windows from "today":

- `get_overview`
- `get_todays_tasks`
- `get_upcoming_tasks`
- `set_recurrence` when backfilling empty `due_date`
- Widget/mobile-runtime snapshot generation when bucketing overdue / due-today tasks or selecting the current focus

The server must derive `today` from local calendar fields (`getFullYear/getMonth/getDate`), never from `toISOString().slice(0, 10)`.

If a valid explicit timezone preference is present for snapshot/glance surfaces, those surfaces should derive `today` in that configured timezone and emit the same timezone in the payload. They must not advertise one timezone while bucketing tasks using another.

Task query paths that bucket by date (overdue/today/upcoming) must use the same timezone context as the day-boundary helpers.

Rationale: UTC slicing can roll the day forward/backward near midnight and cause task drift between "overdue", "today", and "upcoming" buckets.

## Implementation Note

The canonical DB/preference-aware layer for local-day calculations is
`lorvex-workflow/src/timezone`. MCP, Tauri, and CLI code should route
day-scoped task queries through that workflow layer so timezone preference
lookup and fallback behavior stay shared.

The MCP-local time re-export module is not the product contract; it is
only a thin test-support surface for domain date math.

Avoid reimplementing date-boundary logic inline in tool handlers.

For day-scoped windows over absolute timestamp columns (`completed_at`, `created_at`, `updated_at`):

- derive the local-day window first
- convert that window into explicit UTC start/end boundaries through the conn-aware helpers
- compare timestamp columns with `datetime(column) >= datetime(?)` and `datetime(column) < datetime(?)`

Do not use rolling UTC helpers like `datetime('now', '-7 days')` for local-calendar review windows or recent-completion retention. Those operators model the last 168 absolute hours, not the user's last 7 local calendar days.

For date bucketing and Eisenhower urgency classification, use the timezone-aware day-window helpers:

- `app/src-tauri/src/commands/day_context/` (timezone, parsing, window helpers)
- `mcp-server/src/system/time_support.rs` (today_ymd, date_plus_days, trailing_window)

Do not classify `due_date` proximity by parsing `YYYY-MM-DDT23:59:59` against host-local `now`.

## Non-Goals

- No schema changes in this hardening pass.
- No conversion of task deadlines to absolute timestamps.
- No change to event timezone schema or reminder storage format.
