//! Per-entity column allowlists — the single source of truth for the
//! exact set of columns that flow through SELECT queries and payload
//! shadow copies.
//!
//! Every consumer (Tauri `commands/shared/constants.rs`, the store
//! `repositories/task_repo/mod.rs`, and the Tauri / MCP `HABIT_COLS`
//! / `LIST_COLS` shadows) routes
//! through this module so adding a schema column lands in one
//! place. Per-table allowlists scattered across 4-6 spots would
//! drift on every column add — a missed update would let the
//! SELECT return a row with the wrong indices, or the FTS /
//! payload-shadow surface would diverge.
//!
//! This module owns one canonical list per table. Two flavors are
//! exposed because some Tauri row mappers (tasks/lists/habits) read
//! the row without `version` while others include it: callers pick
//! whichever mapper their `*_from_row` expects.
//!
//! - [`Columns::ALL`] — every column, **including** the `version`
//!   column (the LWW-stamp). Use this for any SELECT whose row mapper
//!   reads `version` or for INSERT statements that bind `version`.
//! - [`Columns::WITHOUT_VERSION`] — every column except `version`.
//!   Use this for surfaces whose row type predates `version` and
//!   skips that index.
//! - [`Columns::select_clause()`] — comma-separated string suitable
//!   for `format!("SELECT {} FROM …", select_clause())`.
//! - [`Columns::select_clause_qualified("t")`] — same, but every
//!   column is prefixed with `t.` for JOIN queries.
//!
//! Adding a schema column is now a single edit to the slice in this
//! module; the FTS / payload-shadow surfaces that re-export through
//! this module pick the new column up automatically.

/// A typed column allowlist for one SQL table.
///
/// Every concrete instance lives as a `pub const` below. The
/// `&'static [&'static str]` slices are the source of truth; the
/// `select_clause` / `select_clause_qualified` helpers project them
/// into the comma-separated forms each consumer needs (raw vs
/// `t.`-prefixed) without each call site re-`join`ing the slice.
pub struct Columns {
    /// Table name (used by `select_clause_qualified`).
    pub table: &'static str,
    /// Every column, in declared order. Mirrors the row mapper's
    /// `row.get(0..N)` indices.
    pub all: &'static [&'static str],
    /// Same set with the `version` column stripped, in the same
    /// relative order. Some Tauri row mappers do not read `version`,
    /// so they bind without it.
    pub without_version: &'static [&'static str],
    /// Pre-computed comma-separated form of [`Self::all`]. Equivalent
    /// to `Self::all.join(", ")` but materialized at module-init time
    /// so format strings can include it without an allocation per
    /// call.
    pub select_clause: &'static str,
    /// Pre-computed comma-separated form of [`Self::without_version`].
    pub select_clause_without_version: &'static str,
}

impl Columns {
    /// Comma-separated form of [`Self::all`].
    pub const fn select_clause(&self) -> &'static str {
        self.select_clause
    }

    /// Comma-separated form of [`Self::without_version`].
    pub const fn select_clause_without_version(&self) -> &'static str {
        self.select_clause_without_version
    }

    /// Build the table-qualified SELECT projection (`t.id, t.title,
    /// …`) for JOIN queries. Allocates a new `String` because the
    /// prefix is a runtime value; the result is cheap to feed into
    /// `format!("SELECT {} FROM …")`.
    pub fn select_clause_qualified(&self, prefix: &str) -> String {
        let mut out = String::with_capacity(self.select_clause.len() + self.all.len() * 4);
        for (i, col) in self.all.iter().enumerate() {
            if i > 0 {
                out.push_str(", ");
            }
            // Entries that contain `(` are pre-baked SQL expressions
            // (e.g. the `recurrence_exceptions` JSON subquery rebuilt
            // from the child table by #4585). Substitute the bound
            // owner-id placeholder with the caller's qualified form.
            if col.contains('(') {
                let resolved = col.replace("__OWNER_PREFIX__.id", &format!("{prefix}.id"));
                out.push_str(&resolved);
            } else {
                out.push_str(prefix);
                out.push('.');
                out.push_str(col);
            }
        }
        out
    }
}

