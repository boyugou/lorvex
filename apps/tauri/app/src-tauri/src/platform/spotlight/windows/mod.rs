//! Windows Jump List integration for Lorvex tasks — the platform-
//! native search analogue of macOS Core Spotlight.
//!
//! #3303 P2 split — the previous 673-LOC `windows.rs` file mixed
//! the in-memory task cache, the partial-sort top-N selection, the
//! `ICustomDestinationList` COM rebuild, the Jump-List availability
//! circuit breaker, DB lookups feeding the rebuild, single-task
//! entry points, the bulk reindex flows, and unit tests. Each
//! concern now lives in its own sibling so the Jump List
//! plumbing can be reasoned about independently:
//!
//!   * `attributes` — the `ICustomDestinationList` rebuild driver
//!     (`rebuild_jump_list` / `rebuild_jump_list_inner`) plus the
//!     time-boxed availability circuit breaker
//!     (`JUMP_LIST_UNAVAILABLE_UNTIL_UNIX`,
//!     `jump_list_breaker_tripped`, `trip_jump_list_breaker`) and
//!     the shell-budget constant.
//!   * `query` — `read_jump_list_rows` / (test-only)
//!     `query_task_row` adapters routed through the parent
//!     module's `queries::read_indexable_rows` projection.
//!   * `per_task` — `index_task` / `remove_task` /
//!     `remove_all_tasks` single-task Jump List entry points.
//!   * `reindex` — `reindex_tasks_for_list`, `reindex_tasks_by_ids`,
//!     and the full `reindex_all_tasks` driver.
//!   * `tests` — the existing `#[cfg(test)]` regression tests.
//!
//! The in-memory task cache (`INDEXED_TASKS` + `with_tasks`), the
//! shared `TaskRow` shape, the test-only IO gate
//! (`jump_list_io_enabled`), and the partial-sort top-N selector
//! (`select_top_tasks`) live here so they're a single lookup away
//! from every caller, regardless of which sibling owns the actual
//! Jump List dispatch.

use std::collections::HashMap;
use std::sync::Mutex;

mod attributes;
mod per_task;
mod query;
mod reindex;

#[cfg(test)]
mod tests;

pub use per_task::{remove_all_tasks, remove_task};
pub use reindex::{reindex_all_tasks, reindex_tasks_by_ids, reindex_tasks_for_list};

/// Maximum number of tasks shown in the Jump List "Recent Tasks" category.
/// Jump Lists have limited vertical space; more than 20 items pushes items
/// off-screen on most display configurations.
///
/// this cap is a UX floor *in addition to*
/// the OS-reported `max_slots` returned by `BeginList`. On a
/// modern Windows desktop `max_slots` is typically 10–12 (the
/// shell default for the "user-tasks" Jump List slot count
/// configured under
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_JumpListItems`),
/// which already binds tighter than 20 — so under default
/// settings this constant is effectively dead. We keep it as a
/// belt-and-braces guard for two reasons: (a) a user who raised
/// the registry knob to e.g. 50 would otherwise see Lorvex
/// dominate their entire Jump List; (b) documents-style apps
/// that override the OS slot budget upward have shipped in
/// production (Microsoft Office set 200). The
/// `max_slots.min(MAX_JUMP_LIST_ITEMS as u32)` call below is the
/// enforcement point.
pub(super) const MAX_JUMP_LIST_ITEMS: usize = 20;

/// compute the JumpList-visible candidate slice
/// (partially-sorted by due date then title, capped at
/// `TOP_SNAPSHOT_BUFFER`) WITHOUT cloning the full indexed map.
/// The Jump List only renders `MAX_JUMP_LIST_ITEMS` entries at
/// most, so a full O(N) HashMap clone per mutation was pure
/// waste — at 10,000 open tasks the previous hot path churned
/// ~2 MB of temporary allocations per insert / remove / reindex.
/// We now allocate a ~40-entry `Vec<TaskRow>` regardless of
/// map size.
///
/// The 2× buffer leaves room for the `removed_ids` filter that
/// runs inside `rebuild_jump_list_inner` once the OS reports
/// which entries the user pinned off. Without the buffer a
/// pinned item inside the top-20 would silently shrink the
/// visible list; with it we still have 20 candidates after the
/// filter.
const TOP_SNAPSHOT_BUFFER: usize = MAX_JUMP_LIST_ITEMS * 2;

/// Shared row shape for the projection feeding every Jump List
/// indexer. Lives at the parent level so `attributes` can build
/// shell links from rows produced by `query`.
#[derive(Debug, Clone)]
pub(super) struct TaskRow {
    pub(super) id: String,
    pub(super) title: String,
    pub(super) body: Option<String>,
    pub(super) list_name: Option<String>,
    pub(super) due_date: Option<String>,
}

/// In-memory task state. The Jump List is rebuilt from scratch each time, so
/// we keep the full set of indexed tasks here.
static INDEXED_TASKS: Mutex<Option<HashMap<String, TaskRow>>> = Mutex::new(None);

/// / test-hardening: the Jump List
/// rebuild path opens a COM apartment and writes through to the
/// shell; cargo test must never trigger that. Keep query +
/// shaping helpers testable, but short-circuit the real OS
/// indexing side effects in `cargo test`.
#[inline]
pub(super) fn jump_list_io_enabled() -> bool {
    !cfg!(test)
}

/// the
/// `INDEXED_TASKS` cache is a soft mirror of the database — it
/// is rebuilt from scratch on every Jump List rebuild, so a
/// poison-recovery here cannot serve "permanently stale" data.
/// The `Option<HashMap>` shape is also self-healing: a panicking
/// sibling that left a partial `Some(map)` will be observed by
/// the next caller, who runs `f` against whatever is there;
/// since the Jump List rebuild path always full-replaces the
/// map, the next rebuild fixes any stale entry.
pub(super) fn with_tasks<F, R>(f: F) -> R
where
    F: FnOnce(&mut HashMap<String, TaskRow>) -> R,
{
    let mut guard = INDEXED_TASKS.lock().unwrap_or_else(|p| p.into_inner());
    let map = guard.get_or_insert_with(HashMap::new);
    f(map)
}

/// Parse to `chrono::NaiveDate` rather than lex-compare the
/// YYYY-MM-DD strings. Lex compare on the canonical shape happens
/// to work because the sentinel `"9999-99-99"` and the
/// `"YYYY-MM-DD"` form both sort numerically when every digit
/// position is the same width — but a future widening to ISO
/// timestamps (`"2026-04-26T08:00:00"`) would silently reorder the
/// Jump List. Parse to `NaiveDate` once; treat missing / unparsable
/// due_dates as `NaiveDate::MAX` so they sort to the end. Note:
/// this also relies on `due_date` being
/// the canonical YYYY-MM-DD across the codebase — enforced by
/// the schema CHECK and the validators.
pub(super) fn select_top_tasks(tasks: &HashMap<String, TaskRow>) -> Vec<TaskRow> {
    let mut buffer: Vec<&TaskRow> = tasks.values().collect();
    buffer.sort_by(|a, b| {
        let parse = |s: Option<&str>| {
            s.and_then(|raw| chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d").ok())
                .unwrap_or(chrono::NaiveDate::MAX)
        };
        let da = parse(a.due_date.as_deref());
        let db = parse(b.due_date.as_deref());
        da.cmp(&db).then_with(|| a.title.cmp(&b.title))
    });
    buffer.truncate(TOP_SNAPSHOT_BUFFER);
    buffer.into_iter().cloned().collect()
}
