# Decision record: Today is one list

**Status:** Accepted on 2026-09-28. This record replaces the Focus model: the
per-day curated task list, the Focus section on Today, and the current task
(Now and Next) derived from it.

---

## 1. Context

Today was built from three overlapping concepts:

- **Focus**: a per-day list of hand-picked tasks in a set order, with the
  assistant's briefing attached. A task in Focus was on Today whatever its own
  dates said.
- **The schedule**: a per-day set of time blocks. The page derived one current
  task from it and flagged blocks that ran out.
- **The day's dates**: tasks planned for today or earlier, due today or
  overdue, and tasks already started.

The page split the day into Focus, Overdue, and Also today, marked one task as
Now or Next, offered 30 more minutes when a block ran out, and asked to replan
when several had.

In use, this model worked against how people work:

1. **Two tiers of today.** "Also today" held tasks that were on today by their
   dates but outside the plan. That state asks nothing of the user and settles
   nothing: such a task should either be done today like the others or move to
   another day.
2. **Two signals of importance.** Focus membership and priority could disagree:
   a high-priority task outside Focus sat below lower-priority tasks inside it.
3. **A duplicate of the briefing.** The briefing named the day's important
   tasks and said why; the Focus section listed the same tasks again without
   the reasons.
4. **Serial work assumed.** People start a long-running job and review papers
   while it runs, and interleave replies with deep work. A single Now or Next
   task does not describe that day.
5. **Time blocking assumed.** Most people never schedule their day. For them
   the schedule machinery stayed empty, and the plan's order was an order
   nobody chose.

"Focus" is also the name of the system Focus modes on Apple platforms, which
made the word ambiguous inside Lorvex.

## 2. Decision

**Today is the set of tasks the user means to deal with today, shown as one
list.** The assistant expresses its judgment about the day through which tasks
are on it and through a short briefing, never through a second tier inside the
day.

| Concept | Meaning | Set by |
|---|---|---|
| **Today** | Unfinished tasks planned for today or earlier, due today or overdue, or started. | The task's dates and status |
| **Briefing** | The assistant's short note on one day: what matters and why, what is at risk, what it moved. The app shows it and never edits it. | The assistant |
| **Priority** | The one importance property. It orders Today. | The assistant; the user corrects it |
| **Started** | A task the user has begun. Several can be started at once. | The user or the assistant |
| **Time** | An optional start and end for a task on the day it is planned for: an appointment with oneself. | The user or the assistant |
| **Defer** | Moving a task to a later day, or to no day. It is how a task leaves Today. | The user or the assistant |
| **Capacity** | Today's estimated work compared with the free working time left. | Derived |

These leave the product: Focus (its list, its order, its section, and its
name), "Add to Focus", "In Plan", "Also today", the current task (Now and
Next), "Ran out", "+30 min", and "Replan from now".

## 3. Today's page

The same structure on macOS, iPhone, and iPad, top to bottom:

1. **The date** and one **facts line**: tasks left, the estimated work when any
   task carries an estimate ("about 5 hr of work"), and meetings still ahead.
2. **The briefing**, when the assistant wrote one for today.
3. **One decision when today is overbooked.** While working hours remain and
   the estimated work exceeds the free working time left, the page says so
   ("About 6 hr of work and 4 hr free") and offers to move the least urgent
   tasks that do not fit to tomorrow, naming them. The candidates are tasks
   that are not started, not timed, and not due today or earlier, taken from
   the end of the list. Nothing else about capacity asks for attention.
4. **The list.** Started tasks lead, then everything else, each group in the
   canonical order (priority, then due date). There are no section headers: an
   overdue task carries its red due label and a started task its Started chip,
   so each row says what a header would have.
5. The quick-add field (macOS), the day's habits (iPhone and iPad), what is
   already done (folded on request).

The schedule (the pane beside Today on macOS and iPad, a sheet on iPhone, and
the strip at the top of iPhone Today) draws calendar events and timed tasks on
the clock. It is where the user asks for suggested times and clears the day's
times (section 5).

## 4. A task row

A row is the circle that completes the task, the title, and one metadata line
(list, time, due, estimate, tags). Chips mark state that explains the row or
asks for a decision: Started, Blocked, Pushed often, and "Until 3:00 PM" on a
timed task whose time is running.

