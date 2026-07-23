# Apple UX Polish — Working Log

Design-decision record for code-level product/visual/interaction polish across
the Apple platforms. Complements [`SURFACE_DESIGN.md`](../SURFACE_DESIGN.md) (the
per-platform *spec* — the intended end state) with the **analysis** and
**decisions + rationale** behind non-obvious choices, recorded because
pixel-level visual confirmation happens on-device, after the code lands. When a
decision here is later visually confirmed or revised, note it.

This file holds **rationale**, not a changelog — shipped work lives in git
history. The live, evidence-backed open backlog (with `file:line`) is
[`POLISH_BACKLOG.md`](POLISH_BACKLOG.md); as-built layout wireframes are in
[`wireframes/`](wireframes/INDEX.md).

## Priorities

1. **macOS + iOS** — the two primary surfaces; polish these first.
2. **iPadOS** — thoughtful, iPad-native design (see principles below). Do NOT
   port the macOS layout verbatim.
3. watchOS · visionOS · CarPlay · Widgets — after the above.

## iPad-native design principles (not "macOS on a touchscreen")

iPad differs from a Mac in ways the layout must honor — never blindly mirror the
desktop Mac shell:

- **Orientation is first-class.** iPad rotates between **portrait** and
  **landscape** at runtime. Portrait is much narrower: a Mac-style
  sidebar + content-list + detail (3 columns) is cramped in portrait and should
  collapse (e.g. sidebar as an overlay/`.automatic` column visibility, or a
  2-column list+detail) while landscape can show more columns. Verify both
  orientations; don't assume a single fixed column count.
- **Size class ≠ device.** Multitasking (Split View / Slide Over / Stage
  Manager) changes `horizontalSizeClass` to `.compact` at runtime even on a
  large iPad. The shell already switches tab-bar (compact) ↔ sidebar (regular)
  on `horizontalSizeClass` — good; keep every iPad layout driven by size class,
  not device idiom, so a half-screen iPad window degrades gracefully.
- **Dual input.** Touch targets stay ≥44pt AND pointer affordances (hover
  highlights, `.pointerStyle`, context menus) and hardware-keyboard shortcuts
  all coexist. Don't drop touch ergonomics to gain Mac-like density.
- **Canvas, not stretch.** Use the width for genuinely useful secondary content
  (list+detail, inspectors), not a stretched single column.
- **Drag-and-drop + multi-select** are expected iPad idioms for a task app.

## Decisions log

### 2026-06-02 — localization expansion source resolution
- **The Apple localization expansion pipeline cannot assume one checkout
  layout.** `localization_expand.py` now resolves Tauri locale catalogs through
  `LORVEX_TAURI_LOCALES`, the intended monorepo path, or the sibling
  `lorvex_original` checkout used by this workspace. Seed still only reuses
  exact, unambiguous English matches and excludes `%` placeholder strings.
- **InfoPlist strings are part of the same batch contract.** The expansion
  script now emits and applies missing `InfoPlist.strings` entries per shipping
  target, so usage descriptions and quick-action titles travel with the same
  translation artifact as `.xcstrings`.
- **Translator handoff should be one artifact per language batch.**
  `translation-pack` now emits catalog gaps, occurrence metadata, InfoPlist
  gaps, and output-format instructions together. This makes each locale batch
  reproducible: seed, generate pack, apply the translated response with
  `apply-pack`, then run the localization verifier.
- **Validate the whole translation response before writing either side.**
  `apply-pack` catches unknown languages/targets, empty strings, missing
  metadata-declared translations, and printf placeholder drift across both
  `.xcstrings` and InfoPlist payloads before it mutates either surface.

### 2026-06-02 — iPad Lists batch deletion
- **Lists can batch-delete only when the selected lists are truly empty.** The
  core already rejects deleting any list with assigned tasks, so the iPad batch
  bar exposes the destructive action only when every selected list has
  `totalCount == 0`. The store still routes through `core.deleteList` for every
  ID, then refreshes list catalog state and clears stale selection/detail routes.

