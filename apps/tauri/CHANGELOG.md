# Changelog

All notable user-facing changes to Lorvex are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- **CLI lifecycle parity** — `lorvex task trash` lifecycle (move, restore, permanent-delete with dry-run preview) and batch trash operations bring the CLI to full parity with the app's task lifecycle surface.
- **CLI reminder mutations** — `lorvex task reminder` set/add/remove/clear so agents can manage per-task reminder schedules without going through the desktop UI.
- **CLI calendar subscription management** — `lorvex subscription {list, add, remove, refresh, toggle}` lets agents manage external `.ics` feed subscriptions without the desktop Settings panel.
- **`lorvex-sync-payload` crate** — forward-compat sync payload primitives (payload shadow + attendee shadow) shared by `lorvex-store` and `lorvex-sync`. Hosts the LWW merge/redirect helpers that preserve unknown JSON keys across the wire and sits between `lorvex-domain` and the two consumer crates so storage and sync can both depend on it without forming a cycle.
- **`calendar_event` and `calendar_subscription` workflow modules** — canonical mutation surfaces in `lorvex-workflow` that every consumer (MCP, app IPC, CLI, sync apply) shares, including the single `materialize_attendees` materializer for `calendar_event.attendees[]`.
- **New sync + lifecycle verifiers** — additional gates added to `scripts/verify/` (including `no_trajectory_comments`, issue audit drift, mutation executor coverage, and audit verifier completeness) run alongside the existing contract verifiers.
- **CLAUDE.md rule #9: GitHub-only contact paths (permanent policy)** — every contact-bearing doc routes through GitHub issues/security advisories. No `@lorvex.app` mailbox exists or is planned: the mail-routing tracker (#4096) was retired, and reintroducing any email reference is a permanent dead contact path, not a tracker-gated regression.
- **Windows desktop hardening** — Hello biometric broker, Mica gating, WebView2 hardening, taskbar badge overlay, jump-list integration with invalidation, dark title bar, AUMID, recurrence UNTIL + exception handling, and STA-gated COM init.
- **Multi-OS Rust CI** — full matrix (macOS, Windows, Linux) on every PR plus N+1 batch fetch and seed streaming for faster cold builds.

