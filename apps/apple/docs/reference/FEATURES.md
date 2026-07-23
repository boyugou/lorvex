# Feature Status Catalogue

Status tags: `[SHIPPED]` = present and functional, `[PARTIAL]` = code present but incomplete or has known gaps, `[PLANNED]` = not yet built.

MCP tool count: 118. Scoped calendar edit/delete tools are Apple-specific. Apple Swift is the only Apple ecosystem shipping line for macOS App Store, iOS, iPadOS, watchOS, visionOS, CloudKit/iCloud, WidgetKit, and App Intents.

---

## Apple Surfaces

| Surface | Status | Notes |
|---|---|---|
| macOS — sidebar + all workspaces | [SHIPPED] | Plan: Today, Calendar, Tasks; Reflect: Habits, Reviews, Memory (Memory has no detached-window scene). Lists have no sidebar row — they are managed inline, with the catalog reached via ⌘K |
| macOS — multi-window | [SHIPPED] | Detached list/workspace windows + floating task stickies |
| macOS — menu bar extra | [SHIPPED] | Today HUD: date + due-count, quick-add, next-up list with one-click complete |
| macOS — full command menus + keyboard shortcuts | [SHIPPED] | |
| macOS — settings (General/Assistant/Calendar/CloudSync/Diagnostics/Data/Permissions) | [SHIPPED] | |
| macOS — workspace loading states | [SHIPPED] | Primary async workspaces show a native loading overlay |
| macOS — global error toast | [SHIPPED] | `ContentView.lorvexToast` handles transient app/notification-action failures |
| macOS — list reordering | [SHIPPED] | Lists and habits support persisted drag reordering |
| macOS — calendar date navigation | [SHIPPED] | Week/list navigation with previous, next, Today/This Week, and date picker controls |
| macOS — habit streak/heatmap | [SHIPPED] | Streak metrics + calendar heatmap in the habits workspace |
| macOS — habit milestones | [SHIPPED] | Streak/count milestone waypoints (auto-ladder + optional user target), a progress bar, and a celebration when a waypoint is crossed |
| macOS — Eisenhower matrix | [PARTIAL] | MCP-data-only (urgency/importance quadrant data the AI can read via MCP) — no macOS human surface; `WorkspaceView` redirects `.eisenhower` to Today |
| macOS — dependency-graph workspace | [PARTIAL] | MCP-data-only (task dependency data the AI can read/write via MCP) — no macOS human surface; `WorkspaceView` redirects `.dependencies` to Today |
| macOS — Command Palette (⌘K) | [SHIPPED] | Fuzzy command/navigation palette |
| macOS — Data export/import | [SHIPPED] | Settings → Data writes the version-1 Apple export: portable category JSON plus an independently versioned exact native task graph for same-app restore, including task-domain deletion high-waters and opaque future-field state. CloudKit account/transport state is never restored; JSON may carry the producing device ID only as non-applied provenance. ZIP v1 requires an exact closed manifest inventory and has no blob members. Exact task restore is used only for a fresh task domain with its list/tag roots; otherwise tasks use the portable merge path. Live import terminally drains and proves the exact CloudKit generation, fixed-point pending inbox, and persistent corrupt-record debt under the same coordinator gate; off/record-plan import is local-only. MCP/AI export stays portable, and cross-platform movement is AI-reconciled best-effort rather than a lossless interchange contract |
| iPhone — Today, Tasks, Calendar, Habits, More tabs | [SHIPPED] | Daily-driver surfaces are first-class tabs; the day plan (current focus + optional time-blocks) lives in Today; no separate Focus tab |
| iPhone — global quick-capture sheet | [SHIPPED] | Capture is an action (a ＋ sheet) raised from Today/Tasks toolbars, the task empty-state, and ⌘N — not a tab |
| iPhone — task detail + edit sheet | [SHIPPED] | |
| iPhone — create sheets (task/list/habit/event) | [SHIPPED] | |
| iPhone — secondary workspace reach (Memory, Review) | [SHIPPED] | More tab exposes the secondary workspaces + Settings; Lists is merged into the Tasks tab home |
| iPhone — Settings screen | [SHIPPED] | Settings, diagnostics (incl. a read-only recent crash/hang diagnostics feed), privacy and acknowledgments, data export/import, notification/reminder toggles |
| iPhone — habit milestones | [SHIPPED] | Habit detail shows milestone progress and target editing; completion and batch completion surface milestone celebrations |
| iPad — NavigationSplitView (regular width) | [SHIPPED] | Full sidebar shell with primary tabs and all secondary workspaces |
| iPad — full sidebar (like macOS) | [SHIPPED] | Today, Tasks, Calendar, Habits, Memory, Review, Settings; Lists is merged into the Tasks home |
| iPad — Tasks split workspace | [SHIPPED] | Query-backed status/search browser with persistent list + detail panes on regular width |
| iPad — Calendar agenda workspace | [SHIPPED] | 3-day time grid with pinned visible-event agenda and quick create/edit affordances on regular width |
| iPad — Lists split workspace | [SHIPPED] | List catalog pinned beside selected list task/progress detail on regular width |
| iPad — Habits split workspace | [SHIPPED] | Active habit catalog pinned beside progress metrics and completion/edit/delete controls on regular width |
| iPad — Memory split workspace | [SHIPPED] | Save controls and full memory catalog pinned beside selected content, metadata, and delete controls on regular width |
| iPad — hardware keyboard shortcuts | [SHIPPED] | ⌘R, ⌘N, ⌘1-⌘5, ⌘8, and mnemonic workspace shortcuts (⌘M/⌘E/⌘,); ⌘6/⌘7/⌘9 are visionOS-only |
| Apple Watch — root view (focus task, queue, capture, complete) | [SHIPPED] | Snapshot-backed on device with WatchConnectivity write forwarding to iPhone |
| Apple Watch — Digital Crown focus controls | [SHIPPED] | Crown navigates queued focus tasks |
| Apple Watch — complications | [SHIPPED] | |
| Apple Watch — WCSession write forwarding | [SHIPPED] | The snapshot-backed watch forwards complete/cancel/defer/capture to the iPhone over WCSession; the phone applies the write and pushes back a fresh snapshot. Read-only only without a forwarder (previews) |
| Apple Watch — background complication refresh | [SHIPPED] | Phone-pushed snapshots reload watch WidgetKit timelines; providers also use periodic refresh policies |
| WidgetKit — focus widget (small/medium/large + accessory) | [SHIPPED] | Interactive complete on medium/large |
| WidgetKit — ControlWidget (iOS 18) | [SHIPPED] | Shows the current focus task and opens the app to Today when tapped |
| WidgetKit — Today tasks widget | [SHIPPED] | |
| WidgetKit — Habits/streak widget | [SHIPPED] | |
| WidgetKit — daily-progress ring widget | [SHIPPED] | |
| WidgetKit — AppIntentConfiguration (user-configurable) | [SHIPPED] | Today widget can choose Today tasks or Focus queue and filter with a native list picker |
| CarPlay — task list, row tap opens an action sheet (Complete / Defer / Remove from Focus / Open on iPhone) | [PARTIAL] | Controller and scene delegate present; Apple entitlement approval required for runtime activation |

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