### 2026-06-02 — iPad Habit batch reset/delete
- **Habit multi-select now covers the full daily action set.** Batch complete
  still targets incomplete selected habits; batch reset only targets selected
  habits with completions today; batch delete removes the selected habits and
  exits selection mode. Reset/delete use the existing single-habit core methods
  in sequence so sync/changelog behavior remains identical to row actions.

### 2026-06-02 — iPad Memory AI-only batch deletion
- **Memory multi-select preserves the human-memory boundary.** The iPad Memory
  catalog now supports selection mode, but the destructive batch action only
  enables when every selected entry is AI-owned. The mobile store repeats that
  guard before calling `core.deleteMemory`, so human-authored memory remains
  protected even if UI state is stale or constructed manually.

### 2026-05-31 — mobile loading + empty-state polish (iOS/iPad)
- **Root Today loading overlay gated to initial load.** A full-view blocking
  spinner on *every* refresh conflicts with the Today view's own native
  `.refreshable` pull indicator. Gated to
  `store.isLoading && store.snapshot.today == .empty` so the blocking spinner
  shows only on first load; refreshes animate the native indicator. Mirrors the
  `MobileStoreTasksView` pattern (`isLoading && page.tasks.isEmpty`).
- **Today "Today" section hidden when empty.** A bare `ForEach(openTasks)` with
  no empty branch rendered a header with nothing under it (reads as a layout
  glitch). The "Next" section's empty state already covers the no-tasks case, so
  the redundant section is hidden when `openTasks` is empty.

### 2026-06-01 — macOS token consistency (from a macOS design audit)
- Sheet/pane titles and the Focus workspace title were hardcoded to fonts
  byte-identical to `Typography.sectionHeader` / `Typography.screenTitle`; routed
  through the tokens (zero visual change) so a scale retune reaches them.

### 2026-06-01 — correctness invariants (from a latent-bug audit)
These encode non-obvious invariants worth remembering, not just the fix:
- **Permanent-delete tombstones must be atomic with the delete.** The pre-delete
  payload snapshot reader *throws* (it is non-optional); a `try?` + `if let`
  guard silently nil'd it on a transient read failure and deleted the row with NO
  tombstone, resurrecting it on peers. The contract: read via
  `do/catch EnqueueError.entityNotFound` → nil (benign-absent), let other errors
  propagate so the `withWrite` tx rolls back delete + tombstone together.
- **One-shot flags must be set only after the read they gate succeeds.**
  `seedIfNeeded` flagged before its `MAX(version)` read, losing the HLC
  monotonicity backstop across a transient failure; flag only after success.
- **Don't swallow user-meaningful best-effort failures.** EventKit access-mode
  `setPreference` failure (was `try?`) is surfaced through the calendar import
  report.

### 2026-06-01 — MCP read-tool prompt-injection fencing scope (Rule 6)
A read tool's catalog description must not advertise "fenced against prompt
injection" unless the handler actually applies `SecurityFencing.fenceValue`.
`search_tasks` / `read_memory` advertised it without applying it, and
`get_deferred_tasks` returned the same task shape `list_tasks` fences; all three
now fence. The remaining calendar / list / focus / habit /
review reads are a deliberate per-tool follow-up (fencing changes the output
every MCP client sees, so it is scoped per tool, not applied blanket).

### 2026-06-02 — macOS focus session in-flight gating
macOS focus session starts and controls now share the mobile-style
`isMutatingFocusSession` gate in `AppStore`. The guard lives in the store so
menu shortcuts, Today quick-start, and the Focus workspace
all reject duplicate submissions while one async mutation is active; buttons also
disable off the same state so the rejected click has visible feedback.

### 2026-06-02 — mobile list-detail first-frame loading state
Mobile list detail now resolves its content through an explicit state machine:
a matching `selectedListDetail` renders the list, missing/stale detail renders a
loading row while `.task(id:)` catches up, and the unavailable empty state is
reserved for a failed load. This avoids flashing "List Not Loaded" on deep-link
or sidebar navigation before the async detail load has started.