Actions, on every platform that shows rows:

- **Complete**: the circle.
- **Start** and **Pause**: the started state. macOS: the row's hover button,
  the context menu, the task detail's action row, and ⇧⌘S.
  iPhone and iPad: the leading swipe, the context menu, and the task detail.
- **Defer**: Tomorrow, Next week, a chosen day, or no day. macOS: the hover
  button, the context menu, the task detail, and ⇧⌘D for Tomorrow. iPhone and
  iPad: the trailing swipe, the context menu, and the task detail.
- **Open**: the task detail.

## 5. Time

A time is an optional start and end on the day a task is planned for. These
rules keep it attached to that day:

- A time needs a planned date and both ends. It ends after it starts, at the
  latest at the midnight that ends the day.
- Moving the task to another day without giving it a new time, deferring it,
  or clearing its planned date clears its time. Clearing the time keeps the
  day.
- Completing a task keeps its time: the finished task stays on the day's
  schedule and calendar grid, marked done, as the day's record. A cancelled
  task is not drawn.
- Un-completing a task and pausing a started task put it back where it was,
  with its day, its time, and its deferral count, because both reverse a
  single tap. Returning a cancelled or someday task to open is a fresh start:
  its planned date, its time, and its deferral history were decided before the
  task was set aside, so they are cleared.

A timed task shows its time on its row ("2:00 – 3:00 PM") and stands on the
calendar grid with the day's meetings. While its time runs, the row's chip
reads "Until 3:00 PM". When its time has passed and the task is unfinished, the
row keeps its time and nothing else happens: no "ran out", no offer of more
time, no question about replanning. A time is information the user chose to
record, not a plan the page enforces.

The user sets a time in the task detail's When picker. "Add Time" proposes the
next half hour when the day is today, else 9:00, lasting the task's estimate or
30 minutes. Moving the start keeps the length, the way a calendar event moves.

Suggested times are a service, not a mode. "Suggest Times" in the schedule
lays today's tasks into the free working time from now on, around meetings.
Taken in Today's order, each task gets the earliest free time long enough to
hold it, so a short task can use a gap before a meeting that a longer task
ahead of it did not fit. A timed task already under way keeps its place, a
task without an estimate takes 30 minutes, a ten-minute break follows a task
when it fits, and work whose time passed unfinished is placed again from now.
The user accepts or dismisses the suggestion; a day with no
open tasks offers none. Accepting plans each timed task for the day, so a timed
task is always on its day's list, and the day's other unfinished tasks lose
their times but stay on the day. "Clear Times" removes the day's times and
keeps every task on the day; on iPhone it asks for confirmation first.

## 6. Glances

Every glance leads with the same task, and only when the day says it is the
one that matters now: a timed task whose time is running, else the first
started task, else the timed task that starts next. When none of those exists
no task leads, and a glance shows Today's list from its top with a line saying
how many tasks are left and the work they hold ("5 left today · about 3 hr").
The top of the list is where the plan starts, not an instruction to do that
task now, so a glance never promotes it on its own. The lead carries no "Now"
or "Next" label; its line (the countdown, the time, "Started") says why it
leads.

- **Widgets.** One Today widget (small, medium, large, and the Lock Screen
  families), optionally scoped to one list: the lead task when one leads, the
  tasks after it with their circles, and "N more today". The large size adds the briefing. A
  running timed task shows its time ring. The Control Center button opens
  Today. Habits and Progress are unchanged.
- **Menu bar (macOS).** The lead task, the next two, and one line for the rest.
- **Watch.** The first page is Today: the running timed task with its ring when
  there is one, then the list. A task's actions are Start or Pause, Defer, and
  Cancel. The complication shows how many tasks are left and the lead task.
- **CarPlay.** One list, Today, in the same order; each row offers Complete and
  Defer.
- **Siri and Shortcuts.** Intents read today's list, start, pause, or defer a
  task, plan one for today, and read, suggest, or save the day's times.
  Suggesting times for a day with no open tasks answers "Nothing on <date>
  needs a time." Intents that return task content require Face ID, Touch ID, or
  the passcode, and intents that change existing tasks require an unlocked
  device; capturing a new task and opening Lorvex work from the Lock Screen.