/// SQL expression that rebuilds the `tasks.recurrence_exceptions`
/// JSON wire form (`["2026-04-01","2026-04-08"]`) from
/// `task_recurrence_exceptions`. An empty registry collapses to
/// `NULL` (via `NULLIF(..., '[]')`), not `"[]"` — the canonical
/// "no exceptions" representation shared with the sync payload
/// builders and the Apple app. The owner-row placeholder
/// `__OWNER_PREFIX__.id` is substituted by
/// [`Columns::select_clause_qualified`] to the caller's table alias.
/// The unqualified `select_clause` constants below pre-substitute it
/// to `tasks.id` so the bare-FROM form does not need post-processing.
const TASK_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED: &str =
    "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
     FROM task_recurrence_exceptions WHERE task_id = __OWNER_PREFIX__.id) AS recurrence_exceptions";

/// Mirror of [`TASK_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED`] for
/// `calendar_events`.
const EVENT_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED: &str =
    "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
     FROM calendar_event_recurrence_exceptions WHERE event_id = __OWNER_PREFIX__.id) AS recurrence_exceptions";

// ---------------------------------------------------------------------------
// `tasks` table
// ---------------------------------------------------------------------------

/// Canonical column order for the `tasks` table.
///
/// already unified the order between the store
/// `TASK_COLUMNS` and the Tauri `TASK_COLS`; both surfaces agreed on
/// `version` immediately after `canonical_occurrence_date`. This
/// module promotes the literal to a single declaration.
pub const TASKS: Columns = Columns {
    table: "tasks",
    all: &[
        "id",
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "recurrence",
        TASK_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED,
        "spawned_from",
        "recurrence_group_id",
        "canonical_occurrence_date",
        "version",
        "created_at",
        "updated_at",
        "completed_at",
        "last_deferred_at",
        "last_defer_reason",
        "planned_date",
        "defer_count",
        "recurrence_instance_key",
        "archived_at",
        "available_from",
    ],
    // No surface currently consumes the without-version projection
    // for tasks — Tauri's `TASK_COLS` and store's `TASK_COLUMNS` both
    // use `select_clause` (with `version`) and `task_from_row` reads
    // column index 18 as `version`. The slice is populated only to
    // keep `Columns` symmetric across all five instances and to
    // satisfy the `without_version_strips_only_version` parity test
    //. A future peer-restore path that needs
    // a version-stripped projection can opt in without a struct
    // change.
    without_version: &[
        "id",
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "recurrence",
        TASK_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED,
        "spawned_from",
        "recurrence_group_id",
        "canonical_occurrence_date",
        "created_at",
        "updated_at",
        "completed_at",
        "last_deferred_at",
        "last_defer_reason",
        "planned_date",
        "defer_count",
        "recurrence_instance_key",
        "archived_at",
        "available_from",
    ],
    select_clause: TASKS_SELECT_CLAUSE,
    select_clause_without_version: TASKS_SELECT_CLAUSE_NO_VERSION,
};

const TASKS_SELECT_CLAUSE: &str = concat!(
    "id, title, body, raw_input, ai_notes, status, list_id, priority, due_date, due_time, estimated_minutes, recurrence, ",
    "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') FROM task_recurrence_exceptions WHERE task_id = tasks.id) AS recurrence_exceptions",
    ", spawned_from, recurrence_group_id, canonical_occurrence_date, version, created_at, updated_at, completed_at, last_deferred_at, last_defer_reason, planned_date, defer_count, recurrence_instance_key, archived_at, available_from"
);

