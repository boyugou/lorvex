# Features
This document defines the feature set. Features are organized by tier — what is essential to Lorvex as an AI-native planning system, what keeps the standalone app first-class, and what remains progressive enhancement.

**Status tags:** `[SHIPPED]` = working in production. `[PARTIAL]` = code exists but incomplete. `[PLANNED]` = designed, not started. `[CUT]` = removed from scope.

---

## Core Principles Driving Feature Selection

1. Every feature must either (a) make AI operations more powerful, or (b) make human review/execution more fluid
2. If a feature is only needed because AI doesn't exist, it's a legacy feature — deprioritize or cut
3. Complexity budget: favor fewer features done deeply over many features done shallowly
4. Desktop and mobile are peer runtimes with different capability sets; runtime reduction is allowed, product incoherence is not
5. Platform ownership is split: Apple ecosystem work belongs to the Swift app in `apps/apple`; Tauri owns Windows/Linux desktop, with macOS as a developer/reference build only. Android remains future non-Apple mobile exploration.

---

## Tier 1: Foundation (Must Ship)

### Task Management [SHIPPED]

**Task creation** [SHIPPED]
- AI creates via MCP (primary path)
- Quick capture: local Tauri IPC write from the menu bar text field, with due date presets (today/tomorrow/next week/custom), priority (P1–P3), duration estimate (preset buttons + custom input), comma-separated tags input, and list assignment (remembers last-used list across sessions)
- Inline creation in list views (keyboard shortcut, natural language)
- Every task must have: title, list assignment, status
- Optional but important: due date, duration estimate, priority signal, body/notes

**Task completion** [SHIPPED]
- Single tap on checkbox
- Undo available for 5 seconds (accidental completion is the most common error)
- Completion logged in AI changelog

**Task deferral** [SHIPPED]
- Options: Tomorrow / This Weekend / Next Week / Someday / Pick a Date
- Defer ≠ snooze: AI tracks deferral count per task for prioritization decisions
- Full date picker UI implemented in TaskDetail panel

**Task detail view** [SHIPPED]
- Title (inline editable)
- Body (WYSIWYG Milkdown markdown editor — headings, lists, checkboxes, bold/italic, code, links, blockquotes, auto-save)
- Due date + time
- Duration estimate (with AI-suggested default)
- Tags (AI-inferred by default, human can add)
- `ai_notes` field — AI's observations/suggestions, displayed in distinct visual style, not human-editable
- `raw_input` — original natural language if created via AI (collapsed by default)
- Dependency summary (what this blocks, what blocks it)
- Changelog entries for this specific task
- Controller orchestration is imported from the explicit `task-detail/controller/useTaskDetailController.ts` module; the controller folder intentionally has no `index.ts` implementation entrypoint.

**Task editing** [SHIPPED]
- Inline title edit (double-tap)
- Full edit via detail panel
- Any field editable by human
- Any field writable by AI via MCP

**Task context menu & quick actions** [SHIPPED]
- Double-click task title for inline editing (Enter to save, Escape to cancel)
- Hover quick-actions: snooze-to-tomorrow and snooze-to-next-week buttons appear on hover for active tasks (with confirmation toasts); promote-to-active button (▶) appears for someday tasks
- List color badge: shows the task's list name and color dot in the metadata row (useful in mixed-list views)
- Due time display: shows scheduled time (e.g. "Today 14:00") alongside due date in metadata row
- Due date formatting: "Today", "Tomorrow" for near dates; short weekday name (e.g. "Thu") for dates 2–6 days ahead; "Mar 17" for dates further out. Overdue dates display in danger red, today's dates in accent blue, future dates in muted gray
- Body snippet preview: first meaningful line of task body shown below title (skips checklists and headers)
- **Consistent 2-line task cards** [SHIPPED] — every TaskCard renders a truncated single-line title plus an always-present metadata row (due date, priority, duration, list badge, tags) for uniform visual density across all views
- **Popover inline task expansion** [SHIPPED] — clicking a task row in list views expands an inline popover showing notes preview and quick actions (complete, snooze, open detail) without navigating away from the current view
- Context menu: right-click for complete, reopen, snooze (tomorrow/weekend/next week/2 weeks/someday), due date (today/tomorrow/weekend/next week/clear), recurrence (daily/weekly/monthly/yearly/clear), duration (15m/30m/1h/2h/4h/clear), priority, move-to-list, duplicate, copy task ID, cancel, delete. Snooze and due-date submenus show the actual target date (MM-DD) alongside each label.
- Due date quick-set: right-click → Due date submenu to set or clear due dates without opening task detail
- Right-click on any TaskCard to access quick actions
- Actions: Complete/Reopen, Snooze, Due date, Priority, Move to list, Duplicate, Cancel, Delete permanently
- Recurrence quick-set: right-click → Repeat submenu to set daily/weekly/monthly/yearly recurrence or clear existing recurrence without opening task detail
- Stored task recurrence JSON is parsed through a shared frontend helper used by Calendar, Task Detail, and recurrence shortcut overlays; advanced BYSETPOS shapes remain visible as non-editable advanced recurrence instead of being treated as absent.
- Frontend task update mutations use a narrow `TaskUpdatePatch` contract at the Tauri IPC boundary; task-card submenus, picker overlays, and Task Detail metadata saves can only send supported update fields and typed values.
- Frontend IPC imports are domain-owned: runtime app code imports task reads from `tasks/queries`, lifecycle writes from `tasks/mutations/lifecycle`, quick-capture/update writes from `tasks/mutations/quickCapture`, and non-task surfaces from their focused modules instead of a root IPC barrel.
- Duration quick-set: right-click → Duration submenu to set estimated duration (15m/30m/1h/2h/4h) or clear without opening task detail
- Snooze, Due date, Recurrence, Duration, Priority, and Move to list use submenus for target selection
- Visual checklist progress bar: tasks with checklists show a compact progress bar alongside done/total count
- Duration estimate display: shows the task's estimated time (e.g. "30m") in the metadata row
- Available across all views (Today, All Tasks, List, Upcoming, etc.)

