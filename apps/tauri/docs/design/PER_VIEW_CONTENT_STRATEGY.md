# Per-View Content Strategy

Issue: #97  
Status: Canonical design contract (implementation-ready)

## Intent

Define deterministic default content strategy per core surface so each view consistently answers one primary user question, while preserving AI-native simplicity and trust constraints.

## Scope

In scope surfaces:
- `today`
- `list`
- `upcoming`
- `all`
- `someday`
- `review` (weekly review)
- `daily_review` (daily review history)
- `calendar`
- `changelog`
- `memory`
- `eisenhower`
- `settings`

Out of scope in this artifact:
- Task detail panel field-level interaction contract
- Command palette interaction model
- Backend schema or MCP tool contract changes

## Content Layer Model

Each surface must map content into exactly three layers:

1. Primary: the minimum actionable information required to use the surface correctly.
2. Secondary: contextual information that improves judgment but is not required for first action.
3. Hidden/optional: advanced or noisy information shown only via explicit reveal/interaction.

## Global Priority And Ordering Rules

### G1. State precedence

Apply this precedence in every surface:

1. Cold load (no usable cached data): show loading skeleton/spinner, not empty-state copy.
2. Data-ready: show content.
3. Data-ready but no primary content: show surface-specific empty state.
4. Error:
   - If no usable data is available, show blocking error + retry.
   - If partial data is available, keep rendering available sections and show section-level error treatment.

### G2. Section priority

For each surface, section ordering must prioritize:

1. Immediate decisions or commitments.
2. Time-critical risk (overdue / due soon).
3. Context and guidance.
4. Historical/reference material.

### G3. Deterministic item ordering

Task ordering defaults:

1. Explicit manual order (`current_focus_items` position) wins over computed ordering.
2. Otherwise, time buckets by proximity of commitment:
   - overdue (due_date < today)
   - today pool (planned_date <= today OR due_date <= today)
   - future planned/dated
   - unplanned/undated
3. Inside a bucket:
   - `due_time` ascending (when present)
   - `priority` ascending (1 is highest)
   - stable title/id fallback

Event ordering defaults:

1. all-day events first
2. timed events by `start_time` ascending
3. stable title/id fallback

Changelog ordering defaults:

1. reverse chronological (`timestamp DESC`)

### G4. Progressive disclosure and density control

1. One surface, one primary question. Avoid mixing unrelated workflows in default state.
2. Show compact rows first; reveal metadata on select/open/detail.
3. Keep default row density low in decision-heavy views (`today`).
4. Allow denser informational layouts in browsing/audit views (`all`, `changelog`, `calendar`).

### G5. Localization and accessibility baseline

1. Section headings and empty/error copy must map to i18n keys (no hard-coded user-facing strings in implementation).
2. Empty/loading/error affordances must be keyboard-reachable.
3. Never encode critical meaning by color alone.
4. Keep deterministic ordering independent of locale-specific formatted text.

### G6. Global never-by-default guardrails

1. Never show `cancelled` tasks by default in primary execution surfaces.
2. Never auto-expand verbose metadata (`raw_input`, long `ai_notes`, internal IDs) in high-frequency views.
3. Never duplicate the same task in multiple default sections of the same surface.
4. Never block an entire surface for a non-critical secondary query failure.

## Per-Surface Default Strategy

### 1) Today (`view.type = 'today'`)