const TASKS_SELECT_CLAUSE_NO_VERSION: &str = concat!(
    "id, title, body, raw_input, ai_notes, status, list_id, priority, due_date, due_time, estimated_minutes, recurrence, ",
    "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') FROM task_recurrence_exceptions WHERE task_id = tasks.id) AS recurrence_exceptions",
    ", spawned_from, recurrence_group_id, canonical_occurrence_date, created_at, updated_at, completed_at, last_deferred_at, last_defer_reason, planned_date, defer_count, recurrence_instance_key, archived_at, available_from"
);

// ---------------------------------------------------------------------------
// `lists` table
// ---------------------------------------------------------------------------

pub const LISTS: Columns = Columns {
    table: "lists",
    all: &[
        "id",
        "name",
        "color",
        "icon",
        "description",
        "ai_notes",
        "created_at",
        "updated_at",
        "version",
        "archived_at",
        "position",
    ],
    without_version: &[
        "id",
        "name",
        "color",
        "icon",
        "description",
        "ai_notes",
        "created_at",
        "updated_at",
        "archived_at",
        "position",
    ],
    select_clause:
        "id, name, color, icon, description, ai_notes, created_at, updated_at, version, archived_at, position",
    select_clause_without_version:
        "id, name, color, icon, description, ai_notes, created_at, updated_at, archived_at, position",
};

// ---------------------------------------------------------------------------
// `habits` table
// ---------------------------------------------------------------------------

/// SQL expression that materializes the `weekly` weekday set as a
/// Monday-first (0=Mon … 6=Sun) JSON integer array from the
/// `habit_weekdays` child — the habit payload's `weekdays` field. Empty
/// for every non-weekly cadence and for weekly-every-day. The owner-row
/// placeholder `__OWNER_PREFIX__.id` is substituted by
/// [`Columns::select_clause_qualified`] to the caller's table alias; the
/// unqualified `select_clause` below pre-substitutes it to `habits.id`.
const HABIT_WEEKDAYS_EXPR_QUALIFIED: &str =
    "(SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays \
     WHERE habit_id = __OWNER_PREFIX__.id ORDER BY weekday)) AS weekdays";

pub const HABITS: Columns = Columns {
    table: "habits",
    all: &[
        "id",
        "name",
        "icon",
        "color",
        "cue",
        "frequency_type",
        "per_period_target",
        "day_of_month",
        "target_count",
        "archived",
        "created_at",
        "updated_at",
        "version",
        HABIT_WEEKDAYS_EXPR_QUALIFIED,
    ],
    without_version: &[
        "id",
        "name",
        "icon",
        "color",
        "cue",
        "frequency_type",
        "per_period_target",
        "day_of_month",
        "target_count",
        "archived",
        "created_at",
        "updated_at",
        HABIT_WEEKDAYS_EXPR_QUALIFIED,
    ],
    select_clause: "id, name, icon, color, cue, frequency_type, per_period_target, day_of_month, target_count, archived, created_at, updated_at, version, (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays WHERE habit_id = habits.id ORDER BY weekday)) AS weekdays",
    select_clause_without_version: "id, name, icon, color, cue, frequency_type, per_period_target, day_of_month, target_count, archived, created_at, updated_at, (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays WHERE habit_id = habits.id ORDER BY weekday)) AS weekdays",
};

// ---------------------------------------------------------------------------
// `calendar_events` table
// ---------------------------------------------------------------------------

pub const CALENDAR_EVENTS: Columns = Columns {
    table: "calendar_events",
    all: &[
        "id",
        "title",
        "description",
        "start_date",
        "start_time",
        "end_date",
        "end_time",
        "all_day",
        "location",
        "url",
        "color",
        "recurrence",
        "timezone",
        EVENT_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED,
        "event_type",
        "person_name",
        "created_at",
        "updated_at",
        "version",
    ],
    without_version: &[
        "id",
        "title",
        "description",
        "start_date",
        "start_time",
        "end_date",
        "end_time",
        "all_day",
        "location",
        "url",
        "color",
        "recurrence",
        "timezone",
        EVENT_RECURRENCE_EXCEPTIONS_EXPR_QUALIFIED,
        "event_type",
        "person_name",
        "created_at",
        "updated_at",
    ],
    select_clause: CALENDAR_EVENTS_SELECT_CLAUSE,
    select_clause_without_version: CALENDAR_EVENTS_SELECT_CLAUSE_NO_VERSION,
};

