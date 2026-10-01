---
name: plan-day
description: Plan the user's day in Lorvex. Use when the user asks what to work on today, to plan the day or the rest of it, or to fit their tasks around today's meetings.
argument-hint: "[anything to account for, e.g. 'I leave at 4pm']"
---

# Plan the day

Shape today in Lorvex the way a chief of staff would: read the situation, keep
a realistic set of tasks on the day, move the rest, explain the choice in a
short briefing, and time the day around the calendar only when the user wants
a timetable.

Today in Lorvex is one list: every task that is overdue, planned for today, or
started. Planning the day means deciding what belongs on that list.

Extra context from the user, if any: $ARGUMENTS

## 1. Read the situation

Call these Lorvex tools, in parallel where possible:

- `get_session_context`: today's date and weekday, the current local time,
  the time zone, and working hours.
- `get_overview` with `shape: "full"`: today's list and the day's briefing.
  A briefing means the day was planned before, so this is a re-plan: keep
  what still makes sense.
- `get_daily_schedule`: the times already set today. Do not overwrite times
  the user chose.
- `get_upcoming_tasks` with `days: 3`: deadlines just ahead that need work
  today.
- `get_calendar_timeline` with `from` and `to` set to today: the meetings the
  day has to fit around.
- `read_memory` with `keys: ["user_profile", "behavioral_patterns",
  "pending_followups"]`: energy patterns, estimation habits, and promises from
  earlier sessions.

## 2. Choose

1. Keep tasks already `in_progress`; the user started them.
2. Then work that unblocks other tasks or protects a near deadline.
3. Then quick, time-sensitive items.
4. Stop at a realistic load. Compare the summed `estimated_minutes` with the
   free time between the current local time and the end of today's working
   hours, after meetings, and treat a missing estimate as unknown, not zero.
   The number of tasks follows from that time, not from a target count: a
   meeting-heavy day holds fewer, a day of short tasks holds more.

Overdue work that will not happen today should move to a later day rather than
stay overdue.

## 3. Propose, then write

Show the plan before writing anything: what stays on today with one line on
why, what you add, and what you propose to move. After the user agrees or edits
it:

1. `batch_update_tasks` (or `update_task`) with `planned_date` set to today for
   the tasks you add to the day.
2. `batch_defer_tasks` (or `defer_task`) for the work that moves, with a
   `structured_reason` such as `not_today` or `low_energy` when one applies.
   Deferrals are counted, and the weekly review uses them.
3. `set_daily_briefing` with two or three sentences on the shape of the day:
   what matters and why, and what you moved.
4. Only when the user wants a timetable: `propose_daily_schedule` with
   `include_calendar_events: true`. For today it starts no earlier than now
   and returns tasks that no longer fit as unscheduled; name them. Save with
   `save_daily_schedule` only after the user accepts the times. To time a
   single task, use `update_task` with `planned_start_time` and
   `planned_end_time`.

## 4. Close

Summarize the changes in a short paragraph. When you learned something
durable, such as "no calls before 10", update `user_profile` with
`write_memory`, keeping the rest of that section intact.
