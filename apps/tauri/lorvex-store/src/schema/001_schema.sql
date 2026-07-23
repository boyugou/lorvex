-- Lorvex: canonical schema
-- This file defines the only supported database layout.
-- The app and MCP server expect a fresh database created from this schema.
-- All tables use STRICT mode for type safety.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ── A. Aggregate Roots (synced, stable identity) ────────────────────

CREATE TABLE IF NOT EXISTS lists (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    color       TEXT,
    icon        TEXT,
    description TEXT,
    ai_notes    TEXT,
    version     TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    -- Soft-archive timestamp (RFC-3339 `…Z`); non-NULL = the whole list is
    -- archived (hidden from the active catalog, all its tasks + completed
    -- history preserved, restorable). Orthogonal to deletion.
    archived_at TEXT,
    -- Synced manual display order for the lists catalog/sidebar (ascending;
    -- ties broken by created_at, id). Set by the list-reorder action and carried
    -- as an ordinary LWW column, so a drag on one device converges across peers.
    -- DEFAULT 0 keeps freshly created/imported lists grouped until first ordered.
    position    INTEGER NOT NULL DEFAULT 0
) STRICT;
-- The BEFORE DELETE trigger on `lists` lives below
-- the `tasks` table definition because the trigger body references
-- `tasks` and SQLite resolves the `tasks` reference at
-- CREATE-TRIGGER time. Search this file for `trg_lists_before_delete`
-- to find it.

CREATE TABLE IF NOT EXISTS tasks (
    id                      TEXT PRIMARY KEY,
    title                   TEXT NOT NULL,
    body                    TEXT,
    raw_input               TEXT,
    ai_notes                TEXT,
    status                  TEXT NOT NULL DEFAULT 'open',
    list_id                 TEXT NOT NULL DEFAULT 'inbox' REFERENCES lists(id) ON DELETE RESTRICT,
    priority                INTEGER,
    due_date                TEXT,
    due_time                TEXT,
    estimated_minutes       INTEGER,
    recurrence              TEXT,
    spawned_from            TEXT,
    recurrence_group_id     TEXT,
    recurrence_instance_key TEXT,
    canonical_occurrence_date TEXT,        -- stable RRULE cadence anchor (independent of due_date)
    version                 TEXT NOT NULL,
    created_at              TEXT NOT NULL,
    updated_at              TEXT NOT NULL,
    completed_at            TEXT,
    last_deferred_at        TEXT,
    -- align with the canonical defer-reason allowlist in the domain
    -- layer. Extending this list requires editing both sets — coupled
    -- deliberately so the sync apply / MCP validator and the DB can't
    -- drift.
    last_defer_reason       TEXT
                            CHECK (last_defer_reason IS NULL OR last_defer_reason IN (
                                'not_today', 'blocked', 'low_energy',
                                'needs_breakdown', 'needs_info'
                            )),
    planned_date            TEXT,
    -- civil date (YYYY-MM-DD) before which the task is hidden from
    -- day surfaces (Today pool, day buckets, Upcoming, default open
    -- list lane, focus auto-proposal) and therefore from widgets /
    -- watch / CarPlay. UTC-midnight anchored like `planned_date`, so
    -- it is stable across timezone change. A task is "hidden" while
    -- `available_from > today` AND it is not overdue — an overdue
    -- task always surfaces (overdue-wins). No CHECK: orthogonal to
    -- status, due_date, and planned_date. Still findable in the
    -- Scheduled section, full-text search, and explicit MCP queries.
    available_from          TEXT,
    defer_count             INTEGER NOT NULL DEFAULT 0 CHECK (defer_count >= 0),
    -- soft-delete / Trash. Non-NULL = in trash. Users
    -- can restore from Settings → Data → Trash; a boot-time sweep
    -- hard-deletes anything older than 30 days. This is orthogonal
    -- to `status = 'cancelled'` (cancel = task won't be done;
    -- archive = user moved it out of view). Every task read path
    -- filters `archived_at IS NULL` inline so archived rows never
    -- leak into lists, stats, search, or the MCP surface.
    archived_at             TEXT,
    -- `priority_effective` keeps hot ORDER BY
    -- `COALESCE(priority, 4) ASC` streaming from an index rather
    -- than filesort-ing every LIMIT-bounded fetch. `4` is a safe
    -- sentinel for "unset" that sorts last, given the CHECK below
    -- restricts priority to 1..3.
    --
    -- the prose used to read `COALESCE(priority, 3)`
    -- while the expression below uses `4`. The comment was the bug;
    -- the SQL is load-bearing and unchanged. The prose was updated
    -- so a reader doesn't conclude there's a sentinel mismatch.
    priority_effective      INTEGER GENERATED ALWAYS AS (COALESCE(priority, 4)) VIRTUAL,
    CHECK (priority IS NULL OR (priority >= 1 AND priority <= 3)),
    CHECK (status IN ('open', 'completed', 'cancelled', 'someday')),
    CHECK (due_time IS NULL OR due_date IS NOT NULL),
    -- this CHECK re-evaluates against the row's CURRENT
    -- column values on every UPDATE, not just on writes that touch
    -- `recurrence`. A partial-update path that NULLs any of the three
    -- companion fields (`due_date`, `recurrence_group_id`,
    -- `canonical_occurrence_date`) on a row that still carries
    -- `recurrence` will trip this CHECK with a non-obvious constraint
    -- failure. New writers MUST treat the four fields atomically: when
    -- "ungrouping" a recurring task (e.g. converting it back to a
    -- one-off), null `recurrence` first, then the three companions —
    -- never the reverse — and never null any single companion in
    -- isolation while `recurrence` is still set.
    CHECK (recurrence IS NULL OR (
        due_date IS NOT NULL
        AND recurrence_group_id IS NOT NULL
        AND canonical_occurrence_date IS NOT NULL
    ))
) STRICT;

-- this UNIQUE partial index fires per-row at
-- statement boundaries — a multi-row recurrence batch (e.g. the
-- recurrence-merge codepath) that briefly inserts duplicates before
-- merging them must use a SAVEPOINT so the UNIQUE violation in the
-- intermediate state rolls back cleanly. Today recurrence-merge
-- assigns each occurrence a distinct UUIDv7 PK and rewrites
-- `recurrence_instance_key` only inside the merge transaction, so
-- the constraint sees consistent rows at the commit boundary; any
-- future writer that batches multi-row instance-key rewrites must
-- follow the same SAVEPOINT discipline.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_recurrence_instance_key
    ON tasks(recurrence_instance_key) WHERE recurrence_instance_key IS NOT NULL;

-- BEFORE DELETE trigger on `lists`. Two invariants the
-- bare `ON DELETE RESTRICT` FK on `tasks.list_id` can't enforce:
--
--   1. The `inbox` list is the canonical fallback target for every
--      orphaned task. A peer device that emits a malformed
--      `Delete{lists:'inbox'}` envelope would, on apply, hit the
--      RESTRICT FK and wedge `sync_pending_inbox` indefinitely
--      because no later envelope can ever satisfy the constraint
--      (every task that survives points at inbox). Reject the
--      DELETE outright at the schema level so the apply pipeline
--      surfaces the wedge as a hard validation error instead.
--
--   2. Deleting any other list with surviving tasks would also
--      hit the RESTRICT FK. Re-home those tasks to `inbox` here,
--      BEFORE the DELETE proceeds, so the constraint never fires.
--      This matches the human-facing UX (a list is a folder;
--      deleting the folder doesn't delete the items) and prevents
--      the same sync-wedge mode from blocking a peer's legitimate
--      list removal.
--
-- The trigger has to live AFTER the `tasks` CREATE TABLE because
-- SQLite resolves the body's `tasks` reference at trigger-creation
-- time.
CREATE TRIGGER IF NOT EXISTS trg_lists_before_delete
    BEFORE DELETE ON lists
BEGIN
    -- Block inbox deletion only while there are still tasks anywhere
    -- in the workspace (any list, including inbox itself). The
    -- `reset_all_data_db` flow legitimately wipes everything bottom-
    -- up, leaving `tasks` empty before deleting `lists`; that path
    -- needs to clear `inbox` too. The check distinguishes "user (or
    -- peer) tries to delete the canonical fallback while live tasks
    -- still depend on it" from "full data reset".
    SELECT CASE
        WHEN OLD.id = 'inbox' AND EXISTS (SELECT 1 FROM tasks LIMIT 1) THEN
            RAISE(ABORT, 'cannot delete inbox list: canonical fallback target for orphaned tasks')
    END;
    UPDATE tasks SET list_id = 'inbox' WHERE list_id = OLD.id AND OLD.id != 'inbox';
END;

CREATE TABLE IF NOT EXISTS habits (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    icon            TEXT,
    color           TEXT,
    cue             TEXT,
    -- Cadence rhythm. Each value carries its detail in a dedicated typed column
    -- rather than a JSON blob:
    --   'daily'          → every day (no detail column).
    --   'weekly'         → a specific weekday set in the `habit_weekdays` child;
    --                      an empty set means "every day".
    --   'monthly'        → once per calendar month; `day_of_month` picks the
    --                      reminder day.
    --   'times_per_week' → `per_period_target` completions per week, no weekday
    --                      pinning.
    -- Extending this list requires editing the CHECK, the domain-layer
    -- habit frequency-type enum, and every cadence branch in the
    -- streak / reminder code.
    frequency_type  TEXT NOT NULL DEFAULT 'daily'
                    CHECK (frequency_type IN (
                        'daily', 'weekly', 'monthly', 'times_per_week'
                    )),
    -- Completions required per week for a 'times_per_week' cadence (the N in
    -- "3×/week"). Ignored by every other cadence. Decoupled from `target_count`,
    -- which is the per-day accumulative goal.
    per_period_target INTEGER NOT NULL DEFAULT 1
                      CHECK (per_period_target >= 1),
    -- Reminder day-of-month for a 'monthly' cadence (1–31, clamped to the
    -- month's last day at use sites). NULL leaves it unspecified (reminders fall
    -- back to the 1st). Ignored by every other cadence.
    day_of_month    INTEGER
                    CHECK (day_of_month IS NULL OR day_of_month BETWEEN 1 AND 31),
    -- Per-day accumulative goal (e.g. 8 glasses of water). Fully decoupled from
    -- cadence: it is how many units count as "done" on a scheduled day, never a
    -- period frequency.
    target_count    INTEGER NOT NULL DEFAULT 1
                    CHECK (target_count >= 1),
    -- Optional user-set milestone target on the habit's progress metric: current
    -- streak length for the streak cadences (daily, weekly), total completions
    -- for the count cadences (times_per_week, monthly). NULL leaves the goal
    -- unset, so milestones fall back to the built-in ladder. Positive when set.
    milestone_target INTEGER
                    CHECK (milestone_target IS NULL OR milestone_target > 0),
    archived        INTEGER NOT NULL DEFAULT 0
                    CHECK (archived IN (0, 1)),
    -- persist a normalized dedup key alongside the
    -- displayable `name`. Every habit writer computes this via the
    -- shared normalize-lookup-key pipeline — NFKC + Unicode
    -- case-fold + whitespace-collapse, the same pipeline tag dedup
    -- uses. The DEFAULT '' + the BEFORE-INSERT trigger
    -- below give raw test SEED inserts a sane fallback
    -- (`lower(trim(name))`) so unit tests that don't go through a
    -- writer still satisfy the partial UNIQUE index.
    lookup_key      TEXT NOT NULL DEFAULT '',
    version         TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    -- Synced manual display order for the habits board (ascending; ties broken
    -- by name, id). Set by the habit-reorder action and carried as an ordinary
    -- LWW column, so a drag on one device converges across peers. DEFAULT 0
    -- keeps freshly created habits grouped until first explicitly ordered.
    position        INTEGER NOT NULL DEFAULT 0
) STRICT;

