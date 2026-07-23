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
    version     TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
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
    position    INTEGER NOT NULL DEFAULT 0 CHECK (position >= 0)
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
    estimated_minutes       INTEGER
                            CHECK (estimated_minutes IS NULL OR estimated_minutes BETWEEN 1 AND 1440),
    recurrence              TEXT,
    spawned_from            TEXT,
    -- Lifecycle HLC on the parent that authorized this generated successor.
    -- Root/user-created tasks carry neither lineage field. Keeping the pair
    -- atomic lets inbound reconciliation distinguish a successor that is merely
    -- early from one invalidated by a later reopen/stop decision.
    spawned_from_version    TEXT CHECK (
        spawned_from_version IS NULL OR (
            length(spawned_from_version) = 35
            AND substr(spawned_from_version, 14, 1) = '_'
            AND substr(spawned_from_version, 19, 1) = '_'
            AND substr(spawned_from_version, 1, 13) <= '9999913599999'
            AND substr(spawned_from_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(spawned_from_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(spawned_from_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    recurrence_group_id     TEXT,
    recurrence_instance_key TEXT,
    canonical_occurrence_date TEXT,        -- stable RRULE cadence anchor (independent of due_date)
    -- Independent task registers. `version` below is only the transport/delete
    -- high-water mark; a stale whole-row envelope can still win one register.
    -- The zero defaults keep direct fixture inserts concise. Production create
    -- paths stamp every register explicitly before the first outbound snapshot.
    content_version         TEXT NOT NULL DEFAULT '0000000000000_0000_0000000000000000' CHECK (
        length(content_version) = 35 AND substr(content_version, 14, 1) = '_'
        AND substr(content_version, 19, 1) = '_'
        AND substr(content_version, 1, 13) <= '9999913599999'
        AND substr(content_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(content_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(content_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    schedule_version        TEXT NOT NULL DEFAULT '0000000000000_0000_0000000000000000' CHECK (
        length(schedule_version) = 35 AND substr(schedule_version, 14, 1) = '_'
        AND substr(schedule_version, 19, 1) = '_'
        AND substr(schedule_version, 1, 13) <= '9999913599999'
        AND substr(schedule_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(schedule_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(schedule_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    lifecycle_version       TEXT NOT NULL DEFAULT '0000000000000_0000_0000000000000000' CHECK (
        length(lifecycle_version) = 35 AND substr(lifecycle_version, 14, 1) = '_'
        AND substr(lifecycle_version, 19, 1) = '_'
        AND substr(lifecycle_version, 1, 13) <= '9999913599999'
        AND substr(lifecycle_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(lifecycle_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(lifecycle_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    archive_version         TEXT NOT NULL DEFAULT '0000000000000_0000_0000000000000000' CHECK (
        length(archive_version) = 35 AND substr(archive_version, 14, 1) = '_'
        AND substr(archive_version, 19, 1) = '_'
        AND substr(archive_version, 1, 13) <= '9999913599999'
        AND substr(archive_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(archive_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(archive_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    recurrence_rollover_state TEXT NOT NULL DEFAULT 'none'
                            CHECK (recurrence_rollover_state IN (
                                'none', 'authorized', 'revoked', 'ended'
                            )),
    recurrence_successor_id TEXT,
    version                 TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
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
    -- Reversible archive timestamp. Non-NULL rows are retained until an
    -- explicit restore or guarded permanent delete; there is no scheduled
    -- age-based purge. Archive is orthogonal to `status = 'cancelled'`
    -- (cancel = task won't be done; archive = move it out of active views).
    -- Catalog, stats, search, reminder, and planning reads filter
    -- `archived_at IS NULL`; explicit-id lifecycle reads and full backup
    -- export may intentionally include archived rows.
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
    CHECK (status IN ('open', 'in_progress', 'completed', 'cancelled', 'someday')),
    CHECK (content_version <= version),
    CHECK (schedule_version <= version),
    CHECK (lifecycle_version <= version),
    CHECK (archive_version <= version),
    CHECK (spawned_from_version IS NULL OR spawned_from_version <= version),
    CHECK ((spawned_from IS NULL) = (spawned_from_version IS NULL)),
    CHECK (
        recurrence_instance_key IS NULL OR (
            recurrence_group_id IS NOT NULL
            AND canonical_occurrence_date IS NOT NULL
            AND recurrence_instance_key =
                recurrence_group_id || ':' || canonical_occurrence_date
        )
    ),
    -- Completion is a single lifecycle state. Keeping its status and instant
    -- mutually dependent prevents completed rows from disappearing from
    -- history and prevents reopened/cancelled rows from retaining stale
    -- completion metadata.
    CHECK (
        (status = 'completed' AND completed_at IS NOT NULL)
        OR (status <> 'completed' AND completed_at IS NULL)
    ),
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
    )),
    -- The lifecycle register is the durable recurrence-rollover decision.
    -- `revoked` deliberately retains the old successor id as a negative fact;
    -- re-completion revives that stable identity instead of forking the chain.
    CHECK (
        (
            recurrence_rollover_state = 'none'
            AND recurrence_successor_id IS NULL
            AND (
                recurrence IS NULL
                OR status IN ('open', 'in_progress', 'someday')
            )
        )
        OR (
            recurrence_rollover_state = 'authorized'
            AND recurrence_successor_id IS NOT NULL
            AND status IN ('completed', 'cancelled')
            AND recurrence IS NOT NULL
        )
        OR (
            recurrence_rollover_state = 'revoked'
            AND recurrence_successor_id IS NOT NULL
            AND status IN ('open', 'in_progress', 'someday')
            AND recurrence IS NOT NULL
        )
        OR (
            recurrence_rollover_state = 'ended'
            AND recurrence_successor_id IS NULL
            AND status IN ('completed', 'cancelled')
        )
    )
) STRICT;

-- Current writers derive one deterministic UUIDv8 successor and one validated
-- instance key, so ordinary multi-device completion addresses the same row.
-- A different id claiming the same key is invalid input and fails this UNIQUE
-- index rather than creating a second identity that must be merged.
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
    version         TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Min-register: sync apply folds the minimum peer created_at into this
    -- row even when LWW rejects the rest of the incoming payload, so every
    -- device converges on the earliest creation instant across the fleet.
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    -- Synced manual display order for the habits board (ascending; ties broken
    -- by name, id). Set by the habit-reorder action and carried as an ordinary
    -- LWW column, so a drag on one device converges across peers. DEFAULT 0
    -- keeps freshly created habits grouped until first explicitly ordered.
    position        INTEGER NOT NULL DEFAULT 0 CHECK (position >= 0)
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
    version      TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Min-register: sync apply folds the minimum peer created_at into this
    -- row even when LWW rejects the rest of the incoming payload, so every
    -- device converges on the earliest creation instant across the fleet.
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
) STRICT;
-- Note: lookup_key uniqueness is enforced at the application level by
-- merge_duplicate_tags() in the sync apply pipeline, which needs to
-- temporarily hold two rows with the same lookup_key during merge.

-- Durable partition boundaries for a recurring calendar lineage. The root is
-- implicit; each row identifies the segment beginning at `cutover_date` and
-- shares its deterministic UUIDv8 identity with that segment's calendar event.
-- Rows are upsert-only. `deleted` is an absorbing remove-wins state, so a
-- boundary survives ordinary tombstone GC and permanently prevents stale
-- segment content from becoming live again.
CREATE TABLE IF NOT EXISTS calendar_series_cutovers (
    id              TEXT PRIMARY KEY CHECK (
      length(id) = 36
      AND substr(id, 9, 1) = '-'
      AND substr(id, 14, 1) = '-'
      AND substr(id, 19, 1) = '-'
      AND substr(id, 24, 1) = '-'
      AND length(replace(id, '-', '')) = 32
      AND replace(id, '-', '') NOT GLOB '*[^0-9a-f]*'
      AND id NOT GLOB '*[^0-9a-f-]*'
    ),
    lineage_root_id TEXT NOT NULL CHECK (
      length(lineage_root_id) = 36
      AND substr(lineage_root_id, 9, 1) = '-'
      AND substr(lineage_root_id, 14, 1) = '-'
      AND substr(lineage_root_id, 19, 1) = '-'
      AND substr(lineage_root_id, 24, 1) = '-'
      AND length(replace(lineage_root_id, '-', '')) = 32
      AND replace(lineage_root_id, '-', '') NOT GLOB '*[^0-9a-f]*'
      AND lineage_root_id NOT GLOB '*[^0-9a-f-]*'
      -- UUIDv8 is reserved for deterministic derived identities (cutovers and
      -- occurrence decisions), never a lineage root. This structurally blocks
      -- a cutover from becoming the root of an overlapping nested lineage.
      AND substr(lineage_root_id, 15, 1) <> '8'
    ),
    cutover_date    TEXT NOT NULL,
    state           TEXT NOT NULL CHECK (state IN ('active', 'deleted')),
    version         TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at      TEXT NOT NULL CHECK (
      length(created_at) = 24
      AND strftime('%Y-%m-%dT%H:%M:%fZ', created_at) IS created_at
    ),
    updated_at      TEXT NOT NULL CHECK (
      length(updated_at) = 24
      AND strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) IS updated_at
    ),
    CHECK (
      date(cutover_date, '+0 days') IS cutover_date
      AND substr(cutover_date, 1, 4) <> '0000'
    ),
    CHECK (updated_at >= created_at),
    UNIQUE (lineage_root_id, cutover_date)
) STRICT;

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
    -- every INSERT/UPDATE writer (sync apply, MCP, workflows, export/import,
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
    -- Lightweight structured attendee list for Lorvex-native events: a JSON array
    -- of `{name?, email?}` objects (each entry carries at least one non-empty
    -- field), or NULL for none. AI-settable via MCP and shown in the inspector;
    -- it is a plain annotation, not RSVP/invite state — there is no per-attendee
    -- identity, PARTSTAT status, or delivery tracking. Rides the calendar_event
    -- aggregate's last-writer-wins sync like any other column; unknown per-attendee
    -- sub-keys a newer peer emits round-trip because the array is stored verbatim.
    -- The EventKit provider mirror keeps its own richer, status-bearing
    -- `provider_calendar_events.attendees_json` — a separate, device-local surface.
    attendees             TEXT CHECK (attendees IS NULL OR json_valid(attendees)),
    timezone              TEXT,
    -- Immutable marker for a recurring tail segment. The marker and row id are
    -- the same deterministic cutover UUID. Root/plain events and occurrence
    -- decisions leave it NULL; the durable cutover row, not a rewritten UNTIL,
    -- controls whether and over which slot interval this segment is visible.
    series_cutover_id      TEXT,
    -- A recurring occurrence decision is a deterministic three-state register.
    -- `series_id`, `recurrence_instance_date`, `occurrence_state`, and
    -- `recurrence_generation` are set together on the decision row. The row id
    -- is a UUIDv8 derived from that triple at the Store boundary. Series links
    -- deliberately remain soft references so a decision may arrive before its
    -- master during CloudKit replay. Base rows leave the linkage/state fields
    -- NULL. Every base row carries an independently merged topology version;
    -- recurring masters also carry the generation that selects their active
    -- occurrence decisions.
    series_id             TEXT,
    recurrence_instance_date TEXT,
    occurrence_state      TEXT CHECK (
      occurrence_state IS NULL
      OR occurrence_state IN ('replacement', 'cancelled', 'inherit')
    ),
    -- An identity epoch, not an LWW register: HLC-shaped for global
    -- uniqueness, minted when a master's recurrence topology changes, and
    -- matched by equality to select the occurrence decisions of the current
    -- era. It never merges field-wise the way `*_version` registers do.
    recurrence_generation TEXT CHECK (
      recurrence_generation IS NULL OR (
        length(recurrence_generation) = 35
        AND substr(recurrence_generation, 14, 1) = '_'
        AND substr(recurrence_generation, 19, 1) = '_'
        AND substr(recurrence_generation, 1, 13) <= '9999913599999'
        AND substr(recurrence_generation, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(recurrence_generation, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(recurrence_generation, 20, 16) NOT GLOB '*[^0-9a-f]*'
      )
    ),
    recurrence_topology_version TEXT CHECK (
      recurrence_topology_version IS NULL OR (
        length(recurrence_topology_version) = 35
        AND substr(recurrence_topology_version, 14, 1) = '_'
        AND substr(recurrence_topology_version, 19, 1) = '_'
        AND substr(recurrence_topology_version, 1, 13) <= '9999913599999'
        AND substr(recurrence_topology_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(recurrence_topology_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(recurrence_topology_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
      )
    ),
    -- Independent LWW register for base-event descriptive content
    -- (title/description/location/url/color/type/person/attendees). Timing,
    -- timezone, and recurrence live under `recurrence_topology_version`.
    -- Occurrence decisions remain whole-row LWW and therefore leave both
    -- register-version columns NULL.
    content_version       TEXT CHECK (
      content_version IS NULL OR (
        length(content_version) = 35
        AND substr(content_version, 14, 1) = '_'
        AND substr(content_version, 19, 1) = '_'
        AND substr(content_version, 1, 13) <= '9999913599999'
        AND substr(content_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(content_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(content_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
      )
    ),
    version               TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at            TEXT NOT NULL,
    updated_at            TEXT NOT NULL,
    CHECK (event_type IN ('event', 'birthday', 'anniversary', 'memorial')),
    -- Defense in depth for direct SQL writers. The sync/workflow boundaries
    -- validate through CalendarEventTiming; these checks keep the same three
    -- legal shapes intact if a future writer bypasses those layers.
    -- `+0 days` forces normalization on older Apple system SQLite versions
    -- whose one-argument date() may echo impossible dates such as 2026-02-30.
    CHECK (
      date(start_date, '+0 days') IS start_date
      AND substr(start_date, 1, 4) <> '0000'
    ),
    CHECK (
      end_date IS NULL OR (
        date(end_date, '+0 days') IS end_date
        AND substr(end_date, 1, 4) <> '0000'
      )
    ),
    CHECK (
      start_time IS NULL OR (
        length(start_time) = 5 AND substr(start_time, 3, 1) = ':'
        AND substr(start_time, 1, 2) BETWEEN '00' AND '23'
        AND substr(start_time, 4, 2) BETWEEN '00' AND '59'
        AND replace(start_time, ':', '') NOT GLOB '*[^0-9]*'
      )
    ),
    CHECK (
      end_time IS NULL OR (
        length(end_time) = 5 AND substr(end_time, 3, 1) = ':'
        AND substr(end_time, 1, 2) BETWEEN '00' AND '23'
        AND substr(end_time, 4, 2) BETWEEN '00' AND '59'
        AND replace(end_time, ':', '') NOT GLOB '*[^0-9]*'
      )
    ),
    CHECK (
      CASE
        WHEN all_day = 1 THEN
          start_time IS NULL AND end_time IS NULL
          AND (end_date IS NULL OR end_date >= start_date)
        WHEN start_time IS NULL THEN 0
        WHEN end_date IS NULL OR end_date = start_date THEN
          end_time IS NULL OR end_time >= start_time
        WHEN end_date > start_date THEN end_time IS NOT NULL
        ELSE 0
      END
    ),
    CHECK (recurrence_end_date IS NULL OR recurrence_end_date >= start_date),
    -- `version` is the aggregate high-water mark. Grouped-register joins may
    -- preserve an older content/topology/generation value, but no component
    -- clock may sort above the row clock emitted to sync.
    CHECK (content_version IS NULL OR content_version <= version),
    CHECK (
      recurrence_topology_version IS NULL
      OR recurrence_topology_version <= version
    ),
    CHECK (recurrence_generation IS NULL OR recurrence_generation <= version),
    CHECK (series_cutover_id IS NULL OR series_cutover_id = id),
    -- Decision linkage is both-or-neither; base rows leave both NULL.
    CHECK ((series_id IS NULL) = (recurrence_instance_date IS NULL)),
    CHECK (
      series_id IS NULL OR (
        length(trim(series_id)) > 0
        AND series_id <> id
      )
    ),
    CHECK (
      recurrence_instance_date IS NULL
      OR (
        date(recurrence_instance_date, '+0 days') IS recurrence_instance_date
        AND substr(recurrence_instance_date, 1, 4) <> '0000'
      )
    ),
    -- Legal row shapes:
    -- - plain base: no recurrence/linkage/state/generation; topology is present
    -- - recurring master: recurrence + generation + topology; no decision fields
    -- - occurrence decision: linkage + state + generation; no recurrence/topology
    CHECK (
      CASE
        WHEN series_id IS NOT NULL THEN
          recurrence IS NULL
          AND series_cutover_id IS NULL
          AND occurrence_state IS NOT NULL
          AND recurrence_generation IS NOT NULL
          AND recurrence_topology_version IS NULL
          AND content_version IS NULL
        WHEN recurrence IS NOT NULL THEN
          occurrence_state IS NULL
          AND recurrence_generation IS NOT NULL
          AND recurrence_topology_version IS NOT NULL
          AND content_version IS NOT NULL
        ELSE
          occurrence_state IS NULL
          AND recurrence_generation IS NULL
          AND recurrence_topology_version IS NOT NULL
          AND content_version IS NOT NULL
      END
    ),
    -- Generation is part of occurrence identity. A reset moves the master to a
    -- new generation and leaves old decisions inert without delete fan-out.
    UNIQUE (series_id, recurrence_generation, recurrence_instance_date)
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

CREATE TABLE IF NOT EXISTS preferences (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    version    TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    updated_at TEXT NOT NULL
) STRICT;

-- Creation time is not stored as a column: memory is a last-write key→value
-- store, so a row keeps only its latest content and `updated_at`.
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
    -- (min-id wins, loser tombstoned + redirected) — it is never a bare UNIQUE
    -- that would batch-wedge the inbound sync page.
    key        TEXT NOT NULL UNIQUE,
    content    TEXT NOT NULL,
    version    TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    updated_at TEXT NOT NULL
) STRICT;

-- Day-scoped aggregates: canonical timezone anchors day identity.
CREATE TABLE IF NOT EXISTS daily_reviews (
    date         TEXT PRIMARY KEY,
    summary      TEXT NOT NULL,
    mood         INTEGER,
    energy_level INTEGER,
    wins         TEXT,
    blockers     TEXT,
    learnings    TEXT,
    timezone     TEXT,
    version      TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    CHECK (mood IS NULL OR (mood >= 1 AND mood <= 5)),
    CHECK (energy_level IS NULL OR (energy_level >= 1 AND energy_level <= 5))
) STRICT;

-- Per-date curated focus list: which tasks matter today, hand-picked and
-- ordered, plus an optional briefing. One aggregate per date;
-- `current_focus_items` holds the ordered task references.
CREATE TABLE IF NOT EXISTS current_focus (
    date       TEXT PRIMARY KEY,
    briefing   TEXT,
    timezone   TEXT,
    version    TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

-- Per-date time-blocked day plan: ordered minute-of-day blocks
-- (`focus_schedule_blocks`) with an optional rationale. Complements
-- `current_focus`: that aggregate curates *which* tasks matter today;
-- this one plans *when* the day's time goes.
CREATE TABLE IF NOT EXISTS focus_schedule (
    date       TEXT PRIMARY KEY,
    rationale  TEXT,
    timezone   TEXT,
    version    TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

-- ── B. Relation Edges (synced, composite natural key) ───────────────

CREATE TABLE IF NOT EXISTS task_tags (
    task_id    TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    tag_id     TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    version    TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Plain LWW on the ordinary edge upsert. The one exception is tag-alias
    -- merge repoint: when a duplicate tag collapses into its canonical id and
    -- two edges share the same identity, an equal-version tie-break keeps the
    -- byte-stable earlier created_at so the merge stays commutative across
    -- peers. This is not the fleet-wide min-register the aggregate tables
    -- (tags/habits/habit_reminder_policies) carry.
    created_at TEXT NOT NULL,
    PRIMARY KEY (task_id, tag_id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_task_tags_tag ON task_tags(tag_id);

CREATE TABLE IF NOT EXISTS task_dependencies (
    task_id            TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    version            TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at         TEXT NOT NULL,
    PRIMARY KEY (task_id, depends_on_task_id),
    CHECK (task_id != depends_on_task_id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_task_deps_depends_on ON task_dependencies(depends_on_task_id);

CREATE TABLE IF NOT EXISTS task_calendar_event_links (
    task_id           TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    calendar_event_id TEXT NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
    version           TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL,
    PRIMARY KEY (task_id, calendar_event_id)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_task_calendar_event_links_event ON task_calendar_event_links(calendar_event_id);

-- Canonical task links target a base event (plain event or recurring master),
-- never an occurrence-decision row. Scoped surfaces normalize an occurrence id
-- to its master before writing; these triggers close every direct-SQL route so
-- generation invalidation can never strand a link on an inert decision.
CREATE TRIGGER IF NOT EXISTS trg_task_calendar_event_links_base_insert
    BEFORE INSERT ON task_calendar_event_links
BEGIN
    SELECT CASE WHEN EXISTS (
        SELECT 1 FROM calendar_events
        WHERE id = NEW.calendar_event_id AND series_id IS NOT NULL
    ) THEN RAISE(ABORT, 'task-calendar links must target a base calendar event') END;
END;

CREATE TRIGGER IF NOT EXISTS trg_task_calendar_event_links_base_update
    BEFORE UPDATE OF calendar_event_id ON task_calendar_event_links
BEGIN
    SELECT CASE WHEN EXISTS (
        SELECT 1 FROM calendar_events
        WHERE id = NEW.calendar_event_id AND series_id IS NOT NULL
    ) THEN RAISE(ABORT, 'task-calendar links must target a base calendar event') END;
END;

CREATE TRIGGER IF NOT EXISTS trg_calendar_events_linked_base_identity
    BEFORE UPDATE OF series_id ON calendar_events
    WHEN NEW.series_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM task_calendar_event_links
        WHERE calendar_event_id = OLD.id
      )
BEGIN
    SELECT RAISE(ABORT, 'a linked base calendar event cannot become an occurrence decision');
END;

CREATE TABLE IF NOT EXISTS habit_completions (
    habit_id       TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    completed_date TEXT NOT NULL,
    -- A completion count is always positive: every first-party writer clamps to
    -- >= 1 and a count reaching 0 deletes the row. The CHECK is the last-line
    -- defense so a malformed peer envelope or hand-rolled fixture cannot land a
    -- non-positive count the streak / adherence math would then divide against.
    value          INTEGER NOT NULL DEFAULT 1 CHECK (value > 0),
    note           TEXT,
    version        TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
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
    position INTEGER NOT NULL CHECK (position >= 0),
    task_id  TEXT NOT NULL,
    PRIMARY KEY (date, position)
) STRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_focus_items_date_task ON current_focus_items(date, task_id);
CREATE INDEX IF NOT EXISTS idx_focus_items_task ON current_focus_items(task_id);

CREATE TABLE IF NOT EXISTS focus_schedule_blocks (
    date              TEXT NOT NULL REFERENCES focus_schedule(date) ON DELETE CASCADE,
    position          INTEGER NOT NULL CHECK (position >= 0),
    block_type        TEXT NOT NULL CHECK (block_type IN ('task', 'buffer', 'event')),
    start_minutes     INTEGER NOT NULL,
    end_minutes       INTEGER NOT NULL,
    task_id           TEXT,
    calendar_event_id TEXT,
    event_source      TEXT CHECK (event_source IN ('canonical', 'provider', 'freeform')),
    title             TEXT,
    -- Lock the minute-of-day contract: start/end are minutes from midnight in
    -- [0,1440] with end > start. Both live writers already enforce this; the
    -- CHECK is the last-line defense so a malformed peer envelope or hand-rolled
    -- fixture cannot land a row the timeline projector would then dereference.
    CHECK (start_minutes >= 0 AND end_minutes > start_minutes AND end_minutes <= 1440),
    -- `task_id` is a soft reference because aggregate sync order is arbitrary,
    -- but its identity shape is still canonical: a hyphenated lowercase UUID.
    -- Keep this symmetric with canonical `calendar_event_id` so direct-SQL writers cannot
    -- create a task block that no service/import/sync reader can address.
    CHECK (
      task_id IS NULL OR (
        length(task_id) = 36
        AND substr(task_id, 9, 1) = '-'
        AND substr(task_id, 14, 1) = '-'
        AND substr(task_id, 19, 1) = '-'
        AND substr(task_id, 24, 1) = '-'
        AND length(replace(task_id, '-', '')) = 32
        AND replace(task_id, '-', '') NOT GLOB '*[^0-9a-f]*'
        AND task_id NOT GLOB '*[^0-9a-f-]*'
      )
    ),
    -- Event provenance belongs to the schedule block itself. It must not be
    -- inferred from whether the referenced calendar row has arrived locally:
    -- aggregate sync order is arbitrary, while provider/freeform blocks have no
    -- canonical calendar row at all.
    --
    -- `calendar_event_id` has one meaning only: a canonical Lorvex calendar-event UUID.
    -- Provider identity stays device-local and freeform blocks have no identity.
    CHECK (
      calendar_event_id IS NULL OR (
        length(calendar_event_id) = 36
        AND substr(calendar_event_id, 9, 1) = '-'
        AND substr(calendar_event_id, 14, 1) = '-'
        AND substr(calendar_event_id, 19, 1) = '-'
        AND substr(calendar_event_id, 24, 1) = '-'
        AND length(replace(calendar_event_id, '-', '')) = 32
        AND replace(calendar_event_id, '-', '') NOT GLOB '*[^0-9a-f]*'
        AND calendar_event_id NOT GLOB '*[^0-9a-f-]*'
      )
    ),
    -- enforce the (block_type, task_id, calendar_event_id, event_source)
    -- consistency at the schema level so a malformed peer envelope or
    -- hand-rolled fixture can't land a row that the timeline projector
    -- would then dereference. The application-level write helpers
    -- already obey this contract; the CHECK is the last-line defense
    -- for future writers that don't go through those helpers.
    --   - block_type='task'   → task_id NOT NULL; event fields NULL
    --   - canonical event     → canonical calendar_event_id + source='canonical'
    --   - provider event      → no calendar_event_id + source='provider'
    --   - freeform event      → no calendar_event_id + source='freeform'
    --   - block_type='buffer' → all references/source NULL
    CHECK (
      (block_type = 'task' AND task_id IS NOT NULL
        AND calendar_event_id IS NULL AND event_source IS NULL)
      OR (block_type = 'event' AND task_id IS NULL AND (
        (event_source = 'canonical' AND calendar_event_id IS NOT NULL)
        OR (event_source IN ('provider', 'freeform') AND calendar_event_id IS NULL)
      ))
      OR (block_type = 'buffer' AND task_id IS NULL
        AND calendar_event_id IS NULL AND event_source IS NULL)
    ),
    PRIMARY KEY (date, position)
) STRICT;

-- Weekday set for a 'weekly' habit, materialized from the weekday array carried
-- inside the habit's own sync payload. Parent-owned: the applier rebuilds these
-- rows (delete-then-insert keyed by habit_id) after every habit upsert. It is
-- NOT an independently-synced entity —
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

-- EXDATE child table for recurring tasks.
--
-- The recurrence-exceptions list is normalized into per-date rows
-- rather than a JSON array on `tasks`.
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
    exception_date TEXT NOT NULL CHECK (
      date(exception_date, '+0 days') IS exception_date
      AND substr(exception_date, 1, 4) <> '0000'
    ),
    PRIMARY KEY (task_id, exception_date)
) STRICT;

-- `daily_review_task_links` and `daily_review_list_links`
-- are NOT primary state — they are projections rebuilt from the
-- canonical arrays embedded in the `daily_reviews` aggregate payload
-- (`linked_task_ids` / `linked_list_ids`). The rebuild is a full
-- delete-and-reinsert keyed by `review_date`, performed by the
-- daily-review link materializer whenever a write supplies canonical
-- replacement link sets (MCP full replacement/amend, sync apply, import,
-- payload_shadow merge). Scalar-only Apple UI and App Intent writes preserve
-- the transaction-current projections without rebuilding them. Link arrays
-- are set-valued, and every reader and payload builder orders them by target
-- id; `created_at` is therefore
-- compatibility metadata only, not ordering state or audit history.
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
    version             TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at          TEXT NOT NULL,
    -- store the intended local wall-clock anchor so a
    -- later PREF_TIMEZONE change can re-materialize `reminder_at` and
    -- preserve "9 AM local" semantics. Both columns are nullable for
    -- reminders whose anchor couldn't be resolved (no PREF_TIMEZONE set).
    -- `HH:MM` plus a Foundation-resolvable timezone identifier — we
    -- deliberately do NOT persist the calendar date here; the anchor date is
    -- derived from `reminder_at` interpreted in `original_tz` at re-anchor time.
    original_local_time TEXT,
    original_tz         TEXT,
    -- A reminder anchor is one semantic value split across two columns. A
    -- partial pair cannot be re-materialized after a timezone preference
    -- change, so reject it even for a future direct-SQL writer.
    CHECK ((original_local_time IS NULL) = (original_tz IS NULL)),
    CHECK (
      original_local_time IS NULL OR (
        length(original_local_time) = 5
        AND substr(original_local_time, 3, 1) = ':'
        AND substr(original_local_time, 1, 2) BETWEEN '00' AND '23'
        AND substr(original_local_time, 4, 2) BETWEEN '00' AND '59'
        AND replace(original_local_time, ':', '') NOT GLOB '*[^0-9]*'
      )
    ),
    -- SQLite cannot reproduce Foundation's timezone resolver. Production
    -- ingress validates there; this character allowlist accepts both region
    -- identifiers and Foundation fixed offsets such as `GMT+05:30`, while still
    -- rejecting empty, whitespace-padded, and control-character values.
    CHECK (
      original_tz IS NULL OR (
        length(original_tz) > 0
        AND original_tz = trim(original_tz)
        AND original_tz NOT GLOB '*[^A-Za-z0-9/_+.:-]*'
      )
    )
) STRICT;

CREATE TABLE IF NOT EXISTS task_checklist_items (
    id           TEXT PRIMARY KEY,
    task_id      TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    position     INTEGER NOT NULL CHECK (position >= 0),
    text         TEXT NOT NULL,
    completed_at TEXT,
    version      TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS habit_reminder_policies (
    id            TEXT PRIMARY KEY,
    habit_id      TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    reminder_time TEXT NOT NULL,
    enabled       INTEGER NOT NULL DEFAULT 1
                  CHECK (enabled IN (0, 1)),
    version       TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Min-register: sync apply folds the minimum peer created_at into this
    -- row even when LWW rejects the rest of the incoming payload, so every
    -- device converges on the earliest creation instant across the fleet.
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
    -- writers (platform readers, provider-cache sync, future
    -- migrations) that bypass the IPC gates.
    -- Adding a new kind requires extending the domain const AND every
    -- CHECK list on `task_provider_event_links`,
    -- `provider_calendar_events`, and `provider_scope_runtime_state`.
    provider_kind      TEXT NOT NULL CHECK (provider_kind IN ('eventkit')),
    provider_scope     TEXT NOT NULL,
    provider_event_key TEXT NOT NULL,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    PRIMARY KEY (task_id, provider_kind, provider_scope, provider_event_key)
) STRICT;

-- E.2 Disposable caches (rebuildable from external sources)

-- Device-local mirror of provider (EventKit) events for timeline
-- rendering. Never synced and never exported; refresh rebuilds the rows
-- wholesale from the provider, so this is disposable cache, not canonical
-- data.
CREATE TABLE IF NOT EXISTS provider_calendar_events (
    -- `provider_kind` shares the domain provider-kind allowlist.
    provider_kind      TEXT NOT NULL CHECK (provider_kind IN ('eventkit')),
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
    -- path writes provider rows directly
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
    source_time_kind   TEXT NOT NULL DEFAULT 'floating'
                       CHECK (source_time_kind IN ('floating', 'utc', 'tzid')),
    source_tzid        TEXT,
    organizer_email    TEXT,
    video_call_url     TEXT,
    -- JSON array of `[{"email":"…","name":"…","status":"accepted"}]`.
    -- Stored canonically so projection + diff stays deterministic.
    attendees_json     TEXT,
    last_seen_at       TEXT NOT NULL,
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

-- Device-local notification bookkeeping; never synced. Two stamps, two
-- stages: `last_armed_at` records when this device handed the reminder to
-- UNUserNotificationCenter (the request is scheduled and armed);
-- `last_delivered_at` records when the app observed the armed fire time pass,
-- i.e. the OS has presented the notification. `delivery_state` collapses that
-- pair into the pending/delivered lifecycle the reminder surfaces read.
-- Every reschedule pass replaces the armed set: a pending reminder whose OS
-- request was dropped (budgeted out, permission denied, add failed) has its
-- `last_armed_at` cleared back to NULL, so the stamp always mirrors the
-- currently pending request set and an unshown reminder can never be marked
-- delivered.
CREATE TABLE IF NOT EXISTS task_reminder_delivery_state (
    reminder_id       TEXT PRIMARY KEY REFERENCES task_reminders(id) ON DELETE CASCADE,
    last_armed_at     TEXT,
    last_delivered_at TEXT,
    delivery_state    TEXT NOT NULL DEFAULT 'pending'
                      CHECK (delivery_state IN ('pending', 'delivered')),
    last_error        TEXT,
    updated_at        TEXT NOT NULL
) STRICT;

-- Habit analog of `task_reminder_delivery_state`; device-local, never synced.
-- `last_armed_at` records the latest occurrence fire time this device has an
-- accepted UNUserNotificationCenter request for; each reschedule pass replaces
-- it (or clears it to NULL when the pass drops the policy's requests), so the
-- stamp always mirrors the currently pending OS request set. The derived
-- delivered stamp is gated on it: only occurrences at or before
-- `last_armed_at` can be marked delivered, so a denied / budgeted-out /
-- add-failed nudge stays visible instead of being recorded as shown.
CREATE TABLE IF NOT EXISTS habit_reminder_delivery_state (
    policy_id         TEXT PRIMARY KEY REFERENCES habit_reminder_policies(id) ON DELETE CASCADE,
    last_armed_at     TEXT,
    last_delivered_at TEXT,
    updated_at        TEXT NOT NULL
) STRICT;

-- Vocabulary for `availability_state` and `last_refresh_result` is
-- pinned by the provider-scope writers and the refresh-error
-- recorder. Adding a new provider category requires extending both
-- CHECK lists here — coupled deliberately so the UI state machine
-- stays closed.
CREATE TABLE IF NOT EXISTS provider_scope_runtime_state (
    -- `provider_kind` shares the domain provider-kind allowlist.
    provider_kind          TEXT NOT NULL CHECK (provider_kind IN ('eventkit')),
    provider_scope         TEXT NOT NULL,
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
    version                TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Persisted as SQLite INTEGER but decoded into UInt32 by the outbox read
    -- path. Match the nonzero wire domain at the storage boundary.
    payload_schema_version INTEGER NOT NULL
                           CHECK (payload_schema_version BETWEEN 1 AND 4294967295),
    payload                TEXT NOT NULL,
    -- Device-local provenance for a queued grouped-register Upsert. The bits are
    -- interpreted by entity kind (calendar: content/topology; task:
    -- content/schedule/lifecycle/archive) and never serialized onto the wire.
    -- Baseline/future-record replay re-authors only the user's actual registers.
    register_intent        INTEGER NOT NULL DEFAULT 0
                           CHECK (register_intent BETWEEN 0 AND 15),
    device_id              TEXT NOT NULL,
    created_at             TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    synced_at              TEXT,
    retry_count            INTEGER NOT NULL DEFAULT 0
                           CHECK (retry_count >= 0),
    last_retry_at          TEXT,
    -- Per-row error history. Storing only the most recent failure
    -- string in the global `sync_checkpoints.last_error` key would
    -- let every subsequent failure on any row overwrite it; the
    -- retry loop then could not detect a stuck-in-place failure
    -- (same error N times = strong evidence of a permanent failure
    -- like malformed payload / schema mismatch) and would waste 10
    -- retry cycles
    -- on each. `record_retry` writes the row's error here and tracks an
    -- explicit consecutive per-record streak below to escalate fast-fail.
    last_error             TEXT,
    consecutive_error_count INTEGER NOT NULL DEFAULT 0
                            CHECK (consecutive_error_count >= 0
                                   AND consecutive_error_count <= retry_count),
    -- NULL is the ordinary active/synced state. A retryable push/decode
    -- failure waits until `next_retry_at` and is then re-armed automatically;
    -- authoritative snapshot adoption is an intentional discard fence and is
    -- never eligible for generic recovery. A future-record hold preserves a
    -- local intent whose CloudKit identity is occupied by a record this build
    -- cannot understand; only a later understood envelope may reconcile it.
    disposition            TEXT
                           CHECK (disposition IN
                                  ('retry_wait', 'authoritative_adoption',
                                   'future_record_hold')),
    -- Ownership makes the intentional authoritative-adoption discard fence
    -- releasable at exactly that durable snapshot session's finalize/cancel
    -- boundary. It is not a generic retry owner.
    authoritative_session_token TEXT
        REFERENCES sync_authoritative_snapshot(session_token)
        ON UPDATE CASCADE ON DELETE CASCADE
        CHECK (
        authoritative_session_token IS NULL
        OR (length(authoritative_session_token) > 0
            AND length(authoritative_session_token) <= 128)
        ),
    -- Maximum canonical HLC of the future-authored CloudKit record(s) that
    -- caused this local intent to be fenced. Kept separately from `version`,
    -- which remains the HLC of the preserved local intent itself.
    future_record_version  TEXT CHECK (
        future_record_version IS NULL
        OR (
            length(future_record_version) = 35
            AND substr(future_record_version, 14, 1) = '_'
            AND substr(future_record_version, 19, 1) = '_'
            AND substr(future_record_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(future_record_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(future_record_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    -- Durable policy for resolving the preserved local intent once a later
    -- build understands the opaque CloudKit record. Ordinary inbound holds use
    -- LWW. A complete authoritative snapshot explicitly distinguishes stale
    -- pre-session state from a genuine post-session user/MCP intent.
    future_record_resolution TEXT
                           CHECK (future_record_resolution IN
                                  ('lww', 'remote_authoritative',
                                   'local_after_future')),
    next_retry_at          TEXT,
    recovery_round         INTEGER NOT NULL DEFAULT 0
                           CHECK (recovery_round >= 0),
    CHECK (
        register_intent = 0
        OR (
            operation = 'upsert'
            AND (
                (entity_type = 'calendar_event' AND register_intent BETWEEN 1 AND 3)
                OR (entity_type = 'task' AND register_intent BETWEEN 1 AND 15)
            )
        )
    ),
    CHECK (
        (disposition IS NULL AND next_retry_at IS NULL
         AND authoritative_session_token IS NULL AND future_record_version IS NULL
         AND future_record_resolution IS NULL)
        OR
        (disposition = 'retry_wait'
         AND synced_at IS NULL AND next_retry_at IS NOT NULL
         AND authoritative_session_token IS NULL AND future_record_version IS NULL
         AND future_record_resolution IS NULL)
        OR
        (disposition = 'authoritative_adoption'
         AND synced_at IS NULL AND next_retry_at IS NULL
         AND authoritative_session_token IS NOT NULL AND future_record_version IS NULL
         AND future_record_resolution IS NULL)
        OR
        (disposition = 'future_record_hold'
         AND synced_at IS NULL AND next_retry_at IS NULL
         AND authoritative_session_token IS NULL AND future_record_version IS NOT NULL
         AND future_record_resolution IS NOT NULL)
    )
) STRICT;

CREATE TABLE IF NOT EXISTS sync_tombstones (
    entity_type TEXT NOT NULL CHECK (
        entity_type IN (
            'task', 'list', 'habit', 'tag', 'calendar_event', 'preference',
            'memory', 'daily_review', 'current_focus', 'focus_schedule',
            'task_reminder', 'task_checklist_item', 'habit_reminder_policy',
            'task_tag', 'task_dependency', 'task_calendar_event_link',
            'habit_completion'
        )
    ),
    entity_id   TEXT NOT NULL,
    version     TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    deleted_at  TEXT NOT NULL,
    -- Set only from CloudKit's server-assigned CKRecord.modificationDate for
    -- this exact delete version. Local/newer deletes clear it. NULL is the
    -- conservative state and can never authorize compaction.
    cloud_confirmed_at TEXT CHECK (
        cloud_confirmed_at IS NULL OR length(cloud_confirmed_at) = 24
    ),
    PRIMARY KEY (entity_type, entity_id)
) STRICT;

-- Permanent, absorbing same-type aliases created when two independently-minted
-- identities are proven to name one logical entity. Deletes remain exclusively
-- in sync_tombstones: an alias cannot expire or be overwritten by a later stale
-- loser upsert. The strict descending target order makes cycles impossible and
-- gives competing aliases a deterministic min-id join.
CREATE TABLE IF NOT EXISTS sync_entity_redirects (
    source_type TEXT NOT NULL CHECK (
        length(source_type) > 0 AND length(CAST(source_type AS BLOB)) <= 128
        AND source_type IN (
            'tag', 'habit', 'memory', 'habit_reminder_policy'
        )
    ),
    source_id   TEXT NOT NULL CHECK (
        length(source_id) > 0 AND length(CAST(source_id AS BLOB)) <= 256
    ),
    target_id   TEXT NOT NULL CHECK (
        length(target_id) > 0 AND length(CAST(target_id AS BLOB)) <= 256
        AND target_id < source_id COLLATE BINARY
    ),
    version     TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    created_at  TEXT NOT NULL CHECK (length(created_at) = 24),
    PRIMARY KEY (source_type, source_id)
) STRICT;

-- Local-only, per-device sync runtime key/value store. Keys are namespaced
-- strings owned by the sync engine: device_id and db_instance_id (install
-- identity), retired_device_ids (prior suffixes the HLC clock still scans so a
-- rotated device stays self-monotonic), last_success_at / last_error (status
-- surfaced to the UI), reseed_required (one-shot maintenance flag), the
-- per-account enrolled_zone_epoch, and the retained-hold count. CloudKit change
-- tokens are NOT here; they are BLOB columns on the traversal-progress and
-- generation-descriptor tables.
CREATE TABLE IF NOT EXISTS sync_checkpoints (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;

-- CloudKit account binding, traversal progress, and each successor change token
-- live in the data file and commit atomically with inbound page effects. The
-- external CloudSyncState cache contains only reconstructible CKRecord system
-- fields; restoring this database also restores its exact traversal lineage.
CREATE TABLE IF NOT EXISTS sync_cloudkit_account_binding (
    singleton            INTEGER PRIMARY KEY CHECK (singleton = 1),
    account_identifier   TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    database_instance_id TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    bound_at             TEXT NOT NULL CHECK (length(bound_at) = 24),
    -- Greatest CloudKit CKRecord.modificationDate observed for this account.
    -- This is the only clock allowed to age tombstones into generation
    -- compaction eligibility; device wall time is never used.
    trusted_server_time  TEXT CHECK (
        trusted_server_time IS NULL OR length(trusted_server_time) = 24
    ),
    -- Greatest server modification time of a per-traversal witness that a
    -- terminal zone traversal actually observed. Unlike trusted_server_time,
    -- this proves the local database consumed history through that server
    -- instant and may therefore cover a published compaction cutoff.
    trusted_terminal_server_time TEXT CHECK (
        trusted_terminal_server_time IS NULL
        OR length(trusted_terminal_server_time) = 24
    ),
    UNIQUE (account_identifier, database_instance_id)
) STRICT;

-- Append-only per-account witness that this physical database lineage has ever
-- observed or successfully claimed a CloudKit generation authority. Account
-- binding alone is not such evidence: a fresh app can crash after binding its
-- local database but before creating the first remote control record. Keeping
-- the maximum observed generation separately makes that half-bootstrap
-- resumable while a later missing/rolled-back control record still fails closed.
CREATE TABLE IF NOT EXISTS sync_cloudkit_authority_witness (
    account_identifier          TEXT PRIMARY KEY CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    maximum_observed_generation INTEGER NOT NULL CHECK (
        maximum_observed_generation >= 0
        AND maximum_observed_generation <= 2147483647
    ),
    database_instance_id        TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    observed_at                 TEXT NOT NULL CHECK (length(observed_at) = 24)
) STRICT;

-- Append-only local ledger of every exact remote generation descriptor this
-- database lineage has observed. Account switching retains account-scoped rows;
-- a canceled/crashed traversal must not erase that a newer generation existed,
-- and a later generation must never reuse an older zone/root/ready witness.
CREATE TABLE IF NOT EXISTS sync_cloudkit_generation_descriptor (
    account_identifier   TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    generation           INTEGER NOT NULL CHECK (generation >= 0 AND generation <= 2147483647),
    zone_identifier      TEXT NOT NULL CHECK (
        length(zone_identifier) > 0
        AND length(CAST(zone_identifier AS BLOB)) <= 255
    ),
    generation_identifier TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    ready_witness        TEXT NOT NULL CHECK (
        length(ready_witness) > 0
        AND length(CAST(ready_witness AS BLOB)) <= 128
    ),
    tombstone_compaction_cutoff TEXT CHECK (
        tombstone_compaction_cutoff IS NULL
        OR (
            length(tombstone_compaction_cutoff) = 24
            AND substr(tombstone_compaction_cutoff, 5, 1) = '-'
            AND substr(tombstone_compaction_cutoff, 8, 1) = '-'
            AND substr(tombstone_compaction_cutoff, 11, 1) = 'T'
            AND substr(tombstone_compaction_cutoff, 14, 1) = ':'
            AND substr(tombstone_compaction_cutoff, 17, 1) = ':'
            AND substr(tombstone_compaction_cutoff, 20, 1) = '.'
            AND substr(tombstone_compaction_cutoff, 24, 1) = 'Z'
            AND replace(replace(replace(replace(replace(
                tombstone_compaction_cutoff,
                '-', ''), 'T', ''), ':', ''), '.', ''), 'Z', '')
                NOT GLOB '*[^0-9]*'
        )
    ),
    database_instance_id TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    observed_at          TEXT NOT NULL CHECK (length(observed_at) = 24),
    PRIMARY KEY (account_identifier, generation),
    UNIQUE (account_identifier, zone_identifier),
    UNIQUE (account_identifier, generation_identifier),
    UNIQUE (account_identifier, ready_witness)
) STRICT;

-- The `sync_generation_snapshot_*` family is the outbound rebuild
-- pipeline: this device stages and publishes a complete new-generation
-- baseline to CloudKit.
--
-- One immutable, crash-resumable local baseline for the exact CloudKit
-- candidate lease being built. The source rows are copied once into the child
-- table inside the same transaction as this manifest; subsequent pages never
-- re-read mutable domain state. The singleton is deliberate: CloudKit exposes
-- one account-level rebuild lease and audit retention exposes one matching
-- candidate authorization at a time.
CREATE TABLE IF NOT EXISTS sync_generation_snapshot_staging (
    lease_identifier          TEXT PRIMARY KEY CHECK (
        length(lease_identifier) > 0
        AND length(CAST(lease_identifier AS BLOB)) <= 128
    ),
    singleton                 INTEGER NOT NULL DEFAULT 1 UNIQUE CHECK (singleton = 1),
    account_identifier        TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    database_instance_id      TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    candidate_zone_name       TEXT NOT NULL CHECK (
        length(candidate_zone_name) > 0
        AND length(CAST(candidate_zone_name AS BLOB)) <= 255
    ),
    generation                INTEGER NOT NULL CHECK (
        generation >= 0 AND generation <= 2147483647
    ),
    generation_identifier     TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    lease_owner_identifier    TEXT NOT NULL CHECK (
        lease_owner_identifier = database_instance_id
    ),
    retention_kind            TEXT NOT NULL CHECK (
        retention_kind IN ('active', 'candidate')
    ),
    retention_authorization_token TEXT NOT NULL CHECK (
        length(retention_authorization_token) > 0
        AND length(CAST(retention_authorization_token AS BLOB)) <= 128
    ),
    retention_source_zone_name TEXT NOT NULL CHECK (
        length(retention_source_zone_name) > 0
        AND length(CAST(retention_source_zone_name AS BLOB)) <= 255
    ),
    retention_frontier_epoch  INTEGER NOT NULL CHECK (retention_frontier_epoch >= 0),
    retention_cutoff_timestamp TEXT NOT NULL,
    retention_cutoff_entity_id TEXT NOT NULL,
    retention_policy_value    TEXT NOT NULL,
    retention_policy_version  TEXT NOT NULL CHECK (
        retention_policy_version = ''
        OR (
            length(CAST(retention_policy_version AS BLOB)) = 35
            AND substr(retention_policy_version, 14, 1) = '_'
            AND substr(retention_policy_version, 19, 1) = '_'
            AND substr(retention_policy_version, 1, 13) <= '9999913599999'
            AND substr(retention_policy_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(retention_policy_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(retention_policy_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    -- Trusted cutoff derived from the greatest exact CloudKit record receipt
    -- observed for the bound account minus the 365-day recovery window.
    -- The same value is sealed into the immutable candidate and ready control;
    -- NULL disables tombstone compaction for this capture.
    tombstone_compaction_cutoff TEXT CHECK (
        tombstone_compaction_cutoff IS NULL
        OR length(tombstone_compaction_cutoff) = 24
    ),
    source_local_change_seq   INTEGER NOT NULL CHECK (source_local_change_seq >= 0),
    record_count              INTEGER NOT NULL CHECK (
        record_count >= 0 AND record_count <= 100000
    ),
    canonical_digest          TEXT NOT NULL CHECK (
        length(canonical_digest) = 64 AND canonical_digest NOT GLOB '*[^0-9a-f]*'
    ),
    audit_record_count        INTEGER NOT NULL CHECK (
        audit_record_count >= 0 AND audit_record_count <= record_count
    ),
    audit_witness_digest      TEXT NOT NULL CHECK (
        length(audit_witness_digest) = 64
        AND audit_witness_digest NOT GLOB '*[^0-9a-f]*'
    ),
    total_encoded_bytes       INTEGER NOT NULL CHECK (
        total_encoded_bytes >= 0 AND total_encoded_bytes <= 536870912
    ),
    upload_next_ordinal       INTEGER NOT NULL DEFAULT 0 CHECK (
        upload_next_ordinal >= 0 AND upload_next_ordinal <= record_count
    ),
    readback_page_index       INTEGER NOT NULL DEFAULT 0 CHECK (
        readback_page_index >= 0 AND readback_page_index <= 1000001
    ),
    readback_continuation_token BLOB CHECK (
        readback_continuation_token IS NULL
        OR (
            length(readback_continuation_token) > 0
            AND length(readback_continuation_token) <= 262144
        )
    ),
    readback_witness_observed  INTEGER NOT NULL DEFAULT 0 CHECK (
        readback_witness_observed IN (0, 1)
    ),
    readback_complete         INTEGER NOT NULL DEFAULT 0 CHECK (
        readback_complete IN (0, 1)
    ),
    remote_record_count       INTEGER NOT NULL DEFAULT 0 CHECK (
        remote_record_count >= 0 AND remote_record_count <= 100000
    ),
    remote_total_encoded_bytes INTEGER NOT NULL DEFAULT 0 CHECK (
        remote_total_encoded_bytes >= 0
        AND remote_total_encoded_bytes <= 536870912
    ),
    remote_canonical_digest   TEXT CHECK (
        remote_canonical_digest IS NULL
        OR (
            length(remote_canonical_digest) = 64
            AND remote_canonical_digest NOT GLOB '*[^0-9a-f]*'
        )
    ),
    remote_audit_record_count INTEGER NOT NULL DEFAULT 0 CHECK (
        remote_audit_record_count >= 0
        AND remote_audit_record_count <= remote_record_count
    ),
    remote_audit_witness_digest TEXT CHECK (
        remote_audit_witness_digest IS NULL
        OR (
            length(remote_audit_witness_digest) = 64
            AND remote_audit_witness_digest NOT GLOB '*[^0-9a-f]*'
        )
    ),
    created_at                TEXT NOT NULL CHECK (length(created_at) = 24),
    FOREIGN KEY (account_identifier, database_instance_id)
        REFERENCES sync_cloudkit_account_binding(
            account_identifier, database_instance_id
        ) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CHECK (
        (readback_complete = 0
            AND remote_canonical_digest IS NULL
            AND remote_audit_witness_digest IS NULL)
        OR
        (readback_complete = 1
            AND readback_witness_observed = 1
            AND remote_canonical_digest IS NOT NULL
            AND remote_audit_witness_digest IS NOT NULL)
    )
) STRICT;

-- Exact tombstone identities intentionally omitted from an immutable candidate
-- because CloudKit had confirmed the delete before its trusted recovery cutoff.
-- Final publication deletes only rows still matching all captured values; a
-- newer local delete or refreshed version is therefore never reclaimed by a
-- late generation-finalization callback.
CREATE TABLE IF NOT EXISTS sync_generation_snapshot_compacted_tombstones (
    lease_identifier  TEXT NOT NULL
                      REFERENCES sync_generation_snapshot_staging(lease_identifier)
                      ON DELETE CASCADE,
    entity_type       TEXT NOT NULL,
    entity_id         TEXT NOT NULL,
    version           TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    cloud_confirmed_at TEXT NOT NULL CHECK (length(cloud_confirmed_at) = 24),
    PRIMARY KEY (lease_identifier, entity_type, entity_id)
) STRICT;

-- Candidate-zone save receipts are not fleet-visible authority until the
-- generation control record is CAS-published ready. Keep them under the exact
-- staging lease and promote them to sync_tombstones only inside successful
-- local publication finalization; abandoning a candidate drops them by cascade.
CREATE TABLE IF NOT EXISTS sync_generation_snapshot_tombstone_receipts (
    lease_identifier  TEXT NOT NULL
                      REFERENCES sync_generation_snapshot_staging(lease_identifier)
                      ON DELETE CASCADE,
    entity_type       TEXT NOT NULL,
    entity_id         TEXT NOT NULL,
    version           TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    server_modified_at TEXT NOT NULL CHECK (length(server_modified_at) = 24),
    PRIMARY KEY (lease_identifier, entity_type, entity_id, version)
) STRICT;

-- Canonical envelope bytes are staged once and addressed by a stable ordinal.
-- The opaque record name and per-envelope digest let readback compare compact
-- witnesses without retaining a second in-memory or on-disk payload copy.
CREATE TABLE IF NOT EXISTS sync_generation_snapshot_items (
    lease_identifier  TEXT NOT NULL
                      REFERENCES sync_generation_snapshot_staging(lease_identifier)
                      ON DELETE CASCADE,
    ordinal           INTEGER NOT NULL CHECK (ordinal >= 0 AND ordinal < 100000),
    record_name       TEXT NOT NULL CHECK (
        length(record_name) = 64 AND record_name NOT GLOB '*[^0-9a-f]*'
    ),
    canonical_envelope BLOB NOT NULL CHECK (
        length(canonical_envelope) > 0 AND length(canonical_envelope) <= 786432
    ),
    envelope_digest   TEXT NOT NULL CHECK (
        length(envelope_digest) = 64 AND envelope_digest NOT GLOB '*[^0-9a-f]*'
    ),
    encoded_byte_count INTEGER NOT NULL CHECK (
        encoded_byte_count = length(canonical_envelope)
        AND encoded_byte_count > 0 AND encoded_byte_count <= 786432
    ),
    is_audit          INTEGER NOT NULL CHECK (is_audit IN (0, 1)),
    PRIMARY KEY (lease_identifier, ordinal),
    UNIQUE (lease_identifier, record_name)
) STRICT;

-- Final-state remote inventory observed during nil-token candidate readback.
-- Repeated observations are idempotent, later values for the same record name
-- replace earlier values, and physical deletions remove the row. Payload bytes
-- never live here: this compact table is sufficient to recompute the manifest.
CREATE TABLE IF NOT EXISTS sync_generation_snapshot_readback_items (
    lease_identifier  TEXT NOT NULL
                      REFERENCES sync_generation_snapshot_staging(lease_identifier)
                      ON DELETE CASCADE,
    record_name       TEXT NOT NULL CHECK (
        length(record_name) = 64 AND record_name NOT GLOB '*[^0-9a-f]*'
    ),
    envelope_digest   TEXT NOT NULL CHECK (
        length(envelope_digest) = 64 AND envelope_digest NOT GLOB '*[^0-9a-f]*'
    ),
    encoded_byte_count INTEGER NOT NULL CHECK (
        encoded_byte_count > 0 AND encoded_byte_count <= 786432
    ),
    is_audit          INTEGER NOT NULL CHECK (is_audit IN (0, 1)),
    PRIMARY KEY (lease_identifier, record_name)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_generation_snapshot_readback_audit
    ON sync_generation_snapshot_readback_items(lease_identifier, is_audit, record_name);

-- At most one unfinished traversal per account is admitted by the typed storage
-- API. The row records the exact generation/zone and the only valid next-page
-- cursor; the opaque token is bounded so corrupted checkpoint data cannot grow
-- this local-only table without limit.
CREATE TABLE IF NOT EXISTS sync_cloudkit_traversal_progress (
    account_identifier   TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    zone_identifier      TEXT NOT NULL CHECK (
        length(zone_identifier) > 0
        AND length(CAST(zone_identifier AS BLOB)) <= 255
    ),
    database_instance_id TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    generation           INTEGER NOT NULL CHECK (generation >= 0 AND generation <= 2147483647),
    generation_identifier TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    ready_witness       TEXT NOT NULL CHECK (
        length(ready_witness) > 0
        AND length(CAST(ready_witness AS BLOB)) <= 128
    ),
    traversal_identifier TEXT NOT NULL CHECK (
        length(traversal_identifier) > 0
        AND length(CAST(traversal_identifier AS BLOB)) <= 128
    ),
    traversal_mode       TEXT NOT NULL CHECK (traversal_mode IN ('baseline', 'incremental')),
    starting_change_token BLOB CHECK (
        starting_change_token IS NULL
        OR (length(starting_change_token) > 0 AND length(starting_change_token) <= 262144)
    ),
    observed_generation_root TEXT CHECK (
        observed_generation_root IS NULL
        OR observed_generation_root = generation_identifier
    ),
    observed_ready_witness TEXT CHECK (
        observed_ready_witness IS NULL OR observed_ready_witness = ready_witness
    ),
    observed_traversal_witness TEXT CHECK (
        observed_traversal_witness IS NULL
        OR observed_traversal_witness = traversal_identifier
    ),
    observed_traversal_server_time TEXT CHECK (
        observed_traversal_server_time IS NULL
        OR length(observed_traversal_server_time) = 24
    ),
    next_page_index      INTEGER NOT NULL CHECK (
        next_page_index >= 0 AND next_page_index <= 1000001
    ),
    continuation_token   BLOB CHECK (
        continuation_token IS NULL
        OR (length(continuation_token) > 0 AND length(continuation_token) <= 262144)
    ),
    started_at           TEXT NOT NULL CHECK (length(started_at) = 24),
    updated_at           TEXT NOT NULL CHECK (length(updated_at) = 24),
    PRIMARY KEY (account_identifier),
    FOREIGN KEY (account_identifier, database_instance_id)
        REFERENCES sync_cloudkit_account_binding(
            account_identifier, database_instance_id
        ) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CHECK (
        (traversal_mode = 'baseline' AND starting_change_token IS NULL)
        OR (traversal_mode = 'incremental' AND starting_change_token IS NOT NULL)
    ),
    CHECK (
        (next_page_index = 0 AND (
            (continuation_token IS NULL AND starting_change_token IS NULL)
            OR continuation_token = starting_change_token
        ))
        OR (next_page_index > 0 AND continuation_token IS NOT NULL)
    ),
    CHECK (
        observed_traversal_server_time IS NULL
        OR observed_traversal_witness IS NOT NULL
    )
) STRICT;

-- One latest completion for the active account remains while a later traversal is in
-- progress, so a crash never erases the last
-- proven terminal snapshot. Keeping only the latest generation bounds this
-- device-local proof even if a zone is rebuilt many times. Explicit account
-- adoption clears every witness: after A -> B -> A, A's old completion no
-- longer proves the database contents that may have changed while B was active.
CREATE TABLE IF NOT EXISTS sync_cloudkit_traversal_witness (
    account_identifier   TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    zone_identifier      TEXT NOT NULL CHECK (
        length(zone_identifier) > 0
        AND length(CAST(zone_identifier AS BLOB)) <= 255
    ),
    database_instance_id TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    generation           INTEGER NOT NULL CHECK (generation >= 0 AND generation <= 2147483647),
    generation_identifier TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    ready_witness       TEXT NOT NULL CHECK (
        length(ready_witness) > 0
        AND length(CAST(ready_witness AS BLOB)) <= 128
    ),
    traversal_identifier TEXT NOT NULL CHECK (
        length(traversal_identifier) > 0
        AND length(CAST(traversal_identifier AS BLOB)) <= 128
    ),
    traversal_mode       TEXT NOT NULL CHECK (traversal_mode = 'baseline'),
    observed_generation_root TEXT NOT NULL CHECK (
        observed_generation_root = generation_identifier
    ),
    observed_ready_witness TEXT NOT NULL CHECK (
        observed_ready_witness = ready_witness
    ),
    observed_traversal_witness TEXT NOT NULL CHECK (
        observed_traversal_witness = traversal_identifier
    ),
    completed_page_count INTEGER NOT NULL CHECK (
        completed_page_count > 0 AND completed_page_count <= 1000001
    ),
    final_change_token   BLOB CHECK (
        final_change_token IS NULL
        OR (length(final_change_token) > 0 AND length(final_change_token) <= 262144)
    ),
    completed_at         TEXT NOT NULL CHECK (length(completed_at) = 24),
    PRIMARY KEY (account_identifier),
    FOREIGN KEY (account_identifier, database_instance_id)
        REFERENCES sync_cloudkit_account_binding(
            account_identifier, database_instance_id
        ) ON UPDATE RESTRICT ON DELETE RESTRICT
) STRICT;

-- A terminal incremental cursor is resumable transport state, not proof that
-- the database observed the zone from its beginning. It is therefore stored
-- separately and can never overwrite or downgrade the baseline witness above.
CREATE TABLE IF NOT EXISTS sync_cloudkit_incremental_cursor (
    account_identifier   TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    zone_identifier      TEXT NOT NULL CHECK (
        length(zone_identifier) > 0
        AND length(CAST(zone_identifier AS BLOB)) <= 255
    ),
    database_instance_id TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    generation           INTEGER NOT NULL CHECK (generation >= 0 AND generation <= 2147483647),
    generation_identifier TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    ready_witness       TEXT NOT NULL CHECK (
        length(ready_witness) > 0
        AND length(CAST(ready_witness AS BLOB)) <= 128
    ),
    traversal_identifier TEXT NOT NULL CHECK (
        length(traversal_identifier) > 0
        AND length(CAST(traversal_identifier AS BLOB)) <= 128
    ),
    completed_page_count INTEGER NOT NULL CHECK (
        completed_page_count > 0 AND completed_page_count <= 1000001
    ),
    change_token         BLOB NOT NULL CHECK (
        length(change_token) > 0 AND length(change_token) <= 262144
    ),
    completed_at         TEXT NOT NULL CHECK (length(completed_at) = 24),
    PRIMARY KEY (account_identifier),
    FOREIGN KEY (account_identifier, database_instance_id)
        REFERENCES sync_cloudkit_account_binding(
            account_identifier, database_instance_id
        ) ON UPDATE RESTRICT ON DELETE RESTRICT
) STRICT;


-- Durable fail-closed debt for a LorvexEntity record whose encrypted envelope
-- could not be decoded or applied while the CloudKit change cursor advanced.
-- The exact account/zone/generation scope prevents an old lineage from blocking
-- a later ready generation. A valid replacement or physical deletion of the
-- same record name clears the fence; an authoritative full snapshot clears the
-- whole scoped set only after its complete inventory finalized successfully.
CREATE TABLE IF NOT EXISTS sync_cloudkit_corrupt_record_fences (
    account_identifier    TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    zone_identifier       TEXT NOT NULL CHECK (
        length(zone_identifier) > 0
        AND length(CAST(zone_identifier AS BLOB)) <= 255
    ),
    generation            INTEGER NOT NULL CHECK (
        generation >= 0 AND generation <= 2147483647
    ),
    generation_identifier TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    ready_witness          TEXT NOT NULL CHECK (
        length(ready_witness) > 0
        AND length(CAST(ready_witness AS BLOB)) <= 128
    ),
    record_name            TEXT NOT NULL CHECK (
        length(record_name) > 0
        AND length(CAST(record_name AS BLOB)) <= 1024
    ),
    first_observed_at      TEXT NOT NULL CHECK (length(first_observed_at) = 24),
    last_observed_at       TEXT NOT NULL CHECK (length(last_observed_at) = 24),
    PRIMARY KEY (
        account_identifier, zone_identifier, generation,
        generation_identifier, ready_witness, record_name
    )
) STRICT;


-- The `sync_authoritative_snapshot*` family is the inbound counterpart of
-- `sync_generation_snapshot_*`: this device adopts a complete
-- peer-published zone snapshot as local truth.
--
-- Durable state for the rare over-window recovery that treats a complete
-- CloudKit zone snapshot as authoritative. `preparing` means a relaunch must
-- repeat token clearing + traversal-witness publication (the pre-session queue
-- fence committed atomically with session creation and must never repeat);
-- `ready` is the only phase allowed to fetch the already-durable nil-token
-- traversal; and `pulling` means at least one page has been staged and every
-- continuation checkpoint must bind to this exact session and database.
CREATE TABLE IF NOT EXISTS sync_authoritative_snapshot (
    session_token      TEXT PRIMARY KEY CHECK (
        length(session_token) > 0 AND length(session_token) <= 128
    ),
    singleton          INTEGER NOT NULL DEFAULT 1 UNIQUE CHECK (singleton = 1),
    account_identifier TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ),
    zone_name          TEXT NOT NULL CHECK (
        length(zone_name) > 0
        AND length(CAST(zone_name AS BLOB)) <= 255
    ),
    generation         INTEGER NOT NULL CHECK (generation >= 0 AND generation <= 2147483647),
    generation_identifier TEXT NOT NULL CHECK (
        length(generation_identifier) > 0
        AND length(CAST(generation_identifier AS BLOB)) <= 128
    ),
    ready_witness      TEXT NOT NULL CHECK (
        length(ready_witness) > 0
        AND length(CAST(ready_witness AS BLOB)) <= 128
    ),
    database_instance_id TEXT NOT NULL CHECK (
        length(database_instance_id) > 0
        AND length(CAST(database_instance_id AS BLOB)) <= 128
    ),
    phase              TEXT NOT NULL CHECK (phase IN ('preparing', 'ready', 'pulling')),
    staged_record_count INTEGER NOT NULL DEFAULT 0 CHECK (
        staged_record_count >= 0 AND staged_record_count <= 100000
    ),
    staged_encoded_bytes INTEGER NOT NULL DEFAULT 0 CHECK (
        staged_encoded_bytes >= 0 AND staged_encoded_bytes <= 536870912
    ),
    -- Highest outbox row id visible when the original adoption intent began.
    -- Rows above this boundary are durable post-session local intent. Keep the
    -- original boundary across restart/replacement so wall-clock equality and
    -- process relaunch cannot reclassify an edit.
    outbox_boundary_id  INTEGER NOT NULL CHECK (outbox_boundary_id >= 0),
    started_at         TEXT NOT NULL CHECK (length(started_at) = 24),
    FOREIGN KEY (account_identifier, database_instance_id)
        REFERENCES sync_cloudkit_account_binding(
            account_identifier, database_instance_id
        ) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CHECK (staged_record_count > 0 OR staged_encoded_bytes = 0)
) STRICT;

-- Current `LorvexEntity` records observed while draining the authoritative
-- nil-token snapshot. `envelope` is present only when this build fully decoded
-- the record. Unknown/corrupt rows are still inventoried but make finalization
-- fail closed; otherwise deleting local rows against an incomplete view could
-- destroy data. A CloudKit-level physical deletion removes the matching row.
CREATE TABLE IF NOT EXISTS sync_authoritative_snapshot_records (
    session_id TEXT NOT NULL
               REFERENCES sync_authoritative_snapshot(session_token)
               ON UPDATE CASCADE ON DELETE CASCADE,
    record_name TEXT NOT NULL CHECK (
        length(record_name) > 0 AND length(CAST(record_name AS BLOB)) <= 512
    ),
    state       TEXT NOT NULL CHECK (state IN ('decoded', 'unknown', 'corrupt')),
    -- Decoded and future/unknown records both retain complete envelope bytes;
    -- only structurally corrupt records carry no body and fail finalization.
    envelope    TEXT CHECK (
        envelope IS NULL
        OR (
            length(CAST(envelope AS BLOB)) > 0
            AND length(CAST(envelope AS BLOB)) <= 786432
        )
    ),
    server_modified_at TEXT CHECK (
        server_modified_at IS NULL OR length(server_modified_at) = 24
    ),
    PRIMARY KEY (session_id, record_name),
    CHECK (
        (state IN ('decoded', 'unknown') AND envelope IS NOT NULL)
        OR (state = 'corrupt' AND envelope IS NULL)
    )
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
                        -- because the local tombstone is newer, or
                        -- equal-versioned on the redirect path (the
                        -- direct path routes an equal-HLC pair
                        -- through the equal-version repair join and
                        -- never reaches this arm). Logged here so the
                        -- skip is auditable in the diagnostics
                        -- surface (which only displays
                        -- conflict_log entries).
                        'tombstone_wins',
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
                        'upsert_wins_over_delete'
                    ))
) STRICT;

-- Durable operational claim ledger for task list-fallback convergence re-emits.
-- When an inbound task names a tombstoned/absent list, the receiver rehomes it
-- and emits one fresh-HLC snapshot. Two devices with mutually tombstoned
-- fallback targets would otherwise re-emit strictly newer snapshots forever.
-- Unlike `sync_conflict_log`, these rows are correctness state and MUST NOT be
-- age-reaped. The task FK bounds their lifetime naturally; authoritative-zone
-- adoption clears the whole ledger because it replaces the local history that
-- justified every old claim. `payload_list_id` deliberately has no FK because
-- the claimed list is absent or tombstoned at claim time.
CREATE TABLE IF NOT EXISTS sync_list_fallback_reemit_claims (
    task_id         TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    payload_list_id TEXT NOT NULL,
    PRIMARY KEY (task_id, payload_list_id)
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
    envelope_version      TEXT NOT NULL CHECK (
        length(envelope_version) = 35
        AND substr(envelope_version, 14, 1) = '_'
        AND substr(envelope_version, 19, 1) = '_'
        AND substr(envelope_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(envelope_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(envelope_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    first_attempted_at    TEXT NOT NULL,
    last_attempted_at     TEXT NOT NULL,
    attempt_count         INTEGER NOT NULL DEFAULT 1 CHECK (attempt_count >= 1),
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
-- benignly skipped. Terminal CloudKit completeness therefore counts
-- this table as durable unmaterialized debt. A valid same-slot
-- replacement clears dominated versions; authoritative snapshot
-- adoption clears the table. Horizon GC first persists reseed_required,
-- so shedding an old poison identity cannot make restore proof pass.
CREATE TABLE IF NOT EXISTS sync_quarantine_blocklist (
    entity_type   TEXT NOT NULL,
    entity_id     TEXT NOT NULL,
    version       TEXT NOT NULL CHECK (
        length(version) = 35 AND substr(version, 14, 1) = '_' AND substr(version, 19, 1) = '_'
        AND substr(version, 1, 13) <= '9999913599999'
        AND substr(version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    quarantined_at TEXT NOT NULL,
    PRIMARY KEY (entity_type, entity_id, version)
) STRICT;
CREATE INDEX IF NOT EXISTS idx_sync_quarantine_blocklist_quarantined_at
    ON sync_quarantine_blocklist(quarantined_at);

-- `updated_at` on the local-only `local_counters` table is an
-- epoch-millisecond INTEGER, not a TEXT string, so the counter bump
-- orders numerically. Storing it as a lex-compared TEXT string works only
-- while every digit count matches; it breaks at year 2286 / on width
-- drift / on whitespace. INTEGER forces SQLite to compare numerically
-- end-to-end.

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
    -- transitions. Payloads are valid serialized JSON capped at 4000
    -- bytes each. An over-budget state becomes a structured truncation
    -- sentinel with a bounded preview; a raw prefix plus an ellipsis is
    -- deliberately forbidden because it cannot cross the sync contract.
    before_json      TEXT CHECK (before_json IS NULL OR json_valid(before_json)),
    after_json       TEXT CHECK (after_json IS NULL OR json_valid(after_json)),
    -- Local retention provenance. `retention_epoch` is carried on audit
    -- upsert payloads; the account identifier never leaves this database. An
    -- epoch is meaningful only inside its account. Exact cloud presence is
    -- represented once, zone-scoped, in audit_changelog_cloud_presence below.
    -- Rows authored before the first iCloud binding stay account-NULL until
    -- that one-time binding normalizes them atomically with their outbox copy.
    retention_epoch  INTEGER NOT NULL DEFAULT 0
                     CHECK (retention_epoch >= 0),
    retention_account_identifier TEXT
                     CHECK (
                         retention_account_identifier IS NULL
                         OR (
                             length(retention_account_identifier) > 0
                             AND length(retention_account_identifier) <= 512
                         )
                     )
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

-- The audit-retention frontier is deliberately account-scoped. CloudKit
-- account A's generation must never teach account B to reject rows, nor may a
-- queued A audit record be uploaded after the process switches to B.
-- `audit_retention_binding` holds the one unbound candidate used only by the
-- first-ever binding plus the durable current account identity. A later
-- account switch creates/loads independent state below.
CREATE TABLE IF NOT EXISTS audit_retention_binding (
    singleton                         INTEGER PRIMARY KEY
                                      CHECK (singleton = 1),
    active_account_identifier         TEXT
                                      CHECK (
                                          active_account_identifier IS NULL
                                          OR (
                                              length(active_account_identifier) > 0
                                              AND length(CAST(active_account_identifier AS BLOB)) <= 512
                                          )
                                      ),
    active_zone_name                  TEXT
                                      CHECK (
                                          active_zone_name IS NULL
                                          OR (
                                              length(active_zone_name) > 0
                                              AND length(CAST(active_zone_name AS BLOB)) <= 512
                                          )
                                      ),
    ever_bound                        INTEGER NOT NULL DEFAULT 0
                                      CHECK (ever_bound IN (0, 1)),
    unbound_frontier_epoch            INTEGER NOT NULL DEFAULT 0
                                      CHECK (unbound_frontier_epoch >= 0),
    unbound_frontier_cutoff_timestamp TEXT NOT NULL DEFAULT '' CHECK (
        unbound_frontier_cutoff_timestamp = ''
        OR length(unbound_frontier_cutoff_timestamp) = 24
    ),
    unbound_frontier_cutoff_entity_id TEXT NOT NULL DEFAULT '' CHECK (
        length(CAST(unbound_frontier_cutoff_entity_id AS BLOB)) <= 512
    ),
    unbound_policy_authorized_epoch   INTEGER NOT NULL DEFAULT 0
                                      CHECK (
                                          unbound_policy_authorized_epoch >= 0
                                          AND unbound_policy_authorized_epoch
                                              <= unbound_frontier_epoch
                                      ),
    unbound_policy_value              TEXT NOT NULL DEFAULT '"maximum"',
    unbound_policy_version            TEXT NOT NULL DEFAULT '' CHECK (
        unbound_policy_version = ''
        OR (
            length(CAST(unbound_policy_version AS BLOB)) = 35
            AND substr(unbound_policy_version, 14, 1) = '_'
            AND substr(unbound_policy_version, 19, 1) = '_'
            AND substr(unbound_policy_version, 1, 13) <= '9999913599999'
            AND substr(unbound_policy_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(unbound_policy_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(unbound_policy_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    unbound_policy_ready              INTEGER NOT NULL DEFAULT 1
                                      CHECK (unbound_policy_ready IN (0, 1)),
    updated_at                        TEXT NOT NULL DEFAULT
                                      (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                                      CHECK (length(updated_at) = 24),
    CHECK (
        (ever_bound = 0
         AND active_account_identifier IS NULL
         AND active_zone_name IS NULL)
        OR
        (ever_bound = 1
         AND active_account_identifier IS NOT NULL
         AND active_zone_name IS NOT NULL)
    ),
    CHECK (
        unbound_policy_ready = 0
        OR unbound_policy_authorized_epoch = unbound_frontier_epoch
    ),
    CHECK (
        unbound_frontier_cutoff_timestamp <> ''
        OR unbound_frontier_cutoff_entity_id = ''
    )
) STRICT;

INSERT OR IGNORE INTO audit_retention_binding (singleton) VALUES (1);

CREATE TABLE IF NOT EXISTS audit_retention_account_state (
    account_identifier       TEXT PRIMARY KEY
                             CHECK (
                                 length(account_identifier) > 0
                                 AND length(CAST(account_identifier AS BLOB)) <= 512
                             ),
    frontier_epoch           INTEGER NOT NULL DEFAULT 0
                             CHECK (frontier_epoch >= 0),
    frontier_cutoff_timestamp TEXT NOT NULL DEFAULT '' CHECK (
        frontier_cutoff_timestamp = '' OR length(frontier_cutoff_timestamp) = 24
    ),
    frontier_cutoff_entity_id TEXT NOT NULL DEFAULT '' CHECK (
        length(CAST(frontier_cutoff_entity_id AS BLOB)) <= 512
    ),
    confirmed_frontier_epoch INTEGER NOT NULL DEFAULT 0
                             CHECK (
                                 confirmed_frontier_epoch >= 0
                                 AND confirmed_frontier_epoch <= frontier_epoch
                             ),
    confirmed_cutoff_timestamp TEXT NOT NULL DEFAULT '' CHECK (
        confirmed_cutoff_timestamp = '' OR length(confirmed_cutoff_timestamp) = 24
    ),
    confirmed_cutoff_entity_id TEXT NOT NULL DEFAULT '' CHECK (
        length(CAST(confirmed_cutoff_entity_id AS BLOB)) <= 512
    ),
    policy_authorized_epoch  INTEGER NOT NULL DEFAULT 0
                             CHECK (
                                 policy_authorized_epoch >= 0
                                 AND policy_authorized_epoch <= frontier_epoch
                             ),
    policy_value             TEXT NOT NULL DEFAULT '"maximum"',
    policy_version           TEXT NOT NULL DEFAULT '' CHECK (
        policy_version = ''
        OR (
            length(CAST(policy_version AS BLOB)) = 35
            AND substr(policy_version, 14, 1) = '_'
            AND substr(policy_version, 19, 1) = '_'
            AND substr(policy_version, 1, 13) <= '9999913599999'
            AND substr(policy_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(policy_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(policy_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    policy_ready             INTEGER NOT NULL DEFAULT 0
                             CHECK (policy_ready IN (0, 1)),
    refresh_required_epoch   INTEGER
                             CHECK (
                                 refresh_required_epoch IS NULL
                                 OR refresh_required_epoch >= 0
                             ),
    created_at               TEXT NOT NULL DEFAULT
                             (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                             CHECK (length(created_at) = 24),
    updated_at               TEXT NOT NULL DEFAULT
                             (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                             CHECK (length(updated_at) = 24),
    CHECK (
        policy_ready = 0 OR policy_authorized_epoch = frontier_epoch
    ),
    CHECK (frontier_cutoff_timestamp <> '' OR frontier_cutoff_entity_id = ''),
    CHECK (confirmed_cutoff_timestamp <> '' OR confirmed_cutoff_entity_id = ''),
    CHECK (
        confirmed_frontier_epoch < frontier_epoch
        OR (
            confirmed_frontier_epoch = frontier_epoch
            AND (
                confirmed_cutoff_timestamp < frontier_cutoff_timestamp
                OR (
                    confirmed_cutoff_timestamp = frontier_cutoff_timestamp
                    AND confirmed_cutoff_entity_id <= frontier_cutoff_entity_id
                )
            )
        )
    )
) STRICT;

-- A push authorization is minted only by the typed "join verified remote
-- frontier" API. The mark-before-cloud API requires the opaque token and the
-- exact frontier snapshot, making a forgotten pre-push frontier fetch fail
-- closed instead of reusing a stale account state from an earlier cycle.
CREATE TABLE IF NOT EXISTS audit_retention_outbound_authorization (
    singleton                 INTEGER PRIMARY KEY CHECK (singleton = 1),
    token                     TEXT NOT NULL UNIQUE CHECK (
        length(token) > 0 AND length(CAST(token AS BLOB)) <= 128
    ),
    account_identifier        TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ) REFERENCES audit_retention_account_state(account_identifier) ON DELETE RESTRICT,
    zone_name                 TEXT NOT NULL
                              CHECK (
                                  length(zone_name) > 0
                                  AND length(CAST(zone_name AS BLOB)) <= 512
                              ),
    frontier_epoch            INTEGER NOT NULL CHECK (frontier_epoch >= 0),
    frontier_cutoff_timestamp TEXT NOT NULL CHECK (
        frontier_cutoff_timestamp = '' OR length(frontier_cutoff_timestamp) = 24
    ),
    frontier_cutoff_entity_id TEXT NOT NULL CHECK (
        length(CAST(frontier_cutoff_entity_id AS BLOB)) <= 512
    ),
    created_at                TEXT NOT NULL CHECK (length(created_at) = 24),
    CHECK (frontier_cutoff_timestamp <> '' OR frontier_cutoff_entity_id = '')
) STRICT;

-- A candidate-generation authorization is deliberately separate from the
-- ordinary outbound authorization. It proves that a snapshot was derived from
-- the still-active account/zone/frontier while allowing cloud-presence evidence
-- to be recorded for a fresh, not-yet-active zone. Candidate construction never
-- rewrites `audit_retention_binding.active_zone_name`; only the final activation
-- transaction does that after the remote ready CAS succeeds.
CREATE TABLE IF NOT EXISTS audit_retention_candidate_authorization (
    singleton                 INTEGER PRIMARY KEY CHECK (singleton = 1),
    token                     TEXT NOT NULL UNIQUE CHECK (
        length(token) > 0 AND length(CAST(token AS BLOB)) <= 128
    ),
    account_identifier        TEXT NOT NULL CHECK (
        length(account_identifier) > 0
        AND length(CAST(account_identifier AS BLOB)) <= 512
    ) REFERENCES audit_retention_account_state(account_identifier) ON DELETE RESTRICT,
    source_active_zone_name   TEXT NOT NULL
                              CHECK (
                                  length(source_active_zone_name) > 0
                                  AND length(CAST(source_active_zone_name AS BLOB)) <= 512
                              ),
    candidate_zone_name       TEXT NOT NULL
                              CHECK (
                                  length(candidate_zone_name) > 0
                                  AND length(CAST(candidate_zone_name AS BLOB)) <= 512
                                  AND candidate_zone_name <> source_active_zone_name
                              ),
    frontier_epoch            INTEGER NOT NULL CHECK (frontier_epoch >= 0),
    frontier_cutoff_timestamp TEXT NOT NULL CHECK (
        frontier_cutoff_timestamp = '' OR length(frontier_cutoff_timestamp) = 24
    ),
    frontier_cutoff_entity_id TEXT NOT NULL CHECK (
        length(CAST(frontier_cutoff_entity_id AS BLOB)) <= 512
    ),
    policy_value              TEXT NOT NULL,
    policy_version            TEXT NOT NULL CHECK (
        policy_version = ''
        OR (
            length(CAST(policy_version AS BLOB)) = 35
            AND substr(policy_version, 14, 1) = '_'
            AND substr(policy_version, 19, 1) = '_'
            AND substr(policy_version, 1, 13) <= '9999913599999'
            AND substr(policy_version, 1, 13) NOT GLOB '*[^0-9]*'
            AND substr(policy_version, 15, 4) NOT GLOB '*[^0-9]*'
            AND substr(policy_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
        )
    ),
    created_at                TEXT NOT NULL CHECK (length(created_at) = 24),
    CHECK (frontier_cutoff_timestamp <> '' OR frontier_cutoff_entity_id = '')
) STRICT;

-- Durable evidence that a record may exist in one exact account-generation
-- zone. A new generation adds a sibling mapping; it never overwrites evidence
-- for the retired zone.
-- Intentionally no FK to `ai_changelog`: local pruning must not destroy the
-- account evidence needed to issue and acknowledge a physical CloudKit delete.
CREATE TABLE IF NOT EXISTS audit_changelog_cloud_presence (
    account_identifier TEXT NOT NULL
                       CHECK (
                           length(account_identifier) > 0
                           AND length(CAST(account_identifier AS BLOB)) <= 512
                       ),
    zone_name          TEXT NOT NULL
                       CHECK (
                           length(zone_name) > 0
                           AND length(CAST(zone_name AS BLOB)) <= 512
                       ),
    entity_id          TEXT NOT NULL CHECK (
        length(entity_id) > 0 AND length(CAST(entity_id AS BLOB)) <= 512
    ),
    retention_epoch    INTEGER NOT NULL CHECK (retention_epoch >= 0),
    marked_at          TEXT NOT NULL CHECK (length(marked_at) = 24),
    PRIMARY KEY (account_identifier, zone_name, entity_id),
    FOREIGN KEY (account_identifier)
        REFERENCES audit_retention_account_state(account_identifier) ON DELETE RESTRICT
) STRICT;

-- Account-scoped CloudKit physical-delete work. A row leaves this table only
-- after transport acknowledges the remote deletion. Failures retain the item
-- with bounded exponential backoff; switching accounts cannot acknowledge or
-- upload another account's work.
CREATE TABLE IF NOT EXISTS audit_retention_purge_queue (
    account_identifier TEXT NOT NULL
                       CHECK (
                           length(account_identifier) > 0
                           AND length(CAST(account_identifier AS BLOB)) <= 512
                       ),
    zone_name          TEXT NOT NULL
                       CHECK (
                           length(zone_name) > 0
                           AND length(CAST(zone_name AS BLOB)) <= 512
                       ),
    entity_id          TEXT NOT NULL CHECK (
        length(entity_id) > 0 AND length(CAST(entity_id AS BLOB)) <= 512
    ),
    retention_epoch    INTEGER NOT NULL CHECK (retention_epoch >= 0),
    reason             TEXT NOT NULL
                       CHECK (reason IN (
                           'below_frontier',
                           'policy_horizon',
                           'local_retention',
                           'orphaned_cloud_presence',
                           'reset_tombstone'
                       )),
    attempt_count      INTEGER NOT NULL DEFAULT 0
                       CHECK (attempt_count >= 0),
    next_attempt_at    TEXT CHECK (
        next_attempt_at IS NULL OR length(next_attempt_at) = 24
    ),
    last_error         TEXT CHECK (last_error IS NULL OR length(last_error) <= 2000),
    created_at         TEXT NOT NULL CHECK (length(created_at) = 24),
    updated_at         TEXT NOT NULL CHECK (length(updated_at) = 24),
    PRIMARY KEY (account_identifier, zone_name, entity_id),
    FOREIGN KEY (account_identifier)
        REFERENCES audit_retention_account_state(account_identifier) ON DELETE RESTRICT
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
-- them without a residual `archived_at IS NULL` row-level filter. Archived
-- rows are retained for explicit lifecycle operations and full
-- backup export; there is no archived-catalog or age-cutoff scan to index.
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
-- Expression index over the effective action date for the actionable day
-- buckets (today pool, upcoming, and the list scheduled-range filter). Every
-- caller spells its guards exactly `status IN ('open', 'in_progress') AND
-- archived_at IS NULL`, and SQLite only uses a partial index when the query
-- predicate contains (or provably implies) the index predicate — so this
-- partial WHERE must stay byte-aligned with StatusName.actionableStatusSqlList
-- plus the archived guard. The ascending expression key also streams the
-- upcoming lane's leading `COALESCE(planned_date, due_date) ASC` sort term.
CREATE INDEX IF NOT EXISTS idx_tasks_action_date_actionable
    ON tasks(COALESCE(planned_date, due_date))
    WHERE status IN ('open', 'in_progress') AND archived_at IS NULL;
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
CREATE INDEX IF NOT EXISTS idx_ai_changelog_retention_scope
    ON ai_changelog(retention_account_identifier, retention_epoch, timestamp, id);
CREATE INDEX IF NOT EXISTS idx_audit_retention_purge_pending
    ON audit_retention_purge_queue(
        account_identifier, zone_name, next_attempt_at, created_at, entity_id
    );
CREATE INDEX IF NOT EXISTS idx_audit_changelog_presence_entity
    ON audit_changelog_cloud_presence(entity_id, account_identifier, zone_name);

-- idx_daily_reviews_date removed: PK on (date) already serves as the index.
-- The daily_review_task_links / daily_review_list_links child tables are read
-- only by review_date (PK-served), so neither carries a reverse-lookup
-- secondary index on task_id / list_id (unlike current_focus_items, whose
-- task_id IS reverse-looked-up on task delete via idx_focus_items_task).

-- Partial index on the active pending subset. The canonical
-- get_pending query is `WHERE synced_at IS NULL AND disposition
-- IS NULL AND retry_count < ?
-- ORDER BY id ASC`; `retry_count` rides as a trailing index column so
-- the entire predicate can be evaluated from the index without a
-- base-row read per candidate. The leading `id ASC` drives the FIFO
-- sort as an index walk, and the partial WHERE keeps the index narrow
-- even while retry-wait rows or authoritative-adoption fences are
-- retained outside the active queue.
CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending
    ON sync_outbox(id, retry_count)
    WHERE synced_at IS NULL AND disposition IS NULL;
CREATE INDEX IF NOT EXISTS idx_sync_outbox_retry_due
    ON sync_outbox(next_retry_at, id)
    WHERE synced_at IS NULL AND disposition = 'retry_wait';
-- Normally empty and therefore almost free to maintain. The owner index makes
-- explicit release and FK-cascade parent deletion proportional to that
-- session's fences; the separate age index keeps defensive retention bounded.
CREATE INDEX IF NOT EXISTS idx_sync_outbox_authoritative_owner
    ON sync_outbox(authoritative_session_token)
    WHERE synced_at IS NULL AND disposition = 'authoritative_adoption';
CREATE INDEX IF NOT EXISTS idx_sync_outbox_authoritative_gc
    ON sync_outbox(created_at)
    WHERE synced_at IS NULL AND disposition = 'authoritative_adoption';
CREATE INDEX IF NOT EXISTS idx_sync_outbox_future_hold_identity
    ON sync_outbox(entity_type, entity_id, future_record_version)
    WHERE synced_at IS NULL AND disposition = 'future_record_hold';
CREATE INDEX IF NOT EXISTS idx_sync_outbox_entity ON sync_outbox(entity_type, entity_id);
-- DB-level enforcement of the single-unsynced-row-
-- per-entity coalescing invariant. The coalesced enqueue
-- runs SELECT → DELETE → INSERT on this table; without this UNIQUE
-- partial index two concurrent connections (Apple app + MCP host or
-- extension processes, or parallel MCP commands) could both pass the SELECT
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
CREATE INDEX IF NOT EXISTS idx_focus_schedule_blocks_calendar_event
    ON focus_schedule_blocks(calendar_event_id) WHERE calendar_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sync_tombstones_version
    ON sync_tombstones(version);
CREATE INDEX IF NOT EXISTS idx_sync_entity_redirects_target
    ON sync_entity_redirects(source_type, target_id);
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
-- Visible replacement decisions are fetched by their materialized timing,
-- independently of the original occurrence date they replace. Cancelled and
-- inherit registers never enter this range scan.
CREATE INDEX IF NOT EXISTS idx_calendar_events_replacement_range
    ON calendar_events(start_date, end_date, start_time)
    WHERE occurrence_state = 'replacement';

CREATE INDEX IF NOT EXISTS idx_error_logs_created_at ON error_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_error_logs_source ON error_logs(source, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_task_reminders_due ON task_reminders(reminder_at) WHERE dismissed_at IS NULL AND cancelled_at IS NULL;
-- Compound key (task_id, reminder_at) so the per-task fetch's ORDER
-- BY reminder_at lands on an index walk instead of a TEMP B-TREE
-- filesort. Used by `enrich_tasks_with_reminders` (mcp-server's
-- task-detail enrichment, hot path in get_task / get_todays_tasks).
CREATE INDEX IF NOT EXISTS idx_task_reminders_task ON task_reminders(task_id, reminder_at ASC);
CREATE INDEX IF NOT EXISTS idx_task_checklist_items_task ON task_checklist_items(task_id, position);

CREATE INDEX IF NOT EXISTS idx_habit_completions_date_range ON habit_completions(completed_date DESC);

CREATE INDEX IF NOT EXISTS idx_tasks_planned_date ON tasks(planned_date) WHERE planned_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_available_from ON tasks(available_from) WHERE available_from IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_spawned_from ON tasks(spawned_from) WHERE spawned_from IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sync_pending_inbox_missing ON sync_pending_inbox(missing_entity_type, missing_entity_id);
CREATE INDEX IF NOT EXISTS idx_sync_pending_inbox_drain ON sync_pending_inbox(last_attempted_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_sync_pending_inbox_first_attempted ON sync_pending_inbox(first_attempted_at);

-- Tag lookup by normalized name (hot path for MCP tag resolution)
CREATE INDEX IF NOT EXISTS idx_tags_lookup_key ON tags(lookup_key);

-- Provider calendar events: timeline range query hot path
CREATE INDEX IF NOT EXISTS idx_provider_events_start ON provider_calendar_events(start_date);
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
--
-- ROWID INVARIANT (applies to every FTS table below): the FTS mappings key
-- off the implicit rowids of TEXT-PK tables (`tasks`, `calendar_events`).
-- VACUUM renumbers implicit rowids on tables without an INTEGER PRIMARY KEY,
-- so running VACUUM would silently scramble every FTS mapping. No VACUUM
-- exists anywhere in the codebase; any future compaction feature must rebuild
-- all FTS tables in the same maintenance pass.
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
VALUES ('inbox', 'Inbox', '📥', '0000000000000_0000_0000000000000000', '1970-01-01T00:00:00.000Z', '1970-01-01T00:00:00.000Z');

INSERT OR IGNORE INTO preferences (key, value, version, updated_at)
VALUES ('default_list_id', '"inbox"', '0000000000000_0000_0000000000000000', '1970-01-01T00:00:00.000Z');


-- ── J. Sync Payload Shadow ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sync_payload_shadow (
    entity_type            TEXT NOT NULL,
    entity_id              TEXT NOT NULL,
    base_version           TEXT NOT NULL CHECK (
        length(base_version) = 35
        AND substr(base_version, 14, 1) = '_'
        AND substr(base_version, 19, 1) = '_'
        AND substr(base_version, 1, 13) <= '9999913599999'
        AND substr(base_version, 1, 13) NOT GLOB '*[^0-9]*'
        AND substr(base_version, 15, 4) NOT GLOB '*[^0-9]*'
        AND substr(base_version, 20, 16) NOT GLOB '*[^0-9a-f]*'
    ),
    -- Persisted as SQLite INTEGER but converted to UInt32 when promotion
    -- reconstructs a SyncEnvelope. Keep the storage domain identical to the
    -- wire type and reject the envelope-invalid zero value at the DB boundary.
    payload_schema_version INTEGER NOT NULL
                           CHECK (payload_schema_version BETWEEN 1 AND 4294967295),
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

-- ── L. Local Watch Command Ledger ────────────────────────────────────
-- Phone-local receipt/high-water state for the durable Watch command
-- protocol. These rows are deliberately absent from every sync payload,
-- export, and import contract. They never expire: a delayed WCSession retry
-- must not become eligible to apply again after a time-based cache sweep.
CREATE TABLE IF NOT EXISTS local_watch_command_streams (
    source_install_id       TEXT NOT NULL CHECK (
      length(source_install_id) = 36
      AND substr(source_install_id, 9, 1) = '-'
      AND substr(source_install_id, 14, 1) = '-'
      AND substr(source_install_id, 19, 1) = '-'
      AND substr(source_install_id, 24, 1) = '-'
      AND length(replace(source_install_id, '-', '')) = 32
      AND replace(source_install_id, '-', '') NOT GLOB '*[^0-9a-f]*'
    ),
    workspace_instance_id   TEXT NOT NULL CHECK (
      length(workspace_instance_id) = 36
      AND substr(workspace_instance_id, 9, 1) = '-'
      AND substr(workspace_instance_id, 14, 1) = '-'
      AND substr(workspace_instance_id, 19, 1) = '-'
      AND substr(workspace_instance_id, 24, 1) = '-'
      AND length(replace(workspace_instance_id, '-', '')) = 32
      AND replace(workspace_instance_id, '-', '') NOT GLOB '*[^0-9a-f]*'
    ),
    last_terminal_sequence  INTEGER NOT NULL CHECK (last_terminal_sequence > 0),
    updated_at              TEXT NOT NULL CHECK (length(updated_at) = 24),
    PRIMARY KEY (source_install_id, workspace_instance_id)
) STRICT;

CREATE TABLE IF NOT EXISTS local_watch_command_receipts (
    source_install_id       TEXT NOT NULL CHECK (
      length(source_install_id) = 36
      AND substr(source_install_id, 9, 1) = '-'
      AND substr(source_install_id, 14, 1) = '-'
      AND substr(source_install_id, 19, 1) = '-'
      AND substr(source_install_id, 24, 1) = '-'
      AND length(replace(source_install_id, '-', '')) = 32
      AND replace(source_install_id, '-', '') NOT GLOB '*[^0-9a-f]*'
    ),
    workspace_instance_id   TEXT NOT NULL CHECK (
      length(workspace_instance_id) = 36
      AND substr(workspace_instance_id, 9, 1) = '-'
      AND substr(workspace_instance_id, 14, 1) = '-'
      AND substr(workspace_instance_id, 19, 1) = '-'
      AND substr(workspace_instance_id, 24, 1) = '-'
      AND length(replace(workspace_instance_id, '-', '')) = 32
      AND replace(workspace_instance_id, '-', '') NOT GLOB '*[^0-9a-f]*'
    ),
    command_id              TEXT NOT NULL CHECK (
      length(command_id) = 36
      AND substr(command_id, 9, 1) = '-'
      AND substr(command_id, 14, 1) = '-'
      AND substr(command_id, 19, 1) = '-'
      AND substr(command_id, 24, 1) = '-'
      AND length(replace(command_id, '-', '')) = 32
      AND replace(command_id, '-', '') NOT GLOB '*[^0-9a-f]*'
    ),
    sequence                INTEGER NOT NULL CHECK (sequence > 0),
    payload_checksum        TEXT NOT NULL CHECK (
        length(payload_checksum) = 64
        AND payload_checksum NOT GLOB '*[^0-9a-f]*'
    ),
    outcome                 TEXT NOT NULL CHECK (outcome IN ('applied', 'rejected')),
    code                    TEXT CHECK (
      code IS NULL OR (
        length(code) BETWEEN 1 AND 64
        AND code NOT GLOB '*[^a-z0-9_.]*'
      )
    ),
    message                 TEXT CHECK (
      message IS NULL OR length(CAST(message AS BLOB)) BETWEEN 1 AND 2048
    ),
    command_created_at      TEXT NOT NULL CHECK (length(command_created_at) = 24),
    recorded_at             TEXT NOT NULL CHECK (length(recorded_at) = 24),
    PRIMARY KEY (source_install_id, workspace_instance_id, sequence),
    FOREIGN KEY (source_install_id, workspace_instance_id)
      REFERENCES local_watch_command_streams(source_install_id, workspace_instance_id)
      ON DELETE CASCADE,
    CHECK (
      (outcome = 'applied' AND code IS NULL AND message IS NULL)
      OR (outcome = 'rejected' AND code IS NOT NULL AND length(code) > 0)
    )
) STRICT;

CREATE INDEX IF NOT EXISTS idx_local_watch_receipts_command_id
ON local_watch_command_receipts(source_install_id, workspace_instance_id, command_id);
