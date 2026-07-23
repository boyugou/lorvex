//! Single-task lookup and per-list lookups (with retention-window completed rows).

use lorvex_domain::{ListId, TaskId};
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::{HashMap, HashSet};

use crate::error::StoreError;

use super::{task_from_row, TaskRow, TASK_COLUMNS, TASK_ORDER_BY};

/// Get a single task by ID, regardless of `archived_at` (Trash) state.
///
/// Returns `None` if no task with the given ID exists. This helper
/// intentionally does NOT filter `archived_at IS NULL` because callers
/// split into two camps:
///
/// 1. Restore / archive flows that need to operate on trashed rows
///    (e.g. `restore_task_from_trash`, `permanent_delete_task`).
///    These need the un-filtered shape.
/// 2. Post-CREATE / post-DUPLICATE materialization paths inside
///    `task_write.rs` — those operate on a row they just inserted, so
///    `archived_at IS NULL` by construction.
///
/// Future callers wanting "active task" semantics MUST layer
/// `archived_at IS NULL` themselves (or pick one of the dedicated
/// active-only read paths in `task_repo/{today,overdue,upcoming,
/// list,buckets}.rs` that already enforce the filter and the
/// canonical sort + tiebreaker).
pub fn get_task(conn: &Connection, task_id: &TaskId) -> Result<Option<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| format!("SELECT {TASK_COLUMNS} FROM tasks WHERE id = ?1"));
    Ok(conn
        .prepare_cached(sql)?
        .query_row([task_id.as_str()], task_from_row)
        .optional()?)
}

/// Whether a row exists in `tasks` for the given id and is NOT archived
/// (Trash).
///
/// Single canonical implementation of the `SELECT 1 FROM tasks WHERE id = ?1
/// AND archived_at IS NULL` existence check used at every IPC / MCP boundary
/// that wants to give a "Task not found" diagnostic when a referenced id
/// either does not exist or has been moved to Trash.
/// `prepare_cached` block was repeated byte-for-byte at five production
/// sites (3 in `app/src-tauri/.../tasks/provider_event_links.rs`, 2 in
/// mcp-server's calendar / provider event-link paths). One helper, one
/// schema decision: a future migration that renames `archived_at` or
/// introduces a tri-state lifecycle column only updates one site.
pub fn task_exists_active(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
) -> Result<bool, StoreError> {
    Ok(conn
        .prepare_cached("SELECT 1 FROM tasks WHERE id = ?1 AND archived_at IS NULL")?
        .exists(params![task_id.as_str()])?)
}

/// Validate that every referenced task id exists and is not archived.
///
/// This is the shared batch form of [`task_exists_active`]. Forward-looking
/// planning surfaces such as focus schedules must reject missing and archived
/// task ids before materializing soft-reference rows.
pub fn validate_task_ids_live(
    conn: &Connection,
    task_ids: &[String],
    field_name: &'static str,
) -> Result<(), StoreError> {
    if task_ids.is_empty() {
        return Ok(());
    }

    let mut seen = HashSet::with_capacity(task_ids.len());
    let deduped = task_ids
        .iter()
        .map(String::as_str)
        .filter(|id| seen.insert(*id))
        .collect::<Vec<_>>();
    let placeholders = lorvex_domain::sql_csv_placeholders(deduped.len());
    let sql = format!("SELECT id, archived_at FROM tasks WHERE id IN ({placeholders})");
    let mut stmt = conn.prepare(&sql)?;
    let mut found = HashMap::with_capacity(deduped.len());
    for row in stmt.query_map(rusqlite::params_from_iter(deduped.iter().copied()), |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(1)?))
    })? {
        let (id, archived_at) = row?;
        found.insert(id, archived_at);
    }

    for task_id in task_ids {
        match found.get(task_id.as_str()) {
            Some(None) => {}
            Some(Some(_)) => {
                return Err(StoreError::Validation(format!(
                    "{field_name} references archived task: {task_id}"
                )));
            }
            None => {
                return Err(StoreError::Validation(format!(
                    "{field_name} references non-existent task: {task_id}"
                )));
            }
        }
    }

    Ok(())
}

/// Result envelope for [`get_list_tasks_with_recent_completed`].
///
/// `total_matching` is the count of every row that passes the predicate
/// (open / someday in this list, plus any recently-completed rows in
/// the retention window). The `rows` slice carries up to `limit` rows.
/// callers receive an unbounded `Vec<TaskRow>`
/// and ship it across IPC verbatim. A 50k-task list paid the full
/// row-marshal cost on every list-detail open. The envelope shape
/// here mirrors `ListTasksResult` (same `total_matching` semantics)
/// so the UI can show "showing N of M" + "load more" controls.
#[derive(Debug, Clone)]
pub struct ListTasksWithRecentCompletedResult {
    pub rows: Vec<TaskRow>,
    pub total_matching: i64,
}

/// Get tasks in a specific list, including recently-completed tasks within a
/// retention window.
///
/// Returns non-cancelled tasks where:
/// - `status != 'completed'` (i.e. open, someday), OR
/// - `completed_at` falls within `[recent_completed_start_utc, recent_completed_end_utc)`
///
/// Cancelled tasks are always excluded.
/// Ordered by `TASK_ORDER_BY` (priority_effective ASC, due_date ASC NULLS LAST, id ASC).
///
/// `limit` caps the returned `rows` while
/// `total_matching` reports the full predicate count for "load more"
/// affordances. Callers (Tauri / MCP / CLI) are expected to clamp
/// `limit` against the canonical `GET_ALL_TASKS_LIMIT` (10_000) at
/// the IPC boundary.
pub fn get_list_tasks_with_recent_completed(
    conn: &Connection,
    list_id: &ListId,
    recent_completed_start_utc: &str,
    recent_completed_end_utc: &str,
    limit: u32,
) -> Result<ListTasksWithRecentCompletedResult, StoreError> {
    // do NOT wrap `completed_at` in `datetime(...)` —
    // that forces a function call per row and renders
    // `idx_tasks_completed_at` unusable. The column is already
    // canonical RFC3339 millisecond-Z (lex order = chronological) so direct
    // string comparison is correct AND index-friendly.
    // already established this discipline elsewhere; this site was a
    // regression.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE list_id = ?1 \
               AND archived_at IS NULL \
               AND status != 'cancelled' \
               AND (
                    status != 'completed'
                    OR (
                        completed_at >= ?2
                        AND completed_at < ?3
                    )
               ) \
             ORDER BY {TASK_ORDER_BY} \
             LIMIT ?4"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows: Vec<TaskRow> = stmt
        .query_map(
            params![
                list_id,
                recent_completed_start_utc,
                recent_completed_end_utc,
                limit
            ],
            task_from_row,
        )?
        .collect::<rusqlite::Result<_>>()?;

    // Run the count query against the same predicate so the UI can
    // surface "load more" when the trim was non-trivial. The count
    // query is cheap relative to the row materialization above (it
    // touches the same indices but never reads the wide TASK_COLUMNS
    // projection).
    let total_matching: i64 = conn
        .prepare_cached(
            "SELECT COUNT(*) FROM tasks \
             WHERE list_id = ?1 \
               AND archived_at IS NULL \
               AND status != 'cancelled' \
               AND (
                    status != 'completed'
                    OR (
                        completed_at >= ?2
                        AND completed_at < ?3
                    )
               )",
        )?
        .query_row(
            params![
                list_id,
                recent_completed_start_utc,
                recent_completed_end_utc
            ],
            |row| row.get(0),
        )?;

    Ok(ListTasksWithRecentCompletedResult {
        rows,
        total_matching,
    })
}
