//! Trash (soft-delete) read paths.

use rusqlite::{params, Connection};

use crate::error::StoreError;

use super::{task_from_row, TaskRow, TASK_COLUMNS};

/// Result envelope for [`get_archived_tasks`].
///
/// callers receive a raw `Vec<TaskRow>` and
/// ship it across IPC verbatim. A user with thousands of trashed
/// tasks paid the full marshal cost on every Trash-panel open. The
/// envelope shape mirrors `ListTasksWithRecentCompletedResult` (same
/// `total_matching` semantics from #3007-H3) so the UI can render
/// "showing N of M" + "load more" controls.
#[derive(Debug, Clone)]
pub struct ArchivedTasksPage {
    pub rows: Vec<TaskRow>,
    pub total_matching: i64,
}

/// Load a paginated slice of soft-deleted tasks, ordered most-recently-
/// archived first so the Trash view reads like a timeline. Returns the
/// rows plus the total-matching count so the UI can offer pagination
/// controls without a follow-up `count_archived_tasks` round-trip.
///
/// The `idx_tasks_archived_at` partial index on `archived_at IS NOT NULL`
/// covers both the predicate and the `(archived_at DESC, id ASC)` sort,
/// so the LIMIT/OFFSET stays index-driven instead of falling back to a
/// TEMP B-TREE filesort. The trailing `id ASC` keeps OFFSET pagination
/// stable across cohorts that share the same `archived_at` second.
pub fn get_archived_tasks(
    conn: &Connection,
    limit: u32,
    offset: u32,
) -> Result<ArchivedTasksPage, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let total_matching = count_archived_tasks(conn)?;
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE archived_at IS NOT NULL \
             ORDER BY archived_at DESC, id ASC \
             LIMIT ?1 OFFSET ?2"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![limit, offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(ArchivedTasksPage {
        rows,
        total_matching,
    })
}

/// Count soft-deleted tasks (Trash size).
///
/// route through `prepare_cached` so the Trash panel /
/// Settings → Diagnostics surfaces that poll this counter reuse the
/// prepared statement instead of re-preparing on every poll.
pub fn count_archived_tasks(conn: &Connection) -> Result<i64, StoreError> {
    let mut stmt =
        conn.prepare_cached("SELECT COUNT(*) FROM tasks WHERE archived_at IS NOT NULL")?;
    Ok(stmt.query_row([], |row| row.get(0))?)
}

/// Return task ids for archived rows older than `cutoff_iso` (inclusive lt).
/// Used by the boot-time auto-purge and the manual "Empty Trash" action.
pub fn list_archived_task_ids_older_than(
    conn: &Connection,
    cutoff_iso: &str,
) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT id FROM tasks WHERE archived_at IS NOT NULL AND archived_at < ?1",
    )?;
    let ids: Vec<String> = stmt
        .query_map([cutoff_iso], |row| row.get::<_, String>(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(ids)
}