-- Schema-layer dedup. The partial UNIQUE index closes the
-- SELECT-then-INSERT TOCTOU window an in-memory `create_habit`
-- loop alone could not — two writers racing the SELECT would both
-- think the lookup_key was free and both INSERT. Archived habits
-- don't participate in dedup (a user can recreate a habit with the
-- same name after archiving the old one).
CREATE UNIQUE INDEX IF NOT EXISTS idx_habits_lookup_key_active
    ON habits(lookup_key) WHERE archived = 0;

-- ASCII-only fallback for raw test seeds that insert
-- into `habits` without going through the habit writers. Real writers
-- always pre-compute the full Unicode-normalized key via the shared
-- normalize-lookup-key pipeline and pass it explicitly, so the
-- trigger is a no-op on that path. SQLite's built-in `lower()` is
-- ASCII-only; the trigger therefore covers ASCII test names but is
-- intentionally weaker than the shared normalize-lookup-key pipeline.
-- Production writes never hit this branch.
CREATE TRIGGER IF NOT EXISTS habits_lookup_key_ai_fallback
    AFTER INSERT ON habits
    WHEN NEW.lookup_key = ''
BEGIN
    UPDATE habits SET lookup_key = lower(trim(NEW.name)) WHERE id = NEW.id;
END;

CREATE TABLE IF NOT EXISTS tags (
    id           TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    lookup_key   TEXT NOT NULL,
    color        TEXT,
    version      TEXT NOT NULL,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
) STRICT;
-- Note: lookup_key uniqueness is enforced at the application level by
-- merge_duplicate_tags() in the sync apply pipeline, which needs to
-- temporarily hold two rows with the same lookup_key during merge.

CREATE TABLE IF NOT EXISTS calendar_events (
    id                    TEXT PRIMARY KEY,
    title                 TEXT NOT NULL,
    description           TEXT,
    start_date            TEXT NOT NULL,
    start_time            TEXT,
    end_date              TEXT,
    end_time              TEXT,
    all_day               INTEGER NOT NULL DEFAULT 0
                          CHECK (all_day IN (0, 1)),
    location              TEXT,
    url                   TEXT,
    color                 TEXT,
    recurrence            TEXT,
    -- derived terminal date for recurring events. Mirrors
    -- the RFC 5545 UNTIL bound stored inside the `recurrence` JSON
    -- (`$.UNTIL`) so the timeline range query can prune long-dead
    -- recurrences at the SQL layer instead of fetching every row whose
    -- `start_date <= ?2` and re-checking the bound during timeline
    -- expansion. NULL means "no UNTIL" — either the rule is unbounded
    -- (open-ended) or it terminates via COUNT (which can't be expressed
    -- in pure SQL without enumerating occurrences). The unbounded /
    -- COUNT case is correctly preserved by the timeline predicate
    -- `(recurrence_end_date IS NULL OR recurrence_end_date >= ?1)`.
    -- Populated automatically by SQLite as a STORED generated column —
    -- every INSERT/UPDATE writer (sync apply, MCP, Tauri, export/import,
    -- tests) stays oblivious. STORED so the timeline-prune predicate
    -- `recurrence_end_date IS NULL OR recurrence_end_date >= ?1` can
    -- ride the partial index on `recurrence_end_date` without re-
    -- evaluating the CASE per scan; UNTIL extraction on every read
    -- would dominate cost on the calendar timeline hot path.
    recurrence_end_date   TEXT GENERATED ALWAYS AS (
      CASE
        WHEN recurrence IS NULL THEN NULL
        WHEN NOT json_valid(recurrence) THEN NULL
        WHEN json_extract(recurrence, '$.UNTIL') IS NULL THEN NULL
        WHEN json_extract(recurrence, '$.UNTIL') LIKE '____-__-__' THEN
             json_extract(recurrence, '$.UNTIL')
        WHEN json_extract(recurrence, '$.UNTIL') LIKE '____-__-__T%' THEN
             substr(json_extract(recurrence, '$.UNTIL'), 1, 10)
        WHEN length(json_extract(recurrence, '$.UNTIL')) = 8 THEN
             substr(json_extract(recurrence, '$.UNTIL'), 1, 4) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 5, 2) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 7, 2)
        WHEN length(json_extract(recurrence, '$.UNTIL')) = 16
             AND substr(json_extract(recurrence, '$.UNTIL'), 9, 1) = 'T' THEN
             substr(json_extract(recurrence, '$.UNTIL'), 1, 4) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 5, 2) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 7, 2)
        ELSE NULL
      END
    ) STORED,
    event_type            TEXT NOT NULL DEFAULT 'event',
    person_name           TEXT,
    timezone              TEXT,
    -- Single-occurrence override linkage for recurring events, mirroring
    -- `tasks.recurrence_group_id` / `recurrence_instance_key`. An *override* row
    -- materializes the one occurrence of a recurring series the user edited under
    -- "This Event" scope: it carries `recurrence IS NULL`, `series_id` = the
    -- originating series master's event id, and `recurrence_instance_date` = the
    -- `YYYY-MM-DD` occurrence it replaces (the master simultaneously EXDATEs that
    -- date). The series master keeps its `recurrence` and leaves both columns
    -- NULL — it is the group anchor, addressed by its own id, so "edit/delete
    -- all" sweeps `id = anchor OR series_id = anchor` and no edited occurrence is
    -- orphaned. Plain non-recurring events leave both NULL.
    series_id             TEXT,
    recurrence_instance_date TEXT,
    version               TEXT NOT NULL,
    created_at            TEXT NOT NULL,
    updated_at            TEXT NOT NULL,
    CHECK (event_type IN ('event', 'birthday', 'anniversary', 'memorial')),
    CHECK (all_day = 0 OR (start_time IS NULL AND end_time IS NULL)),
    -- Override linkage is both-or-neither: a single-occurrence override sets
    -- `series_id` (its master's id) and `recurrence_instance_date` (the occurrence
    -- it replaces) together; every master / plain event leaves both NULL.
    CHECK ((series_id IS NULL) = (recurrence_instance_date IS NULL)),
    -- Two overrides of the same series can't both claim one occurrence. The
    -- pair is (NULL, NULL) for every master / plain event; SQLite treats NULLs
    -- as distinct in a UNIQUE index, so only real overrides are constrained.
    UNIQUE (series_id, recurrence_instance_date)
) STRICT;

-- `calendar_events.recurrence_end_date` is a STORED generated column
-- (see the column definition above) — SQLite recomputes it on every
-- INSERT/UPDATE atomically with the row write, so the previous AFTER
-- INSERT/UPDATE trigger pair (and its 4-way duplication of the same
-- CASE expression) is no longer needed. The same correctness arguments
-- apply: writers can supply any value and SQLite always overrides;
-- malformed JSON falls through to NULL so `expand_row_for_range`
-- handles the surfacing at query time; the timeline pruning
-- predicate compares ISO `YYYY-MM-DD` like-for-like because the
-- generated CASE normalizes RFC 5545 BASIC DATE / DATE-TIME forms to
-- the hyphenated date prefix.

CREATE TABLE IF NOT EXISTS calendar_subscriptions (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    url        TEXT NOT NULL,
    color      TEXT,
    enabled    INTEGER NOT NULL DEFAULT 1
               CHECK (enabled IN (0, 1)),
    version    TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    -- generated normalized form of `url` used as the
    -- dedup key. The normalization is intentionally lightweight —
    -- pure SQLite string ops, no IRI/RFC 3986 parser — because the
    -- expression has to be deterministic and synchronous for
    -- `GENERATED ALWAYS AS (...) STORED` to be reproducible across
    -- writers. The pipeline:
    --
    --   1. lower-case the entire URL (host case-insensitivity per
    --      RFC 3986 §3.2.2; we accept the path-case folding as
    --      acceptable collateral — distinct paths that differ only
    --      in case are vanishingly rare on calendar publishers and
    --      the dedup goal outweighs the false-positive risk).
    --   2. strip the default `:80` and `:443` ports so a publisher
    --      that emits a verbose port doesn't shadow the bare-host
    --      form of the same feed.
    --   3. trim a trailing `/` so `…/cal.ics` and `…/cal.ics/`
    --      collide.
    --
    -- Heavier normalization (percent-encoding canonicalization,
    -- query-parameter sort) is intentionally not performed at the
    -- schema layer: the generated-column approach trades a small
    -- false-negative window for a hard schema-level dedup contract
    -- that survives every writer (Tauri, MCP, sync-replay, CLI,
    -- tests).
    -- Normalize the default-port suffix even when no path segment
    -- follows. A bare `replace(':443/', '/')` only matches when the
    -- port is followed by a path slash, so `https://example.com:443`
    -- (no path) would survive unnormalized and collide with the
    -- canonical `https://example.com` form on the UNIQUE index,
    -- doubling the fetch cadence for the same feed.
    --
    -- A naive `replace(':443', '')` is unsafe because the substring
    -- can appear inside a path segment (`/api/v:443/foo`), and
    -- `replace(':80', '')` would falsely match the prefix of `:8080`
    -- (`https://example.com:8080/path` → `https://example.com80/path`).
    --
    -- Instead, append a sentinel `/` to the input so every authority
    -- ends in `/` and the existing `:443/` / `:80/` token strips
    -- cover the no-path case uniformly. The trailing `rtrim('/')`
    -- drops the sentinel along with any pre-existing trailing slash
    -- so `https://example.com:443`, `https://example.com:443/`, and
    -- `https://example.com` all converge on `https://example.com`.
    --
    -- Steps (innermost → outermost):
    --   1. lower(url) — case-fold authority + scheme.
    --   2. lower(url) || '/' — append sentinel.
    --   3. replace(':443/', '/') — strip default https port (path or sentinel).
    --   4. replace(':80/', '/')  — strip default http port (path or sentinel).
    --   5. rtrim('/') — drop the sentinel + any trailing path slash.
    url_normalized TEXT GENERATED ALWAYS AS (
        rtrim(
            replace(
                replace(lower(url) || '/', ':443/', '/'),
                ':80/', '/'
            ),
            '/'
        )
    ) STORED
) STRICT;

-- Schema-level UNIQUE on the normalized URL form. A bare TEXT
-- column would accept two rows that point at the same ICS publisher
-- (e.g. `https://Example.com/cal.ics` and
-- `https://example.com/cal.ics/`), doubling the fetch cadence and
-- producing duplicate `provider_calendar_events` writes whose
-- composite PK would conflict on every refresh.
CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_subscriptions_url_normalized
    ON calendar_subscriptions(url_normalized);