### Focus Tools
`get_current_focus`, `set_current_focus`, `add_to_current_focus`, `remove_from_current_focus`, `clear_current_focus`, `propose_daily_schedule`, `get_saved_focus_schedule`, `save_focus_schedule`

### Calendar Tools
`create_calendar_event`, `batch_create_calendar_events`, `update_calendar_event`, `delete_calendar_event`, `edit_scoped_calendar_event`, `delete_scoped_calendar_event`, `search_calendar_events`, `get_calendar_timeline`, `export_calendar_ics`, `add_calendar_event_exception`, `remove_calendar_event_exception`, `link_task_to_event`, `unlink_task_from_event`, `link_task_to_provider_event`, `unlink_task_from_provider_event`, `get_linked_events_for_task`, `get_linked_tasks_for_event`

### Habit Tools
`get_habits`, `create_habit`, `update_habit`, `delete_habit`, `reorder_habits`, `complete_habit`, `uncomplete_habit`, `adjust_habit_completion`, `batch_complete_habits`, `get_habit_stats`, `get_habit_completions`, `get_habit_reminder_policies`, `upsert_habit_reminder_policy`, `delete_habit_reminder_policy`

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
| CloudKit sync (read + write) | [SHIPPED] | Live mode includes outbound record export, private database subscription, remote-change refresh, inbound record application, and atomic SQLite change-token checkpointing; distributed builds still require CloudKit entitlement/container provisioning |
| HLC conflict resolution | [SHIPPED] | Typed HLC generation/receive, parse-first LWW gates, conflict logging, merge HLCs, and device-suffix collision detection |
| Idempotency cache (MCP write retry) | [SHIPPED] | In-memory 24h TTL + durable mcp_idempotency DB table backing for cross-restart replay |
| Prompt-injection fencing on MCP read responses | [SHIPPED] | Structured read payloads carrying user-controlled text are key-aware fenced through `SecurityFencing.fenceValue`, including task, calendar, list/tag, focus, habit, review, and memory reads |
| App Group widget snapshot sharing | [SHIPPED] | Requires LORVEX_WIDGET_APP_GROUP_ID |
| Managed App Group storage | [SHIPPED] | Every surface (app, MCP helper, widgets, App Intents, notifications) resolves the single Lorvex-managed App Group database via `DbLocator` — no external-DB picker or security-scoped bookmark. The only override is the dev `LORVEX_APPLE_DB_PATH`, honored on unsandboxed builds only; portability is export/import. `ManagedStorageInvariantTests` pins this |
| App Intents (Shortcuts, Spotlight) | [SHIPPED] | |
| EventKit mirroring (read) | [SHIPPED] | Settings exposes native all-except / only-selected calendar filtering before provider events enter the mirror |
| EventKit write-back (Lorvex calendar create/update/delete) | [SHIPPED — macOS only] | macOS writes Lorvex-originated events through to the dedicated EventKit calendar; iPhone/iPad/visionOS are read-only (ingest for display, create Lorvex-native events only, never write to Apple Calendar). Provider-owned external events remain read-only mirrors everywhere |
| Notifications (macOS) | [SHIPPED] | |
| Notifications (iOS — scheduling parity) | [SHIPPED] | Task reminders, rich actions, permission recovery, and app-icon badge wiring |
| Habit milestones | [SHIPPED] | Streak/count milestone waypoints (auto-ladder + optional `milestone_target`). `create_habit`/`update_habit` accept `milestone_target`; `get_habits`/`get_habit_stats` expose the milestone metric, next waypoint, and progress; `complete_habit`/`batch_complete_habits` return `reached_milestone` |
| Defer-note history | [SHIPPED] | The free-text defer note persists into `ai_changelog` (reserved `_defer` object); `get_task` returns a read-only `defer_history` (note fenced) |
| Crash/diagnostics observability (MetricKit) | [SHIPPED] | A MetricKit subscriber persists crash/hang/CPU/disk diagnostics into `error_logs`; the iOS Settings surface shows a read-only Recent Diagnostics list |
| Widget snapshot publishing | [SHIPPED] | One `WidgetSnapshotPublisher` engine in `LorvexWidgetKitSupport` drives every surface's App Group snapshot |
