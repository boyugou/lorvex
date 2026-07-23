# Data Model
The data model is designed for an AI-native planning system with a first-class standalone app. Every field exists because it makes assistant operations more intelligent, sync semantics more stable, or human review/execution more meaningful. There are no "UI-driven" fields that only exist because a form needed to display something.

---

## Core Principle: Two Layers

**Deep layer (AI's domain):** Rich, context-heavy, relationship-aware data. AI reads and writes this layer freely via MCP.

**Surface layer (Human's view):** The UI presents a curated, simplified view of the deep layer. Humans see title, due date, priority indicator, list. The complexity is always there if they open the detail panel — but it doesn't intrude.

---

## Schema

### tasks

Exact DDL lives in [`lorvex-store/src/schema/001_schema.sql`](../../lorvex-store/src/schema/001_schema.sql). The excerpt below mirrors the current task row shape but is not a second schema source.

```sql
CREATE TABLE tasks (
  -- Identity
  id          TEXT PRIMARY KEY,           -- UUIDv7
  title       TEXT NOT NULL,              -- The task, in plain language

  -- Content
  body        TEXT,                       -- Markdown. Notes, details, context
  raw_input   TEXT,                       -- Original NL string if AI-created ("remind me to call Marcus about project")
  ai_notes    TEXT,                       -- AI's observations, analysis, suggestions. Not human-editable in UI.
                                          -- Example: "This blocks 3 other tasks. Deadline risk: high."

  -- Status
  status      TEXT NOT NULL DEFAULT 'open',
              -- Values: open | completed | cancelled | someday.
              -- Deferral is an action (defer_task) that pushes planned_date forward;
              -- defer_count tracks count. Status stays 'open' across deferrals.
              -- 'someday' = GTD Someday/Maybe. Low priority backlog. AI assistant can surface when free time appears.

  -- Organization
  list_id     TEXT NOT NULL DEFAULT 'inbox' REFERENCES lists(id) ON DELETE RESTRICT,
              -- Normal task creation must resolve to a real list.
              -- Public list deletion APIs are blocked while assigned tasks
              -- still reference the list.
              -- Canonical steady state: ordinary tasks always belong to a real list.
              -- The lower-level `trg_lists_before_delete` trigger is a
              -- sync/direct-SQL safety net, not the public API contract.
  -- tags: stored in task_tags join table, derived at read time as JSON array

  -- Priority
  priority    INTEGER,                    -- 1|2|3 importance band. Importance-first, not urgency-first. AI-set, human can override.
  priority_effective INTEGER GENERATED ALWAYS AS (COALESCE(priority, 4)) VIRTUAL,
                                          -- Canonical sort key. Wraps priority so NULL sorts AFTER 3 (4=P-unset).
                                          -- Use this in every ORDER BY — `priority ASC` alone puts NULLs first on SQLite.
                                          -- Indexed via idx_tasks_status_priority_effective_due in the consolidated `001_schema.sql` baseline.

  -- Time (two-date model: due_date = external deadline, planned_date = intended work date)
  due_date    TEXT,                       -- ISO 8601 date (YYYY-MM-DD). External deadline.
  planned_date TEXT,                      -- ISO 8601 date (YYYY-MM-DD). When the user/AI plans to work on this.
                                          -- Set by defer_task (pushes forward) or direct update.
                                          -- Today view shows tasks where planned_date <= today OR
                                          -- (planned_date IS NULL AND due_date <= today).
  due_time    TEXT,                       -- HH:MM (24h), optional
  estimated_minutes INTEGER,               -- Optional rough duration estimate. Strongly improves scheduling and review quality when present.
  -- Reminders are stored in the `task_reminders` table, not on the task row.

  -- Recurrence
  recurrence  TEXT,                       -- RRULE-aligned JSON: {"FREQ": "WEEKLY", "INTERVAL": 1, "BYDAY": ["MO", "WE"], "UNTIL": "2026-12-31"}
  recurrence_exceptions TEXT,              -- JSON array of skipped canonical occurrence dates.
                                          -- null = no recurrence
                                          -- FREQ: "DAILY" | "WEEKLY" | "MONTHLY" | "YEARLY"
                                          -- INTERVAL: every N periods (default 1)
                                          -- BYDAY: weekday codes for weekly recurrence (e.g. ["MO","WE","FR"]).
                                          --        For MONTHLY/YEARLY, weekdays must carry an ordinal prefix
                                          --        (e.g. ["1MO","-1FR"]) or be paired with BYSETPOS.
                                          -- BYMONTHDAY: array of days-of-month for monthly/yearly recurrence
                                          --             (±1..31, negative counts from month end; e.g. [1, 15], [-1])
                                          -- BYMONTH: month-of-year filters for weekly/monthly/yearly recurrence (e.g. [2, 8])
                                          -- BYSETPOS: select N-th occurrence within the BY* set for monthly/yearly recurrence (e.g. [1], [-1])
                                          -- WKST: week start day code ("MO"…"SU"), default "MO"
                                          -- COUNT: cap series length (mutually exclusive with UNTIL on the
                                          --        calendar surface; the canonical normalizer keeps either).
                                          -- UNTIL: YYYY-MM-DD date, optional end date
  spawned_from TEXT,                       -- Parent task ID for recurring successors
  recurrence_group_id TEXT,                -- Shared UUID linking all instances in a recurrence series
  recurrence_instance_key TEXT,            -- Unique key for deduplication across recurring instances
  canonical_occurrence_date TEXT,          -- Stable RRULE cadence anchor (independent of due_date)

  -- Dependencies: stored in task_dependencies edge table, derived at read time as JSON array
  -- Reverse edges (what this task blocks) also derived at read time.

  -- Sync version
  version       TEXT NOT NULL,            -- HLC timestamp for sync (all synced tables carry this)

  -- Timestamps
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  completed_at  TEXT,
  last_deferred_at   TEXT,                     -- Last time this task was deferred
  last_defer_reason  TEXT,                     -- Reason given for the most recent deferral
  defer_count   INTEGER NOT NULL DEFAULT 0,    -- How many times deferred. Tracked for AI prioritization decisions.
  archived_at   TEXT,                          -- Soft-delete/trash timestamp. Live reads filter archived_at IS NULL.
  CHECK (priority IS NULL OR (priority >= 1 AND priority <= 3)),
  CHECK (status IN ('open', 'completed', 'cancelled', 'someday')),
  CHECK (recurrence IS NULL OR (
      due_date IS NOT NULL
      AND recurrence_group_id IS NOT NULL
      AND canonical_occurrence_date IS NOT NULL
  ))
) STRICT;
```

### lists

```sql
CREATE TABLE lists (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  color       TEXT,                       -- Hex color, e.g. "#FF6B6B"
  icon        TEXT,                       -- Emoji or SF Symbol name
  description TEXT,

  -- AI metadata
  ai_notes    TEXT,                       -- AI-only scope/profile notes for this list. Not shown by default in list UI.

  -- Sync version
  version     TEXT NOT NULL,              -- HLC timestamp for sync

  -- Timestamps
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
) STRICT;
```

#### List deletion semantics

Public list deletion APIs are blocked until assigned tasks are moved or
permanently deleted. The MCP `delete_list` path checks the assigned task
count before issuing the delete and returns a validation error if any
tasks still point at the list.

The schema-level `trg_lists_before_delete` trigger is a lower-level
sync/direct-SQL safety net for writes that bypass those APIs. It
re-homes non-inbox list deletes to `inbox` by updating surviving tasks
before the delete reaches the foreign-key constraint, and it blocks
inbox deletion while live tasks exist because `inbox` is the canonical
fallback target. This trigger keeps malformed or out-of-order sync
envelopes from wedging apply on a raw FK restriction; it does not relax
the public API rule that normal list deletes must be task-free first.

### ai_changelog

The audit trail. Every AI operation writes here. This is the trust layer — humans can always see what AI assistant has done.

```sql
CREATE TABLE ai_changelog (
  id               TEXT PRIMARY KEY,
  timestamp        TEXT NOT NULL,

  -- What happened
  operation        TEXT NOT NULL,
  -- Open vocabulary: create/update/complete/delete/defer/batch_*,
  -- preview tools, undo, import, and future MCP operations.

  entity_type      TEXT NOT NULL,         -- task | list | focus_schedule | current_focus | etc.
  entity_id        TEXT,                  -- primary affected entity (null for batch)
  entity_ids       TEXT,                  -- JSON array, used for batch operations

  -- Human-readable description (critical — this is what humans read)
  summary          TEXT NOT NULL,
  -- Example: "Created task 'Call dentist' in Health list, due Friday"
  -- Example: "Moved 5 tasks from Work list to High priority based on Friday deadline"
  -- Example: "Marked 'Review manuscript' as deferred (3rd time)"

  -- Context
  initiated_by     TEXT NOT NULL DEFAULT 'ai', -- human/system/user/manual | AI identity
  mcp_tool         TEXT,                  -- Which MCP tool was called, if applicable
  source_device_id TEXT,                  -- Device that originated the changelog entry

  -- Audit snapshots for state transitions. Serialized JSON objects;
  -- NULL when a transition has no before/after side, for legacy rows,
  -- or when the writer intentionally did not capture snapshots.
  before_json      TEXT,
  after_json       TEXT,

  -- Serialized MCP undo token JSON for destructive/bulk writes that
  -- support revert. The token carries its own expires_at value.
  undo_token       TEXT,

  -- 1 for dry-run/preview audit rows; 0 for canonical writes.
  is_preview       INTEGER NOT NULL DEFAULT 0
) STRICT;
```

The live schema owns the exact CHECK constraints and field comments in
`lorvex-store/src/schema/001_schema.sql`. This section mirrors the current
column contract and semantics, not every DDL detail, so it stays useful without
becoming a second migration source.

### current_focus (Today's Focus)

AI assistant's curated plan for the day. This powers the "Today's Focus" section in Today view — the ordered subset of today's tasks that the AI recommends working on.

```sql
CREATE TABLE current_focus (
  date        TEXT PRIMARY KEY,           -- YYYY-MM-DD
  briefing    TEXT,                       -- AI's contextual note for the day
  timezone    TEXT,                       -- IANA timezone when plan was created
  version     TEXT NOT NULL,              -- HLC timestamp for sync
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
) STRICT;

-- Ordered task items for each day's focus plan (parent-owned materialization).
-- task_id is a soft reference — no FK constraint, because the referenced task
-- may not exist locally yet during sync apply.
CREATE TABLE current_focus_items (
  date        TEXT NOT NULL REFERENCES current_focus(date) ON DELETE CASCADE,
  position    INTEGER NOT NULL,           -- 0-based display order
  task_id     TEXT NOT NULL,
  PRIMARY KEY (date, position)
) STRICT;
```

Why a separate table (not a boolean on tasks):
- Preserves order (which task is #1 matters)
- Supports the briefing note (AI assistant's daily message to the user)
- Date-specific (tomorrow's plan differs from today's)
- Historical (you can look at past days)
- Doesn't pollute the task model with ephemeral display data

**Today view model:** The Today view shows tasks where `planned_date <= today` OR (`planned_date IS NULL` AND `due_date <= today`). Today's Focus is the ordered subset within Today, defined by the current focus's `task_ids`. When no current focus exists, the Today view still shows all qualifying tasks sorted by priority then due date — the Today's Focus section simply does not appear.

---

### error_logs

Development/runtime error sink used for debugging regressions across app windows.

```sql
CREATE TABLE error_logs (
  id          TEXT PRIMARY KEY,          -- UUIDv7
  source      TEXT NOT NULL,             -- frontend.window | frontend.promise | rust | mcp | sync...
  level       TEXT NOT NULL DEFAULT 'error', -- debug | info | warn | error
  message     TEXT NOT NULL,             -- concise error summary
  details     TEXT,                      -- optional stack trace / metadata (truncated)
  created_at  TEXT NOT NULL
) STRICT;
```

This table is intentionally append-oriented and separate from `ai_changelog`:
- `ai_changelog` answers "what actions happened".
- `error_logs` answers "what broke and when".

---

### preferences

Shared configuration between the app and AI assistant.

```sql
CREATE TABLE preferences (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,              -- JSON
  version     TEXT NOT NULL,              -- HLC timestamp for sync
  updated_at  TEXT NOT NULL
) STRICT;
```

Example entries:
- `working_hours`: `{"start": "09:00", "end": "18:00"}`
- `energy_peak`: `{"morning": true, "afternoon": false}`
- `default_list_id`: `"uuid-of-personal-list"`
- `weekly_review_day`: `"friday"`

AI assistant reads these when making scheduling decisions. The app reads them for display defaults. Either can update them.

---

### daily_reviews

AI assistant-authored end-of-day entries capturing the user's lived experience of each day. This is the foundation of the Daily Review module.

```sql
CREATE TABLE IF NOT EXISTS daily_reviews (
  date               TEXT PRIMARY KEY,  -- YYYY-MM-DD
  summary            TEXT NOT NULL,     -- user's day in prose, written by AI assistant
  mood               INTEGER,           -- 1-5 (optional)
  energy_level       INTEGER,           -- 1-5 (optional)
  wins               TEXT,              -- what went well (AI assistant extracts)
  blockers           TEXT,              -- what got in the way
  learnings          TEXT,              -- explicit insights from the day
  ai_synthesis       TEXT,              -- AI assistant's longitudinal observations
  timezone           TEXT,              -- IANA timezone when review was written
  version            TEXT NOT NULL,     -- HLC timestamp for sync
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  CHECK (mood IS NULL OR (mood >= 1 AND mood <= 5)),
  CHECK (energy_level IS NULL OR (energy_level >= 1 AND energy_level <= 5))
) STRICT;

-- Join tables for linked tasks and lists
-- Parent-owned materializations: task_id/list_id are soft references (no FK constraint).
CREATE TABLE IF NOT EXISTS daily_review_task_links (
  review_date TEXT NOT NULL REFERENCES daily_reviews(date) ON DELETE CASCADE,
  task_id     TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  PRIMARY KEY (review_date, task_id)
) STRICT;

CREATE TABLE IF NOT EXISTS daily_review_list_links (
  review_date TEXT NOT NULL REFERENCES daily_reviews(date) ON DELETE CASCADE,
  list_id     TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  PRIMARY KEY (review_date, list_id)
) STRICT;
```

**Design notes:**
- `date` is the primary key — one entry per calendar day
- `summary` is required; all other fields are optional (AI assistant fills what it can from the conversation)
- `ai_synthesis` holds AI assistant's higher-level observations across multiple days (e.g., "you've had low energy three Mondays in a row")
- Accessed via MCP tools: `add_daily_review`, `get_daily_review`, `get_review_history`, `amend_daily_review`

---

### focus_schedule (Focus Schedule)

AI-generated daily schedule for Today's Focus tasks. `propose_daily_schedule` only schedules tasks in the current focus (not the entire task pool). Stored so humans can review, compare with actuals, and so AI can learn.

```sql
CREATE TABLE focus_schedule (
  date        TEXT PRIMARY KEY,           -- YYYY-MM-DD (one schedule per day)
  rationale   TEXT,                       -- AI's reasoning for the schedule
  timezone    TEXT,                       -- IANA timezone
  version     TEXT NOT NULL,              -- HLC timestamp for sync
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
) STRICT;

-- Ordered time blocks for each schedule
CREATE TABLE focus_schedule_blocks (
  schedule_date TEXT NOT NULL REFERENCES focus_schedule(date) ON DELETE CASCADE,
  position      INTEGER NOT NULL,
  block_type    TEXT NOT NULL CHECK (block_type IN ('task', 'buffer', 'event')),
  start_time    INTEGER NOT NULL,         -- minute-of-day 0-1439 (API uses HH:MM strings)
  end_time      INTEGER NOT NULL,         -- minute-of-day 0-1439 (API uses HH:MM strings)
  task_id       TEXT,                     -- for 'task' blocks
  event_id      TEXT,                     -- for 'event' blocks
  title         TEXT,                     -- for 'event' blocks
  PRIMARY KEY (schedule_date, position)
) STRICT;
```

Focus Schedule is directly applied on save. When saved, the schedule's task block order is also synced to `current_focus_items` to keep the two aligned.

---

## Field Design Notes

### `tasks.ai_notes` — What AI Writes Here

This field is the AI's working space. It's displayed in the UI in a visually distinct style (different background, "AI Notes" label) and is not editable by humans. Examples of what AI writes:

```
"This task blocks 'Submit grant application' and 'Schedule lab meeting'.
 Recommend completing before Thursday."

"You've deferred this 4 times. Original reason from March 2: 'waiting for
 Sarah's feedback'. Consider following up or marking cancelled."

"Similar to the 'API documentation' task you completed in January (took 3h
 despite 1h estimate). Suggest budgeting more time."
```

This is how AI communicates its analysis back to the human without modifying the task content.

### `lists.ai_notes` — Scope Profile for Routing

For lists, `ai_notes` serves a different purpose: list boundary metadata for assistants.

Recommended structure:
- Scope statement: what belongs in this list.
- Explicit exclusions: what should be routed elsewhere.
- Heuristics/examples: short examples to reduce ambiguous classification.

Example:

```
Scope: PhD core research output (papers, experiments, advisor actions).
Exclude: life admin, chores, random reading backlog.
Route ambiguous review tasks to Misc unless tied to active paper deadlines.
```

### `raw_input` — Why Store the Original NL

When AI creates a task from natural language, the original phrase is preserved:
- "hey remind me to follow up with the Barcelona hotel about the booking"
- "need to review the Q4 numbers before board meeting"

This serves two purposes:
1. Human can verify AI's interpretation was correct
2. AI can use it for context when making future decisions about the task

### Dependencies — `task_dependencies` Edge Table

Dependencies are stored in the `task_dependencies` relational edge table — NOT as a column on the tasks table. The `depends_on` JSON array that appears in API responses is **derived at read time** by querying the edge table.

```sql
CREATE TABLE task_dependencies (
  task_id            TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  depends_on_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  version            TEXT NOT NULL,       -- HLC timestamp for sync
  created_at         TEXT NOT NULL,
  PRIMARY KEY (task_id, depends_on_task_id),
  CHECK (task_id != depends_on_task_id)
) STRICT;
```

Example: if `task_dependencies` has rows `(B, A)` and `(C, A)`, then:
- Task B depends on Task A
- Task C depends on Task A
- Task A blocks Tasks B and C (derived by reverse lookup)

The API returns `depends_on: ["task-a-id"]` on Task B's JSON, but this is computed from the edge table, not stored on the task row.

### Task Ordering

Tasks have no persistent task-level sort order field. Ordering only exists in two places:
- **Today's Focus** — the `current_focus_items` sub-table defines display order via a `position` column.
- **Focus Schedule** — the `focus_schedule_blocks` sub-table defines time-block order via a `position` column.

Everywhere else, tasks are sorted by `priority_effective ASC, due_date ASC NULLS LAST, id ASC` — exposed in code as the `TASK_ORDER_BY` constant in `lorvex-store/src/repositories/task/read/mod.rs`. `priority_effective` is the generated-column wrapper around `priority` (NULL→4) so P-unset tasks sort after P3. `id ASC` is the deterministic tiebreaker required for stable OFFSET pagination.

**Per-view exceptions are permitted** when a view's user-facing semantics demand a different sort axis. The canonical catalog of permitted divergences lives in [Sort Keys](#sort-keys) below. Every such divergence MUST carry an inline comment above the `ORDER BY` explaining why it diverges from the canonical clause and what user expectation it serves. Reviewers should treat an undocumented divergence as a bug — the next maintainer cannot tell intentional UX from accidental drift without the comment.

### Sort Keys

The canonical task sort key is

```
ORDER BY priority_effective ASC, due_date ASC NULLS LAST, id ASC
```

This is the user-facing default. Every general task list view (All Tasks, list views, Eisenhower, Kanban within a quadrant, search results, MCP `list_tasks`, etc.) MUST use it. Exposed in code as the `TASK_ORDER_BY` constant in `lorvex-store/src/repositories/task/read/mod.rs`.

`id ASC` is the deterministic tiebreaker required for stable OFFSET pagination — two rows that compare equal on every earlier axis must still order identically between LIMIT pages, otherwise rows flicker or duplicate across the pagination boundary.

Per-view divergences are permitted only when a view's user-facing semantics demand a different leading axis. The current catalog:

| View | Source | Sort key | Why it diverges |
|------|--------|----------|-----------------|
| Today pool (date-bound) | `lorvex-store/src/repositories/task/read/today.rs` (canonical today bucket) | `priority_effective ASC, due_time ASC NULLS LAST, created_at DESC, id ASC` | Every row in the bucket already shares the same calendar day by construction, so the canonical `due_date` axis is degenerate. Substitutes `due_time` so deadline-bearing tasks bubble up by time-of-day, then `created_at DESC` so the most recently captured task lands above older equal-priority siblings. |
| Today pool — high-priority undated | `lorvex-store/src/repositories/task/read/today.rs` (undated bucket) | `priority_effective ASC, created_at DESC, id ASC` | Every row gates on both `due_date IS NULL` and `planned_date IS NULL`, so the canonical `due_date ASC NULLS LAST` axis is degenerate and dropped. Substitutes `created_at DESC` so a freshly captured P1/P2 idea surfaces above older equal-priority siblings. |
| Weekly review — overdue items | `lorvex-workflow/src/weekly_review/sections.rs` | `due_date ASC, priority_effective ASC, id ASC` | The reviewer's question is "what's most overdue?", so the deadline axis leads and priority becomes the secondary tiebreaker. |
| Weekly review — frequently deferred | `lorvex-workflow/src/weekly_review/sections.rs` (`deferred_items_sql`) | `defer_count DESC, <canonical key>` | The reviewer's question is "what am I dodging the most?", so `defer_count DESC` leads and the canonical clause becomes the inner tiebreaker. |
| Weekly review — someday peek | `lorvex-workflow/src/weekly_review/sections.rs` | `created_at DESC, id ASC` | Someday/Maybe entries are undated by definition; recency is the most useful axis for a periodic review pass. |
| TUI dashboard — due today | `lorvex-cli/src/tui/mod.rs` | `priority_effective ASC, updated_at DESC, id ASC` | A terminal dashboard wants the most recently touched equal-priority task at the top; `due_date` is degenerate (every row is today) and the dashboard does not show `due_time`. |
| TUI dashboard — upcoming preview | `lorvex-cli/src/tui/mod.rs` | `COALESCE(planned_date, due_date) ASC, priority_effective ASC, updated_at DESC, id ASC` | The user is scanning the next few action dates, so the action date leads and the canonical clause becomes inner tiebreakers. |
| MCP task-pattern analytics — deferral feed | `mcp-server/src/system/guidance/task_pattern_analysis/metrics/collect.rs` | `defer_count DESC, priority_effective ASC, due_date ASC NULLS LAST, updated_at DESC, id ASC` | Analytics output ordered by deferral intensity for AI-side pattern detection; not a user-facing task list. |

Rules for adding a new divergence:

1. The divergence MUST serve a user-facing or analytics semantic that the canonical clause cannot express. "I want a different default" is not a reason.
2. An inline comment above the `ORDER BY` MUST explain (a) what canonical clause this diverges from and (b) what user expectation the divergence serves.
3. `id ASC` (or another deterministic tiebreaker on a unique-or-monotone column) MUST appear as the last axis so OFFSET pagination stays stable.
4. Add the row to the table above in the same PR that introduces the divergence.

### Today Pool Definition

The "today" pool is: `status = 'open' AND (planned_date <= today OR (planned_date IS NULL AND due_date <= today))`.

For display, the UI splits the today pool into three buckets:
1. **Overdue** — tasks with `due_date < today` (or `planned_date < today` with no future due_date)
2. **Today** — tasks planned or due for today
3. **Higher-importance undated** — tasks with neither `planned_date` nor `due_date` but elevated importance (P1/P2)

### Action Vocabulary

The system uses a specific vocabulary for task operations:
- **Plan** — set or update `planned_date` (when the user/AI intends to work on the task)
- **Defer** — push `planned_date` forward + increment `defer_count` (via `defer_task`)
- **Set Due Date** — set the external deadline (`due_date`)
- **Complete** — mark as done (`status = 'completed'`)
- **Cancel** — soft delete (`status = 'cancelled'`)
- **Delete Forever** — hard delete (physical row removal, irreversible)
- **Move to Someday** — set `status = 'someday'` (GTD Someday/Maybe)
- **Add to Focus** — insert row into `current_focus_items` sub-table
- **Remove from Focus** — delete row from `current_focus_items` sub-table

---

## Indexes

`lorvex-store/src/schema/001_schema.sql` is the source of truth for complete
index DDL. This design doc intentionally does not duplicate the full list
because index shape is an active performance contract and drifts quickly.

Stable invariants the live schema currently protects:

- Task browse/focus queries use partial open-task indexes over status/list,
  `priority_effective`, due date, and deterministic `id` tiebreakers while
  excluding archived rows.
- Deferred-task queries have dedicated `(status, defer_count DESC, id ASC)`
  indexes, including a list-scoped variant, so the planner can stream the
  displayed ordering.
- Changelog reads use `(timestamp DESC, id DESC)` so same-millisecond rows have
  deterministic ordering and polling boundaries do not drop entries.
- Daily reviews rely on the `date` primary key; there is no separate
  `idx_daily_reviews_date`.
- Sync outbox pending work uses a narrow partial unsynced index
  `(id, retry_count) WHERE synced_at IS NULL`, plus a unique
  partial per-entity unsynced index to enforce coalescing.
- Calendar, reminder, recurrence, blob-GC, and join-table indexes live beside
  their table contracts in `001_schema.sql`; update that file first, then adjust
  these invariants only when the query behavior changes.

---

## Common Query Patterns

### Today's tasks (what AI's `get_todays_tasks` returns)
```sql
-- Today pool: status = 'open' AND (planned_date <= today OR (planned_date IS NULL AND due_date <= today))
-- Display splits into 3 buckets: overdue, today, high-priority undated
SELECT * FROM tasks
WHERE status = 'open'
  AND (
    planned_date <= :today
    OR (planned_date IS NULL AND due_date <= :today)
  )
ORDER BY priority_effective ASC, due_date ASC NULLS LAST, id ASC;
```

### AI overview query (single call for situational awareness)
```sql
SELECT
  (SELECT count(*) FROM tasks WHERE status = 'open') as open_count,
  (SELECT count(*) FROM tasks WHERE status = 'open' AND due_date < :today) as overdue_count,
  (SELECT count(*) FROM tasks WHERE status = 'open' AND due_date = :today) as today_pool_count,
  (SELECT count(*) FROM tasks WHERE status = 'completed' AND completed_at >= :seven_days_ago_utc) as completed_this_week;
-- Plus top 5 by priority, plus list breakdown
```

### Stalled lists (for weekly review)
```sql
SELECT l.id, l.name,
       count(t.id) as task_count,
       min(t.priority) as top_priority,
       min(t.updated_at) as last_activity
FROM lists l
JOIN tasks t ON t.list_id = l.id AND t.status = 'open'
GROUP BY l.id
HAVING last_activity < datetime('now', '-7 days')
ORDER BY top_priority ASC, last_activity ASC;
```

---

## Migration Strategy

Migrations use a linear, checksummed framework in `lorvex-store/src/migration/`. Migration SQL files are embedded in the binary and applied on startup. The framework tracks applied migrations with checksums to detect drift.

### Current Pre-Public-Release Schema Policy

Lorvex is still governed as a pre-public-release product. The active database contract is a single squashed baseline in `lorvex-store/src/schema/001_schema.sql`, and all tables are created idempotently (`CREATE TABLE IF NOT EXISTS`) from that consolidated file.

During this phase, development-only schema history is disposable. If the clean model changes, update the consolidated baseline and callers directly instead of adding backward-compatibility shims, re-export aliases, or migration paths for old pre-release shapes. Package/app version numbers do not create a current data-format compatibility promise.

Future post-public-release database compatibility is a separate policy. Once real user databases must be preserved across public releases, changes should move to numbered, linear, non-skippable migrations backed by checksum verification and explicit import/sync compatibility tests.



### calendar_events

Independent calendar events (meetings, appointments), separate from task due dates. Added as part of the Calendar View module.

```sql
CREATE TABLE calendar_events (
  id                    TEXT PRIMARY KEY,
  title                 TEXT NOT NULL,
  description           TEXT,
  start_date            TEXT NOT NULL,     -- YYYY-MM-DD
  start_time            TEXT,              -- HH:MM
  end_date              TEXT,              -- YYYY-MM-DD
  end_time              TEXT,              -- HH:MM
  all_day               INTEGER NOT NULL DEFAULT 0,
  location              TEXT,
  color                 TEXT,              -- Hex color
  recurrence            TEXT,              -- JSON recurrence rule (same format as tasks)
  recurrence_exceptions TEXT,              -- JSON string[] of EXDATE dates (YYYY-MM-DD)
  event_type            TEXT NOT NULL DEFAULT 'event',
                        -- 'event' | 'birthday' | 'anniversary' | 'memorial'
  person_name           TEXT,              -- For birthday/anniversary events
  timezone              TEXT,              -- IANA timezone
  version               TEXT NOT NULL,     -- HLC timestamp for sync
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  CHECK (event_type IN ('event', 'birthday', 'anniversary', 'memorial')),
  CHECK (all_day = 0 OR (start_time IS NULL AND end_time IS NULL))
) STRICT;
```

### memories

Persistent AI memory entries — structured notes the assistant maintains about the user. Displayed in the AI Memory view.

```sql
CREATE TABLE memories (
  id          TEXT PRIMARY KEY,       -- opaque UUIDv7 row identity
  key         TEXT NOT NULL UNIQUE,   -- topic key (e.g. "user_profile", "project_paper")
  content     TEXT NOT NULL,          -- AI assistant's notes (markdown)
  version     TEXT NOT NULL,          -- HLC timestamp for sync
  updated_at  TEXT NOT NULL
) STRICT;
```

**Intentional Tauri divergence - memory converges on `key`, not `id`.** The
opaque `id` column exists for byte-equality with the shared schema (the Apple
app routes memory sync envelopes on `id` so a human/AI-chosen `key` stays out of
provider-visible routing metadata). Tauri currently has no active cloud sync
transport, so that id-routing driver is moot: Tauri treats `memories` as a
`key`-keyed natural-key aggregate and converges every write - local and inbound -
through an `ON CONFLICT(key) DO
UPDATE` LWW upsert (`memory_ops::upsert_memory_entry`,
`sync::apply::aggregate::memory`). The `id` is a device-local, insert-only row
identity, deliberately excluded from the `ON CONFLICT(key)` update arm so a
re-echoed memory never rewrites it. Because the LWW upsert absorbs a duplicate
`key` directly, Tauri needs no id-routing collision merge (the Apple-side
min-id-wins tombstone-and-redirect step) and no `key` UNIQUE ever wedges an
inbound sync page.

### sync_outbox

Append-only sync outbox for cross-device propagation. Every write operation enqueues an outbox entry.

```sql
CREATE TABLE sync_outbox (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type            TEXT NOT NULL,     -- 'task' | 'list' | 'calendar_event' | etc.
  entity_id              TEXT NOT NULL,
  operation              TEXT NOT NULL,     -- 'upsert' | 'delete'
  version                TEXT NOT NULL,     -- HLC version of the change
  payload_schema_version INTEGER NOT NULL,  -- Schema version of the payload format
  payload                TEXT NOT NULL,     -- Canonical JSON snapshot of the entity
  device_id              TEXT NOT NULL,
  created_at             TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  synced_at              TEXT,              -- NULL until pushed to remote
  retry_count            INTEGER NOT NULL DEFAULT 0,
  last_retry_at          TEXT,
  last_error             TEXT               -- Per-row error history. The
                                            -- retry loop compares the latest
                                            -- failure to this column to
                                            -- detect a stuck-in-place row
                                            -- (same error repeating = strong
                                            -- evidence of a permanent
                                            -- failure) and fast-fail before
                                            -- the global retry budget runs
                                            -- out.
) STRICT;
```

#### Undo

Undo is token-based: the mutation surface returns or stores an undo
token carrying the pre-mutation state needed to replay a revert within
the short user-visible undo window. Token payloads vary by family:
task lifecycle/update tokens snapshot the task fields and linked
reminder/focus state they must restore; MCP delete/preference tokens
carry the deleted row or prior preference value; Tauri calendar/list
delete tokens carry self-contained `EntitySnapshot` JSON.

Undo is a plain reverse write on every surface. Forward mutations
enqueue their sync envelopes immediately; invoking Undo restores the
local state from the token's snapshot and emits fresh envelopes with
newer HLC versions (upserts for restored rows, deletes + tombstones
for rows the undo removes, e.g. a spawned recurrence successor). Peers
converge under ordinary LWW regardless of whether the forward
envelopes were already pushed — at worst one forward/reverse envelope
pair rides the transport.

### sync_checkpoints

Key-value store for sync cursors, device identity, and sync health metadata.

```sql
CREATE TABLE sync_checkpoints (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;
```

### device_state

Key-value table for device-local state. This table is **NOT synced** across devices — it holds ephemeral UI state that is specific to the current device.

```sql
CREATE TABLE device_state (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;
```

Example entries:
- `focus_mode_target_task_id`: the task currently in focus mode on this device

Unlike `preferences` (which syncs and represents user intent), `device_state` is purely local runtime state.

---

### task_reminders

Multiple reminders per task. Replaces the previous single `reminder_at` column on the tasks table.

```sql
CREATE TABLE task_reminders (
  id           TEXT PRIMARY KEY,
  task_id      TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  reminder_at  TEXT NOT NULL,       -- ISO 8601 datetime
  dismissed_at TEXT,                -- When the user dismissed this reminder
  cancelled_at TEXT,                -- When the reminder was cancelled
  version      TEXT NOT NULL,       -- HLC timestamp for sync
  created_at   TEXT NOT NULL
) STRICT;
```

### task_calendar_event_links

Join table linking tasks to canonical calendar events.

```sql
CREATE TABLE task_calendar_event_links (
  task_id           TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  calendar_event_id TEXT NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
  version           TEXT NOT NULL,       -- HLC timestamp for sync
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  PRIMARY KEY (task_id, calendar_event_id)
) STRICT;
```

### habits

Dedicated habit definitions with frequency tracking.

```sql
CREATE TABLE habits (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  icon            TEXT,                    -- emoji or icon identifier
  color           TEXT,                    -- hex color
  frequency_type  TEXT NOT NULL DEFAULT 'daily', -- 'daily' | 'weekly' | 'monthly' | 'custom'
  frequency_value TEXT,                    -- JSON: e.g. {"days":["mon","wed","fri"]}
  target_count    INTEGER NOT NULL DEFAULT 1,
  archived        INTEGER NOT NULL DEFAULT 0,
  version         TEXT NOT NULL,           -- HLC timestamp for sync
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
) STRICT;
```

### habit_completions

Per-day completion records for habits.

```sql
CREATE TABLE habit_completions (
  habit_id       TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  completed_date TEXT NOT NULL,            -- YYYY-MM-DD
  value          INTEGER NOT NULL DEFAULT 1,
  note           TEXT,
  version        TEXT NOT NULL,            -- HLC timestamp for sync
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  PRIMARY KEY (habit_id, completed_date)
) STRICT;
```

### habit_reminder_policies

Per-habit reminder slots. A habit may have multiple reminder times; the
canonical uniqueness boundary is `(habit_id, reminder_time)`.

```sql
CREATE TABLE habit_reminder_policies (
  id               TEXT PRIMARY KEY,
  habit_id         TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  reminder_time    TEXT NOT NULL,             -- HH:MM
  enabled          INTEGER NOT NULL DEFAULT 1,
  version          TEXT NOT NULL,            -- HLC timestamp for sync
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL,
  UNIQUE(habit_id, reminder_time)
) STRICT;
```

### habit_reminder_delivery_state

Local suppression/runtime state for habit reminder notifications. Delivery
suppression stays local-only via this state table rather than syncing through
the canonical reminder policy row.

```sql
CREATE TABLE habit_reminder_delivery_state (
  policy_id        TEXT PRIMARY KEY REFERENCES habit_reminder_policies(id) ON DELETE CASCADE,
  last_fired_at    TEXT,
  updated_at       TEXT NOT NULL
) STRICT;
```

---

### Applied Migrations

The current pre-public-release schema uses a single consolidated migration file. All tables are created idempotently (`CREATE TABLE IF NOT EXISTS`) in one file. This is the active squashed baseline, not a promise to preserve earlier development-only schemas.

| Version | File | Description |
|---|---|---|
| 001 | `001_schema.sql` | Consolidated schema for core canonical entities, local sync/runtime tables, habit tracking, tags, and projections. |

### Additional Tables (not fully described above)

The canonical schema in `lorvex-store/src/schema/001_schema.sql` contains many additional tables beyond those described in detail above. These include:

**Synced entities:**
- `tags` — tag definitions with `display_name`, `lookup_key`, color
- `task_tags` — join table linking tasks to tags
- `calendar_subscriptions` — ICS calendar subscription URLs
- `memory_revisions` — revision history for AI memory entries (supports undo/restore)

**Parent-owned materializations:**
- `calendar_event_attendees` — attendee list for calendar events

**Local-only state:**
- `task_provider_event_links` — links between tasks and native calendar provider events
- `provider_calendar_events` — cached native calendar events (Windows Appointments, Linux ICS)
- `provider_scope_runtime_state` — refresh/availability state for calendar providers
- `task_reminder_delivery_state` — local delivery tracking for task reminders
- `blob_fetch_queue` — pending blob downloads for sync

**Sync infrastructure:**
- `sync_tombstones` — soft-delete markers with optional redirect
- `sync_device_cursors` — per-device sync progress tracking
- `sync_conflict_log` — recorded merge conflicts (winner/loser versions)
- `sync_pending_inbox` — durable FK-retry queue for out-of-order sync envelopes
- `local_counters` — local integer counters such as `local_change_seq`
- `local_sync_owner` — lease-based sync backend ownership
- `mcp_host_authority` — singleton external MCP host authority (`app` or `cli`)
- `mcp_idempotency` — MCP write-response retry cache keyed by `(tool_name, idempotency_key)`; stores `request_checksum`, cached response payload, and a 24h expiry so same-payload retries replay the original response while changed-payload key reuse is rejected
- `sync_payload_shadow` — last-known payload for delta computation

**Content-addressed storage:**
- `blob_assets` — content-addressed binary storage metadata

**Derived projections:**
- `tasks_fts` — FTS5 virtual table for full-text search on tasks (title, body, ai_notes, tags); the `tags` column holds space-separated tag display_names aggregated via trigger from `task_tags` + `tags`
- `calendar_events_fts` — FTS5 virtual table for calendar event search (title, description, location)

See `lorvex-store/src/schema/001_schema.sql` for the complete canonical schema.