### 2026-06-02 — mobile Today avoids duplicating the Next task
The Today screen keeps `MobileHomeSnapshot.openTasks` unchanged for shared model
semantics, but its Today section now filters out `snapshot.nextTask`. The top
card remains the single action surface for the next task, while the lower Today
section starts at the next remaining open task instead of repeating the same row.

### 2026-06-02 — iPhone Today persistent capture affordance
Today now exposes a compact-width toolbar Capture button that jumps to the
Capture tab. The existing bottom ornament remains for visionOS, but iPhone no
longer depends on that no-op modifier or an empty-state-only path for quick
capture, preserving the AI-first input flow from the primary screen.

### 2026-06-02 — Tauri sync cadence/controller logic coverage
Tauri now has unit coverage for the renderer sync cadence policy and calendar
subscription sync controller. The cadence tests lock quick retry/offline
priority, desktop/mobile platform floors, deterministic error-backoff jitter,
and Android resume resync boundaries; the controller tests cover offline skips,
minimum-gap throttling, in-flight rejection, and error reporting.

### 2026-06-02 — Tauri settings mutation in-flight guards
Calendar subscription toggle/color controls now expose and honor their mutation
pending states, with hook-level duplicate-submit guards and disabled row
controls while a write is in flight. Habit reminder add/toggle/delete follows
the same pattern for upsert/delete mutations so reminder rows no longer accept
stacked writes before the previous IPC call settles.

### 2026-06-02 — Tauri diagnostic AI-changelog actor filtering
Diagnostic bundle export and the diagnostics device dropdown now reuse the
shared assistant-actor SQL predicate that already gates the in-app Activity
Log. Human/user/system/manual changelog rows stay out of assistant-facing
diagnostic exports and no longer contribute source-device IDs to the dropdown;
diagnostics tests cover both read paths.

### 2026-06-02 — iPad Tasks multi-select batch actions
The mobile Tasks workspace now exposes an iPad-only selection mode that keeps
the existing split-detail single selection intact while adding explicit row
checks and a bottom batch action bar. Selected open tasks can be completed or
deferred together; selected completed/cancelled tasks can be reopened together.
MobileStore gained batch complete/defer/reopen wrappers using the existing
unscoped task-mutation guard so duplicate batch submissions are rejected while
the first IPC/core call is in flight.

### 2026-06-02 — iPad Habits batch complete selection
The mobile Habits workspace now mirrors the iPad selection-mode affordance from
Tasks for its highest-frequency batch action: completing selected incomplete
habits for today. MobileStore gained a stable-order batch habit completion
wrapper over the core batch API, and the selection bar disables itself while a
habit mutation is in flight.

### 2026-07-10 — polish backlog pruning (fixed items)
Consolidated `FIXED` findings from `POLISH_BACKLOG.md` after landing, per that
file's own move-and-delete protocol:
- **Security fencing rollout.** Extended `SecurityFencing.fenceValue` beyond the
  tasks/memory scope above to calendar timeline/search/link, list/list-health,
  tag, current-focus/saved-schedule, habit/habit-reminder, and daily/weekly
  review reads, adding fenced fields (`cue`, `note`, `rationale`, `wins`,
  `blockers`, `learnings`, `ai_synthesis`, `quote`, `comment`, `location`,
  `person_name`, `habit_name`) and string arrays such as `tags`.
- **macOS batch reopen now animates.** Batch "Reopen" wraps its snapshot
  assignment in the same `withAnimation(.snappy(duration: 0.18))` the sibling
  complete/defer/cancel batch actions already use, so reopened rows animate
  between sections like their siblings instead of snapping.
- **macOS shell dropped its always-present third column.** The shell is
  sidebar + workspace with the task detail in a trailing `.inspector` shown
  only while a task is selected; non-task workspaces no longer render an idle
  "No Task Selected" pane.
- **macOS batch cancel respects recurring scope.** Batch cancel captures
  recurring tasks in a selection and shows the same occurrence-vs-series scope
  dialog as single-task cancel before mutating; the chosen scope applies only
  to the recurring IDs in the batch.