### Changed
- **Canonical mutation executor** — `IpcMutationExecutor` plus the shared `Flush` trait centralize how the app, CLI, and MCP surfaces drive `lorvex-workflow` mutations and their post-write side effects (changelog, outbox enqueue, projection refresh), so every surface emits identical envelopes and audit rows. The eight per-mutation wrapper variants have been collapsed onto one `execute_with` core (#4577) and the `BatchCancelFlushBackend` layer has been folded into the generic `MutationFlushBackend<E>` base (#4528, #4544) so per-mutation flush plumbing stays at one definition site.
- **TaskUpdateInput typed `Patch<T>`** — every "omit / set / clear" patch field on `update_task` (and the batch mirror) now flows through the typed `Patch<T>` enum from the wire layer to the SQL writer (#4553, #4562), with Patch helper coverage swept across every adjacent input shape (#4546). The task-update mutation is decomposed into per-effect siblings and routes through one shared executor.
- **`lorvex-workflow` per-concern subtrees** — `calendar_event` (#4557 part 3, #4579), `task_create` (#4557 part 1, #4563), `calendar_normalization` (#4594), `task_update` (#4562), focus current writes (#4596), habits reminders (#4598), and the calendar normalization sweep (#4594) each live as a per-concern directory of sibling files. Each effect type owns its own file (create, update, load, attendees, recurrence_skeleton; input, wire, prepared, advice, date_parse, orchestrator, effects, child_inserts; etc.) so the per-mutation plumbing stays paged-in together and contract tests pin one descriptor per file.
- **Workflow descriptor + changelog hoists** — `current_focus` and `habit_reminder` MutationDescriptors moved from per-surface code into `lorvex-workflow` (#4588); the changelog writer moved from `lorvex-workflow` into `lorvex-store` (#4590) so every surface that writes a row goes through the same store-layer writer.
- **Child-table normalization** — `task_recurrence_exceptions` (#4585, #4599) replaces the JSON EXDATE column, and `sync_outbox_undo_group_chain` (#4585, #4597) replaces the inline undo group chain so cascade GC and FK constraints govern lifecycle instead of opportunistic JSON edits.
- **Due-date timezone routing** — naive `YYYY-MM-DD` due-date inputs are now interpreted in the user's configured timezone (preference key `system.user_timezone`) before being normalized to UTC, instead of always being read as UTC; tasks captured on the evening of a local date no longer roll forward by one day on agents in eastern timezones.
- **Settings IA + chrome polish** — the Settings tree is reorganized into a single canonical IA (general / appearance / sync / data / advanced) with consistent chrome (segmented headers, lane spacing, lane separators, sticky-search affordances), per the R16 A9 audit (#4560 part 2, #4578).
- **Calendar event wire shape** — `update_calendar_event` (MCP + IPC + CLI) now uses "JSON null clears, omission preserves" as the only clearing contract. The legacy `clear_fields[]` array is gone from the wire; null on the field itself is the canonical signal to clear an optional column.
- **Sync correctness** — cascade-tombstone-before-LWW gate, apply-cycle accountancy, redirect chain bounds, cross-type chase, coalesced savepoint enqueue, redirect canonicalization, cross-type shadow guard, post-write drain hook, and typed `Hlc` threading throughout the apply pipeline.
- **Typed enums at boundaries** — sync envelope, import lifecycle, preference, FFI, and parse boundaries now use typed enums instead of stringly-typed values; `TaskStatus`, `EntityKind`, and `SyncTimestamp` newtypes flow end-to-end.
- **MCP audit + idempotency** — every write tool emits an audit-trail entry, dedup keys gate idempotent retries, pagination + ordering is consistent across queries, and CLI parity is enforced via contract tests.
- **Frontend a11y + UX** — mutation `onError` handlers wired across mutations, mobile modal a11y, swipe-reveal collision fix, slide-panel cleanup, context-menu keyboard submenu, habit form validation, placeholder contrast, z-token consolidation, larger tap targets, quick-add validation, and cancellable app-version queries.

### Fixed
- **Sync regressions** — restored `DeleteLwwDecision::Reject` unit, propagated in-handler LWW rejection through `*DeleteOutcome::LwwRejected`.
- **task-update + calendar correctness** — four targeted fixes landed in #4541 covering task-update edge cases and calendar event timing rules that were drifting between the app, CLI, and MCP surfaces.
- **R17 A6 correctness cluster (8 bugs)** — eight task-update / calendar / sync edge cases landed in #4591 (#4582, #4583).
- **macOS ICS round-trip** — RDATE / RECURRENCE-ID / EXDATE TZID round-trip + parse hardening, plus tray tooltip, prodid, summary cap, sequence, and lipo-equality polish.
- **Schema migration trail + i18n drift** — hotfix across 31 locales for shelve_list skipped_task_ids handling.
- **Contract verifier + governance sweep** — wave-8 (#4580) and wave-10 (#4595) realign stale contract verifiers with canonical reality, trajectory-comment verifier extended with `pre-fix` / `pre-#NNNN` triggers and the wider rule family (#4593, this PR).
- **R17 A7+A8 interaction + CSS sweep** — interaction polish + CSS audit landed in #4589 (#4586).
- **R17 A9 power-user elevation** — 10 power-user surface upgrades landed in #4592 (#4587).

### Removed
- **Tauri Apple ecosystem scaffolding retired** — iOS/iPadOS, App Store, iCloud/CloudKit, App Group, WidgetKit, and App Intents work moved out of the Tauri line. Apple-platform production work belongs to the Swift app under `apps/apple`.
- **Dead code shields swept** — eleven dead-code shields removed across the workspace once the typed Patch sweep made them unreachable (#4546).
- **Dead code + stale state** — typed envelope reads, `is_allowed_attendee_status` removal, graph-pagination rationale captured, redundant useState type annotations dropped, decorative SVGs marked `aria-hidden`, z-overlay tokenized.

## [1.0.0]

### Added
- **Lorvex CLI** — Agent-first terminal companion runtime with 42 commands: task queries (today, overdue, upcoming, search), mutations (capture, complete, reopen, defer), focus planning, list management, data export/import, TUI dashboard with --watch, MCP serve, and cross-platform MCP install.
- **Shared Runtime (`lorvex-runtime`)** — Cross-platform shared operating model: DB locator, device identity, local_change_seq, sync ownership leases, MCP host authority detection, and capability profiles.
- **Multi-Surface Architecture** — App + CLI coexistence with single MCP endpoint policy, shared DB, and documented in `MULTI_SURFACE_ARCHITECTURE.md`.
- **OpenClaw/ClawHub Skill** — Lorvex skill for agent discovery with workflow guidance and MCP tools reference.
- **Retired CloudKit circuit breaker** — historical Tauri CloudKit auto-sync hardening; the Tauri line now keeps only provider-neutral sync abstractions and has no active cloud sync transport.
- **E2E tests** — 28 Playwright tests across 8 specs covering navigation, quick capture, today view, settings, view switching, i18n visual regression, main-window smoke, and the welcome-offline banner.
- **3 SQL indexes** — `planned_date`, `spawned_from`, `sync_pending_inbox` for query performance.
- **Calendar Events** — Monthly and weekly calendar views with full CRUD for events.
- **Daily Review + Habit Log** — Daily review with habit check-in tracking.
- **Eisenhower Matrix** — Urgency/importance quadrant view for all open tasks (⌘7).
- **Calendar view shortcut** — ⌘6 opens Calendar, ⌘7 opens Eisenhower.
- **Touch ID memory lock** — AI Memory view can be locked behind biometric auth. Auto-locks when you switch away from the app. Toggle in Settings.
- **Auto-updater** — App checks for new versions on startup and shows an update banner in the sidebar when one is available.
- **In-app toast notifications** — Subtle success/error feedback at the bottom of the screen when completing tasks, capturing, deferring, etc.
- **Recurrence display** — Task detail panel shows a human-readable summary of recurring task rules (e.g. "Every week on Mon, Wed until Dec 31").
- **Searchable language picker** — Language selector in Settings is now a searchable combobox. Handles all 31 supported languages cleanly.
- **Morning briefing notification** — Fires once per day at your configured briefing time with your AI plan summary or focus/overdue count.
- **Weekly review notification** — Prompts you on your configured review day and time.
- **31 supported languages** — Added Arabic, German, Spanish, French, Hindi, Indonesian, Italian, Japanese, Korean, Malay, Dutch, Polish, Portuguese, Russian, Thai, Turkish, Ukrainian, Vietnamese, and additional locales rounding the total to 31 (in addition to English and Chinese).
- **Window state persistence** — App remembers its last size and position between launches.
- **System tray menu** — Custom Lorvex icon in the menu bar. Right-click for Open / Quick Capture / Quit.
- **Command palette write actions** — Complete, defer, cancel, and reopen tasks directly from ⌘K. Tab on a result to move it to a different list. Create lists via `@scope`.
- **Calendar events in Upcoming view** — Events now appear alongside tasks in the next-7-days view.
- **Clickable changelog entries** — AI activity log entries link to the referenced task.
- **List creation and rename** — Create new lists from sidebar, rename via double-click.
- **Export/Import** — Full data export and import via MCP and app UI.
- **Keyboard accessibility** — Focus-visible indicators across all core views (sidebar, task detail, today view, list view, changelog, focus mode, all tasks, command palette, quick capture, popover, toast, error boundary).
- **Empty-state messaging** — All 7 core views use consistent ModuleStatePanel with AI-first messaging.
- **Birthday/anniversary events** — Calendar events now support `event_type` (event, birthday, anniversary, memorial) and `person_name` metadata. AI assistants can create birthday events with annual recurrence.
- **Skip occurrence for recurring events** — Recurring events in the calendar day panel show a ⊘ icon that expands to "Skip this occurrence" + "Delete". Skipping hides a single date without deleting the recurrence pattern (EXDATE).

### Removed
- **Inbox** — The inbox triage model was removed. The conversation with the AI assistant is now the review layer — tasks are created directly as `open` with proper list assignment. All inbox-related UI, keyboard shortcuts, and MCP tools have been removed.
- **Legacy `reminder_at` column** — The single-reminder field on the tasks table has been removed. The `task_reminders` table is now the sole reminder model, supporting multiple reminders per task. The schema is consolidated into `001_schema.sql`.
- **`is_pinned` field** — Removed entirely from schema, MCP contracts, Tauri IPC, and frontend. The pin-as-urgency-floor concept was unintuitive and confused users who expected "pin to top" behavior. Priority and urgency scoring handle the use cases better.

### Changed
- **Export/Import** now covers all user-data tables: task reminders, task-event links, and habit reminder policies are preserved on roundtrip. Previously these were silently dropped.
- **Boolean fields** — `is_pinned`, `all_day`, `is_notified` are now native booleans at both the Tauri IPC boundary AND the MCP tool contracts (previously integer 0/1). AI assistants should send `true`/`false`, not `1`/`0`.
- Task completion via MCP now **automatically creates the next recurrence** instead of requiring manual assistant follow-up.
- `complete_task` MCP response now returns `{ completed, next_occurrence }` instead of just the completed task.
- **TodayView performance** — Due-today/overdue tasks now fetched via dedicated SQL query instead of loading all tasks and filtering client-side.
- **Today deduplication** — Tasks in the Focus plan no longer duplicate in the "Due Today" section.
- **Dependency upgrades** — React 18→19, Tailwind CSS 3→4, rusqlite 0.32→0.38, dirs 5→6, @vitejs/plugin-react 4→6. No user-facing behavior change.

### Fixed
- **Pin urgency bug** — Pinning a task with a deadline was REDUCING its urgency score (from 8.0 to 2.0 for a P1 task due today). Pin now sets a floor instead of bypassing dynamic factors.
- Sync bridge errors are now reported instead of silently swallowed.
- **Click responsiveness** — Removed 150ms click delay from all task cards (was for undiscoverable double-click-to-edit).
- **Calendar "New Event" button** — Added prominent header button; previously event creation required clicking a date cell.
- **DailyReview form** — Added visible labels and required-field validation (summary was silently required before).
- **SomedayView quick-add** — Tasks now created atomically as "someday" instead of flashing briefly in TodayView.
- **Keyboard accessibility** — Added focus-visible indicators to hover-reveal patterns across TaskDetail, ScheduleTimeline, WeekGrid, and PopoverWindow.
- **PopoverWindow scroll** — Content area (tasks, events, briefing) now scrolls when it exceeds the window height.
- **Kanban columns** — Flex instead of fixed 320px width; fits narrower windows without horizontal scrolling.
- **First-run welcome** — Added CTA button directing new users to Settings.
- **QuickCapture tags** — Tags were silently lost due to comma-separated vs JSON array format mismatch. Fixed.
- **TaskCard cache** — Completing a task from the card didn't invalidate the open TaskDetail panel. Fixed.
- **Lists staleTime** — Renamed/recolored lists showed stale info in TaskCards forever. Changed from Infinity to 60s.
- **Completion animation** — Task cards now fade + shrink on completion before disappearing.
- **Enter animations** — TaskDetail slides in, QuickCapture/CommandPalette spring in with backdrop fade.
- Missing refetchInterval on today view and weekly review queries.
- Missing i18n keys for list creation/rename across all 18 locales.

### Historical Mobile Companion Prototype

This section records pre-boundary Tauri responsive/mobile work. iPhone/iPad
production work now belongs to the Swift app under `apps/apple`.

- **Full feature parity** — all 14 views accessible on mobile (tab bar + More menu).
- Bottom tab bar with SVG icons, safe-area padding, and overdue count badge.
- "More" tab with bottom sheet menu: 11 items organized by usage frequency (Calendar, Eisenhower, Kanban, Dependencies, Daily Review, Weekly Review, AI Activity, AI Memory, All Tasks, Someday, Settings).
- Search button in mobile header (navigates to All Tasks search).
- Touch-optimized: all hover-reveal controls (quick actions, reorder buttons) always visible on touch devices.
- **Long-press context menu** — hold any task card for 500ms to access ~15 actions (snooze, due date, recurrence, priority, move to list, pin, cancel, delete). Cancels on scroll.
- 44px minimum touch targets on all interactive elements (Apple HIG compliance).
- Safe-area support for notch/Dynamic Island (header) and home indicator (nav bar).
- Task detail slides up from bottom with safe-area header.
- QuickCapture drag handle tappable to dismiss.
- Responsive stat card grids (2 columns on mobile, 4 on desktop).
- Reduced horizontal padding on narrow screens (px-8 → 16px on <480px).
- `is_pinned` MCP contract converted from u8 to native bool — AI assistants send `true`/`false`.

### MCP Tools Added
- `reopen_task` — Reopen completed/cancelled/deferred tasks with proper lifecycle side effects (cancels auto-spawned recurring successors, recomputes urgency).
- `add_to_current_focus` — Append tasks to existing current focus without replacing (dedup, preserves briefing). Safer alternative to `set_current_focus` for adding individual tasks.
- `get_ai_changelog` — An assistant can query its own operation history with filters (entity_type, operation, entity_id, since).
- `reorganize_list` — Reorder tasks in a list by urgency, deadline, priority, or manual order.
- `propose_daily_schedule` — Generate a time-blocked Focus Schedule with start/end slots from today's focus tasks. Respects working_hours and available time.
- `analyze_task_patterns` — Analyze task behavior patterns from task history.

### MCP Ergonomics Improved
- Improved tool descriptions for `create_task`, `batch_complete_tasks`, `set_current_focus`, `get_ai_changelog`, `get_recent_logs` — clearer guidance for AI assistants.
- Added 13 missing field descriptions across `AddDailyReviewArgs` and `UpdateTaskArgs`.
- `batch_cancel_tasks_in_list` now returns cancelled task objects (previously only returned a count).
- `update_task.status` description warns about bypassing lifecycle tool side effects.

---

## [0.1.0-alpha]

Initial alpha release.

### Core Features
- AI-operated task management via MCP (32 tools)
- Today dashboard with AI briefing, today's focus, urgency ranking
- Inbox verification layer for assistant-proposed tasks
- Task detail with inline editing (title, notes, checklist items)
- Focus Mode — full-screen one-task-at-a-time
- Someday / Maybe list
- Upcoming (next 7 days, grouped by date)
- All Tasks with search and filters
- AI Activity log (changelog)
- AI Memory viewer
- Weekly Review with stalled lists, frequently-deferred tasks
- Command Palette (⌘K) with task search and navigation
- Quick Capture (⌘N)
- Settings: working hours, focus limit, language, theme, timezone, launch on login, assistant MCP one-click setup
- SQLite local storage, no cloud sync
- macOS native — dark/light/system theme
