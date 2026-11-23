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

Today in Lorvex is one list: every unfinished task whose day is today or
earlier, and every started task. A task's day is its `planned_date` when it has
one, else its `due_date`. Planning the day means deciding what belongs on that
list.

Extra context from the user, if any: $ARGUMENTS

## 1. Read the situation

Call these Lorvex tools, in parallel where possible:

- `get_session_context`: today's date and weekday, the current local time,
  the time zone, and working hours.
- `get_overview` with `shape: "full"`: today's list (`today`), the day's
  briefing, and the most important tasks that are not on today (`tasks`),
  which are the candidates to add. A briefing means the day was planned
  before, so this is a re-plan: keep what still makes sense.
- `get_daily_schedule`: the times already set today. Do not overwrite times
  the user chose.
- `get_upcoming_tasks` with `days: 3`: the tasks of the next three days,
  starting tomorrow, for deadlines that need work today.
- `get_calendar_timeline` with `from` and `to` set to today: the meetings the
  day has to fit around.
- `propose_daily_schedule`: its `available_minutes` is the working time
  today's meetings leave free, counted from now. It saves nothing.
- `read_memory` with `keys: ["user_profile", "routines",
  "behavioral_patterns", "pending_followups"]`: energy patterns, the rules the
  user plans by, estimation habits, and promises from earlier sessions.

## 2. Choose

1. Keep tasks already `in_progress`; the user started them.
2. Then work that unblocks other tasks or protects a near deadline.
3. Then quick, time-sensitive items.
4. Stop at a realistic load. Compare the summed `estimated_minutes` with
   `available_minutes`, and treat a missing estimate as unknown, not zero.
   The number of tasks follows from that time, not from a target count: a
   meeting-heavy day holds fewer, a day of short tasks holds more.

Late work that will not happen today should move to a later day rather than
sit on today. Deferring it takes it off today until that day; its `due_date`
is unchanged, so it still reads as late there. A started task leaves today
only when it is deferred, which pauses it, or finished.

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
4. Only when the user wants a timetable: call `propose_daily_schedule` again
   now that the day's list is settled. For today it starts no earlier than now
   and returns tasks that no longer fit as unscheduled; name them. Save with
   `save_daily_schedule` only after the user accepts the times. To time a
   single task, use `update_task` with `planned_start_time` and
   `planned_end_time`.

## 4. Close

Summarize the changes in a short paragraph. When you learned something
durable, such as "no calls before 10", update `user_profile` with
`write_memory`, keeping the rest of that section intact.
