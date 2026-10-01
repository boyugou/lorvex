---
name: weekly-review
description: Run a guided weekly review of the user's Lorvex tasks. Use when the user asks for a weekly review, a look back at the week, what slipped or stalled, or a plan for next week.
---

# Weekly review

A short review the user can finish in a few sentences: you do the clerical
work, and the user makes the decisions.

## 1. Gather

- `get_weekly_brief`: completed this week, stalled lists, frequently deferred
  tasks, overdue count, someday items, tasks created this week, and estimate
  accuracy.
- `get_overview`: the current state.
- `read_memory` with `keys: ["list_summaries", "behavioral_patterns",
  "pending_followups"]`.
- `get_review_history` with `from` set to seven days ago: when the user keeps
  daily reviews, their wins and blockers are the best evidence for the week.

## 2. Present

Keep it short and concrete, in this order:

1. **Wins**: what got done, highlighting the two or three that mattered most.
2. **Slipped**: tasks deferred again and again (`frequently_deferred`) and
   overdue work.
3. **Stalled**: lists with no recent completions.
4. **Suggestions**: at most five numbered options, each a concrete action the
   user can accept in a word: drop it, break it into smaller tasks, schedule
   it for a day next week, or park it in Someday.

Change nothing yet.

## 3. Apply the decisions

Do exactly what the user decided, with batch tools where they fit:

- Drop: `cancel_task` or `batch_cancel_tasks`.
- Break down: `batch_create_tasks` for the smaller steps, then cancel or keep
  the original as the user prefers.
- Schedule: `batch_update_tasks` with `planned_date` (the intended work day)
  and, if asked, `priority`.
- Park: `set_task_someday`.

Leave anything the user did not address as it is.

## 4. Record

- Update `list_summaries` and `behavioral_patterns` with `write_memory` when
  the review changed them (for example, "writing tasks take about twice the
  estimate"). Rewrite the whole section: `write_memory` replaces it.
- Remove resolved items from `pending_followups`.
- If the user says how the week felt, record it with `add_daily_review` for
  today.
