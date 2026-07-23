//! Task repository — shared query implementations for the `tasks` table.
//!
//! Used by both the Tauri app and the MCP server. All task queries go through
//! these functions so the WHERE-clause logic exists in exactly one place.

mod archive;
mod buckets;
mod core;
mod deferred;
mod lifecycle;
mod list;
mod lookup;
mod overdue;
mod overview;
mod recurrence;
mod row;
mod scheduling;
mod search;
mod tags;
mod today;
mod upcoming;

pub use archive::{
    count_archived_tasks, get_archived_tasks, list_archived_task_ids_older_than, ArchivedTasksPage,
};
pub use buckets::count_open_task_day_buckets;
pub use core::{TaskCore, TaskCoreFields};
pub use deferred::{count_deferred_tasks, get_deferred_tasks};
pub use lifecycle::{TaskLifecycleTimestamps, TaskLifecycleTimestampsFields};
pub use list::list_tasks;
pub use lookup::{
    get_list_tasks_with_recent_completed, get_task, task_exists_active, validate_task_ids_live,
    ListTasksWithRecentCompletedResult,
};
pub use overdue::{count_overdue_tasks, get_overdue_tasks};
pub use overview::{get_open_tasks_by_priority, get_recently_completed_tasks};
pub use recurrence::{TaskRecurrenceState, TaskRecurrenceStateFields};
pub use row::TaskRow;
pub use scheduling::{TaskScheduling, TaskSchedulingFields};
pub use search::search_tasks_with_fallback;
pub use tags::get_tasks_by_tag;
pub use today::{
    count_exact_today_tasks, count_high_priority_undated_tasks, count_overdue_tasks_for_today,
    count_today_tasks, get_exact_today_tasks, get_high_priority_undated_tasks,
    get_overdue_tasks_for_today, get_today_tasks,
};
pub use upcoming::{count_upcoming_tasks, get_upcoming_tasks};

// `search_tasks` is gated on `cfg(test)`
// because production call-paths exclusively use the CJK-safe
// `search_tasks_with_fallback` (re-exported above). The bare
// function exists only for FTS-only behaviour tests.
#[cfg(test)]
pub(crate) use search::search_tasks;

