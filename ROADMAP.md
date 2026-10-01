# Roadmap

Organized by lane: **Apple** (`apps/apple`) and **Shared** (`schema/`, `spec/`,
`cloudkit/`). The Apple core port has landed; its decision record is
`docs/decisions/pure-swift-core-port.md`.

Apple Swift is the only shipping line: macOS App Store, direct macOS builds,
iOS, iPadOS, watchOS, WidgetKit, App Intents, EventKit, CloudKit/iCloud, and
other Apple-native capabilities. visionOS is out of scope for now. The former
cross-platform Tauri line was removed from this repository on 2026-09-17.

## Next up

### Apple (Swift)
- CloudKit live sync on devices: the container `iCloud.com.lorvex.apple` is
  provisioned and its schema is deployed to Production. The `.live` mode runs
  `CloudSyncController`, an actor wrapping `CKSyncEngine` over one `Lorvex`
  zone (`docs/decisions/cksyncengine-transport.md`). Still owed: two-device
  proof on TestFlight builds, including the iOS sync pass that runs inside a
  background task before the database suspends, and silent-push wakes.
- CarPlay runtime activation: entitlement approval pending from Apple.
- watchOS / CarPlay / Widgets design audits (need on-device).
- Claude Code plugin distribution: `/plugin marketplace add boyugou/lorvex`
  resolves once the public repository carries `plugins/lorvex` and
  `.claude-plugin/marketplace.json`.

### Shared
- `schema/schema.sql` is the app's schema authority. Schema changes go through
  the numbered migration ladder and the sync-payload manifests
  (`schema/migrations/README.md`, `schema/sync_payload/`).

## Done
- **Review pages name the tasks their sentences count.** The week page's
  **Overdue** section lists open tasks past their due date, earliest first,
  each with how long ago it was due in local days; the day page's **Still
  open** section lists the tasks due that day that are not done. Both lists
  show up to five and end with a count of the rest, and every listed row opens
  its task (macOS selects it in All Tasks; iPhone pushes it on the Review
  stack). One shared view draws these lists and the week's "Kept getting
  pushed" rows (`LorvexReviewTaskList`). The data comes from
  `WeeklyReview.Snapshot.overdueTasks` and `DayReview.DaySummary.dueOpenTasks`;
  the MCP `get_weekly_brief` output is unchanged.
- **Assistants on This Mac.** The MCP helper records the name, title, and
  version each client sends in the `initialize` handshake, and refreshes the
  last-used time at most every ten minutes while the client calls tools. macOS
  Settings → Assistant lists each client with when it last used Lorvex, so a
  user can confirm a connection works end to end. The record is device-local
  (`device_state`), written outside the sync, change-log, and HLC paths.
- **Assistant guidance in three layers.** The MCP host sends a condensed
  operating model as its `initialize` instructions
  (`apps/apple/Sources/LorvexMCPHost/MCPHostInstructions.swift`), which Claude
  Code and Claude Desktop put in the model's system prompt; the Claude Code
  plugin (`plugins/lorvex`) starts the helper inside the installed app and adds
  plan-day, capture, weekly-review, and tidy-memory skills; tool descriptions
  carry each tool's contract. `get_session_context` reports the weekday and
  local time. Tests fail when the instructions or a skill name a tool,
  parameter, or field the tools do not define. The playbook is
  `docs/design/AI_OPERATING_MODEL.md`.
- **Shipped languages: English and Simplified Chinese.** Every catalog, bundle
  plist, `InfoPlist.strings` set, and the in-app language picker carry exactly
  `en` and `zh-Hans`, so a UI string costs one translation. The eleven other
  localizations were dropped on 2026-09-17 and remain in git history.
- **Habit milestones.** Streak/count milestone waypoints (auto-ladder plus an
  optional user `milestone_target`) with a celebration when a waypoint is crossed;
  the macOS and iPhone/iPad habit surfaces ship progress, goal editing, and
  milestone celebration. MCP:
  `create_habit`/`update_habit` accept `milestone_target`;
  `get_habits`/`get_habit_stats` expose the milestone metric, next waypoint, and
  progress; `complete_habit`/`batch_complete_habits` return `reached_milestone`.
  `habits.interval` was dropped from the schema. Tauri carries `milestone_target`
  through its Rust store/sync.