**Keyboard task navigation** [SHIPPED]
- j/ArrowDown and k/ArrowUp to move focus between tasks
- Enter to open focused task in detail panel
- `x` to complete/reopen focused task (with undo), `c` to cancel focused task (with undo), `s` to snooze to tomorrow, `S` (Shift+s) to snooze to next Monday
- `d` to set due date to today, `D` (Shift+d) to set due date to tomorrow, `e` to start inline title editing, `r` to toggle weekly recurrence, `R` (Shift+r) to open recurrence picker overlay (daily/weekdays/weekly/biweekly/monthly/yearly)
- `y` to duplicate focused task
- `a` to promote someday task to active (open) status
- `m` to move focused task to another list via keyboard-driven picker overlay (filterable, arrow keys, Enter to confirm)
- `1`–`3` to set priority (P1–P3; pressing same number again clears priority)
- Complete and cancel keyboard actions include undo toast; other actions show confirmation toast
- Visual highlight (accent border + ring) on focused TaskCard
- Automatic scroll-into-view for focused task
- Enabled in Today, All Tasks, List, Someday, Upcoming, Kanban, Eisenhower, and Dependencies views
- All keyboard shortcuts discoverable via `?` help panel overlay
- Keyboard-driven picker overlays: `m` move-to-list (filterable search), `R` recurrence (7 presets), `t` due date (today/tomorrow/weekend/next week/2 weeks/1 month/clear with date preview), `w` duration (15m/30m/1h/2h/4h/clear with current value display)
- CalendarView keyboard shortcuts: ←/→ to navigate months/weeks, `t` to jump to today, `m` to toggle month/week view
- Alt+↑/↓ to reorder tasks within a list view (focus follows moved task)
- TaskDetail closes on Escape (safe when inline editors are focused)

---

### Lists [SHIPPED]

**Structure** [SHIPPED]
- Tasks live in Lists
- Lists are grouped into implicit Projects (AI-inferred clustering — see below)
- No nested lists in v1 (YAGNI — this adds complexity without proportional value)

**List creation** [SHIPPED]
- Human creates named lists (the only required manual organizational act)
- AI assigns tasks to lists based on context
- AI can create lists too via MCP (e.g., "Create a list for the Spain trip")
- List has: name, color (hex), icon (emoji), optional description

**AI-inferred list clustering** [PLANNED]
- AI observes which lists and tasks are semantically related
- Suggests grouping them under a category label in the sidebar
- Human confirms or dismisses
- This is different from forcing humans to create a folder hierarchy upfront

**Smart Views (built-in, not user-created)** [SHIPPED]
- **Today** — Tasks where `planned_date <= today` OR (`planned_date IS NULL` AND `due_date <= today`), plus Today's Focus (the ordered `current_focus` subset) and overdue. The default view. Day progress bar (completed/total) in header.
- **Next 7 Days** — tasks grouped by day, with list badges for context, inline task creation per day, past events dimmed, list filter pills, priority filter pills, tag filter pills, sort within day (default/priority/due date), multi-select bulk actions, collapsible day sections with expand/collapse all toggle
- **All Tasks** — searchable full view for browsing the entire task database
  - Group by: status (default), list, due date (overdue/today/tomorrow/this week/later/no date), priority (P1–P3 + no priority), or tag — persisted in localStorage
  - Collapsible section groups with expand/collapse all toggle — persisted in localStorage
  - Supports multi-select bulk operations (complete, cancel, move to list)
  - Tag filter chips for narrowing by task tags (intersection filter, combinable with text search)
  - List filter pills for narrowing by specific list (combinable with text search and tag filter)
  - Priority filter pills (P1–P3) for narrowing by priority level (combinable with all other filters)
  - Sort options: default, due date, priority, newest (created date), title (alphabetical)
  - Keyboard shortcuts (navigate, select, complete, snooze, edit) — discoverable via `?` overlay
- **Someday / Maybe** — ideas and low-priority tasks with search, sort (newest/oldest/priority), group-by (none/list/priority/tag) with collapsible sections, list filter pills, priority filter pills, tag filter pills, multi-select bulk actions, inline add
- **Completed** — recent completions with timeline

