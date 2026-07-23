# Lorvex — Roadmap

Single source of truth for project status. Every `[x]` is verified shipped. Every `[ ]` is genuinely not done.

**Principle: 止于至善.** There are no version milestones or priority tiers based on release timing. Everything worth doing should be done. Priority is determined only by dependency ordering (what unblocks other work) and user impact.

---

## Shipped

### Core Platform
- [x] SQLite schema with WAL mode, migrations, shared DB between app and MCP server
- [x] Tauri 2.x desktop app (macOS, Windows, Linux)
- [x] React 19 + TypeScript + Tailwind CSS 4 frontend
- [x] MCP server (Rust, 117 tools, stdio transport)
- [x] Lorvex CLI: agent-first terminal runtime (MCP serve, TUI, doctor/setup, scriptable shell commands)
- [x] Shared runtime crate (`lorvex-runtime`): DB locator, device identity, surface HLC runtime, sync leases, MCP authority
- [x] Multi-surface architecture: App + CLI share one DB, single MCP endpoint policy
- [x] Shared types package (`@lorvex/shared`)
- [x] 31 locales (English, Chinese, Japanese, Korean, and 27 more)
- [x] i18n audit: all user-visible strings use translation keys, with runtime interpolation/plural formatting for localized count phrases

### Task Management
- [x] Full task lifecycle: create, update, complete, cancel, defer, reopen, permanent delete
- [x] Batch operations: complete, cancel, defer, move, reopen, create
- [x] AI-managed priority (P1–P3) replaces computed urgency_score
- [x] Task dependencies stored in `task_dependencies` edge table; `depends_on` JSON is a read-time projection
- [x] Recurring tasks with auto-spawn on completion
- [x] Tags, priorities (1-3), duration estimates, actual time tracking
- [x] AI notes (assistant-only annotations)
- [x] FTS5 full-text search with BM25 ranking (prefix matching, phrase search, LIKE fallback)

### Calendar & Scheduling
- [x] Calendar events CRUD with monthly/weekly views
- [x] Calendar event types: event, birthday, anniversary, memorial
  - Meetings are ordinary calendar events with attendees, URLs, descriptions, and optional task links; they are not a separate `calendar_events.event_type` variant.
  - Task blocks live in focus schedules and task-event links; they are not a separate `calendar_events.event_type` variant.