/// Result of a search query, including matched rows and total count.
#[derive(Debug, Clone)]
pub struct SearchResult {
    pub rows: Vec<TaskRow>,
    pub total_matching: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskStatusListFilter {
    Open,
    Completed,
    Cancelled,
    Someday,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskListSortBy {
    PriorityDue,
    DueDate,
    PlannedDate,
    UpdatedAt,
    CreatedAt,
    Title,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortDirection {
    Asc,
    Desc,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TaskDateRange {
    pub from: Option<String>,
    pub to: Option<String>,
}

/// Tri-state presence filter for nullable date columns.
///
/// `ListTasksQuery` expressed `has_due_date`
/// and `has_planned_date` as `Option<bool>`. That encoding overloaded
/// `Option::None` to mean "no filter" while `Some(true)`/`Some(false)`
/// meant "column IS NOT NULL"/"column IS NULL". Three states masquerading
/// as two compose poorly: every consumer had to re-derive the meaning of
/// each boolean at every layer (CLI flag pair, MCP arg, store predicate,
/// docs), and a missing `Some(_)` arm at any layer silently degraded into
/// "no filter applied" with zero compiler signal.
///
/// `DateFilter` makes the three-state nature explicit and exhaustive at
/// the type level so each variant must be handled wherever the filter is
/// translated.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DateFilter {
    /// No constraint — match rows regardless of NULL/NOT NULL status.
    #[default]
    Any,
    /// Match rows where the column IS NOT NULL.
    Present,
    /// Match rows where the column IS NULL.
    Absent,
}

/// Adjacency-edge presence filter for `task_dependencies`.
///
/// two independent `bool` fields,
/// `blocked_only` and `blocking_others`, encoded the four valid combos
/// (no filter, blocked-side only, blocking-side only, both). Independent
/// booleans split a closed enumeration into two open knobs whose joint
/// state had to be re-validated per call-site, and the wire-level
/// untriaged shape of "two bools default false" carried no meaning at
/// the type level.
///
/// `BlockingFilter` collapses the four valid combinations into a single
/// closed enum so consumers route through one exhaustive match.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum BlockingFilter {
    /// No dependency-graph constraint.
    #[default]
    Any,
    /// Only tasks that are currently blocked by an open/someday blocker.
    BlockedOnly,
    /// Only tasks that currently block at least one open/someday dependent.
    BlockingOthers,
    /// Both — tasks that are simultaneously blocked AND blocking.
    BlockedAndBlocking,
}

impl BlockingFilter {
    /// Convenience constructor mirroring the legacy `(blocked_only,
    /// blocking_others)` boolean pair so call-sites that still receive
    /// raw flags from a wire format can normalize once.
    pub const fn from_flags(blocked_only: bool, blocking_others: bool) -> Self {
        match (blocked_only, blocking_others) {
            (false, false) => Self::Any,
            (true, false) => Self::BlockedOnly,
            (false, true) => Self::BlockingOthers,
            (true, true) => Self::BlockedAndBlocking,
        }
    }

    /// `true` if the filter requires tasks with at least one open blocker.
    pub const fn requires_blocked(self) -> bool {
        matches!(self, Self::BlockedOnly | Self::BlockedAndBlocking)
    }

    /// `true` if the filter requires tasks that block at least one open dependent.
    pub const fn requires_blocking_others(self) -> bool {
        matches!(self, Self::BlockingOthers | Self::BlockedAndBlocking)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListTasksQuery {
    pub list_id: Option<String>,
    pub status: TaskStatusListFilter,
    pub priority: Option<u8>,
    pub due_range: Option<TaskDateRange>,
    pub planned_range: Option<TaskDateRange>,
    pub completed_range: Option<TaskDateRange>,
    pub created_range: Option<TaskDateRange>,
    pub due_presence: DateFilter,
    pub planned_presence: DateFilter,
    pub tags: Vec<String>,
    pub text: Option<String>,
    pub blocking: BlockingFilter,
    pub sort_by: TaskListSortBy,
    pub sort_direction: SortDirection,
    pub limit: u32,
    pub offset: u32,
}

impl Default for ListTasksQuery {
    fn default() -> Self {
        Self {
            list_id: None,
            status: TaskStatusListFilter::Open,
            priority: None,
            due_range: None,
            planned_range: None,
            completed_range: None,
            created_range: None,
            due_presence: DateFilter::Any,
            planned_presence: DateFilter::Any,
            tags: Vec::new(),
            text: None,
            blocking: BlockingFilter::Any,
            sort_by: TaskListSortBy::PriorityDue,
            sort_direction: SortDirection::Asc,
            limit: 100,
            offset: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ListTasksResult {
    pub rows: Vec<TaskRow>,
    pub total_matching: i64,
}

/// Canonical counts for the mutually-exclusive open-task day buckets.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpenTaskDayBucketCounts {
    pub overdue: i64,
    pub today_pool: i64,
    pub upcoming: i64,
}

/// Canonical ORDER BY clause for task queries.
///
/// Must be paired with a `SELECT ... FROM tasks ...` using the
/// `priority_effective` virtual column. `id ASC` is the deterministic
/// tiebreaker required for stable OFFSET pagination per CLAUDE.md rule #4.
///
/// Do not substitute `created_at DESC` — HLC advancement and sync-apply
/// re-writes mean `created_at` is not stable across devices or merges, so
/// using it as the tiebreaker can duplicate or skip rows between pages.
pub const TASK_ORDER_BY: &str = "priority_effective ASC, due_date ASC NULLS LAST, id ASC";

/// Column list for SELECT queries. Matches the field order in `task_from_row`.
///
/// The single declaration lives in [`crate::repositories::columns::TASKS`];
/// this constant is a thin alias. New call sites should reach for
/// `lorvex_store::repositories::columns::TASKS.select_clause()`
/// directly.
pub(super) const TASK_COLUMNS: &str = crate::repositories::columns::TASKS.select_clause;

/// Process-lifetime cache of the table-qualified SELECT projection
/// (`t.id, t.title, …`). Building this on demand by calling
/// `TASK_COLUMNS.split(", ").map(|c| format!("t.{c}")).collect::<Vec<_>>()
/// .join(", ")` would cost ~28 String allocations plus a `Vec<String>`
/// per call, which is unacceptable on the FTS keystroke hot path
/// (`search_tasks_*`, `count_tasks_by_tags`). Mirrors the
/// `LIST_COLUMNS_QUALIFIED` pattern in `list_repo.rs`. Use this
/// constant any time a JOIN query needs the canonical projection;
/// fall back to `Columns::select_clause_qualified(prefix)` if the
/// alias differs.
pub(super) static TASK_COLUMNS_QUALIFIED_T: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| crate::repositories::columns::TASKS.select_clause_qualified("t"));

/// `TASK_ORDER_BY` with every leading column prefixed with the `t.`
/// table alias, so JOIN-bearing tag-scoped queries (the only place
/// rebuild loop. Mirrors the `TASK_COLUMNS_QUALIFIED_T` pattern: a
/// single `LazyLock<String>` shared by every JOIN-style read.
///
/// The transform splits each `<col> <ASC|DESC> [NULLS LAST]` segment
/// of `TASK_ORDER_BY` and prepends `t.` to the column. The lead
/// segment of `TASK_ORDER_BY` is the only place a column name can
/// appear without a comma boundary, so a naive `.replace(", ", ", t.")`
/// would miss it; the splitn-based rebuild handles both.
pub(super) static TASK_ORDER_BY_QUALIFIED_T: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| {
        // Pre-allocate the joined buffer instead of collecting into a
        // `Vec<String>` and calling `.join(", ")` (which itself allocates
        // a fresh `String`). The result lives for the process lifetime,
        // so this only ever runs once, but writing it the cheap way keeps
        // the pattern consistent with the rest of the hot-path repo
        // surface (#3367).
        let mut out = String::with_capacity(TASK_ORDER_BY.len() + 16);
        for (i, seg) in TASK_ORDER_BY.split(", ").enumerate() {
            if i > 0 {
                out.push_str(", ");
            }
            let mut parts = seg.splitn(2, ' ');
            let col = parts
                .next()
                .expect("TASK_ORDER_BY must have non-empty leading segment");
            out.push_str("t.");
            out.push_str(col);
            if let Some(rest) = parts.next() {
                out.push(' ');
                out.push_str(rest);
            }
        }
        out
    });

/// Map a `rusqlite::Row` to a `TaskRow`. Column indices must match `TASK_COLUMNS`.
pub(super) fn task_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskRow> {
    Ok(TaskRow {
        core: TaskCore {
            id: row.get(0)?,
            title: row.get(1)?,
            body: row.get(2)?,
            raw_input: row.get(3)?,
            ai_notes: row.get(4)?,
            status: row.get(5)?,
            list_id: row.get(6)?,
            priority: row.get(7)?,
            version: row.get(16)?,
            created_at: row.get(17)?,
            updated_at: row.get(18)?,
        },
        scheduling: TaskScheduling {
            due: {
                let date: Option<lorvex_domain::time::Date> = row.get(8)?;
                let time: Option<lorvex_domain::time::TimeOfDay> = row.get(9)?;
                lorvex_domain::time::DueAt::from_optional_pair(date, time).map_err(|e| {
                    rusqlite::Error::FromSqlConversionFailure(
                        8,
                        rusqlite::types::Type::Text,
                        Box::new(std::io::Error::new(
                            std::io::ErrorKind::InvalidData,
                            e.to_string(),
                        )),
                    )
                })?
            },
            estimated_minutes: row.get(10)?,
            planned_date: row.get(22)?,
            available_from: row.get(26)?,
            defer_count: row.get(23)?,
            last_deferred_at: row.get(20)?,
            last_defer_reason: row.get(21)?,
        },
        recurrence: TaskRecurrenceState {
            recurrence: row.get(11)?,
            recurrence_exceptions: row.get(12)?,
            spawned_from: row.get(13)?,
            recurrence_group_id: row.get(14)?,
            canonical_occurrence_date: row.get(15)?,
            recurrence_instance_key: row.get(24)?,
        },
        lifecycle: TaskLifecycleTimestamps {
            completed_at: row.get(19)?,
            archived_at: row.get(25)?,
        },
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