- **Defer-note history.** A defer's free-text note persists into `ai_changelog`
  (reserved `_defer` object); `get_task` returns a read-only `defer_history` (note
  fenced).
- **Crash/diagnostics observability.** A MetricKit subscriber persists
  crash/hang/CPU/disk diagnostics into `error_logs`; the iOS Settings surface shows
  a read-only Recent Diagnostics list.
- **MCP catalog at 114 tools.** Trimmed `get_capabilities` and
  `list_pending_outbox_entries`.
- **`saved_search` removed** — schema tables plus all UI/core/sync; the feature no
  longer exists.
- **Dead code removed, widget publishing unified.** Dropped the `McpHostAuthority`
  Swift wrapper, `SyncLease`, and `WidgetSnapshotBuilder`; widget snapshot
  publishing is one `WidgetSnapshotPublisher` engine in `LorvexWidgetKitSupport`.
  The now-decoupled Apple schema also drops the `mcp_host_authority` and
  `local_sync_owner` tables, which only ever served the Tauri consumer (Tauri
  keeps them in its own schema copy).
- **Schema-freeze tripwire.** A dormant post-launch schema-freeze check
  (`apps/apple/script/verify_schema_freeze.py` + `schema/migration_policy.json`,
  armed at launch) guards the two-regime invariant in
  `docs/design/SCHEMA_OPTIMALITY.md`.
- **MCP tool-parity audit vs the Tauri reference.** Diffed the
  85 reference tools against Apple's catalog (now 114): two real
  create-but-never-delete gaps closed (`delete_habit_reminder_policy` with
  tombstone-emitting sync semantics; `remove_calendar_event_exception`
  restoring skipped occurrences, behavior-pinned against the timeline
  expansion); the remaining differences are deliberate renames
  (`set_recurrence`→`set_task_recurrence`, provider-link naming) and the
  deliberately unported `control_app_ui`/local link-edge tools.
- **Data-export/import localization QA complete.** Native-copy review passed
  across the import/export strings (descriptions, previews, summaries) in all
  thirteen languages; the review caught and fixed a literal "1" in the
  Russian/Polish one-category record count (Russian's one covers 21/31/101…,
  so the literal misreported those counts). Plural-rule polish is the
  catalog-wide plural-variation conversion recorded below.
- **Scheduled-vs-planned split: resolved as planned-first.** The calendar
  lane's `getScheduledTasks` filters `COALESCE(planned_date, due_date)` at
  the SQL level — identical to the Tauri reference query — so app-planned
  tasks surface in their week. Pinned by the dual-backend contract
  "a planned task appears in the scheduled window on its planned day".
- **Habits across every surface.** Reminder policies now drive
  real daily notifications on macOS and iOS (shared scheduler architecture,
  cleanup-first/no-empty-prompt permission discipline applied to task
  reminders too) and surface as chips in both habit details. The watch gains
  a Habits section with one-tap completion over a new completeHabit
  WatchConnectivity mutation; working hours became user-configurable on both
  Settings surfaces (shared WorkingHoursPreference helper) with the propose
  button's tooltip naming the window.
- **Plural correctness across every surface.** The catalog facade
  resolves strings itself, so xcstrings plural variations never engaged via
  the platform; the reader now owns plural resolution (LorvexPluralRules:
  CLDR categories for all 13 languages). Every manual one/many key pair —
  macOS app (16), mobile, widgets (incl. VoiceOver labels), watch
  complication, and all 17 Siri intent dialogs — converted to
  plural-variation keys with authored Russian/Polish few forms;
  mixed-placeholder dialogs normalized to positional specifiers. Zero manual
  plural pairs remain in any catalog; verifier and completeness tests
  validate the variation shape.
- **Review/habit product wave.** Reviews: daily autosave +
  visible save state, recent-review history strip with in-window editing,
  weekly week-by-week navigation with per-week notes. Habits: reminder
  policies now schedule real daily notifications (mirroring the task-reminder
  architecture) and surface as chips in the expanded row. Preferences:
  working hours configurable in Settings → General; wizard completion mirrors
  into the core's setup state so assistants stop re-onboarding finished
  users. All pinned by the dual-backend contract suite (22 contracts × 2
  backends).