- [x] Recurrence with EXDATE exception support
- [x] Recurring calendar scoped edit/delete workflows are backend-owned across Tauri and MCP, so "this occurrence" and "this and following" changes commit atomically instead of relying on frontend multi-IPC sequencing.
- [x] Calendar event create/update normalization is shared through `lorvex-workflow`, so Tauri and MCP enforce the same title/text hygiene, URL/color/timezone validation, date/time projection, recurrence BYMONTHDAY anchoring, and DST gap/ambiguity policy.
- [x] .ics subscription sync (HTTP fetch, VEVENT parse, background refresh)
- [x] Native calendar reading (Windows Appointments + Linux local calendar/ICS provider mirror, cross-device dedup, auto-sync, stale cleanup, today's past events included, local midnight calculation)
- [x] Task ↔ event linkage
- [x] Focus schedules with timeline UI
- [x] Drag-to-reschedule in calendar grid

### Habits & Reviews
- [x] Habit tracking with streaks, completion rates, daily check-in
- [x] Habit reminder policies with fire log
- [x] Daily reviews (mood, energy, wins, blockers, learnings, AI synthesis)
- [x] Weekly review with stalled lists and deferred task analysis

### Planning & Dashboard
- [x] AI-composed dashboard with configurable sections
- [x] Current focus with AI briefing
- [x] Today view with smart task grouping

### Editor & Notes
- [x] WYSIWYG markdown editor (Milkdown) for task notes
- [x] Headings, lists, checkboxes, bold/italic, code, links, blockquotes
- [x] `lorvex-image://` URL resolution in Milkdown editor
- [x] Image storage limits (50 images, 50 MB total, 5 MB per image)
- [x] Automatic orphan image GC on note save
- [x] Graceful placeholder for missing/unsynced images

### UI & Interaction
- [x] Command Palette (⌘K) with search, quick actions, scoped list commands
- [x] Quick Capture (⌘N) with list/date/priority options
- [x] Menu bar popover with inline quick-add
- [x] Sticky note floating windows
- [x] Eisenhower matrix, Kanban board, dependency graph views
- [x] Eisenhower/Kanban time horizon toggle (7d/14d/30d/60d/90d/All)
- [x] Keyboard shortcuts throughout
- [x] Sidebar with collapsible toolbox for less-used views
- [x] 3-state sidebar module visibility in Settings (Show/More/Hidden per module)
- [x] Task detail: single "More" collapsible for all secondary metadata, relations, and info
- [x] Consistent 2-line task card layout (truncated title + always-present metadata row)
- [x] Popover inline task expansion (click to expand with notes + actions)
- [x] Quick Capture collapsible options ("More options" toggle)
- [x] Focus mode timer redesign (text-2xl, visible shortcut hints, button-style minimize)
- [x] Dependency graph: show dependency names, hide-completed toggle
- [x] Mobile navigation: 5 missing views added
- [x] Weekly review date range display + throughput label

### Themes & Appearance
- [x] 12 theme options: Paper, Light, Dark, Ember, Midnight, Liquid Glass (dark+light), Mica (dark+light), Adwaita (dark+light), System (auto-detect)
- [x] Distinctive structural CSS per theme (corners, shadows, borders, blur, button styles)
- [x] Platform-native theme fidelity: Mica from WinUI 3 tokens, Adwaita from libadwaita SCSS, Liquid Glass from WWDC 2025 specs
- [x] Cross-window theme propagation
- [x] Platform-specific CSS (Windows Segoe UI, Linux system fonts, Android touch targets, tablet breakpoints)
- [x] Font scale setting (Settings → Appearance → Font Size slider)
- [x] Unified Toggle switch component across all Settings panels
- [x] Settings comprehensive design polish (20 files)
- [x] Typography refactor: 10px→12px baseline, section label modernization
- [x] RTL locale support (dir="rtl" on document)
- [x] Focus-visible accessibility rings on all inputs

### MCP Server Quality
- [x] Comprehensive schemars descriptions on all tool parameters
- [x] Server instructions primer for LLM consumers
- [x] Changelog error propagation in all primary write operations
- [x] UpdateList nullable field support (color/icon/description/ai_notes clearable to null)
- [x] Typed enums for annotation_type, frequency_type (compile-time safety)
- [x] FTS5 full-text search with BM25 ranking
- [x] CHECK constraint on tasks.status column
- [x] Consistent `updated_at` naming across all tables (current_focus.modified_at renamed)
- [x] Shared `lorvex-domain` Rust crate (pure domain logic: types, HLC, merge policy, validation, time, FTS, parsing)
- [x] urgency_score removed — AI-managed priority replaces computed formula (zero write-path cost)
- [x] Task dependencies moved to an edge table
- [x] focus_task_count preference removed — focus schedules naturally limit by available time
- [x] Guarded startup migrations (one-time flags for FTS, junction table, tags backfill)
- [x] `planned_date` column added — two-date model (due_date = deadline, planned_date = intended work date)
- [x] `deferred` status removed — defer is now an action that sets planned_date forward, keeps status open
- [x] `Patch<T>` is the canonical partial-update contract — three-state enum (`Unset` / `Clear` / `Set(v)`) used for every PATCH-style mutation across `lorvex-store`, `lorvex-cli`, `mcp-server`, `lorvex-workflow`, and the Tauri adapters
- [x] Cross-surface mutation pipeline runs through the `Mutation<T>` orchestrator in `lorvex-workflow` — every write site flows through pre-snapshot → apply → audit/outbox/local-change finalizer with HLC stamping centralized in one session, so MCP, CLI, and Tauri surfaces share one write skeleton
- [x] `lorvex-workflow` crate owns shared cross-surface workflow operations — the dependency graph reads `store → workflow → {mcp, app, cli, sync apply}`, so every surface enforces the same validation, status side-effects, changelog projection, and version stamping

### Data Management
- [x] Data cleanup UI (purge cancelled tasks, retention policies, clear logs)
- [x] Reset Preferences / Delete All Data (Danger Zone in settings)
- [x] Selective data export (backend supports entity-type filtering via `include` param)
- [x] Safe data import (ON CONFLICT DO UPDATE, no CASCADE triggers)
- [x] Tauri task input validation (title/body/priority/tag limits, parity with MCP)

### Sync & Data
- [x] File bridge sync (shared folder)
- [x] Export/import (both Tauri snapshot and MCP JSONL)
- [x] All entities wired through sync pipeline
- [x] Exponential backoff on sync failures
- [x] Atomic file bridge writes (temp file + rename, no partial files)

### Platform
- [x] macOS: Touch ID, dock badge, transparent overlays, IME support, tray icon
- [x] Cross-platform window management (macOS/Windows/Linux/mobile)
- [x] Notifications with quiet hours, morning briefing, weekly review prompts
- [x] Auto-updater, launch on login
- [x] Direct desktop release prep for Developer ID / Windows / Linux channels
- [x] Alpha release channel artifacts removed (consolidated to single production config)
- [x] Windows taskbar badge overlay (ITaskbarList3) — red circle icon + unread count text
- [x] Windows Jump List integration (ICustomDestinationList) — recent tasks in taskbar right-click menu
- [x] Windows Hello biometric lock (Windows Hello via `windows` crate WebAuthN/Credential API)

### CLI & Multi-Surface
- [x] Lorvex CLI: agent-first MCP runtime with shared DB, modular scriptable command surface
- [x] CLI planning parity: calendar CRUD/linking/exceptions, dated focus planning, daily review get/history/add/amend, task reminder set/add/remove/clear, task Trash move/restore/delete dry-run, and habit reminder policy list/upsert/delete
- [x] lorvex-runtime crate: shared DB locator, device identity, surface HLC runtime, local_change_seq, sync leases, MCP host authority
- [x] Multi-surface architecture: App + CLI coexistence with single MCP endpoint policy
- [x] CLI typed CliError enum (replaces 70+ Box<dyn Error> signatures)

### Quality & Testing
- [x] Sync retry/backoff: auto-sync failure handling with jitter
- [x] MCP server typed McpError migration (all 117 tools)
- [x] Tauri app typed AppError migration (all commands)
- [x] E2E UI tests with Playwright (inventory is source-derived; run `npx -w app playwright test --list` for the current test/spec count)

---

## In Progress

- **Continuous hardening loop**: the [GitHub issue tracker](https://github.com/boyugou/ai-native-todo/issues) is the authoritative, high-resolution list of active work (sync correctness, panic-safety, perf, a11y, forward-compat, observability). Items flow into Shipped as they close. Checklist items in this file are kept deliberately coarse — they represent whole feature areas, not individual bugs.

---

## Planned

### Near-term

- [ ] CLI packaging: Homebrew formula, Windows installer, Linux binary distribution
- [ ] Windows toast notification activation (INotificationActivationCallback COM class registration)
- [ ] Android BiometricPrompt

### Design & UX
- [x] Task detail panel restructuring (more notes space, less chrome) — overflow menu, promoted AI notes, quick date chips, dead code removal

### Future Exploration
- [ ] Free-form journal module
- [ ] Goals module
- [ ] Plugin system via MCP servers
- [ ] Native macOS 26 Liquid Glass (NSGlassEffectView)
- [ ] Module-level privacy policies
- [ ] Multi-agent identity and attribution

---

## How to Use This Roadmap

- Start from **In Progress** to see what's actively being worked on.
- **Shipped** is the complete feature inventory — check here before implementing something "new."
- **Planned** items have no priority ordering by version — pick based on dependency and impact.
- After shipping a feature, move it from Planned/In Progress to Shipped.
- Keep this file concise. Detailed specs belong in issues, not here.