CREATE TABLE IF NOT EXISTS preferences (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    version    TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

-- Creation time is not stored as a column: it is recoverable from the
-- `created_at` of the first `upsert` row in `memory_revisions` for this memory's
-- `key`, but only best-effort while that first upsert revision is retained
-- (revision retention keeps N-per-key and deletes the oldest first, so it may
-- GC that first row on older databases).
CREATE TABLE IF NOT EXISTS memories (
    -- Opaque, sync-stable row identity (UUIDv7, minted via
    -- `EntityID.newEntityIDString()` at row creation). This — never `key` — is
    -- the outbound sync-envelope routing id and therefore the provider-visible
    -- remote row identity when a future provider-backed sync transport exists.
    -- Decoupling identity from `key` keeps a human/AI-chosen memory title
    -- (which may name a person) out of routing metadata; the title travels only
    -- inside the encrypted `content`-carrying payload, like the memory body
    -- itself.
    id         TEXT PRIMARY KEY,
    -- Human/AI-authored section title and the addressable identifier the MCP
    -- tools (get/write/delete_memory) look memories up by — hence UNIQUE, so
    -- `WHERE key = ?` stays a fast exact-match lookup. Being a secondary UNIQUE
    -- on a synced table, two devices creating the SAME key offline mint two
    -- different `id`s; the inbound collision CONVERGES via `ApplyMemoryMerge`
    -- (min-id wins, loser tombstoned + redirected), mirroring the
    -- `calendar_subscriptions.url_normalized` merge — it is never a bare UNIQUE
    -- that would batch-wedge the inbound sync page.
    key        TEXT NOT NULL UNIQUE,
    content    TEXT NOT NULL,
    version    TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS memory_revisions (
    id TEXT PRIMARY KEY,                 -- UUIDv7
    memory_key TEXT NOT NULL,
    content TEXT,                         -- NULL for delete operations
    operation TEXT NOT NULL
              CHECK (operation IN ('upsert', 'delete', 'restore')),
    source_revision_id TEXT,              -- non-null for restore (points to the revision being restored from)
    actor TEXT NOT NULL DEFAULT 'ai',     -- 'ai' | 'human'
    version TEXT NOT NULL,                -- HLC
    created_at TEXT NOT NULL,
    CHECK (actor IN ('ai', 'human')),
    -- Restore provenance: a 'restore' revision must name the revision it
    -- reinstates from. 'upsert' / 'delete' leave `source_revision_id` NULL.
    CHECK (operation <> 'restore' OR source_revision_id IS NOT NULL)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_memory_revisions_key_created
    ON memory_revisions (memory_key, created_at DESC);

-- Day-scoped aggregates: canonical timezone anchors day identity.
CREATE TABLE IF NOT EXISTS daily_reviews (
    date         TEXT PRIMARY KEY,
    summary      TEXT NOT NULL,
    mood         INTEGER,
    energy_level INTEGER,
    wins         TEXT,
    blockers     TEXT,
    learnings    TEXT,
    ai_synthesis TEXT,
    timezone     TEXT,
    version      TEXT NOT NULL,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    CHECK (mood IS NULL OR (mood >= 1 AND mood <= 5)),
    CHECK (energy_level IS NULL OR (energy_level >= 1 AND energy_level <= 5))
) STRICT;

CREATE TABLE IF NOT EXISTS current_focus (
    date       TEXT PRIMARY KEY,
    briefing   TEXT,
    timezone   TEXT,
    version    TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS focus_schedule (
    date       TEXT PRIMARY KEY,
    rationale  TEXT,
    timezone   TEXT,
    version    TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

-- ── B. Relation Edges (synced, composite natural key) ───────────────

CREATE TABLE IF NOT EXISTS task_tags (
    task_id    TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    tag_id     TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    version    TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (task_id, tag_id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_task_tags_tag ON task_tags(tag_id);

CREATE TABLE IF NOT EXISTS task_dependencies (
    task_id            TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    version            TEXT NOT NULL,
    created_at         TEXT NOT NULL,
    PRIMARY KEY (task_id, depends_on_task_id),
    CHECK (task_id != depends_on_task_id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_task_deps_depends_on ON task_dependencies(depends_on_task_id);

CREATE TABLE IF NOT EXISTS task_calendar_event_links (
    task_id           TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    calendar_event_id TEXT NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
    version           TEXT NOT NULL,
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL,
    PRIMARY KEY (task_id, calendar_event_id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_task_calendar_event_links_event ON task_calendar_event_links(calendar_event_id);

CREATE TABLE IF NOT EXISTS habit_completions (
    habit_id       TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    completed_date TEXT NOT NULL,
    -- A completion count is always positive: every first-party writer clamps to
    -- >= 1 and a count reaching 0 deletes the row. The CHECK is the last-line
    -- defense so a malformed peer envelope or hand-rolled fixture cannot land a
    -- non-positive count the streak / adherence math would then divide against.
    value          INTEGER NOT NULL DEFAULT 1 CHECK (value > 0),
    note           TEXT,
    version        TEXT NOT NULL,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL,
    PRIMARY KEY (habit_id, completed_date)
) STRICT;

-- ── C. Parent-Owned Collections (local materializations, not synced) ─

-- Parent-owned materializations: rebuilt from parent aggregate payloads.
-- Child refs (task_id, list_id) are soft references — no FK constraint.
-- The parent aggregate owns canonical truth; referenced entities may not
-- exist locally yet during sync apply. Parent FK (date) is kept for CASCADE.

CREATE TABLE IF NOT EXISTS current_focus_items (
    date     TEXT NOT NULL REFERENCES current_focus(date) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    task_id  TEXT NOT NULL,
    PRIMARY KEY (date, position)
) STRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_focus_items_date_task ON current_focus_items(date, task_id);
CREATE INDEX IF NOT EXISTS idx_focus_items_task ON current_focus_items(task_id);

CREATE TABLE IF NOT EXISTS focus_schedule_blocks (
    schedule_date TEXT NOT NULL REFERENCES focus_schedule(date) ON DELETE CASCADE,
    position      INTEGER NOT NULL,
    block_type    TEXT NOT NULL CHECK (block_type IN ('task', 'buffer', 'event')),
    start_time    INTEGER NOT NULL,
    end_time      INTEGER NOT NULL,
    task_id       TEXT,
    event_id      TEXT,
    title         TEXT,
    -- Lock the minute-of-day contract: start/end are minutes from midnight in
    -- [0,1440] with end >= start. Both live writers already enforce this; the
    -- CHECK is the last-line defense so a malformed peer envelope or hand-rolled
    -- fixture cannot land a row the timeline projector would then dereference.
    CHECK (start_time >= 0 AND end_time >= start_time AND end_time <= 1440),
    -- enforce the (block_type, task_id, event_id)
    -- consistency at the schema level so a malformed peer envelope or
    -- hand-rolled fixture can't land a row that the timeline projector
    -- would then dereference. The application-level write helpers
    -- already obey this contract; the CHECK is the last-line defense
    -- for future writers that don't go through those helpers.
    --   - block_type='task'   → task_id NOT NULL, event_id NULL
    --   - block_type='event'  → task_id NULL (event_id optional —
    --       MCP `save_focus_schedule` accepts freeform "event" blocks
    --       that carry just a title for items not synced from a
    --       calendar provider, e.g. "Lunch")
    --   - block_type='buffer' → both NULL
    CHECK (
      (block_type = 'task'   AND task_id IS NOT NULL AND event_id IS NULL)
      OR (block_type = 'event'  AND task_id IS NULL)
      OR (block_type = 'buffer' AND task_id IS NULL AND event_id IS NULL)
    ),
    PRIMARY KEY (schedule_date, position)
) STRICT;

CREATE TABLE IF NOT EXISTS calendar_event_attendees (
    event_id TEXT NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
    -- Stable per-attendee identity, synthesized deterministically from the
    -- attendee's identifying fields: an `email:`-prefixed lowercased CAL-ADDRESS
    -- email when present, else a `name:`-prefixed lowercased display name, else
    -- an `anon:`-prefixed content hash (the first 8 bytes of the SHA-256 of the
    -- attendee entry's canonical JSON, as 16 lowercase hex chars) for a fully
    -- anonymous attendee. Keying on this instead of the email lets a name-only
    -- attendee (empty email) materialize instead of dropping the whole event,
    -- and keeps two distinct name-only attendees from collapsing onto a shared
    -- empty-email key. The anonymous fallback hashes content rather than the
    -- attendee's array index because the outbound array is emitted
    -- `ORDER BY attendee_id`, so an index would shift whenever a keyed peer
    -- sorts around it; hashing the content keeps the id stable across re-emit.
    -- Device-local: re-synthesized on every apply, never carried on the wire.
    attendee_id TEXT NOT NULL,
    email    TEXT NOT NULL,
    name     TEXT,
    -- the canonical RFC 5545 PARTSTAT subset is the single source of
    -- truth at every write surface (the domain attendee-status
    -- allowlist). The schema CHECK is the last-line defense so a
    -- forked builder or a direct SQL writer cannot land an off-canon
    -- value. The hyphen form `needs-action` matches RFC 5545
    -- spelling; the underscore variant is rejected at write, sync
    -- apply, and import boundaries instead of being repaired on read.
    status   TEXT CHECK (status IS NULL OR status IN (
                   'accepted', 'declined', 'tentative', 'needs-action'
               )),
    PRIMARY KEY (event_id, attendee_id)
) STRICT;

-- Weekday set for a 'weekly' habit, materialized from the weekday array carried
-- inside the habit's own sync payload. Parent-owned: the applier rebuilds these
-- rows (delete-then-insert keyed by habit_id) after every habit upsert, exactly
-- like `calendar_event_attendees`. It is NOT an independently-synced entity —
-- no `version` column, no dispatch-table handler, no convergence merge; a habit
-- merge simply drops the loser's rows via ON DELETE CASCADE while the winner
-- keeps the rows its own payload rebuilt. `weekday` uses the Monday-first
-- convention 0=Mon … 6=Sun (matching the domain `WeekDay` enum). An empty set
-- (no rows) means the weekly habit is scheduled every day.
CREATE TABLE IF NOT EXISTS habit_weekdays (
    habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    weekday  INTEGER NOT NULL CHECK (weekday BETWEEN 0 AND 6),
    PRIMARY KEY (habit_id, weekday)
) STRICT;

-- EXDATE child tables for the two canonical recurring entities.
--
-- The recurrence-exceptions list is normalized into per-date rows
-- rather than a JSON array on the owning row
-- (`tasks.recurrence_exceptions` / `calendar_events.recurrence_exceptions`).
-- That makes every membership check (EXDATE filter during timeline
-- expansion, duplicate-on-add validation, undo restore) a primary-key
-- equality probe instead of a JSON parse, and avoids rewriting an
-- entire blob via LWW UPDATE on each mutation. Ad-hoc reads via
-- correlated `json_group_array` subqueries still yield the wire-form
-- JSON the sync envelope expects without storing it twice.
--
-- `ON DELETE CASCADE` keeps the registries consistent with the
-- owning entity's lifecycle. Composite PK `(<owner_id>,
-- exception_date)` blocks duplicate EXDATEs at the schema layer.
CREATE TABLE IF NOT EXISTS task_recurrence_exceptions (
    task_id        TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    exception_date TEXT NOT NULL,
    PRIMARY KEY (task_id, exception_date)
) STRICT;

CREATE TABLE IF NOT EXISTS calendar_event_recurrence_exceptions (
    event_id       TEXT NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
    exception_date TEXT NOT NULL,
    PRIMARY KEY (event_id, exception_date)
) STRICT;

-- per-attendee forward-compat shadow.
--
-- `calendar_event_attendees` stores only the known fields `email`, `name`,
-- `status`. A newer peer may emit additional per-attendee keys (e.g.
-- `role`, `rsvp_deadline`). Without preservation, the local apply path
-- extracts the known columns and rebuilds the parent `attendees` array
-- from the DB on the next outbound enqueue, silently erasing anything
-- the current schema doesn't know about. This table carries the
-- unknown-per-attendee extras across re-echo so a mixed-version peer
-- mesh round-trips them without drop.
--
-- Mirrors the aggregate-level `sync_payload_shadow` pattern, scoped to
-- the one array that currently carries rich per-item payloads. If the
-- calendar schema later grows more nested object arrays with the same
-- forward-compat concern (e.g. `focus_schedule.blocks[*]`), generalize
-- this pattern rather than copying it per-array.
--
-- Rows are keyed by the same synthesized `attendee_id` as
-- `calendar_event_attendees` (see that table), so the extras join survives
-- empty and duplicate emails. `extra_fields_json` is a JSON object of
-- the surplus keys only — never the full attendee JSON — so the
-- on-re-echo merge stays side-effect-free if a future known field is
-- added to `calendar_event_attendees`.
CREATE TABLE IF NOT EXISTS calendar_event_attendee_shadow (
    event_id           TEXT NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
    attendee_id        TEXT NOT NULL,
    extra_fields_json  TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    PRIMARY KEY (event_id, attendee_id)
) STRICT;

-- `daily_review_task_links` and `daily_review_list_links`
-- are NOT primary state — they are projections rebuilt from the
-- canonical arrays embedded in the `daily_reviews` aggregate payload
-- (`linked_task_ids` / `linked_list_ids`). The rebuild is a full
-- delete-and-reinsert keyed by `review_date`, performed by
-- the daily-review link materializer after
-- every aggregate write (MCP create/update, sync apply, import,
-- payload_shadow merge). The `created_at` column is therefore not a
-- mutation-time anchor — it is set to "now" on each rebuild so the
-- ORDER BY in the aggregate link-id loader produces a stable
-- projected order; do not rely on it for audit history.
--
-- Consequences:
--   * No FK from `task_id` / `list_id` to their parent table — an
--     out-of-order sync apply may stage the link before the parent
--     materializes, and a concurrent hard-delete of the parent must
--     not retroactively fail the daily-review rebuild. Orphan drift
--     is surfaced via `error_logs` (`store.daily_review.materialize_*.orphan`).
--   * Direct INSERT / UPDATE of these tables outside `materialize_review_*_links`
--     will be silently overwritten on the next aggregate write; do not
--     mutate them as primary state.
--   * Sync envelopes never carry these tables — the aggregate
--     (`daily_review`) carries the arrays and apply rebuilds the
--     projection on the receiving device.
CREATE TABLE IF NOT EXISTS daily_review_task_links (
    review_date TEXT NOT NULL REFERENCES daily_reviews(date) ON DELETE CASCADE,
    task_id     TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    PRIMARY KEY (review_date, task_id)
) STRICT;

-- see `daily_review_task_links` above for the full
-- projection-rebuild contract; the same semantics apply here.
CREATE TABLE IF NOT EXISTS daily_review_list_links (
    review_date TEXT NOT NULL REFERENCES daily_reviews(date) ON DELETE CASCADE,
    list_id     TEXT NOT NULL,
    created_at  TEXT NOT NULL,
    PRIMARY KEY (review_date, list_id)
) STRICT;

-- ── D. Independent Child Entities (synced, own UUIDv7) ──────────────

CREATE TABLE IF NOT EXISTS task_reminders (
    id                  TEXT PRIMARY KEY,
    task_id             TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    reminder_at         TEXT NOT NULL,
    dismissed_at        TEXT,
    cancelled_at        TEXT,
    version             TEXT NOT NULL,
    created_at          TEXT NOT NULL,
    -- store the intended local wall-clock anchor so a
    -- later PREF_TIMEZONE change can re-materialize `reminder_at` and
    -- preserve "9 AM local" semantics. Both columns are nullable for
    -- rows migrated from the offset-delta era and for reminders whose
    -- anchor couldn't be resolved (no PREF_TIMEZONE set). `HH:MM` plus
    -- IANA zone name — we deliberately do NOT persist the calendar
    -- date here; the anchor date is derived from `reminder_at`
    -- interpreted in `original_tz` at re-anchor time.
    original_local_time TEXT,
    original_tz         TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS task_checklist_items (
    id           TEXT PRIMARY KEY,
    task_id      TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    position     INTEGER NOT NULL,
    text         TEXT NOT NULL,
    completed_at TEXT,
    version      TEXT NOT NULL,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS habit_reminder_policies (
    id            TEXT PRIMARY KEY,
    habit_id      TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    reminder_time TEXT NOT NULL,
    enabled       INTEGER NOT NULL DEFAULT 1
                  CHECK (enabled IN (0, 1)),
    version       TEXT NOT NULL,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL
) STRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_habit_reminder_policies_habit_time
    ON habit_reminder_policies(habit_id, reminder_time);

-- ── E. Local-Only State ─────────────────────────────────────────────

-- E.1 Durable overlays (survive restarts, included in device snapshot)

CREATE TABLE IF NOT EXISTS task_provider_event_links (
    task_id            TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    -- the canonical `provider_kind` allowlist lives in the domain
    -- layer; the schema CHECK is the last-line defense for direct SQL
    -- writers (calendar_subscription_sync, platform readers, future
    -- migrations) that bypass the IPC gates.
    -- Adding a new kind requires extending the domain const AND every
    -- CHECK list on `task_provider_event_links`,
    -- `provider_calendar_events`, and `provider_scope_runtime_state`.
    provider_kind      TEXT NOT NULL CHECK (provider_kind IN (
                           'eventkit',
                           'google_calendar',
                           'ical_subscription',
                           'ics',
                           'linux_ics',
                           'outlook',
                           'windows_appointments'
                       )),
    provider_scope     TEXT NOT NULL,
    provider_event_key TEXT NOT NULL,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    PRIMARY KEY (task_id, provider_kind, provider_scope, provider_event_key)
) STRICT;

-- E.2 Disposable caches (rebuildable from external sources)

CREATE TABLE IF NOT EXISTS provider_calendar_events (
    -- `provider_kind` shares the domain provider-kind allowlist.
    provider_kind      TEXT NOT NULL CHECK (provider_kind IN (
                           'eventkit',
                           'google_calendar',
                           'ical_subscription',
                           'ics',
                           'linux_ics',
                           'outlook',
                           'windows_appointments'
                       )),
    provider_scope     TEXT NOT NULL,
    provider_event_key TEXT NOT NULL,
    title              TEXT NOT NULL,
    description        TEXT,
    start_date         TEXT NOT NULL,
    start_time         TEXT,
    end_date           TEXT,
    end_time           TEXT,
    all_day            INTEGER NOT NULL DEFAULT 0
                       CHECK (all_day IN (0, 1)),
    location           TEXT,
    color              TEXT,
    recurrence         TEXT,
    recurrence_exceptions TEXT,
    -- derived UNTIL bound for the recurring leg of the
    -- timeline range query. Mirror of `calendar_events.recurrence_end_date`
    -- for the device-local provider mirror — STORED generated column so
    -- every provider-cache writer (eventkit/google/ICS sync, subscription
    -- refresh, tests) stays oblivious. Provider rows are especially
    -- vulnerable to RFC 5545 BASIC-format UNTIL because the ICS-import
    -- path (`calendar_subscription_sync`) writes provider rows directly
    -- without routing through `validate_recurrence_canonical`, so an
    -- upstream feed carrying `UNTIL=20141231T235959Z` would land here
    -- verbatim — the CASE normalizes those forms to the same hyphenated
    -- date prefix the timeline pruning predicate compares against.
    -- NULL means unbounded or COUNT-bounded.
    recurrence_end_date TEXT GENERATED ALWAYS AS (
      CASE
        WHEN recurrence IS NULL THEN NULL
        WHEN NOT json_valid(recurrence) THEN NULL
        WHEN json_extract(recurrence, '$.UNTIL') IS NULL THEN NULL
        WHEN json_extract(recurrence, '$.UNTIL') LIKE '____-__-__' THEN
             json_extract(recurrence, '$.UNTIL')
        WHEN json_extract(recurrence, '$.UNTIL') LIKE '____-__-__T%' THEN
             substr(json_extract(recurrence, '$.UNTIL'), 1, 10)
        WHEN length(json_extract(recurrence, '$.UNTIL')) = 8 THEN
             substr(json_extract(recurrence, '$.UNTIL'), 1, 4) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 5, 2) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 7, 2)
        WHEN length(json_extract(recurrence, '$.UNTIL')) = 16
             AND substr(json_extract(recurrence, '$.UNTIL'), 9, 1) = 'T' THEN
             substr(json_extract(recurrence, '$.UNTIL'), 1, 4) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 5, 2) || '-' ||
             substr(json_extract(recurrence, '$.UNTIL'), 7, 2)
        ELSE NULL
      END
    ) STORED,
    event_type         TEXT NOT NULL DEFAULT 'event',
    person_name        TEXT,
    timezone           TEXT,
    source_time_kind   TEXT NOT NULL DEFAULT 'floating'
                       CHECK (source_time_kind IN ('floating', 'utc', 'tzid')),
    source_tzid        TEXT,
    organizer_email    TEXT,
    video_call_url     TEXT,
    -- JSON array of `[{"email":"…","name":"…","status":"accepted"}]`.
    -- Stored canonically so projection + diff stays deterministic.
    attendees_json     TEXT,
    last_seen_at       TEXT NOT NULL,
    last_refreshed_at  TEXT NOT NULL,
    -- mirror the `event_type` allowlist on the canonical
    -- `calendar_events` table. Without it a malformed
    -- provider write (or a future ICS extension) could land an
    -- unrecognized value here and escape the read-time projection's
    -- assumption that `event_type` is one of four known kinds.
    CHECK (event_type IN ('event', 'birthday', 'anniversary', 'memorial')),
    PRIMARY KEY (provider_kind, provider_scope, provider_event_key)
) STRICT;

-- `provider_calendar_events.recurrence_end_date` is a STORED generated
-- column (see column definition above) — same rationale as
-- `calendar_events.recurrence_end_date`: SQLite recomputes atomically
-- on every INSERT/UPDATE, eliminating the AFTER-trigger second-write
-- pass and the 4-way duplication of the same CASE expression.

-- E.3 Runtime state (checkpoints, delivery, diagnostics)

CREATE TABLE IF NOT EXISTS device_state (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS task_reminder_delivery_state (
    reminder_id    TEXT PRIMARY KEY REFERENCES task_reminders(id) ON DELETE CASCADE,
    last_fired_at  TEXT,
    last_notified_at TEXT,
    delivery_state TEXT NOT NULL DEFAULT 'pending'
                   CHECK (delivery_state IN ('pending', 'delivered')),
    last_error     TEXT,
    updated_at     TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS habit_reminder_delivery_state (
    policy_id        TEXT PRIMARY KEY REFERENCES habit_reminder_policies(id) ON DELETE CASCADE,
    last_fired_at    TEXT,
    updated_at       TEXT NOT NULL
) STRICT;

-- Vocabulary for `availability_state` and `last_refresh_result` is
-- pinned by the provider-scope writers and the refresh-error
-- recorder. Adding a new provider category requires extending both
-- CHECK lists here — coupled deliberately so the UI state machine
-- stays closed.
CREATE TABLE IF NOT EXISTS provider_scope_runtime_state (
    -- `provider_kind` shares the domain provider-kind allowlist.
    provider_kind          TEXT NOT NULL CHECK (provider_kind IN (
                               'eventkit',
                               'google_calendar',
                               'ical_subscription',
                               'ics',
                               'linux_ics',
                               'outlook',
                               'windows_appointments'
                           )),
    provider_scope         TEXT NOT NULL,
    enabled                INTEGER NOT NULL DEFAULT 1
                           CHECK (enabled IN (0, 1)),
    availability_state     TEXT NOT NULL DEFAULT 'enabled'
                           CHECK (availability_state IN (
                               'enabled',
                               'disabled',
                               'permission_denied',
                               'authorization_error',
                               'fetch_error',
                               'parse_error'
                           )),
    last_refresh_attempt_at TEXT,
    last_refresh_success_at TEXT,
    last_refresh_result    TEXT
                           CHECK (last_refresh_result IS NULL OR last_refresh_result IN (
                               'success',
                               'permission_denied',
                               'authorization_error',
                               'fetch_error',
                               'parse_error'
                           )),
    last_error             TEXT,
    -- Earliest RFC3339 UTC timestamp at which a refresh may next be
    -- attempted. Written from a server-provided Retry-After header on
    -- HTTP 429 responses so we honor the provider's rate-limit hint
    -- instead of retrying on the application layer's generic 60-minute poll.
    -- NULL means "no cooldown — attempt allowed now".
    next_attempt_at        TEXT,
    PRIMARY KEY (provider_kind, provider_scope)
) STRICT;

CREATE TABLE IF NOT EXISTS error_logs (
    id         TEXT PRIMARY KEY,
    source     TEXT NOT NULL,
    level      TEXT NOT NULL DEFAULT 'error'
               CHECK (level IN ('debug', 'info', 'warn', 'error')),
    message    TEXT NOT NULL,
    details    TEXT,
    created_at TEXT NOT NULL
) STRICT;

-- ── F. Sync Infrastructure ──────────────────────────────────────────

-- the two version-shaped columns on this row carry
-- DIFFERENT semantics. `version` (TEXT) is the per-entity HLC stamp
-- used by every LWW comparison on the apply side — one logical value
-- per row, sortable lexicographically. `payload_schema_version`
-- (INTEGER) is the envelope-format generation tag the sync apply
-- pipeline uses to gate forward-compatible payload shape changes;
-- it bumps once per cross-cutting schema migration, not per write.
-- The names look similar but they answer different questions ("which
-- write wins this row?" vs. "can my apply pipeline parse this
-- envelope?"); keep them distinct in code (don't fold one into the
-- other on read) and don't compare them with the same operators.
CREATE TABLE IF NOT EXISTS sync_outbox (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type            TEXT NOT NULL,
    entity_id              TEXT NOT NULL,
    operation              TEXT NOT NULL
                           CHECK (operation IN ('upsert', 'delete')),
    version                TEXT NOT NULL,
    payload_schema_version INTEGER NOT NULL,
    payload                TEXT NOT NULL,
    device_id              TEXT NOT NULL,
    created_at             TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    synced_at              TEXT,
    retry_count            INTEGER NOT NULL DEFAULT 0,
    last_retry_at          TEXT,
    -- Per-row error history. Storing only the most recent failure
    -- string in the global `sync_checkpoints.last_error` key would
    -- let every subsequent failure on any row overwrite it; the
    -- retry loop then could not detect a stuck-in-place failure
    -- (same error N times = strong evidence of a permanent failure
    -- like malformed payload / schema mismatch) and would waste 10
    -- retry cycles
    -- on each. `record_retry` now writes the row's error here and
    -- compares to the previous value to escalate fast-fail.
    last_error             TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS sync_tombstones (
    entity_type          TEXT NOT NULL,
    entity_id            TEXT NOT NULL,
    version              TEXT NOT NULL,
    deleted_at           TEXT NOT NULL,
    redirect_entity_id   TEXT,
    redirect_entity_type TEXT,
    PRIMARY KEY (entity_type, entity_id)
) STRICT;

CREATE TABLE IF NOT EXISTS sync_checkpoints (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS sync_device_cursors (
    device_id            TEXT PRIMARY KEY,
    last_sync_at         TEXT NOT NULL,
    last_applied_version TEXT
) STRICT;

-- `resolution_type` mirrors the canonical resolution-type constants
-- in the domain layer. Extending this enum requires editing both the
-- constant set AND this CHECK list —
-- the Settings → Diagnostics → Sync Conflicts filter dropdown
-- does a DISTINCT query on this column and would otherwise leak
-- rogue values into the UI.
CREATE TABLE IF NOT EXISTS sync_conflict_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type     TEXT NOT NULL,
    entity_id       TEXT NOT NULL,
    winner_version  TEXT NOT NULL,
    loser_version   TEXT NOT NULL,
    loser_device_id TEXT NOT NULL,
    loser_payload   TEXT,
    resolved_at     TEXT NOT NULL,
    resolution_type TEXT NOT NULL
                    CHECK (resolution_type IN (
                        'lww',
                        'tag_merge',
                        'recurrence_dedup',
                        'fk_stalled',
                        'fk_unresolved',
                        'reseed_required',
                        'pending_inbox_exhausted',
                        'cycle_break',
                        -- memory + aggregate free-text:
                        -- inbound aggregate payload truncated at apply
                        -- because it exceeded a domain byte/char cap.
                        'content_truncated',
                        -- a delete envelope arrived for a
                        -- merge loser; the delete was dropped rather than
                        -- propagating to the merge winner.
                        'redirected_delete_dropped',
                        -- an upsert envelope was rejected
                        -- because the local tombstone is newer (or
                        -- equal-versioned). Logged here so the
                        -- skip is auditable in the diagnostics
                        -- surface (which only displays
                        -- conflict_log entries).
                        'tombstone_wins',
                        -- a forward-compat payload shadow was
                        -- reaped during promote_payload_shadows
                        -- because the live local row is strictly
                        -- newer than the shadow's base_version.
                        -- Logged so the shadow's preserved unknown
                        -- fields are not silently dropped by the
                        -- SQL `>=` gate without any conflict_log
                        -- entry.
                        'shadow_obsolete',
                        -- a calendar_event payload
                        -- contained two or more attendee entries that
                        -- collided after `trim().to_lowercase()` email
                        -- normalization. The apply pipeline keeps a
                        -- single deterministic winner (chosen by
                        -- lexicographically-smallest canonical JSON of
                        -- the entry) and logs one row per dropped
                        -- attendee so the audit surface names exactly
                        -- which attendee metadata was lost.
                        'attendee_email_collision',
                        -- a payload-shadow merge whose
                        -- redirect crosses two different entity types
                        -- (e.g. task -> memory) cannot safely re-home
                        -- the loser's forward-compat unknown-key
                        -- payload across the schema boundary; the
                        -- shadow is dropped and an entry is logged
                        -- here so the conflict surface sees it
                        -- alongside other merge outcomes.
                        'cross_type_redirect_drop',
                        -- an upsert envelope was strictly
                        -- newer than a local delete tombstone, so the
                        -- apply pipeline removed the tombstone and
                        -- applied the upsert (concurrent-update wins
                        -- over concurrent-delete). Logged on both the
                        -- non-redirect and redirect-target branches so
                        -- an operator looking at "why did this
                        -- previously-deleted entity reappear?" sees
                        -- an audit trail in Settings → Diagnostics.
                        -- Without this entry, the upsert-wins-over-
                        -- delete branch would silently undo a real
                        -- DELETE the cluster had agreed on while
                        -- every other LWW outcome wrote a
                        -- conflict_log row.
                        'upsert_wins_over_delete',
                        -- a `task` upsert whose payload `list_id` is
                        -- tombstoned on this device rehomed to
                        -- inbox/oldest (the per-device resolveListId
                        -- fallback), so the receiver re-emitted a
                        -- fresh-HLC snapshot to converge peers. This
                        -- is the ONE-SHOT dedup ledger for that
                        -- re-emit, keyed by (entity_id, payload
                        -- list_id) in (entity_id, loser_version): it
                        -- bounds the mutual-tombstone ping-pong to one
                        -- re-emit per side so two devices with crossed
                        -- fallback targets cannot flap forever.
                        'list_fallback_reemit'
                    ))
) STRICT;

CREATE TABLE IF NOT EXISTS sync_pending_inbox (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    envelope              TEXT NOT NULL,
    reason                TEXT NOT NULL,
    missing_entity_type   TEXT,
    missing_entity_id     TEXT,
    -- identity columns extracted from the envelope at
    -- insert time so repeated deliveries of the same envelope coalesce
    -- via the UNIQUE index below. Without this, each redelivery (e.g.
    -- a sync provider replaying a record after a transient pull failure,
    -- or apply_envelope being called twice on a deferred envelope) wrote
    -- a fresh row with `attempt_count = 1`, defeating the attempt
    -- cap that's the inbox's stuck-envelope safety net.
    envelope_entity_type  TEXT NOT NULL,
    envelope_entity_id    TEXT NOT NULL,
    envelope_version      TEXT NOT NULL,
    first_attempted_at    TEXT NOT NULL,
    last_attempted_at     TEXT NOT NULL,
    attempt_count         INTEGER NOT NULL DEFAULT 1,
    -- Cache the most recent error message for each entry so the
    -- drain's Err branch only writes a fresh `error_logs` row when
    -- the failure mode changes. Without this de-duplication, every
    -- drain cycle for a permanently-erroring entry would write the
    -- same error_logs row, growing the diagnostic feed for the
    -- full FULL_RESYNC_HORIZON_DAYS even though the user can act on
    -- a single occurrence. Mirrors the outbox's same-error
    -- escalation. NULL until the first error is observed; an
    -- Ok(Deferred) drain leaves it untouched.
    last_error            TEXT
) STRICT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_pending_inbox_envelope_identity
    ON sync_pending_inbox(envelope_entity_type, envelope_entity_id, envelope_version);

-- Poison-envelope blocklist for the pending inbox.
--
-- An entry here means a previous attempt to enqueue or drain the
-- envelope identity `(entity_type, entity_id, version)` exhausted the
-- per-row retry budget and was promoted to an EXHAUSTED conflict.
-- Without this blocklist, a peer that keeps redelivering the same
-- poison identity (e.g. provider retries against an envelope whose
-- FK target was GC'd before delivery) would re-enter the pending
-- inbox, increment `attempt_count` from 1 again, and ping-pong the
-- exhausted-conflict logger forever — producing one new conflict
-- row per redelivery instead of converging.
--
-- `enqueue_pending` short-circuits to `Ok(())` for any envelope
-- identity present here, so the caller's apply path treats it as
-- benignly skipped. Entries are GC'd alongside the pending inbox
-- horizon so a future replay (e.g. after a full reseed lands the
-- missing FK target) is not blocked indefinitely.
CREATE TABLE IF NOT EXISTS sync_quarantine_blocklist (
    entity_type   TEXT NOT NULL,
    entity_id     TEXT NOT NULL,
    version       TEXT NOT NULL,
    quarantined_at TEXT NOT NULL,
    PRIMARY KEY (entity_type, entity_id, version)
) STRICT;
CREATE INDEX IF NOT EXISTS idx_sync_quarantine_blocklist_quarantined_at
    ON sync_quarantine_blocklist(quarantined_at);

-- `updated_at` on every local-only runtime table is an
-- epoch-millisecond INTEGER, not a TEXT string. The CAS guard in
-- `claim_mcp_host_authority` and the diagnostic timestamp on
-- `local_sync_owner` rely on numeric ordering. Storing as TEXT silently
-- lex-compared (works only while every digit count matches; breaks at
-- year 2286 / on width drift / on whitespace). INTEGER columns force
-- SQLite to compare numerically end-to-end.

-- Used by the Tauri consumer only; the Apple app coordinates app↔MCP-host
-- differently.
CREATE TABLE IF NOT EXISTS local_sync_owner (
    lease_name          TEXT PRIMARY KEY,
    owner_id            TEXT NOT NULL,
    expires_at_epoch_ms INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL
) STRICT;

-- integer counters live in their own table so the bump path is
-- `value = value + 1` against an INTEGER column instead of
-- round-tripping through TEXT and CAST. A generic key/value table
-- would force `CAST(CAST(value AS INTEGER) + 1 AS TEXT)`, which
-- truncates silently on 64-bit overflow and resets the counter to 0
-- on corrupt-input parse failures — both breaking monotonicity.
CREATE TABLE IF NOT EXISTS local_counters (
    name       TEXT PRIMARY KEY,
    value      INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
) STRICT;

-- MCP host authority is its own row with a typed
-- `priority` column so adding a new MCP_HOST_KIND in the future doesn't
-- silently re-shuffle the same-millisecond tiebreak via lex compare on
-- `value`. The CAS predicate now uses (priority, updated_at) rather
-- than (updated_at, value lex). The table is a singleton — `id = 1`
-- enforced by CHECK so concurrent writers can't accidentally shard
-- the row across multiple identities.
--
-- Used by the Tauri consumer only; the Apple app coordinates app↔MCP-host
-- differently.
CREATE TABLE IF NOT EXISTS mcp_host_authority (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    host       TEXT NOT NULL CHECK (host IN ('app', 'cli')),
    priority   INTEGER NOT NULL,
    host_path  TEXT,
    updated_at INTEGER NOT NULL
) STRICT;

-- ── G. Syncable Audit Stream ────────────────────────────────────────

-- export classifies rows as AI-originated via
-- `WHERE initiated_by NOT IN ('human','system','user','manual')`.
-- The structural CHECKs below (non-empty, trimmed) prevent whitespace
-- variants like 'claude ' / '  gpt-4' from leaking through as distinct
-- AI identities. The operation/entity_type vocabularies grow over
-- time with new MCP tools, so we enforce shape rather than a closed
-- allowlist.
CREATE TABLE IF NOT EXISTS ai_changelog (
    id               TEXT PRIMARY KEY,
    timestamp        TEXT NOT NULL
                     CHECK (length(timestamp) > 0),
    operation        TEXT NOT NULL
                     CHECK (
                         length(operation) > 0
                         AND operation = trim(operation)
                     ),
    entity_type      TEXT NOT NULL
                     CHECK (
                         length(entity_type) > 0
                         AND entity_type = trim(entity_type)
                     ),
    entity_id        TEXT,
    summary          TEXT NOT NULL,
    initiated_by     TEXT NOT NULL DEFAULT 'ai'
                     CHECK (
                         length(initiated_by) > 0
                         AND initiated_by = trim(initiated_by)
                     ),
    mcp_tool         TEXT,
    source_device_id TEXT,
    -- structured before/after JSON snapshots for update operations.
    -- NULL for rows written before this column existed, create
    -- operations (no prior state), delete operations (no post state),
    -- and any operation that does not explicitly capture state
    -- transitions. Payloads are serialized JSON objects capped at
    -- 4000 bytes each, with a trailing ellipsis marker when the full
    -- entity exceeds the cap.
    before_json      TEXT,
    after_json       TEXT,
    -- serialized MCP undo token JSON. Populated for destructive
    -- / bulk MCP writes that support revert (delete_list, delete_habit,
    -- batch_create_tasks, batch_update_tasks, set_preference). Stays
    -- NULL for MCP writes with no revert path and for rows produced
    -- by the Tauri app (which owns its own in-process undo cache).
    -- The token carries its own RFC3339 `expires_at` so the
    -- Changelog view's Undo button rejects stale tokens without a
    -- separate TTL column.
    undo_token       TEXT,
    -- Typed discriminator for preview audit rows. The contract is
    -- pinned structurally (rather than via `mcp_tool LIKE '%_preview'`
    -- string-matching, which would misclassify any future tool name
    -- with a literal `_preview` suffix). `is_preview = 1` for rows
    -- written by `write_preview_audit_entry` (dispatch_dry_run,
    -- import_preview, reorganize_list_preview); `is_preview = 0`
    -- for the canonical write path (`log_change_and_enqueue_sync`).
    -- Default 0 so existing readers don't have to special-case NULL.
    is_preview       INTEGER NOT NULL DEFAULT 0
                     CHECK (is_preview IN (0, 1))
) STRICT;

-- Per-changelog entity-id registry. Each batch / bulk MCP write that
-- touches N entities registers one row per entity here so per-entity
-- audit replay reduces to an indexed `(entity_id, changelog_id)` PK
-- seek. Normalizing into per-entity rows (rather than a JSON-array
-- TEXT column on `ai_changelog`) keeps every "show me everything
-- affecting task X" reader off a `json_each` scan of the full
-- changelog.
--
-- The wire-form JSON (`["task-1","task-2"]`) is rebuilt at read time
-- by the correlated `json_group_array` over an `entity_id`-ordered
-- subquery in the ai_changelog read path so payload builders,
-- exporters, and the Activity attribution reader all see the same
-- JSON shape.
--
-- PK is `(entity_id, changelog_id)` so the leftmost prefix serves the
-- per-entity attribution lookup directly. A secondary index keyed by
-- `changelog_id` covers the join used by the read-side subquery
-- (`WHERE changelog_id = ai_changelog.id`).
CREATE TABLE IF NOT EXISTS ai_changelog_entities (
    changelog_id TEXT NOT NULL REFERENCES ai_changelog(id) ON DELETE CASCADE,
    entity_id    TEXT NOT NULL,
    PRIMARY KEY (entity_id, changelog_id)
) STRICT;

-- ── Indexes ─────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at);
-- every hot read path against `tasks` filters
-- `archived_at IS NULL` (today/upcoming/overdue/list/search/tags/deferred).
-- Carrying that predicate as a partial-WHERE on the leading composite
-- indexes shrinks each index to the live rowset and lets the planner use
-- them without a residual `archived_at IS NULL` row-level filter. The
-- dedicated trash view path uses `idx_tasks_archived_at` and is unaffected.
CREATE INDEX IF NOT EXISTS idx_tasks_completed_at ON tasks(completed_at) WHERE status = 'completed' AND completed_at IS NOT NULL;
-- `priority_effective`-keyed siblings for the canonical `TASK_ORDER_BY`
-- (`priority_effective ASC, due_date ASC NULLS LAST, id ASC`), carrying the
-- same `archived_at IS NULL` partial as the priority-keyed siblings above.
--
-- These indexes do NOT satisfy `TASK_ORDER_BY` directly: an ascending index
-- stores NULLs FIRST, so the `due_date ASC NULLS LAST` leg (non-default null
-- placement) can never be served by the ascending index order — every read on
-- this key materializes a temporary B-tree sort. The indexes still earn their
-- place by narrowing to the live rowset via the leading `status` / `list_id`
-- columns and the `archived_at IS NULL` partial, so that sort runs over the
-- filtered set rather than the whole table; the trailing `id ASC` keeps the
-- tie-break deterministic within that sort.
CREATE INDEX IF NOT EXISTS idx_tasks_status_priority_effective_due
    ON tasks(status, priority_effective ASC, due_date ASC, id ASC) WHERE archived_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_list_status_priority_effective_due
    ON tasks(list_id, status, priority_effective ASC, due_date ASC, id ASC) WHERE archived_at IS NULL;
-- The due-date-leading partial scopes to non-null due dates so its natural
-- ASC ordering matches range/equality predicates without indexing the NULL
-- tail.
CREATE INDEX IF NOT EXISTS idx_tasks_due_status_priority_effective
    ON tasks(due_date ASC, status, priority_effective ASC)
    WHERE archived_at IS NULL AND due_date IS NOT NULL;
-- the two partial indexes cover the
-- get_tasks_by_date_range hot path with and without completed
-- tasks included. SQLite only uses a partial index when the query
-- predicate implies the index predicate, so we need both.
CREATE INDEX IF NOT EXISTS idx_tasks_action_date_open
    ON tasks(COALESCE(planned_date, due_date))
    WHERE status NOT IN ('cancelled', 'completed');
CREATE INDEX IF NOT EXISTS idx_tasks_action_date_non_cancelled
    ON tasks(COALESCE(planned_date, due_date))
    WHERE status != 'cancelled';
-- Partial indexes for the deferred-tasks read path (both the fetch
-- and the count query). Without these, the query falls back to
-- the broader status-anchored composite plus a TEMP B-TREE filesort
-- for the (defer_count DESC, id ASC) ORDER BY.
--
-- Two variants — one for the unscoped fetch and one keyed by
-- list_id — cover both call patterns. Each carries `status` as the
-- leading key column so the planner picks them up via the same
-- equality match it uses today for `idx_tasks_status_*`, and the
-- partial WHERE narrows the indexed rowset to the deferred subset
-- (typically a small fraction of all open tasks). `defer_count >= 1`
-- and `archived_at IS NULL` live in the partial predicate rather
-- than the key list because they're filters, not sort keys.
--
-- The middle key column intentionally omits `updated_at DESC`. The
-- runtime query also drops `updated_at` from its ORDER BY —
-- `updated_at` is HLC-rewritten on conflict resolution and not
-- stable across peer writes, so it's unsuitable as a pagination
-- tiebreaker. Carrying it in the index
-- columns would prevent SQLite from doing a strict index-only ordered
-- scan and force a sort despite the partial predicate. The
-- (status, defer_count DESC, id ASC) shape exactly matches the
-- query's ORDER BY so the planner can stream rows in order.
CREATE INDEX IF NOT EXISTS idx_tasks_deferred_open
    ON tasks(status, defer_count DESC, id ASC)
    WHERE defer_count >= 1 AND archived_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_deferred_open_by_list
    ON tasks(list_id, status, defer_count DESC, id ASC)
    WHERE defer_count >= 1 AND archived_at IS NULL;

-- Composite (timestamp DESC, id DESC) index lets the changelog read
-- paths use `id DESC` as a deterministic tiebreaker inside same-
-- millisecond timestamp clusters without losing the timestamp-DESC
-- seek + LIMIT optimization. Without the `id DESC` tiebreaker, two
-- rows that share a millisecond order non-deterministically, and
-- same-ms rows would silently drop on `WHERE timestamp > ?` polling
-- boundaries.
CREATE INDEX IF NOT EXISTS idx_changelog_timestamp ON ai_changelog(timestamp DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_entity ON ai_changelog(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_changelog_operation ON ai_changelog(operation);
-- the `(entity_id, changelog_id)` PK serves
-- the leftmost per-entity attribution lookup; the secondary index
-- below covers the inverse direction — the read-side correlated
-- subquery (`WHERE changelog_id = ai_changelog.id`) joining child
-- rows back into a JSON array. Without the secondary, that scan
-- would have to use the PK and seek by trailing-column equality.
CREATE INDEX IF NOT EXISTS idx_ai_changelog_entities_changelog
    ON ai_changelog_entities(changelog_id);

-- idx_daily_reviews_date removed: PK on (date) already serves as the index.
-- The daily_review_task_links / daily_review_list_links child tables are read
-- only by review_date (PK-served), so neither carries a reverse-lookup
-- secondary index on task_id / list_id (unlike current_focus_items, whose
-- task_id IS reverse-looked-up on task delete via idx_focus_items_task).

-- partial index on the unsynced subset. The canonical
-- get_pending query is `WHERE synced_at IS NULL AND retry_count < ?
-- ORDER BY id ASC`; `retry_count` rides as a trailing index column so
-- the entire predicate can be evaluated from the index without a
-- base-row read per candidate. The leading `id ASC` drives the FIFO
-- sort as an index walk, and the partial WHERE keeps the index narrow
-- (the unsynced subset is small relative to the synced history we
-- retain for diagnostics).
CREATE INDEX IF NOT EXISTS idx_sync_outbox_unsynced
    ON sync_outbox(id, retry_count) WHERE synced_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sync_outbox_entity ON sync_outbox(entity_type, entity_id);
-- DB-level enforcement of the single-unsynced-row-
-- per-entity coalescing invariant. The coalesced enqueue
-- runs SELECT → DELETE → INSERT on this table; without this UNIQUE
-- partial index two concurrent connections (Tauri main thread + MCP
-- server, or parallel MCP commands) could both pass the SELECT
-- guard, both DELETE (one is a no-op), and both INSERT — leaving
-- the table with two unsynced rows for the same entity. The
-- partial-WHERE keeps synced history
-- (rows with non-NULL `synced_at`) outside the constraint so the
-- audit trail of past push attempts remains intact.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_outbox_unsynced_per_entity
    ON sync_outbox(entity_type, entity_id) WHERE synced_at IS NULL;
-- The per-sync-cycle GC (`DELETE FROM sync_outbox WHERE synced_at
-- IS NOT NULL AND synced_at < cutoff`) prunes acknowledged history by
-- timestamp. The unsynced-subset partial indexes above cannot serve it
-- (they exclude exactly the rows it ranges over), so without a dedicated
-- synced_at index the GC full-scans the retained synced history every
-- cycle. The partial WHERE keeps this index to just the synced subset.
CREATE INDEX IF NOT EXISTS idx_sync_outbox_synced_at ON sync_outbox(synced_at) WHERE synced_at IS NOT NULL;
-- Indexes for focus-schedule and sync-tombstone hot paths.
CREATE INDEX IF NOT EXISTS idx_focus_schedule_blocks_task
    ON focus_schedule_blocks(task_id) WHERE task_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sync_tombstones_version
    ON sync_tombstones(version);
CREATE INDEX IF NOT EXISTS idx_sync_tombstones_deleted_at
    ON sync_tombstones(deleted_at);
CREATE INDEX IF NOT EXISTS idx_sync_conflict_log_resolved_at
    ON sync_conflict_log(resolved_at);
CREATE INDEX IF NOT EXISTS idx_sync_conflict_log_type_id
    ON sync_conflict_log(resolution_type, id DESC);

CREATE INDEX IF NOT EXISTS idx_calendar_events_start_date ON calendar_events(start_date);
CREATE INDEX IF NOT EXISTS idx_calendar_events_end_date ON calendar_events(end_date);
CREATE INDEX IF NOT EXISTS idx_calendar_events_range_start ON calendar_events(start_date, end_date, start_time);
-- partial index on `start_date` for recurring events.
-- The timeline query splits into two index-friendly legs (one for
-- recurrence-bearing rows, one for fixed-span rows); the recurring
-- leg uses this partial index so a calendar with thousands of
-- non-recurring single-day events doesn't force a full table scan
-- every time the timeline opens.
CREATE INDEX IF NOT EXISTS idx_calendar_events_recurring_start
    ON calendar_events(start_date) WHERE recurrence IS NOT NULL;
-- pruning index on the derived UNTIL bound. The timeline
-- recurring-leg predicate is now
--   recurrence IS NOT NULL
--   AND start_date <= ?2
--   AND (recurrence_end_date IS NULL OR recurrence_end_date >= ?1)
-- so a long-dead recurrence (UNTIL='2014-12-31') no longer scans through
-- every historical row whose start_date <= ?2. The partial filter keeps
-- the index small (one entry per recurring row, not per row in the
-- table) and the leading column is the bound itself so range pruning
-- by `recurrence_end_date >= ?1` lands on an index seek.
CREATE INDEX IF NOT EXISTS idx_calendar_events_recurring_end_date
    ON calendar_events(recurrence_end_date) WHERE recurrence IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_error_logs_created_at ON error_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_error_logs_source ON error_logs(source, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_task_reminders_due ON task_reminders(reminder_at) WHERE dismissed_at IS NULL AND cancelled_at IS NULL;
-- Compound key (task_id, reminder_at) so the per-task fetch's ORDER
-- BY reminder_at lands on an index walk instead of a TEMP B-TREE
-- filesort. Used by `enrich_tasks_with_reminders` (mcp-server's
-- task-detail enrichment, hot path in get_task / get_todays_tasks).
CREATE INDEX IF NOT EXISTS idx_task_reminders_task ON task_reminders(task_id, reminder_at ASC);
CREATE INDEX IF NOT EXISTS idx_task_checklist_items_task ON task_checklist_items(task_id, position);

CREATE INDEX IF NOT EXISTS idx_habit_completions_date ON habit_completions(habit_id, completed_date DESC);
CREATE INDEX IF NOT EXISTS idx_habit_completions_date_range ON habit_completions(completed_date DESC);

CREATE INDEX IF NOT EXISTS idx_tasks_planned_date ON tasks(planned_date) WHERE planned_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_available_from ON tasks(available_from) WHERE available_from IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_spawned_from ON tasks(spawned_from) WHERE spawned_from IS NOT NULL;
-- index the trash subset so the `empty_trash` purge
-- predicate (`archived_at < cutoff`) and the Trash view list query
-- hit an index instead of scanning the full tasks table. Partial
-- because the common case is "no archived rows". Compound key
-- (archived_at DESC, id ASC) covers the Trash view's full ORDER BY,
-- avoiding the TEMP B-TREE filesort that the prior single-column
-- shape needed for the (archived_at DESC, id ASC) sort.
CREATE INDEX IF NOT EXISTS idx_tasks_archived_at ON tasks(archived_at DESC, id ASC) WHERE archived_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sync_pending_inbox_missing ON sync_pending_inbox(missing_entity_type, missing_entity_id);
CREATE INDEX IF NOT EXISTS idx_sync_pending_inbox_drain ON sync_pending_inbox(last_attempted_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_sync_pending_inbox_first_attempted ON sync_pending_inbox(first_attempted_at);

-- Tag lookup by normalized name (hot path for MCP tag resolution)
CREATE INDEX IF NOT EXISTS idx_tags_lookup_key ON tags(lookup_key);

-- Provider calendar events: timeline range query hot path
CREATE INDEX IF NOT EXISTS idx_provider_events_start ON provider_calendar_events(start_date);
CREATE INDEX IF NOT EXISTS idx_provider_events_scope ON provider_calendar_events(provider_kind, provider_scope);
-- partial index on `start_date` for recurring provider
-- events (mirror of `idx_calendar_events_recurring_start`). Same
-- rationale: split the timeline query into index-friendly legs.
CREATE INDEX IF NOT EXISTS idx_provider_events_recurring_start
    ON provider_calendar_events(start_date) WHERE recurrence IS NOT NULL;
-- mirror of `idx_calendar_events_recurring_end_date` for
-- the provider mirror. Subscribed feeds frequently keep historical
-- recurring events that have long since expired (an old "Standup —
-- UNTIL 2018-06" rule that nobody removed); without this index the
-- timeline range query scans every one of them.
CREATE INDEX IF NOT EXISTS idx_provider_events_recurring_end_date
    ON provider_calendar_events(recurrence_end_date) WHERE recurrence IS NOT NULL;
-- Pair index on (start_date, end_date) for the fixed-span leg of
-- the timeline split. A start_date-only index would force the
-- planner to scan every row whose start_date <= ?2 and re-check
-- end_date in a residual filter.
CREATE INDEX IF NOT EXISTS idx_provider_events_range_start
    ON provider_calendar_events(start_date, end_date);

-- Subscription removal: find events by provider scope
CREATE INDEX IF NOT EXISTS idx_task_provider_event_links_scope ON task_provider_event_links(provider_kind, provider_scope);

-- ── Full-Text Search (FTS5) ─────────────────────────────────────────

-- `tokenize='unicode61 remove_diacritics 2'` folds
-- accents and does proper Unicode segmentation. Without it, a task
-- titled "Café" silently misses on a search for "cafe" (the default
-- `simple` tokenizer is byte-based and ASCII-only for word boundaries).
--
-- `tags` is the 4th indexed column. We aggregate each
-- task's tag display_names (space-separated) so a search for
-- "budget" hits a task tagged `#budget` through the FTS path instead
-- of only via the LIKE fallback. We keep the table as full-content
-- FTS5 (no `content='tasks'`) because the `tags` column has no
-- 1:1 backing column on `tasks` — external-content mode would break
-- `'rebuild'` for that column. The storage overhead (two copies of
-- title/body/ai_notes) is acceptable for a single-user SQLite DB.
CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
    title, body, ai_notes, tags,
    tokenize='unicode61 remove_diacritics 2'
);

-- FTS_TASKS_TRIGGERS_START
-- Helper CTE (inlined in triggers): concatenate the display_names of
-- every tag linked to a given task. NULL when the task has no tags,
-- which FTS5 treats as empty — indexing on 4 columns still works.
CREATE TRIGGER IF NOT EXISTS tasks_fts_insert AFTER INSERT ON tasks BEGIN
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    VALUES (
        new.rowid,
        new.title,
        new.body,
        new.ai_notes,
        (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.task_id = new.id ORDER BY tg.lookup_key ASC))
    );
END;

-- Scope the UPDATE trigger to the indexed text columns so a mutation
-- that only touches e.g. priority / due_date / status doesn't trip a
-- FTS delete+insert cycle for every row. The trigger must NOT fire
-- on every one of the ~28 columns; doing so would pay the FTS
-- re-index cost ~75% of the time on non-searchable edits.
CREATE TRIGGER IF NOT EXISTS tasks_fts_update AFTER UPDATE OF title, body, ai_notes ON tasks BEGIN
    DELETE FROM tasks_fts WHERE rowid = old.rowid;
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    VALUES (
        new.rowid,
        new.title,
        new.body,
        new.ai_notes,
        (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.task_id = new.id ORDER BY tg.lookup_key ASC))
    );
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_delete AFTER DELETE ON tasks BEGIN
    DELETE FROM tasks_fts WHERE rowid = old.rowid;
END;

-- keep the FTS `tags` column fresh as tag membership and
-- tag display names change. Each trigger deletes+reinserts the
-- affected task's FTS row, pulling current title/body/ai_notes from
-- `tasks` and recomputing the aggregated tag string.
CREATE TRIGGER IF NOT EXISTS tasks_fts_tag_link_insert AFTER INSERT ON task_tags BEGIN
    DELETE FROM tasks_fts WHERE rowid = (SELECT rowid FROM tasks WHERE id = new.task_id);
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.task_id = t.id ORDER BY tg.lookup_key ASC))
      FROM tasks t WHERE t.id = new.task_id;
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_tag_link_delete AFTER DELETE ON task_tags BEGIN
    DELETE FROM tasks_fts WHERE rowid = (SELECT rowid FROM tasks WHERE id = old.task_id);
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.task_id = t.id ORDER BY tg.lookup_key ASC))
      FROM tasks t WHERE t.id = old.task_id;
END;

-- When a tag's display_name changes, every task carrying that tag
-- needs its FTS row rebuilt so searches hit the new name. Scoped to
-- `OF display_name` so colour-only updates don't trip re-indexing.
--
-- this trigger fires DELETE+INSERT for every task
-- carrying the renamed tag — at scale, renaming a popular tag (e.g.
-- "work") on an account with thousands of associated tasks rewrites
-- thousands of FTS rows in a single statement. That cost is acceptable
-- because (a) tag renames are rare relative to task writes, (b) FTS
-- search hits would otherwise return the stale name in the indexed
-- `tags` column and the user would see "no match" for the new name on
-- still-tagged tasks, and (c) deferring the re-index would require a
-- background reconciliation pass that the rest of the schema doesn't
-- need. If a future feature surface enables bulk tag renames, route
-- them through a dedicated batch path that runs the FTS rebuild in
-- chunks rather than hitting this trigger N times.
CREATE TRIGGER IF NOT EXISTS tasks_fts_tag_rename AFTER UPDATE OF display_name ON tags BEGIN
    DELETE FROM tasks_fts
     WHERE rowid IN (SELECT t.rowid FROM tasks t
                     JOIN task_tags tt ON tt.task_id = t.id
                    WHERE tt.tag_id = new.id);
    INSERT INTO tasks_fts(rowid, title, body, ai_notes, tags)
    SELECT t.rowid, t.title, t.body, t.ai_notes,
           (SELECT GROUP_CONCAT(dn, ' ') FROM (SELECT tg.display_name AS dn FROM task_tags tt2 JOIN tags tg ON tg.id = tt2.tag_id WHERE tt2.task_id = t.id ORDER BY tg.lookup_key ASC))
      FROM tasks t
      JOIN task_tags tt ON tt.task_id = t.id
     WHERE tt.tag_id = new.id;
END;
-- FTS_TASKS_TRIGGERS_END

-- FTS5 trigram index for CJK substring search.
--
-- `tasks_fts` above uses the `unicode61` tokenizer, which treats a
-- contiguous CJK run as a single opaque token. A search for `中文`
-- therefore cannot hit a task titled `写一个中文任务` via the main
-- FTS path, so `search_tasks_with_fallback` used to degrade to a
-- `WHERE title LIKE '%' || ?1 || '%' OR body LIKE ...` full-table
-- scan on every CJK keystroke. With ~10k tasks that scan was an
-- observable pause in the search bar for Chinese/Japanese/Korean
-- users.
--
-- The trigram tokenizer (SQLite 3.34+) indexes every 3-character
-- window of the source text so
-- substring MATCH works for CJK and other whitespace-less scripts
-- without scanning the base table.
--
-- Scope:
--   * External-content mode (`content='tasks'`) — the three indexed
--     columns all map 1:1 onto `tasks` columns, so postings are the
--     only on-disk cost. (Unlike `tasks_fts`, whose `tags` column
--     has no backing column, forcing it to be a full-content table.)
--   * Tag display_name substring hits stay on the existing tag-EXISTS
--     LIKE path. A tag collection is small (dozens, not thousands) so
--     the scan is cheap there and a second indexed column per-row
--     isn't worth the write amplification.
-- Asymmetry note: `tasks_fts_trigram` indexes only
-- the three text columns (`title`, `body`, `ai_notes`). The sibling
-- `tasks_fts` table also indexes `tags` (the space-joined display
-- name aggregate), so a Chinese / Japanese / Korean substring
-- search for a term that appears ONLY as a tag will not hit the
-- trigram path — it falls through to the LIKE-on-tags scan in the
-- search fallback. For a small tag collection
-- (dozens, not thousands per task) the LIKE scan is cheap; for
-- typical CJK search workloads (terms sit inside title/body) the
-- trigram path matches as expected.
--
-- Adding `tags` to this trigram table would require switching it
-- from external-content (`content='tasks'`) to full-content mode,
-- because `tags` has no 1:1 backing column on `tasks` — the same
-- structural shape `tasks_fts` uses. That migration
-- (re-create + bulk re-project + 4 new tag-link / tag-rename
-- triggers + checksum drift) is intentionally deferred until a
-- CJK-tag-substring user report justifies the schema churn. Pin
-- the asymmetry here so a future maintainer doesn't accidentally
-- assume parity with `tasks_fts`.
CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts_trigram USING fts5(
    title, body, ai_notes,
    content='tasks',
    content_rowid='rowid',
    tokenize='trigram'
);

-- No open-time `('rebuild')` is issued, matching the sibling `tasks_fts`
-- above: a fresh DB creates this index empty (`tasks` is empty at schema-apply
-- time) and the `tasks_fts_trigram_*` triggers below keep it in lock-step with
-- `tasks` on every insert / update / delete. The Apple store replays this whole
-- schema verbatim on every open, so an unguarded `INSERT INTO
-- tasks_fts_trigram(...) VALUES('rebuild')` would tear down and re-project the
-- trigram index from all tasks on every launch — O(all tasks) work made
-- redundant by the triggers.

-- FTS_TASKS_TRIGRAM_TRIGGERS_START
CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_insert AFTER INSERT ON tasks BEGIN
    INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes)
    VALUES (new.rowid, new.title, new.body, new.ai_notes);
END;

-- Scoped to the indexed text columns so mutations of priority /
-- due_date / status don't pay a trigram re-index cost. Same
-- rationale as the `tasks_fts_update` note above.
CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_update AFTER UPDATE OF title, body, ai_notes ON tasks BEGIN
    INSERT INTO tasks_fts_trigram(tasks_fts_trigram, rowid, title, body, ai_notes)
    VALUES ('delete', old.rowid, old.title, old.body, old.ai_notes);
    INSERT INTO tasks_fts_trigram(rowid, title, body, ai_notes)
    VALUES (new.rowid, new.title, new.body, new.ai_notes);
END;

CREATE TRIGGER IF NOT EXISTS tasks_fts_trigram_delete AFTER DELETE ON tasks BEGIN
    INSERT INTO tasks_fts_trigram(tasks_fts_trigram, rowid, title, body, ai_notes)
    VALUES ('delete', old.rowid, old.title, old.body, old.ai_notes);
END;
-- FTS_TASKS_TRIGRAM_TRIGGERS_END

-- Calendar events FTS: title + description + location for text search
-- across potentially thousands of accumulated events. Same
-- accent-folding tokenizer as tasks_fts.
CREATE VIRTUAL TABLE IF NOT EXISTS calendar_events_fts USING fts5(
    title, description, location,
    content='calendar_events',
    content_rowid='rowid',
    tokenize='unicode61 remove_diacritics 2'
);

-- FTS_CALENDAR_TRIGGERS_START
CREATE TRIGGER IF NOT EXISTS calendar_events_fts_insert AFTER INSERT ON calendar_events BEGIN
    INSERT INTO calendar_events_fts(rowid, title, description, location)
    VALUES (new.rowid, new.title, new.description, new.location);
END;

-- scoped to the indexed text columns — see the
-- tasks_fts_update note above for the rationale.
CREATE TRIGGER IF NOT EXISTS calendar_events_fts_update AFTER UPDATE OF title, description, location ON calendar_events BEGIN
    INSERT INTO calendar_events_fts(calendar_events_fts, rowid, title, description, location)
    VALUES ('delete', old.rowid, old.title, old.description, old.location);
    INSERT INTO calendar_events_fts(rowid, title, description, location)
    VALUES (new.rowid, new.title, new.description, new.location);
END;

CREATE TRIGGER IF NOT EXISTS calendar_events_fts_delete AFTER DELETE ON calendar_events BEGIN
    INSERT INTO calendar_events_fts(calendar_events_fts, rowid, title, description, location)
    VALUES ('delete', old.rowid, old.title, old.description, old.location);
END;
-- FTS_CALENDAR_TRIGGERS_END

-- ── Seed singleton rows ─────────────────────────────────────────────

-- Seed the well-known Inbox list so every fresh database has a default target
-- for task creation. The fixed ID 'inbox' follows the same sentinel pattern as
-- other well-known local rows.
INSERT OR IGNORE INTO lists (id, name, icon, version, created_at, updated_at)
VALUES ('inbox', 'Inbox', '📥', '0000000000000_0000_0000000000000000', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

INSERT OR IGNORE INTO preferences (key, value, version, updated_at)
VALUES ('default_list_id', '"inbox"', '0000000000000_0000_0000000000000000', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));


-- ── J. Sync Payload Shadow ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sync_payload_shadow (
    entity_type            TEXT NOT NULL,
    entity_id              TEXT NOT NULL,
    base_version           TEXT NOT NULL,
    payload_schema_version INTEGER NOT NULL,
    raw_payload_json       TEXT NOT NULL,
    -- Persist the original peer's device id so
    -- `promote_payload_shadows` can replay the envelope with real
    -- attribution. A synthesized `device_id = "shadow-promotion"`
    -- placeholder would corrupt `sync_conflict_log.loser_device_id`
    -- for any subsequent truncation / LWW conflict logged during
    -- promote.
    source_device_id       TEXT NOT NULL DEFAULT '',
    updated_at             TEXT NOT NULL,
    PRIMARY KEY (entity_type, entity_id)
) STRICT;

-- ── K. MCP Idempotency Cache ──────────────────────────────────────────
-- This table caches the full response payload keyed by the client-
-- supplied `idempotency_key`, letting a retry short-circuit and
-- replay the original response byte-for-byte. Without it,
-- `create_task` / `batch_create_tasks` would mint a fresh UUID and
-- run the INSERT unconditionally — a client retrying a request that
-- appeared to fail mid-response (e.g. transport timeout after the
-- DB commit but before the client saw the result) would silently
-- produce duplicate rows. Rows expire 24h after creation; boot-time
-- sweep in the MCP server drops anything past `expires_at` so the
-- table never grows unbounded.

-- `request_checksum` is a stable hash of the
-- request payload at the time the cached response was minted. On
-- lookup, the caller hashes the *current* payload with the same
-- algorithm and compares — a mismatch indicates a key collision (the
-- assistant reused an idempotency token across two semantically
-- different calls) rather than a genuine retry. Replaying the
-- earlier response under that condition would silently lie to the
-- caller, so the lookup arm rejects mismatched checksums instead of
-- returning the cached payload.
CREATE TABLE IF NOT EXISTS mcp_idempotency (
    key               TEXT NOT NULL,
    tool_name         TEXT NOT NULL,
    request_checksum  TEXT NOT NULL CHECK(length(request_checksum) > 0),
    response_payload  TEXT NOT NULL,
    created_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    expires_at        TEXT NOT NULL,
    PRIMARY KEY (tool_name, key)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_mcp_idempotency_expires ON mcp_idempotency(expires_at);