- **MCP tool-parameter integrity audit.** Every declared input
  across the Apple MCP catalog (currently 114 tools) checked against handler
  reads, both directions. Three surfaces advertised parameters they ignored — all
  fixed end to end with dual-backend contracts: the core
  `getWeeklyReviewSnapshot(weekOf:)` week anchor (anchored week windows, also
  powering the app's weekly-review navigation), `get_weekly_brief`'s four
  section limits (now serving the documented brief shape with honest
  per-section meta), and `propose_daily_schedule`'s working-hours overrides +
  calendar toggle. Inverse direction (handler reads never declared) is clean.
- **Live-feedback UI wave.** Every issue from the user's hands-on
  pass fixed at code level: AppKit-level dynamic window floor
  (`WindowMinWidthEnforcer`, NSWindow-tested — the SwiftUI-only minimum never
  re-clamped open windows), busy-only privacy hint with one-click upgrade in
  the calendar, scroll anchors on every hour row (dead Earlier/Later pills),
  `LorvexDateChip` (graphical calendar popover) across all date inputs, Tasks
  tab identity copy, task-inspector debounced autosave with an in-flight
  draft-clobber guard, visible line-based batch capture (window + menu bar),
  drag-reschedule bridged into the planned-day storage frame. Plus the
  scheduled-task lane fix (`COALESCE(planned_date, due_date)`), calendar task
  pill drag + context-menu re-planning, and the dual-backend contract suite
  (11 contracts; caught the fake's missing canonical sort and the importer's
  staleness-window bug — restore now uses `importDailyReview`).
- **Computer-use visual QA wave.** Every macOS surface toured
  live in both appearances; four real bugs caught on-screen and fixed with
  regressions: date-only dues rendered one day early west of UTC (UTC-midnight
  day read with the local calendar), unlocalized Today titles, the list-scoped
  Tasks view lacked the inline quick-add (routing gap), and task status
  mutations left sidebar list counts stale (25 call sites). Also landed from
  the tour: calendar event deletion (edit sheet had no delete path),
  in-flight gating on the event sheets, and an explicit "Add Only — reads
  blocked" state for write-only calendar permission. Dual-backend contracts
  grew to 15, adding the calendar event lifecycle.
- **Backup/restore integrity.** The export wire format and the
  restore path now carry the complete task model (AI notes, dependencies, list
  membership, ordered checklists with completion state, reminders, recurrence
  rules with skipped occurrences) and daily reviews restore at any
  historical date (`importDailyReview`, exempt from the interactive staleness
  window, mirroring the Tauri sync-mode import). The dual-backend contract
  suite (`DualBackendContractTests`, 11 contracts × fake/real) caught three
  real fake-vs-core divergences along the way.
- **Review-fix + UI polish wave.** 37/47 round-two review
  findings resolved (every persistence/sync/subtle-bug item incl. the S-01
  redirect gates, full CloudKit transport hardening CK-01…04, HLC observation,
  retention GC, schema-migration runner, shadow promotion). macOS UI pass: dynamic 3-pane
  window minimum, fixed-width toolbar search, sidebar scroll-reset root cause,
  daily-review autosave + history strip, habits check-in lane, 14pt reading
  sizes, labeled header actions, inline quick-add on Today and list panes.
  Open: ARCH-01/03…11 architectural refactors (standalone projects).
- **MCP parity with the original reference catalog, and beyond.** The current Apple catalog has 114 tools.
  Parity work added tools the reference never had: `edit_scoped_calendar_event`,
  `delete_scoped_calendar_event`
  (full recurring-event scope machinery using `CalendarRecurrenceScope`),
  `batch_create_calendar_events`,
  `add_calendar_event_exception`, `batch_cancel_tasks_in_list`,
  `batch_cancel_tasks`, `permanent_delete_task`, `delete_preference`,
  plus `Calendar +N more` overflow badge and `Tasks Table view` on macOS.
- **Full MCP tool description quality pass.** The full Apple MCP catalog was
  reviewed; ~50 tools upgraded to include when-to-use guidance, parameter semantics, recurrence
  caveats, response shapes, and security fencing notes.
- **Tauri MCP parity gap closure.** Added 5 missing tools:
  `batch_cancel_tasks`, `batch_cancel_tasks_in_list`, `permanent_delete_task`,
  `delete_preference`, `add_calendar_event_exception`. Also added
  `batchCancelTasksInList` to the service layer (LorvexCoreServicing) and
  `deletePreference` + `addCalendarEventException` service methods. Later
  additions leave the current catalog at 114 tools.
- **Tasks workspace @AppStorage persistence.** `isTableMode` saved so the
  user's list/table toggle survives navigation and restarts.
- **MCP durable idempotency.** `mcp_idempotency` table backing wired end-to-end:
  `McpIdempotency` (LorvexStore) → `LorvexMcpIdempotencyServicing` (LorvexCore
  protocol) → `SwiftLorvexCoreService` conformance
  → `CoreBridgeClient.mcpIdempotency` → `ToolRegistryDispatch` DB fallback on
  in-memory miss and DB persist on store. Boot-sweep at MCP host startup.
- **macOS Tasks Table view.** Sortable `SwiftUI.Table` mode toggled from the
  Tasks workspace toolbar (tablecells icon). Priority, Status, Title, Due, List
  columns; multi-selection shared with List mode; priority filter auto-hides in
  Table mode. `LorvexTask.Priority` and `Status` gained `Comparable` conformance.
- **Calendar off-screen event indicators.** Sticky "Earlier ↑" / "Later ↓"
  capsule pills appear in the calendar week grid when timed events fall above or
  below the current viewport. Tapping scrolls to the nearest hidden event.
  macOS 14-compatible via `coordinateSpace` preference key.
- **MCP tool description quality pass.** 20+ high-traffic tools updated with
  when-to-use guidance, parameter semantics, recurrence caveats, response shapes,
  and security fencing notes to match the Tauri reference quality bar.
- **Shared doc reorganization.** Cross-app behavioral contracts (DESIGN_PHILOSOPHY,
  AI_OPERATING_MODEL, CALENDAR_BEHAVIOR, SORT_KEYS, SYNC_APPLY_SEMANTICS) moved
  from app-specific `docs/design/` folders to root `docs/design/` and
  `docs/vision/`. App-local copies replaced with 3-line redirect stubs.
- **Root CI workflow.** `.github/workflows/apple-ci.yml` covers the monorepo at
  the root: Swift package build/tests, the Apple static verifiers, and the
  Apple-only schema-integrity checks (embed byte-parity via
  `verify_schema_embed.sh`, migration ladder, schema freeze). The workflow is
  `workflow_dispatch`-only while hosted macOS CI is paused; the local
  `apps/apple/script/verify_all.sh` gate is the validation of record.
- **Pure-Swift core port (Phases 1–5).** The `LorvexAppleCore` package backs the
  Apple app end-to-end:
  - Phase 1 — `LorvexDomain`: value types, validation, RRULE recurrence, DST,
    HLC, canonical JSON. Pure, I/O-free.
  - Phase 2 — `LorvexStore`: SQLite over `schema/schema.sql` (GRDB.swift).
  - Phase 3 — `LorvexWorkflow`: mutation executor, `ai_changelog`, idempotency.
  - Phase 4 — `LorvexSync`: CloudKit envelope, conflict resolution.
  - Phase 5 — cutover: `SwiftLorvexCoreService` backs `LorvexCoreServicing` over
    the Swift core; the app builds and `swift test` (app + core) passes.
- **Today as one ordered list; Focus retired.** Today shows every unfinished
  task planned for today or earlier, due today or overdue, or already
  started, ordered started-first then by priority then by due date, with no
  separate current-task concept and no saved focus schedule.
  `set_daily_briefing`, `get_daily_schedule`, and `save_daily_schedule` back
  the assistant's per-day briefing and optional planned start/end times over
  the real on-disk store.
- **Feedback routing.** All contact and support routes through the
  https://lorvex.app/support/ pages; Lorvex does not expose an in-app or MCP
  feedback submission path.
- **MCP on-disk Swift-core regression coverage.** The Swift MCP host now has
  on-disk bridge tests for task, list, and tag lifecycle writes, including
  reopened-registry mutation paths.
- **Script suite reconciled.** The `apps/apple/script/` verify/packaging suite
  runs against the Swift backend; no `cargo`/bridge step remains.
- **Phase 0 — monorepo merge.** Apple tree → `apps/apple`; Tauri snapshot →
  `apps/tauri` (removed again on 2026-09-17, tag `tauri-snapshot-final`); shared
  `schema/`, `cloudkit/`, `spec/` hoisted to root; root README/CLAUDE/ROADMAP.
  `rust-bridge/` deleted.