- **Calendar off-screen-pill helpers renamed to match behavior.** The helpers
  that scroll to the nearest hidden event were named
  `earliestAboveMinute`/`latestBelowMinute` but implemented the opposite
  (`.max`/`.min` for *nearest*); renamed to `nearestAbove/BelowMinute` with
  corrected docstrings. No behavior change.
- **Mobile task mutations no longer share one global lock.**
  `MobileStore.isMutatingTask` tracks in-flight task IDs instead of one global
  flag, so a mutation on one row no longer blocks a tap on a different row.
- **iPad batch actions round out to reopen.** The iPad Tasks/Habits/Lists/
  Memory selection-mode batch actions above now also cover reopen; iPad
  drag-drop and compact-row context menus were verified not to be defects
  (drop targets exist where expected; the bare `MobileTaskRow` is always
  wrapped by the context-menu-carrying `MobileActionTaskRow`).
- **Tauri/Apple recurrence interval caps converged.** Both now share
  `RECURRENCE_INTERVAL_*` constants, covered by calendar/task tests.

Also re-verified clean: an adversarial pass re-checked every functional
`DONE:` claim previously logged in this file (macOS interaction/batch/table;
iOS/iPad loading-gates/focus/adaptive-split/drag-drop; the `update_task`
field-gating, HLC seed coverage, and tombstone-atomicity claims) against
current code — no stale, partial, or regressed findings. A Tauri parity pass
found no React Query key/scope omissions, en/zh i18n strict parity (2091
keys), and no Tauri dead code, unused locale keys, or doc staleness.

## Wireframes & analysis method

For each surface, an ASCII wireframe of the **as-built** layout plus the data
each region shows and notes on the **ideal** interaction — articulating the
layout in text documents the current design and gives a spatial frame for
reasoning about improvements without a running device. The wireframes live in
[`wireframes/`](wireframes/INDEX.md), each region citing the `file:line` that
renders it (a transcription of the hierarchy, not an invention). Three surfaces
are captured (macOS shell, macOS calendar week grid, iPhone tab shell); the
remaining surfaces are listed in the index. These are working analysis artifacts
(my-app-only, no external references).

## Tauri scope note (2026-06-01)

The Tauri build targets **macOS only** for Apple, serving primarily as a
functional parity reference for the Swift app. Other Apple devices are
Swift-only. Tauri's iOS/iPad code may stay as-is for now (low-priority cleanup
only if it causes problems). Swift is the priority for the Apple ecosystem.

## Open backlog

The evidence-backed, code-level open items (with `file:line`) are tracked in
[`POLISH_BACKLOG.md`](POLISH_BACKLOG.md). Design-level items that need on-device
visual judgment rather than a code pinpoint:

- **#103 density retune (macOS + iOS).** Whether dense secondary rows should
  upsize from `tertiaryText` (.caption) toward `secondaryText` (.body) per the
  "calmer/larger" philosophy — the token tier is already centralized; the call
  needs an on-device read.
- **Dynamic Type for fixed-point fonts.** A few fixed-point sites remain (macOS
  calendar block 9pt, macOS onboarding ~56pt hero glyph); give them semantic
  treatment. A long tail of raw `.font(...)` sites still bypass `Typography`
  tokens (low priority, screen-by-screen).
- **Per-platform design audits not yet run:** watchOS, visionOS, CarPlay,
  Widgets (need on-device).
- **Calendar MCP metadata parity (cross-platform).** Create/update pass
  recurrence/timezone/url/color/event_type/person_name/attendees; remaining
  larger parity: scoped recurring edits/deletes, batch-create dry runs.

## Handoff notes

### Hotspot line-cap
`script/verify_hotspots.py` enforces a 399-line cap; the gate passes clean.

### Dead-code orphan scan
A cross-target verification of the previously-listed orphan candidates found
nothing safely removable: some named symbols no longer exist (stale list), and
the rest are `public` exported parity ports in `core/` (mirrors of the Rust
oracle, e.g. `FtsRepo` SQL, documented in `core/PORT_STATUS.md`) — zero static
callers but intentionally retained, not dead.