const CALENDAR_EVENTS_SELECT_CLAUSE: &str = concat!(
    "id, title, description, start_date, start_time, end_date, end_time, all_day, location, url, color, recurrence, timezone, ",
    "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id) AS recurrence_exceptions",
    ", event_type, person_name, created_at, updated_at, version"
);

const CALENDAR_EVENTS_SELECT_CLAUSE_NO_VERSION: &str = concat!(
    "id, title, description, start_date, start_time, end_date, end_time, all_day, location, url, color, recurrence, timezone, ",
    "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id) AS recurrence_exceptions",
    ", event_type, person_name, created_at, updated_at"
);

// ---------------------------------------------------------------------------
// `ai_changelog` table
// ---------------------------------------------------------------------------

/// SQL expression that rebuilds the legacy `ai_changelog.entity_ids`
/// JSON wire form (`["task-1","task-2"]`) from
/// `ai_changelog_entities`. The owner-row placeholder
/// `__OWNER_PREFIX__.id` is substituted by
/// [`Columns::select_clause_qualified`] for joined queries. The
/// unqualified `select_clause` constant below pre-substitutes it to
/// `ai_changelog.id` so a bare-FROM projection needs no
/// post-processing.
const AI_CHANGELOG_ENTITY_IDS_EXPR_QUALIFIED: &str =
    "(SELECT NULLIF(json_group_array(entity_id ORDER BY entity_id), '[]') \
     FROM ai_changelog_entities WHERE changelog_id = __OWNER_PREFIX__.id) AS entity_ids";

/// Canonical column order for `ai_changelog`. The `entity_ids`
/// position carries the correlated-subquery expression that rebuilds
/// the wire-form JSON from `ai_changelog_entities`; consumers reading
/// the projected row at this tuple index get the same JSON string
pub const AI_CHANGELOG: Columns = Columns {
    table: "ai_changelog",
    all: &[
        "id",
        "timestamp",
        "operation",
        "entity_type",
        "entity_id",
        AI_CHANGELOG_ENTITY_IDS_EXPR_QUALIFIED,
        "summary",
        "initiated_by",
        "mcp_tool",
        "source_device_id",
        "before_json",
        "after_json",
        "undo_token",
        "is_preview",
    ],
    // `ai_changelog` has no `version` column — the audit stream is
    // append-only and deduplicated by `id`. The without-version
    // mirror exists only for `Columns` shape symmetry.
    without_version: &[
        "id",
        "timestamp",
        "operation",
        "entity_type",
        "entity_id",
        AI_CHANGELOG_ENTITY_IDS_EXPR_QUALIFIED,
        "summary",
        "initiated_by",
        "mcp_tool",
        "source_device_id",
        "before_json",
        "after_json",
        "undo_token",
        "is_preview",
    ],
    select_clause: AI_CHANGELOG_SELECT_CLAUSE,
    select_clause_without_version: AI_CHANGELOG_SELECT_CLAUSE,
};

const AI_CHANGELOG_SELECT_CLAUSE: &str = concat!(
    "id, timestamp, operation, entity_type, entity_id, ",
    "(SELECT NULLIF(json_group_array(entity_id ORDER BY entity_id), '[]') \
     FROM ai_changelog_entities WHERE changelog_id = ai_changelog.id) AS entity_ids",
    ", summary, initiated_by, mcp_tool, source_device_id, before_json, after_json, undo_token, is_preview"
);

#[cfg(test)]
mod tests;
