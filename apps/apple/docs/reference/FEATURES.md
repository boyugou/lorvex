# Feature Status Catalogue

Status tags: `[SHIPPED]` = present and functional, `[PARTIAL]` = code present but incomplete or has known gaps, `[PLANNED]` = not yet built.

MCP tool count: 116. Scoped calendar edit/delete tools are Apple-specific. Apple Swift is the only Apple ecosystem shipping line for macOS App Store, iOS, iPadOS, watchOS, CloudKit/iCloud, WidgetKit, and App Intents.

---

## Apple Surfaces

| Surface | Status | Notes |
|---|---|---|
| macOS — sidebar + all workspaces | [SHIPPED] | Today, Calendar, All Tasks, Review, Habits (⌘1–⌘5), then the user's lists as task scopes and an Archived section; Memory (⌘6, no detached-window scene) and Settings sit in a pinned footer. Lists have no sidebar row — they are managed inline, with the catalog reached via ⌘K |
| macOS — multi-window | [SHIPPED] | Detached list/workspace windows + floating task stickies |
| macOS — menu bar extra | [SHIPPED] | Today / Next 7 Days panel: date, quick-add (reads days, times, lengths, and #lists like every capture field), today's schedule and tasks with one-click complete, habit check-in rings, the seven-day agenda, events that open in the main window, Open Lorvex and Quit; the icon carries the due-today/overdue count |
| macOS — Quick Capture window | [SHIPPED] | A floating one-field window over any app, opened by an optional system-wide shortcut (⌃⌥Space, ⌃Space, ⌥Space, or ⌃⇧Space, chosen in Settings → General; off by default), File → Quick Capture (⌥⌘N), the Command Palette, or the Dock menu. It reads the line like every capture field, shows the details under the field, confirms the list the task landed in, keeps a dismissed draft, and reports a shortcut another app already owns |
| macOS — Open at Login | [SHIPPED] | A switch in Settings → General that makes Lorvex open when the user signs in (`SMAppService.mainApp`), so the menu bar icon and the Quick Capture shortcut are ready. It shows the system's state, follows a change made in System Settings, and, when macOS waits for approval, offers a button to the Login Items pane |
| macOS — full command menus + keyboard shortcuts | [SHIPPED] | |
| macOS — settings (General/Assistant/Calendar/CloudSync/Diagnostics/Data/Permissions) | [SHIPPED] | |
| macOS — workspace loading states | [SHIPPED] | Primary async workspaces show a native loading overlay |
| macOS — global error toast | [SHIPPED] | `ContentView.lorvexToast` handles transient app/notification-action failures |
| macOS — list reordering | [SHIPPED] | Lists and habits support persisted drag reordering |
| macOS — calendar navigation and View menu | [SHIPPED] | Day, Week, and Month modes with previous, next, a Today / This Week / This Month reset, and a date picker. The View menu repeats the mode choice and holds the reset (⌘T) and the Unplanned Tasks column (⌥⌘U) while the Calendar is on screen |
| macOS — calendar planning by drag | [SHIPPED] | A task dropped on a time in the week or day grid, on a day's all-day row, or on a month cell is planned there; a timed block moves by drag in 15-minute steps, and its top or bottom edge sets when the task starts or ends (the estimate stays as it is), showing the new time as you drag; the Unplanned Tasks rail lists open tasks with no planned day. Every placement and resize is one undoable Plan Task (⌘Z); dragging or resizing an event is undoable too |
| macOS — calendar context menus | [SHIPPED] | Right-clicking an event or a task on the week and month grids opens its menu (Open Details, Edit, Delete for a Lorvex event; the shared task menu for a task); a month day also offers Create Event |
| macOS — habit inspector | [SHIPPED] | In-place editing (name, encouragement, and Repeat / Reminder / Goal popovers), streak metrics, a history grid, and the by-weekday pattern |
| macOS, iPhone, iPad — habit skip days | [SHIPPED] | Skip Today sets a habit aside for one day as an excused day, neither done nor missed: it bridges daily and weekly streaks, leaves the 30-day rate, silences that day's reminder, and draws as a dotted ring with a skip mark, a dashed cell in the rhythm strip and history grid. Reachable from the card/row menus, the swipe, the detail page, and the assistant (`skip_habit`, `unskip_habit`); a check-in on a skipped day lifts the skip |
| macOS — habit milestones | [SHIPPED] | Streak/count milestone waypoints (auto-ladder + optional user target), a progress bar, and a celebration when a waypoint is crossed |
| macOS — Command Palette (⌘K) | [SHIPPED] | Fuzzy command/navigation palette; the New Task row reads the typed line like a capture field and names the task and details it will create |
| macOS — Data export/import | [SHIPPED] | Settings → Data writes the version-1 Apple export: portable category JSON plus an independently versioned exact native task graph for same-app restore, including task-domain deletion high-waters and opaque future-field state. CloudKit account/transport state is never restored; JSON may carry the producing device ID only as non-applied provenance. ZIP v1 requires an exact closed manifest inventory and has no blob members. Exact task restore is used only for a fresh task domain with its list/tag roots; otherwise tasks use the portable merge path. With sync live, import runs one best-effort sync pass first and the imported rows upload through the outbox like any other change; with sync off, import is local-only. MCP/AI export stays portable, and cross-platform movement is AI-reconciled best-effort rather than a lossless interchange contract |
| iPhone — Today, Calendar, Tasks, Review tabs | [SHIPPED] | Daily-driver surfaces are first-class tabs; Today is one ordered list of what's planned for today or earlier, due today or overdue, or already started, with optional planned times; there is no separate Focus tab |
| iPhone — global quick-capture sheet | [SHIPPED] | Capture is an action, not a place: the round ＋ beside the tab bar (on every tab), ⌘N with a keyboard, the Home Screen Quick Capture action, and the Quick Capture control raise one capture sheet and leave the current tab selected |
| iPhone — task detail + edit sheet | [SHIPPED] | |
| iPhone — create sheets (task/list/habit/event) | [SHIPPED] | |
| iPhone — secondary workspace reach (Habits, Memory, Settings) | [SHIPPED] | Habits and Memory are rows at the bottom of the Tasks tab home and Settings a toolbar button on Today, all pushed as typed routes; Lists is merged into the Tasks tab home |
| iPhone — Settings screen | [SHIPPED] | Settings, diagnostics (incl. a read-only recent crash/hang diagnostics feed), privacy and acknowledgments, data export/import, notification/reminder toggles |
| iPhone — habit milestones | [SHIPPED] | Habit detail shows milestone progress and target editing; completion and batch completion surface milestone celebrations |
| iPad — tab shell (regular width) | [SHIPPED] | The iPhone shell at full width: one tab bar with Today, Calendar, Tasks, and Review plus the round ＋ capture button, each tab with its own navigation stack. Habits and Memory open from the Tasks tab home and Settings from Today; Lists is merged into the Tasks home. There is no sidebar — wide layouts add a second pane inside a tab |
| iPad — Today schedule pane | [SHIPPED] | At regular width the day's schedule stands in a 380pt pane beside the Today list; on iPhone it opens from the day strip |
| iPad — Tasks split workspace | [SHIPPED] | Query-backed status/search browser with persistent list + detail panes on regular width |
| iPad — Calendar agenda workspace | [SHIPPED] | Time grid of one, two, or three day columns by width, with the agenda pane beside it from 860pt wide and quick create/edit affordances; Month mode names each day's events and tasks in the grid, beside (from 860pt) or above the chosen day's agenda |
| iPad — Habits split workspace | [SHIPPED] | Active habit catalog pinned beside progress metrics and completion/edit/delete controls on regular width |
| iPad — Memory split workspace | [SHIPPED] | Save controls and full memory catalog pinned beside selected content, metadata, and delete controls on regular width |
| iPad — hardware keyboard shortcuts | [SHIPPED] | ⌘R, ⌘N, ⌘1-⌘4 for the tabs in bar order, ⌘5 Habits, ⌘6 Memory, ⌘, Settings (the Mac's numbering) |
| Apple Watch — root view (Today lead task + list, habits, capture) | [SHIPPED] | Snapshot-backed on device with WatchConnectivity write forwarding to iPhone |
| Apple Watch — Digital Crown page navigation | [SHIPPED] | Crown moves through the watch's pages (Today, habits, capture) and scrolls each page's list |
| Apple Watch — complications | [SHIPPED] | |
| Apple Watch — WCSession write forwarding | [SHIPPED] | The snapshot-backed watch forwards complete/cancel/defer/capture to the iPhone over WCSession; the phone applies the write and pushes back a fresh snapshot. Read-only only without a forwarder (previews) |
| Apple Watch — background complication refresh | [SHIPPED] | Phone-pushed snapshots reload watch WidgetKit timelines; providers also use periodic refresh policies |
| WidgetKit — Today widget (small/medium/large + accessory) | [SHIPPED] | Tapping the lead task's ring or a row's circle completes the task in place on the Home Screen families (small, medium, large); the Lock Screen accessory families draw the ring without the button |
| WidgetKit — ControlWidget (iOS, macOS) | [SHIPPED] | Shows the task at the top of Today and opens the app to Today when tapped |
| WidgetKit — Quick Capture control (iOS, iPadOS) | [SHIPPED] | A Control Center, Lock Screen, and Action button control that opens the app with the capture sheet ready, on a cold launch and on a resume. The tap leaves one request in the App Group handoff store and the app presents the sheet when its scene becomes active; the control carries no task data, so it has no snapshot to reload |
| WidgetKit — Today tasks widget | [SHIPPED] | |
| WidgetKit — Habits/streak widget | [SHIPPED] | |
| WidgetKit — daily-progress ring widget | [SHIPPED] | |
| WidgetKit — AppIntentConfiguration (user-configurable) | [SHIPPED] | Today widget can be scoped to a specific list with a native list picker |

---

## MCP Tool Catalog

All tools are implemented in `LorvexMCPHost`. The host runs `SwiftLorvexCoreService` over the pure-Swift core, opening the single Lorvex-managed App Group database resolved by the core's `DbLocator`. The dev `LORVEX_APPLE_DB_PATH` override is honored only on an unsandboxed build; there is no external-DB picker or database bookmark. Preview/in-memory stores are test-injected development paths, not user-facing MCP configuration.

### Task Tools — Read
`get_task`, `list_tasks`, `get_deferred_tasks`, `get_upcoming_tasks`, `search_tasks`, `get_dependency_graph`

### Task Tools — Write
`create_task`, `update_task`, `cancel_task`, `defer_task`, `reopen_task`, `complete_task`, `start_task`, `pause_task`, `move_task_to_list`, `set_task_someday`, `archive_task`, `unarchive_task`, `append_to_task_body`, `set_task_ai_notes`, `set_list_ai_notes`

### Task Batch Tools
`batch_create_tasks`, `batch_update_tasks`, `batch_complete_tasks`, `batch_cancel_tasks`, `batch_cancel_tasks_in_list`, `batch_defer_tasks`, `batch_reopen_tasks`, `batch_move_tasks`, `permanent_delete_task`

### Task Checklist Tools
`add_task_checklist_item`, `remove_task_checklist_item`, `toggle_task_checklist_item`, `update_task_checklist_item`, `reorder_task_checklist_items`

### Task Reminder Tools
`add_task_reminder`, `remove_task_reminder`, `set_task_reminders`, `get_due_task_reminders`, `get_upcoming_task_reminders`

### Task Recurrence Tools
`set_task_recurrence`, `remove_task_recurrence`, `add_task_recurrence_exception`, `remove_task_recurrence_exception`

### List Tools
`get_list`, `get_lists`, `create_list`, `update_list`, `delete_list`, `archive_list`, `unarchive_list`, `reorder_lists`, `get_list_health_snapshot`, `list_all_tags`, `rename_tag`, `merge_tags`, `delete_tag`

### Day Planning Tools
`propose_daily_schedule`, `get_daily_schedule`, `save_daily_schedule`, `set_daily_briefing`

### Calendar Tools
`create_calendar_event`, `batch_create_calendar_events`, `update_calendar_event`, `delete_calendar_event`, `edit_scoped_calendar_event`, `delete_scoped_calendar_event`, `search_calendar_events`, `get_calendar_timeline`, `export_calendar_ics`, `add_calendar_event_exception`, `remove_calendar_event_exception`, `link_task_to_event`, `unlink_task_from_event`, `link_task_to_provider_event`, `unlink_task_from_provider_event`, `get_linked_events_for_task`, `get_linked_tasks_for_event`

### Habit Tools
`get_habits`, `create_habit`, `update_habit`, `delete_habit`, `reorder_habits`, `complete_habit`, `uncomplete_habit`, `skip_habit`, `unskip_habit`, `adjust_habit_completion`, `batch_complete_habits`, `get_habit_stats`, `get_habit_completions`, `get_habit_reminder_policies`, `upsert_habit_reminder_policy`, `delete_habit_reminder_policy`

### Memory Tools
`read_memory`, `write_memory`, `rename_memory`, `delete_memory`

### Review Tools
`get_daily_review`, `add_daily_review`, `amend_daily_review`, `get_review_history`, `get_weekly_brief`

### System / Context Tools
`get_overview`, `get_session_context`, `get_ai_changelog`, `get_recent_logs`, `get_sync_status`, `get_setup_status`, `complete_setup`, `get_guide`

### Preferences Tools
`get_preference`, `get_all_preferences`, `set_preference`, `delete_preference`

### Data Tools
`export_data`

---

## Core Infrastructure

| Feature | Status | Notes |
|---|---|---|
| Pure-Swift core (LorvexWorkflow, LorvexStore, LorvexSync) | [SHIPPED] | `LorvexAppleCore` package via `LorvexCoreServicing` (`SwiftLorvexCoreService`) |
| SQLite persistence | [SHIPPED] | `LorvexStore` (GRDB) over `schema/schema.sql` |
| Canonical ai_changelog funnel for all MCP mutations | [SHIPPED] | Enforced in Swift `LorvexWorkflow` (`ChangelogWrite`); durable write-through is suppressed only by the user's explicit `off` privacy policy |
| CloudKit sync (read + write) | [SHIPPED] | Live mode runs on `CKSyncEngine`: outbound record export from the local outbox, the engine's private database subscription and change fetches, inbound record application, and engine-state checkpoints in SQLite; distributed builds still require CloudKit entitlement/container provisioning |
| HLC conflict resolution | [SHIPPED] | Typed HLC generation/receive, parse-first LWW gates, conflict logging, merge HLCs, and device-suffix collision detection |
| Idempotency cache (MCP write retry) | [SHIPPED] | In-memory 24h TTL + durable mcp_idempotency DB table backing for cross-restart replay |
| Prompt-injection fencing on MCP read responses | [SHIPPED] | Structured read payloads carrying user-controlled text are key-aware fenced through `SecurityFencing.fenceValue`, including task, calendar, list/tag, day-planning, habit, review, and memory reads |
| MCP argument normalization | [SHIPPED] | Before a tool runs, the dispatcher removes fence tokens from every string argument and checks each `enum`-declared argument (top level, array items, nested batch objects) against the tool's input schema; any other value fails with a `validation` error listing the allowed values |
| App Group widget snapshot sharing | [SHIPPED] | Requires LORVEX_WIDGET_APP_GROUP_ID |
| Managed App Group storage | [SHIPPED] | Every surface (app, MCP helper, widgets, App Intents, notifications) resolves the single Lorvex-managed App Group database via `DbLocator` — no external-DB picker or security-scoped bookmark. The only override is the dev `LORVEX_APPLE_DB_PATH`, honored on unsandboxed builds only; portability is export/import. `ManagedStorageInvariantTests` pins this |
| App Intents (Shortcuts, Spotlight) | [SHIPPED] | |
| EventKit mirroring (read) | [SHIPPED] | Settings exposes native all-except / only-selected calendar filtering before provider events enter the mirror |
| EventKit write-back (Lorvex calendar create/update/delete) | [SHIPPED — macOS only] | macOS writes Lorvex-originated events through to the dedicated EventKit calendar; iPhone/iPad are read-only (ingest for display, create Lorvex-native events only, never write to Apple Calendar). Provider-owned external events remain read-only mirrors everywhere |
| Notifications (macOS) | [SHIPPED] | |
| Notifications (iOS — scheduling parity) | [SHIPPED] | Task reminders, rich actions, permission recovery, and app-icon badge wiring |
| Habit milestones | [SHIPPED] | Streak/count milestone waypoints (auto-ladder + optional `milestone_target`). `create_habit`/`update_habit` accept `milestone_target`; `get_habits`/`get_habit_stats` expose the milestone metric, next waypoint, and progress; `complete_habit`/`batch_complete_habits` return `reached_milestone` |
| Defer-note history | [SHIPPED] | The free-text defer note persists into `ai_changelog` (reserved `_defer` object); `get_task` returns a read-only `defer_history` (note fenced) |
| Assistant change log | [SHIPPED] | Every assistant write is recorded in `ai_changelog`, shown under Settings > Diagnostics and returned by `get_ai_changelog`; Today does not list it. Task rows carry before/after enriched JSON, briefing rows the day's previous briefing text, and saved-schedule rows the previous planned dates and times, so the log shows what each change replaced |
| Crash/diagnostics observability (MetricKit) | [SHIPPED] | A MetricKit subscriber persists crash/hang/CPU/disk diagnostics into `error_logs`; the iOS Settings surface shows a read-only Recent Diagnostics list |
| On-device failure diagnosis | [SHIPPED] | The iOS Recent Diagnostics feed also carries the `error`-level rows Lorvex logs itself, each tappable for its full detail; the Diagnostics summary adds the outbox's retrying depth and the newest transport error still attached to an unsynced row |
| Widget snapshot publishing | [SHIPPED] | One `WidgetSnapshotPublisher` engine in `LorvexWidgetKitSupport` drives every surface's App Group snapshot |