**Snapshot-undo for list delete** [SHIPPED]
- Deleting a list (sidebar context menu or list view header) surfaces a transient toast with an Undo action. The backend (#3420, sharing the `EntitySnapshot` machinery in `commands/calendar/events/undo/`) mints a self-contained JSON token containing the full pre-delete `lists` row. Within the ~5 s TTL the row is re-created with a fresh HLC version. Lists are simpler than calendar events: `delete_list` rejects deletion when any task is still assigned, so there are no edges to replay — just the row. After the toast expires the navigation step ("go to Today") runs, so a same-second misclick is reverted without ever stranding the user away from the restored list.

**List Browsing Views** [SHIPPED]
- Clicking any user list shows ALL tasks in that list (open + recently completed)
- This is a full reading view — humans need to see all their Work tasks, all their Personal tasks, etc.
- More metadata per row than Today view (due date, due time, priority indicator, list badge in multi-list views)
- Sort options: default (manual order), due date, priority, newest, title; priority filter pills, tag filter pills
- Multi-select bulk operations (complete, snooze, cancel, move to list)
- The app is an AI-native planning system, but it is ALSO a fully functional task manager that humans can read and browse without AI

---

### AI Activity (`ai_changelog`) [SHIPPED]

Every AI operation generates a plain-language changelog entry:
```
2026-02-28 09:14  Created 3 tasks from your conversation about the Spain trip
2026-02-28 09:22  Moved "Book flights" to high priority — deadline is in 5 days
2026-02-28 14:30  Marked "Review manuscript" as deferred — it has been pushed 3 times
```

- Visible as a dedicated sidebar view
- Shows: timestamp, human-readable description, operation type, affected entities
- Every entry links to the affected task(s)
- Links to affected entities for each operation
- Operation-type filter pills (create, update, complete, delete, triage, plan) with counts — toggle to focus on specific activity types
- Entity-type filter pills for narrowing by entity kind (task, list, etc.)
- Text search across entry summaries and MCP tool names
- "Copy log" button copies filtered changelog entries as formatted text to clipboard
- Progressive "Load more" pagination (starts at 50, loads 50 more per click)

---

### AI Memory View [SHIPPED]

Displays persistent context notes used by the AI assistant across sessions.

- Memory cards with formatted key names, content, and relative update timestamps
- Icon mapping per memory key type (user profile, list summaries, behavioral patterns, etc.)
- Search/filter across memory keys and content with match count display (filtered/total)
- Optional biometric lock: when enabled, memory view requires Touch ID/biometrics to unlock and auto-locks when the app loses focus
- Query cache cleared when memory is locked (data not kept in RAM while locked)
- **`notes_for_ai`**: a human-owned memory block where the user stores persistent instructions or context for their AI assistant. Displayed separately from AI-generated memory entries. Editable in the AI Memory view, readable via MCP session/memory surfaces, but not writable by AI through MCP.
- **Memory revision history**: every `write_memory`, `delete_memory`, and `restore_memory_revision` operation records an append-only revision in the `memory_revisions` table. Users can browse revision history per key and restore any previous version.

**MCP tools** — AI-owned memory CRUD, revision history, restore, and read access to human-owned `notes_for_ai` through session/memory reads. See [MCP_TOOLS.md](MCP_TOOLS.md) for the full tool reference.

---

### MCP Server [SHIPPED]

The MCP server is a first-class automation interface and one of Lorvex's biggest differentiators. This is not an afterthought. At the same time, Lorvex must remain a genuinely strong standalone app on every runtime. Desktop + MCP is the strongest operator experience; standalone runtimes still need to be coherent products in their own right. For the complete tool reference, see [MCP_TOOLS.md](MCP_TOOLS.md). Current generated tool inventory totals live in `docs/reference/REPO_FACTS.md`.

**Tool families:**
- **Tasks**: CRUD, lifecycle (complete/cancel/reopen), batch operations, dependencies, recurrence, reminders, deferral
- **Lists**: CRUD, reorganize, health snapshot
- **Calendar**: CRUD, recurrence exceptions, event linking, provider integration, ICS export
- **Focus & Planning**: Current focus, focus schedule, daily/weekly review
- **Memory**: Read/write/delete AI memory, notes for AI, revision history, restore
- **Habits**: CRUD, single and batch completion tracking, reminders, stats
- **Query & Analysis**: Overview, search, upcoming, dependency graph, task pattern analysis, session context
- **Preferences & Settings**: Get/set/delete preferences, UI control, setup

`get_overview` and the desktop app overview share the same typed `lorvex-workflow::overview` snapshot contract for aggregate stats, list counts and truncation metadata, priority/recent task slices, current focus summary, and habit counts. MCP still owns response fencing and compact payload shaping; the App still owns IPC projection and task enrichment.

**All write operations auto-log to `ai_changelog`, shown in the UI as AI Activity**

**Input ergonomics**
Lorvex exposes one MCP runtime, and it expects canonical JSON types at the contract boundary. Assistant/client integrations should normalize payloads before calling tools instead of depending on runtime-specific coercion.

---

### Views [SHIPPED]

**Today View** [SHIPPED]
- Shows tasks where `planned_date <= today` OR (`planned_date IS NULL` AND `due_date <= today`)
- Section: "Today's Focus" (AI-curated ordered subset from `current_focus`, with AI's reasoning)
- Section: "Also Due Today" (remaining qualifying tasks, by list group)
- Section: "Overdue" (with days-overdue indicator)
- Minimal chrome: checkbox, title, list badge, priority indicator, due time
- No sidebars or panels by default — the daily view is the app
- **AI-controlled dashboard composition**: AI assistant can set which sections appear and in what order via the `dashboard_layout` preference (using `set_preference` MCP tool). Available section types: `ai_briefing`, `focus`, `schedule`, `overdue_alert`, `recently_completed`, `upcoming_week`, `someday_peek`, `stats`. Layout changes are kept infrequent to preserve spatial stability. A small indicator shows when the layout was set by AI.
- `overdue_alert` section supports a compact overdue task list (clickable rows) with a "Reschedule all to today" batch action button, not only a count banner.
- Today's Focus section order is human-adjustable by drag-and-drop — the entire task card is draggable (grab cursor, opacity feedback on drag source, highlight ring on drop target); up/down arrow buttons appear on hover for fine-grained reordering; Alt+↑/↓ keyboard shortcuts also work. Reordering updates the `current_focus_items` positions so widget and schedule surfaces use the same sequence.
- Header stat pills: overdue count, today pool count, scheduled duration, estimated finish time ("done by ~HH:MM" — sum of remaining open task durations added to current time, updates every minute), completed this week, week-over-week completion comparison (↑/↓ vs last week), day streak (active or continue prompt)
- Day progress bar: visual bar showing completed/total for today's tasks
- "Copy plan" button: copies today's due tasks, today's focus, and calendar events as a formatted markdown checklist to the clipboard
- **Today's calendar events** section with color bar, time range, location; **"NOW" badge** with pulse + highlight ring for currently-happening events; **"in Xm"** badge for events starting within 30 minutes
- **Collapsible sections**: each dashboard section (focus, schedule, overdue alert, recently completed, someday peek, upcoming week, stats, AI briefing) can be collapsed/expanded by clicking its header. Collapsed state persists in localStorage.

**Next 7 Days View** [SHIPPED]
- Tasks grouped by day with day headers (Today, Tomorrow, Wednesday Mar 4…)
- Drag tasks between date groups to reschedule (with confirmation toast)
- Count by day visible as a heat indicator
- Overloaded days visually flagged
- All 7 days always visible (even empty ones), with inline add task on each day
- "Copy week plan" button exports the full 7-day plan as markdown (events + task checklist per day) to clipboard

**List View** [SHIPPED]
- All tasks in a selected list
- Sortable: AI-recommended order (default), priority, due date, creation date, duration
- Status filter: Open / Completed / All
- Tag filter
- Inline task creation: press Enter at the bottom of a list to add a task without leaving the view
- Total estimated duration shown in header (e.g. "2h 30m estimated") alongside open/completed counts
- "Copy plan" button exports list tasks as markdown checklist to clipboard

**Task Detail Panel** [SHIPPED]
- Slides in from right when task is selected
- All task fields visible and editable
- Clickable task ID in header for quick copy to clipboard (useful for MCP operations and dependency linking)
- `ai_notes` displayed in a visually distinct block (different background, labeled "AI Notes")
- Changelog entries specific to this task at bottom
- Dependency links: what this blocks / what blocks it

---

### Menu Bar Popover [SHIPPED]

- Menu bar icon always visible; click opens quick-glance popover
- Shows today's date, overdue count, and plan task count
- **Next Up** task list with inline complete (check circle), snooze-to-tomorrow (clock icon), and snooze-to-next-week (calendar icon) on hover
- Priority indicator for higher-importance tasks (P1/P2), due time, and per-task duration badge in task rows
- Header shows total estimated duration for all plan tasks
- **Today's calendar events** section: compact event list with color dot, time, and title; past events dimmed; all-day events first; max 4 shown with "+N more" overflow; **"NOW" badge** with pulse animation for currently-happening events; **"in Xm" badge** for events starting within 30 minutes
- AI briefing snippet from today's focus
- Current focus task chips (up to 2 with "+N more")
- Action bar: Open App, Copy Plan, Quick Capture

### Quick Capture (Menu Bar) [SHIPPED]

- Click or global shortcut (Cmd/Ctrl+N) opens floating text field
- User types raw text → press Return → task created in the selected list (or default list) with that text as title
- **No AI processing in the app.** The app simply stores the raw text.
- Closes immediately after submit (non-blocking)
- The AI-powered creation path is: user tells AI assistant in an MCP client → AI assistant calls MCP tools → task created with full metadata
- Quick date buttons (Today, Tomorrow, Next week, custom date picker) and priority pills (P1–P3) for immediate metadata
- Duration preset buttons (15m, 30m, 1h, 2h, 4h) with custom numeric fallback
- Collapsible body/notes field ("Add notes" toggle expands inline textarea)
- **Collapsible options section** [SHIPPED] — "More options" toggle hides/shows date picker, priority pills, tags input, and duration presets; collapsed by default for minimal-friction capture
- List selector dropdown for direct list assignment (remembers last-used list)

---

## Tier 2: Important Enhancement

### Duration & Scheduling [PARTIAL]

**Duration estimates** [SHIPPED] — Duration field exists, displayed across all views with progressive detail
- AI proposes duration when creating task (based on task type + historical data)
- Human can override
- Duration displayed in: task list badges, calendar WeekGrid + DayPanel task rows (compact "Xm" / "Xh Ym" labels alongside due_time), Today's Focus section header total, UpcomingView header total + per-day totals
- Running total of today's scheduled work shown as "Xh Ym scheduled today" pill in TodayView header

**Focus Schedule** [PARTIAL] — `propose_daily_schedule` generates time-blocked schedules for Today's Focus tasks with ready-to-use `blocks[]` output; `save_focus_schedule` persists schedules and auto-activates the TodayView schedule section; `get_saved_focus_schedule` retrieves a previously saved schedule with blocks; interactive timeline UI with current-time indicator, dismiss action, inline task completion, and progress bar
- AI-generated schedule: schedules Today's Focus tasks (not the entire task pool) in time slots with 10-minute buffer blocks
- `propose_daily_schedule` output includes a `blocks[]` array matching `save_focus_schedule` input format (type/task_id/start_time/end_time) for direct pass-through
- `save_focus_schedule` auto-injects `schedule` section into the dashboard layout preference if absent (no separate `set_preference` call needed)
- Accounts for: task durations, working hours preference, calendar events (including recurring events)
- Calendar-aware scheduling: tasks are placed around fixed calendar events; event blocks shown inline in timeline
- Interactive schedule timeline: dismiss, complete tasks inline, visual progress indicator
- Human can: dismiss, remove individual task blocks, reorder tasks (up/down shuffle); add individual blocks not yet implemented
- Schedule dynamically updates when tasks complete or are rescheduled

**Week time-block view** [SHIPPED]
- Toggle between list and timeline modes in the Next 7 Days (Upcoming) view
- 7-column grid with hourly time slots (06:00–23:00)
- Tasks with `due_time` positioned at their scheduled time, height scaled by `estimated_minutes`
- Calendar events shown as colored blocks at their actual time
- All-day events in a dedicated header row; untimed tasks in a separate section
- Overdue tasks highlighted in danger color
- Completed count badges per day column
- Auto-scrolls to current time on mount

**Day timeline view** [SHIPPED]
- Hourly grid (06:00–23:00) in the CalendarView day panel with list/timeline toggle
- Calendar events positioned at their actual times with color-coded blocks
- Tasks with `due_time` positioned at their scheduled time, height scaled by `estimated_minutes`
- Untimed tasks shown in a separate "No time" section above the grid
- All-day events in a dedicated header section
- Drag-to-reschedule: drag timed or untimed tasks to a time slot (snaps to 15-min intervals) with confirmation toast
- Auto-scrolls to current time on mount
- This view is a power-user feature, not the default

### Recurring Tasks [SHIPPED]

- Recurrence rules: daily, weekly (on specific days), monthly, every N days, weekdays only
- When a recurring task is completed, next instance is auto-created
- AI can create recurring tasks via MCP
- Full recurrence UI editor in TaskDetail panel — humans can view and modify recurrence rules
- Recurrence rule stored as JSON on the task (`freq`, `interval`, `byday`, `bymonthday`, `until`)

### Calendar View [SHIPPED]

- Month grid view: tasks and calendar events plotted on their respective days
- Week view: 7-day horizontal layout with events + tasks per day
- Ownership model: [Calendar behavior](CALENDAR_BEHAVIOR.md) distinguishes editable Lorvex-owned `calendar_events` from read-only external `provider_calendar_events`
- Backed by independent `calendar_events` table, separate from task due dates
- Human can create/edit/delete events directly in Calendar view
- AI can create/edit/delete/query events via MCP calendar tools (CRUD, scoped recurring edits/deletes, recurrence exceptions, event-task linking, provider integration, ICS export — see [MCP_TOOLS.md](MCP_TOOLS.md#calendar))
- Clicking a day opens that day's event + task stack
- List filter pills and tag filter pills for narrowing displayed tasks by list or tag (intersection filter, combinable with date browsing)
- Drag-to-reschedule: drag task pills between date cells (month grid) or day columns (week view) to change due dates visually, with confirmation toast
- DayPanel tasks are also draggable to calendar date cells for cross-panel rescheduling
- Month grid: per-day count badges (task + event count, completed checkmark count) next to date numbers
- Past event dimming: events whose end time has passed render at reduced opacity with strikethrough (TodayView, DayPanel, UpcomingView)
- Current time indicator: red dot + line on DayTimeline and WeekTimeline today columns
- Event ↔ task linkage: tasks can be linked to calendar events
- Recurrence exception (EXDATE): recurring events in the day panel show a ⊘ icon to skip individual occurrences without deleting the series. Skipped dates are stored in `recurrence_exceptions` and excluded from calendar expansion.
- Recurring calendar scoped edits/deletes [SHIPPED]: the user-facing scope picker still offers "this event", "this and following", and "all in series", but the mutation is now a single backend workflow (`lorvex-workflow` recurrence split helpers plus thin Tauri/MCP commands). Replacement creation, exception insertion, original truncation, and collapse deletion run inside one SQLite transaction so partial duplicate/orphan series cannot survive a mid-operation failure.
- Calendar event normalization [SHIPPED]: Tauri IPC and MCP create/update paths delegate title/text hygiene, URL allowlisting, color/timezone/date/time validation, all-day projection, recurrence BYMONTHDAY anchoring, and DST skipped/ambiguous wall-clock policy to `lorvex-workflow::calendar_normalization`.
- Week calendar grid modularity [SHIPPED]: desktop WeekGrid owns orchestration only; cells, event pills, task pills, completed-task popovers, and roving focus live in focused modules with direct behavior coverage.
- .ics calendar subscription sync: subscribe to external calendar feeds (Google Calendar, Outlook, etc.) via URL. Two surfaces drive the same workflow: the Settings panel in the desktop app (CRUD form) and the agent-first CLI (`lorvex subscription {list, add, remove, refresh, toggle}`). Background periodic refresh (60-min interval), HTTPS fetch with VEVENT parsing (RRULE, EXDATE, ATTENDEE, URL, ORGANIZER extraction), automatic upsert/removal of events. Events display with source attribution in calendar views. URL scheme validation (https:// only) and response size limit (10 MB) for security.
- Event types: `event_type` field supports `event` (default), `birthday`, `anniversary`, `memorial` — enables birthday/important-date tracking with optional `person_name` metadata
  - Linked tasks shown as compact chips below each event in the day panel
  - Linked events shown in task detail panel with colored indicator and date/time
  - Backed by `task_calendar_event_links` table with composite primary key
- **Snapshot-undo for calendar event delete** [SHIPPED] — deleting a calendar event surfaces a transient toast with an Undo action; the backend (`commands/calendar/events/undo/`, #3392) mints a self-contained JSON token carrying the full pre-delete row plus every linked-task id. Within the ~5 s TTL the row + every link are re-created with a fresh HLC version Sync peers converge under LWW.

### Daily Review / Habit Tracking [SHIPPED]

- AI assistant writes end-of-day review entries via MCP review tools (see [MCP_TOOLS.md](MCP_TOOLS.md#workflow))
- Human can also create/edit today's review entry directly in the Daily Review view (mood/energy pickers, summary, wins/blockers/learnings fields) via `upsert_daily_review` IPC command
- Each entry captures: prose summary, mood (1-5), energy level (1-5), wins, blockers, learnings, linked task/list IDs, habit completion state, and AI assistant's longitudinal synthesis
- **Habit tracking:** dedicated `habits`, `habit_completions`, `habit_reminder_policies`, and `habit_reminder_delivery_state` tables with MCP tools for CRUD, completion tracking, reminders, and stats (see [MCP_TOOLS.md](MCP_TOOLS.md#workflow)). Supports daily/weekly/custom frequencies, streak computation, 30-day completion rates with cadence-aware denominators, multiple reminder slots per habit, and local-only delivery suppression. The sync pipeline covers canonical habit and reminder policy data; delivery state stays device-local. The Today dashboard shows habit check-in rows (completion circle, streak badge, toggle) via `get_todays_habits` IPC + `TodayHabitsSection`. The dedicated `HabitsView` (shown by default in the sidebar) uses `get_habits_with_stats` to render a 12-week completion heatmap (84-cell grid), per-habit stats (current streak, best streak, 30-day completion rate with frequency-aware denominator, total completions), and a toggle button with optimistic cache update (heatmap + stat cards update immediately without waiting for refetch).
- The Daily Review view in the app displays an inline form for today's entry at the top, plus recent history below
- Data stored in `daily_reviews` table
- Review streak badge shows consecutive days with review entries (e.g., "🔥 5 days")
- Mood/energy trend sparkline: SVG line chart of last 14 days with averages, appears above the review form when 3+ reviews exist

### Tags [SHIPPED]

- AI-assigned by default (inferred from task content and list context)
- Human can add/remove
- Tag filter pills available across all task views (All Tasks, Eisenhower, Kanban, Someday, Upcoming, Calendar, ListView, Dependencies) via shared `TagFilterPills` component
- Group-by-tag option in All Tasks and Someday views (multi-tagged tasks appear in each relevant section)
- Tags are capped at 30 per task to keep filtering, rendering, and sync payloads bounded

### Task Dependencies [SHIPPED]

- `depends_on` field: list of task IDs this task is blocked by (single truth source for dependencies)
- Reverse relationship ("what does this task block?") derived at read time from other tasks' `depends_on`
- AI considers dependency relationships when making prioritization decisions (blocked tasks deprioritized; tasks that unblock others prioritized)
- Interactive dependency management in task detail: add/remove `depends_on` entries with inline task search (UI presents both "depends on" and "blocks" views, but all writes go through `depends_on`)
- AI can identify dependency relationships from natural language ("this can't start until X is done")
- **Dependency graph view** [SHIPPED] — Dedicated view showing task dependency chains organized into topologically-layered clusters, with all/blocked/ready filtering, list/tag filter pills, search, visual blocking indicators, connected component grouping, filter-aware empty states, inline "Depends on: Task A, Task B" labels per node, and a toggle to hide completed tasks from the graph

### Weekly Review Mode [SHIPPED]

- Dedicated "Weekly Review" view triggered by AI or user
- Pre-populated by AI:
  - Lists with no next action (stalled)
  - Tasks deferred 3+ times (worth re-evaluating)
  - Completed tasks from past week (feel good, see progress)
  - Someday/Maybe items that may now be relevant
  - AI's suggested focus areas for next week
- Human makes decisions; AI executes the changes
- Target: 15 minutes to complete a high-quality weekly review
- Net velocity stat card (completed minus created) shows whether the user is gaining or losing ground

---

## Tier 3: Polish & Depth


### Intelligent Notifications [SHIPPED]

- Morning briefing notification (configurable time, default 8am): today's focus count, overdue count, AI briefing text
- At-risk deadline notification: surfaces tasks due within 1 day, with once-per-day suppression (persisted via preference)
- Weekly review prompt: fires on configured day/time (default Friday 4pm)
- Multi-reminder model: `task_reminders` table supports multiple per-task reminders with add/remove UI in TaskDetail
- Notification burst grouping: 3+ simultaneous reminders collapse into one grouped notification
- In-memory + DB dedup: `notifiedReminderKeys` set prevents duplicate dispatches; `is_notified` flag in DB prevents re-fire across restarts
- All notification timing and scheduling preferences are human-configurable in Settings

### Mobile Runtime Direction [PLANNED]

- Canonical Tauri status: **Android future runtime only**. iOS and iPadOS product work belongs to the Swift app in `apps/apple`.
- The React frontend keeps touch-screen layout primitives via the shared runtime capability contract (`runtimeId`, `runtimeClass`, and capability booleans) so a future Android runtime can reuse product logic.
- Bottom tab bar with 4 tabs (Today, Upcoming, Lists, More) + SVG icons + overdue badge
- "More" bottom sheet menu: 10 items including Daily Review, Weekly Review, Eisenhower, Kanban, Dependencies, AI Activity, AI Memory, All Tasks, Someday, Settings
- Full-screen task detail with slide-up animation, safe-area headers
- QuickCapture as bottom sheet with drag handle dismiss
- Search button in mobile header (navigates to All Tasks search)
- Mobile safe areas: display cutouts, gesture navigation, keyboard
- Touch-optimized: hover-reveal controls always visible, 44px minimum touch targets
- Responsive layouts: stat grids 2-col on mobile, padding reduced on narrow screens

### Store Metadata & Public Policy Surfaces [CUT]

- Tauri no longer owns App Store metadata or App Store reviewer flows.
- Apple App Store policy, screenshots, privacy labels, and review notes belong to the Swift app under `apps/apple`.
- Tauri release copy should stay scoped to direct desktop distribution for Windows/Linux and the macOS developer/reference build.

### Spotlight Integration [SHIPPED]

- macOS Spotlight can search tasks via CoreSpotlight (`CSSearchableIndex`)
- Tasks indexed on create/update, removed on delete/complete
- Results show task title, list, due date
- Clicking opens the app to that task via deep link
- Full implementation under `app/src-tauri/src/platform/spotlight/` (`mod.rs`, `queries.rs`, `diagnostics.rs`, `noop.rs`, plus `macos/` and `windows/` per-OS backends)

### Desktop Widget Surfaces [CUT]

- Apple WidgetKit surfaces belong to the Swift app under `apps/apple`.
- Tauri may keep generic snapshot/export concepts only when they are useful for desktop integrations or future non-Apple surfaces.
- Do not add App Group, WidgetKit, or generated Xcode extension scaffolds back to the Tauri tree.

### Command Palette (⌘K) [SHIPPED] — Navigation, task search, inline quick capture, scoped list capture (@list::title), task actions (complete/defer/cancel/move-to-list), list create/archive/delete

- Search tasks, lists, actions
- Quick actions: New Task, Switch to Today, Open Weekly Review, etc.
- A command palette for fast keyboard-driven navigation and actions

### Theming & Appearance [SHIPPED]

- 12 theme options: Paper, Light, Dark, Ember, Midnight, Liquid Glass (dark+light), Mica (dark+light), Adwaita (dark+light), System auto-detect
- 4 shipped appearance profiles: Clarity (default), Studio, Focus Compact, Liquid Glass
- Cross-window theme propagation: theme changes in the main window broadcast to the popover window via Tauri events
- macOS transparent overlay windows with rounded corners (macOSPrivateApi enabled)
- AI briefing toggle: users can enable/disable the AI briefing section in TodayView and menu bar popover via Settings
- **Font scale setting** [SHIPPED] — Settings → Appearance → Font Size slider with 5 options (Small / Compact / Default / Large / Extra Large). Applies a CSS font-size scale factor to the entire app. Persisted as a user preference.
- **Unified Toggle component** [SHIPPED] — iOS/macOS-style animated toggle switch used across all Settings panels, replacing mixed checkbox/toggle patterns with a single consistent control
- **Typography baseline** [SHIPPED] — minimum 12px font size enforced across the app; removed uppercase `tracking-widest` styling from labels for improved readability and visual calm
- Assistant sync settings controller orchestration is imported from the explicit `settings/controller/assistant/sync/useAssistantSyncController.ts` module; the sync controller folder intentionally has no `index.ts` implementation entrypoint.

### Eisenhower Matrix View (Power User) [SHIPPED] — Quadrant display + AI classification + drag-and-drop between quadrants to change priority + copy matrix to clipboard

- Visual quadrant view of all open tasks
- AI pre-classifies, human can drag between quadrants with confirmation toast
- List filter pills, tag filter pills, and search for narrowing to a specific list, tag, or keyword
- Time horizon toggle (7d / 14d / 30d / 60d / 90d / All) — defaults to 60 days
- Filter-aware empty state distinguishes "no tasks" from "filters eliminated all results"
- Mainly useful for periodic auditing ("am I spending time in Q2?")

### Accessibility & Internationalization [SHIPPED]

- **RTL locale support** [SHIPPED] — `dir="rtl"` attribute automatically set on the root element for Arabic, Hebrew, Persian, and Urdu locales, ensuring correct text direction and mirrored layout
- **Focus-visible accessibility rings** [SHIPPED] — all interactive inputs, buttons, and controls display visible keyboard focus indicators (`focus-visible` outline rings) for keyboard-only navigation
- i18n: all user-visible strings use translation keys, plus shared runtime interpolation/plural helpers for locale-aware count phrases

---

## Explicitly Out of Scope

- **Collaboration / shared lists** — Lorvex is a single-user personal planning system by design
- **Pomodoro timer** — may add later but not core
- **Email integration for auto-capture** — requires permissions infra; can add later
- **Offline MCP** — MCP requires AI assistant, so always online
- **Plugin system** — too early

---

## Lorvex CLI [SHIPPED]

Agent-first terminal companion runtime. Shares the same local DB with the App.
App, CLI, and MCP writes use the shared `lorvex-runtime` surface HLC runtime so local version stamps share one initialization, seed, observation, poison-recovery, and test-reset contract.
Checklist workflow writes (`add`, `update`, `toggle`, `remove`, `reorder`), `set_recurrence`, `reorganize_list`, `task.create`, `task.batch_create`, `task.batch_update`, and `task.batch_cancel_in_list` call `lorvex-workflow` typed owners directly from both CLI and MCP instead of sending CLI mutations through MCP JSON `public_api` shims. CLI permanent delete now calls `lorvex-workflow::task_permanent_delete` directly and keeps outbox/changelog projection at the CLI boundary.

- `lorvex setup` — initialize DB, install MCP config
- `lorvex doctor` — comprehensive health check with structured warning codes
- `lorvex status` — quick dashboard summary
- `lorvex mcp serve` — stdio MCP server for agent clients
- `lorvex mcp install --for <client>` — configure Claude Code / Codex / Claude Desktop
- `lorvex tui` / `lorvex tui --watch` — lightweight terminal dashboard
- Diagnostics: `status`, `doctor`, `sync status/outbox`, `changelog`
- Task queries: `tasks`, `graph`, `today`, `overdue`, `upcoming`, `deferred`, `reminder due/upcoming`, `search`, `show`
- Task reminder mutations: `reminder set/add/remove/clear`
- Task mutations: `capture`, `update`, `complete`, `reopen`, `cancel`, `defer`, `trash move/restore/delete --dry-run`, `tag rename`; lifecycle commands accept one or more task IDs, Trash move/restore and delete dry-runs are batchable, and `update` supports field clears plus tag and dependency set/add/remove/clear patches
- Habit commands: `habits`, `habit create/update/delete`, `habit complete/batch-complete/uncomplete/stats`, and `habit reminder list/upsert/delete`
- Calendar: `calendar list/show/today/create/batch-create/update/delete`, task-event links, provider-event links, recurrence exceptions, and ICS export for scriptable event CRUD
- Focus planning: `focus`, `focus set`, `focus add`, `focus remove`, `focus clear`, plus `focus schedule propose/get/save`; all support explicit `--date YYYY-MM-DD`
- Reviews: `review get/history/add/amend` for daily journals, plus `review weekly` for a seven-day progress/stalled/deferred/someday snapshot
- List management: `lists`, `list <id>`, `list health`, `list create/update/delete`, `move`
- Sync diagnostics: `sync status`, `sync outbox` for local sync health and pending queue inspection
- Data portability: `export`, `import`
- All mutations write to shared sync outbox and bump local_change_seq
- JSON output (`--format json`) for agent/script integration

See `docs/design/MULTI_SURFACE_ARCHITECTURE.md` for the full App + CLI coexistence model.

---

## Feature Interaction Notes

### MCP + Quick Capture
Quick Capture writes locally through the app's Tauri IPC path and shares the same domain/store invariants as MCP writes: task validation, changelog/sync ownership, and canonical mutation semantics stay aligned even though the UI and assistant surfaces enter through different adapters.

### AI Activity (`ai_changelog`)
Every MCP write operation logs a changelog entry with operation, entity type, summary, and actor identity. The changelog powers the activity feed and task attribution.

### Duration + Focus Schedule
Duration is an input to the Focus Schedule. Focus Schedule output shows tasks as time blocks. These are distinct features but deeply coupled — invest in both together.