- **The system Focus filter.** An Apple Focus mode can narrow the widgets and
  the watch to chosen lists; while it is on, they also leave out the briefing.
  The app, notifications, and Shortcuts keep every list. The filter's former
  options, a Focus profile and whether to show tasks outside Focus, left with
  Focus.

## 7. The assistant

Planning a day is choosing which tasks are on it:

1. Read the situation: `get_session_context`, `get_overview` with
   `shape: "full"` (which carries the day's list and its briefing),
   `get_daily_schedule`, upcoming deadlines, the calendar, and memory.
2. Put the chosen tasks on the day with `batch_update_tasks` (`planned_date`),
   adjust priorities, and move what will not fit with `batch_defer_tasks`.
3. Write the day's briefing with `set_daily_briefing`: two or three sentences
   on what matters and why.
4. When the user wants a timetable: `propose_daily_schedule`, then
   `save_daily_schedule` once the user accepts. A single task's time is set
   with `update_task` (`planned_start_time` and `planned_end_time`).

Today does not list the assistant's writes. Each one is recorded in
`ai_changelog` with the entity's state before and after, shown under
Settings > Diagnostics and returned by `get_ai_changelog`, so the history can be
reviewed later without taking room on the day.

`get_current_focus`, `set_current_focus`, `add_to_current_focus`,
`remove_from_current_focus`, and `clear_current_focus` are removed.
`save_focus_schedule` and `get_saved_focus_schedule` become
`save_daily_schedule` and `get_daily_schedule`, and `set_daily_briefing` is
new. The server instructions and the plan-day skill teach the flow above.

## 8. Data

Lorvex had not launched when this model shipped, so the model is stored
directly instead of being mapped onto the Focus tables, and data from earlier
builds does not carry over:

- **Schema.** `current_focus`, `current_focus_items`, `focus_schedule`, and
  `focus_schedule_blocks` are gone. A task's time is two columns beside
  `planned_date`, `planned_start_minutes` and `planned_end_minutes`, and the
  table's checks enforce the first rule of section 5. `daily_briefings` holds
  one briefing per day; clearing a briefing deletes its row.
- **Sync and backups.** The task's sync payload carries its planned time, and
  `daily_briefing` is its own sync entity. A backup archive holds
  `daily_briefings.json` in place of the Focus files.
- **CloudKit.** Sync uses a new namespace (zones prefixed `LorvexGeneration-`
  and a new generation control record), so the new build never reads records an
  earlier build wrote, and an earlier build never reads the new ones.
- **Earlier databases.** A database written by an earlier build is not
  migrated, and no import path from earlier builds exists; the only person with
  data in them re-creates it through the assistant. Such a database records a
  schema checksum this build does not know, so the store refuses to open it and
  leaves the file untouched.
- **System identifiers.** The Today widget's kind
  (`com.lorvex.apple.widget.today`), the Control Center control's kind
  (`com.lorvex.control.today`), and the watch complication's kind
  (`com.lorvex.apple.watchkitapp.widgets.today`) are named for Today. The
  system keys a placed widget or control by its kind, so one placed from an
  earlier build is added again once. The widget extension's bundle identifier
  (`com.lorvex.apple.focuswidget`) is a registered App ID and is unchanged.

## 9. Consequences

- **Priority carries emphasis alone,** so it has to stay meaningful: if every
  task is high priority, the order says nothing. The assistant's guidance says
  so, and the briefing names the few tasks that matter.
- **Unfinished work carries over.** A task planned for today and not done is
  still on Today tomorrow. The assistant's morning pass, or the user, defers
  what will not happen.
- **A long Today is a signal.** The capacity decision exists for that case.
- **Glances lose the ring by default.** It returns only for a timed task whose
  time is running, the one case where it measures something real.

## 10. Alternatives considered

- **Rename Focus** ("Top three", "Must do"): still a second importance signal
  and still a second tier.
- **Keep Focus but hide its section**, using it only to order the list: the
  order would have a cause the user cannot see.
- **Let the user pin tasks to the top**: a second importance signal again.
- **Keep Now and Next for untimed work**: an order nobody chose, presented as a
  fact.