Primary (in order):
1. Date header + high-signal pills.
2. Today's Focus tasks (if `current_focus` exists — the ordered subset within Today).
3. Remaining today tasks: `planned_date <= today` OR (`planned_date IS NULL` AND `due_date <= today`), deduped against Today's Focus.
4. Overdue alert (deduped against Today's Focus).

Secondary:
- AI briefing
- Focus schedule timeline
- Recently completed
- Someday peek
- Stats summary
- Today's calendar events

Hidden/optional:
- Full changelog/history
- Completed/cancelled backlog

Ordering:
- Today's Focus uses `current_focus_items` position order.
- Remaining today rows: `due_time` asc, then priority asc, due date asc.
- Overdue rows: oldest due first, with Today's Focus dedupe.

State behavior:
- Loading: keep shell/header visible; use in-content loading treatment.
- Empty: explicit all-clear message when no actionable sections.
- Error: section-level degradation for secondary failures; blocking retry only when core overview/plan data unavailable.

Never by default:
- Same task shown in both Today's Focus and Overdue sections.

### 2) Inbox [CUT]

> **Note:** The Inbox UI/review surface was removed; the conversation with the AI assistant is now the review layer. Tasks are created directly as `open` status with proper list assignment. This surface is no longer part of the active view set. The schema-seeded `inbox` default list remains only as a bootstrap/default-routing artifact.

### 3) List (`view.type = 'list'`)

Primary (in order):
1. List identity (name/icon/description/count).
2. Open tasks in actionable order.
3. Inline add row.

Secondary:
- Recently completed section.
- Move-up/move-down reorder controls.

Hidden/optional:
- Cancelled tasks.
- Deep metadata (raw input, long reasoning blocks).

Ordering:
- Task ordering: priority asc, due date asc.

State behavior:
- Loading: blocking list loading state.
- Empty: "list is clear" with immediate add affordance.
- Error: blocking error panel with retry and safe back navigation.

Never by default:
- Cancelled tasks treated as list execution work.

### 4) Upcoming (`view.type = 'upcoming'`)

Primary (in order):
1. Next 7-day tasks grouped by local date.

Secondary:
- Per-day count and estimated load summary.

Hidden/optional:
- Completed/cancelled tasks.

Ordering:
- Date ascending, then priority asc, due time asc inside each date group.

State behavior:
- Loading: centered loading.
- Empty: clear no-upcoming guidance.
- Error: blocking retry state if date-range query fails.

Never by default:
- Undated tasks mixed into upcoming commitments.

### 5) All Tasks (`view.type = 'all'`)

Primary (in order):
1. Search + filter controls.
2. Status-grouped task sections (`open`, `someday`).

Secondary:
- Sort mode controls.
- Bulk selection and bulk actions.

Hidden/optional:
- `completed` and `cancelled` groups behind explicit toggles.

Ordering:
- By selected sort mode within each status group.
- Group order is stable and deterministic.

State behavior:
- Loading: centered loading.
- Empty: distinguish "no tasks" vs "no search matches".
- Error: blocking error + retry.

Never by default:
- Completed/cancelled sections without opt-in.

### 6) Someday (`view.type = 'someday'`)

Primary:
1. Someday/maybe task list.

Secondary:
- Count and reminder copy.

Hidden/optional:
- Execution-heavy controls.

Ordering:
- Newest first (`created_at DESC`).

State behavior:
- Loading: centered loading.
- Empty: no-someday message + guidance.
- Error: blocking retry state if query fails.

Never by default:
- Someday tasks in today/upcoming commitment lanes.

### 7) Weekly Review (`view.type = 'review'`)

Primary (in order):
1. Frequently deferred tasks (intervention actions).
2. Stalled lists (review/open actions).
3. Overdue summary signal.

Secondary:
- Weekly completion and creation stats.
- Someday audit candidates.

Hidden/optional:
- Full raw changelog dump.

Ordering:
- Highest intervention priority first (defer count / staleness / overdue risk).

State behavior:
- Loading: blocking loading state.
- Empty: explicit "nothing to review" state.
- Error: blocking retry state for weekly review query failure.

Never by default:
- Completed-history noise before active intervention items.

### 8) Daily Review History (`view.type = 'daily_review'`)

Primary:
1. Review entries in reverse chronological order.

Secondary:
- Structured fields (wins/blockers/learnings/habits).
- AI synthesis block.

Hidden/optional:
- Linked task technical IDs (if shown, keep compact/truncated).

Ordering:
- Newest review date first.

State behavior:
- Loading: skeleton or neutral hold state.
- Empty: daily_reviewing starter message.
- Error: blocking retry state for review query failure.

Never by default:
- Large diagnostic payloads.

### 9) Calendar (`view.type = 'calendar'`)

Primary (in order):
1. Month/week calendar grid.
2. Selected-day panel (events + open tasks).

Secondary:
- Completed count indicators.
- Event create/edit controls.

Hidden/optional:
- Task detail panel until explicit selection.

Ordering:
- Events: all-day first, then start-time asc.
- Tasks: due-time asc, then priority asc, due date asc.

State behavior:
- Loading: blocking loading for date-range fetch.
- Empty: date-level "no items" treatment in day panel.
- Error: blocking error + retry for tasks/events range fetch failure.

Never by default:
- Cancelled tasks/events in active calendar lanes.

### 10) Changelog (`view.type = 'changelog'`)

Primary:
1. AI-initiated activity timeline.

Secondary:
- Feedback utilities (copy/export/clear).

Hidden/optional:
- Raw before/after payloads.
- Human-initiated internal activity unless explicitly requested.

Ordering:
- Reverse chronological timeline.

State behavior:
- Loading: centered loading.
- Empty: no-activity state.
- Error: blocking retry on timeline fetch failure; feedback-tool failures are non-blocking.

Never by default:
- Showing feedback-tool errors as fatal for timeline rendering.

### 11) Memory (`view.type = 'memory'`)

Primary:
1. Lock gate (when enabled).
2. Memory card list once unlocked.

Secondary:
- Relative update timestamps.

Hidden/optional:
- Memory content while locked.

Ordering:
- Stable deterministic key order (or explicit updated-time order if changed intentionally; do not mix).

State behavior:
- Loading: centered loading after unlock.
- Empty: no-memory state.
- Error: auth failures stay local to lock panel; memory fetch failures show retry state.

Never by default:
- Revealing memory content before successful unlock when lock is enabled.

### 12) Eisenhower (`view.type = 'eisenhower'`)

Primary:
1. Four quadrants with active tasks only.

Secondary:
- Quadrant hints and counts.

Hidden/optional:
- Completed/cancelled tasks.

Ordering:
- Priority asc, due date asc, then created order fallback within each quadrant.

State behavior:
- Loading: centered loading.
- Empty: per-quadrant empty placeholders.
- Error: blocking retry if source task query fails.

Never by default:
- Mixing archived/completed tasks into active quadrants.

### 13) Settings (`view.type = 'settings'`)

Primary (in order):
1. High-frequency user controls (theme/language/sidebar modules/behavioral prefs).
2. Critical reliability controls (sync/status paths).

Secondary:
- Advanced toggles and diagnostics.

Hidden/optional:
- Dangerous/destructive actions behind explicit confirmation.

Ordering:
- Ownership and frequency first, diagnostics later.

State behavior:
- Loading: section-level placeholders for async preference loads.
- Empty: not applicable.
- Error: per-control inline failure feedback; avoid blocking the entire settings surface.

Never by default:
- Raw internal config blobs or filesystem internals.

## Default Never-Show List (Cross-Surface)

Unless explicitly requested by user action, do not show these by default:

1. Cancelled tasks in execution views.
2. Duplicate task cards in one surface.
3. Full raw metadata payloads (JSON blobs, DB IDs, sync internals).
4. Destructive controls without confirmation/arming.
5. Memory content while lock is active.

## Acceptance Checklist

### Contract completeness

- [ ] Every in-scope surface documents primary/secondary/hidden content.
- [ ] Every in-scope surface has explicit loading/empty/error behavior.
- [ ] Every in-scope surface defines deterministic ordering.
- [ ] Every in-scope surface has a "never by default" list.

### Behavioral consistency

- [ ] Only `open` tasks appear as commitments in Today/Upcoming/Calendar defaults.
- [ ] Completed/cancelled visibility follows opt-in rules.
- [ ] Same task ID is not rendered twice in one default surface.
- [ ] Partial query failures do not blank otherwise-usable screens.

### Accessibility and localization

- [ ] State copy uses i18n keys.
- [ ] Loading/error/empty affordances are keyboard reachable.
- [ ] Ordering logic does not depend on localized display strings.

### Delivery readiness

- [ ] The strategy can be mapped one-to-one to component-level acceptance tests.
- [ ] Any intentional deviation from this contract is folded into canonical docs, linked issue comments, or manual-gate artifacts before implementation merge.

## Explicit Non-Goals

1. No redesign of visual brand/style tokens in this issue.
2. No new data model, migration, or MCP tool schema change.
3. No autonomous AI policy changes beyond what is needed to honor display contracts.
4. No expansion of feature scope beyond content hierarchy/state behavior.
5. No replacement of existing navigation model.
