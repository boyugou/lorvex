---
name: daily-review
description: Close the user's day in Lorvex with a short daily review. Use when the user says they are done for the day, asks for a daily review or an end-of-day wrap-up, or asks how today went.
argument-hint: "[how the day felt, in the user's own words]"
---

# Daily review

A few minutes at the end of the day: you read what happened and draft the
entry, and the user corrects it. The review is the user's own record, so how
the day felt is theirs to say.

How the day felt, if the user already said: $ARGUMENTS

## 1. Gather

Call these Lorvex tools, in parallel where possible:

- `get_session_context`: today's date and the current local time.
- `get_daily_review`: today's review, or `null`. When one exists, this is an
  update: show what it says first.
- `list_tasks` with `status: "completed"` and both `completed_from` and
  `completed_to` set to today: what moved forward.
- `get_overview` with `shape: "full"`: today's list, so you can see what is
  still open, and the day's briefing, if one was written.
- `get_habits`: which habits were kept. A habit with `skipped_today` was set
  aside by the user, which is not a miss.

## 2. Draft

Show the draft in plain sentences, in this order, and write nothing yet:

1. **Moved forward**: the completed tasks, naming the two or three that
   mattered most.
2. **Still open**: what is left on today, and the tasks you would move to
   tomorrow.
3. **Habits**: the ones kept, and the ones that were not.
4. **The entry**: a `summary` of two to four sentences built from the facts
   above, and `wins`, `blockers`, and `learnings` only where the day or the
   user's words support them. Never invent a feeling or a reason.

Then ask for the two ratings, `mood` and `energy_level`, each 1 to 5. Do not
guess them. If the user skips a rating, leave it out.

## 3. Write

After the user answers or edits the draft:

- No review yet: `add_daily_review` with the agreed fields and
  `linked_task_ids` for the tasks the summary names.
- A review exists: `amend_daily_review` for only the fields the user changed.
  `add_daily_review` would replace the whole entry.
- Open tasks the user wants off today: `batch_defer_tasks` with `until_date`
  set to tomorrow and a `structured_reason` such as `not_today` or
  `low_energy` when one applies. Defer only the tasks the user named, and say
  the date.

## 4. Close

Say in a sentence or two what was recorded and what moved to tomorrow. The
weekly review reads these entries, so a blocker that keeps coming back is
worth a line in the entry.
