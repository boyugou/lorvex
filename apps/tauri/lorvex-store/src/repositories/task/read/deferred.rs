//! Open-task read paths filtered by deferral pressure.

use lorvex_domain::naming::STATUS_OPEN;
use lorvex_domain::query::*;
use rusqlite::{params, Connection};

use crate::error::StoreError;

use super::{task_from_row, TaskRow, TASK_COLUMNS};

/// #3656 — single helper that builds the deferred-task query for
/// either the global view (`list_id = None`) or the list-filtered
/// view (`list_id = Some(_)`), driving `get_deferred_tasks` and
/// `count_deferred_tasks` from one source of SQL truth. The
/// `select` argument lets the same helper produce both the row
/// projection (`{TASK_COLUMNS}`) and the count (`COUNT(*)`); the
/// predicate / ordering / limit clauses are otherwise identical and
/// lived in four duplicated `OnceLock<String>` blobs.
fn build_deferred_sql(select: &str, list_filter: bool, with_pagination: bool) -> String {
    let list_clause = if list_filter { " AND list_id = ?1" } else { "" };
    let order = if with_pagination {
        " ORDER BY defer_count DESC, id ASC"
    } else {
        ""
    };
    let limit_clause = match (with_pagination, list_filter) {
        (true, true) => " LIMIT ?2 OFFSET ?3",
        (true, false) => " LIMIT ?1 OFFSET ?2",
        _ => "",
    };
    format!(
        "SELECT {select} FROM tasks \
         WHERE status = '{STATUS_OPEN}' AND defer_count >= 1 AND tasks.archived_at IS NULL{list_clause}{order}{limit_clause}"
    )
}

/// Get open tasks that have been deferred at least once.
///
/// Ordered by deferral pressure first, then `id ASC` for deterministic
/// pagination.
///
/// dropped `updated_at DESC` from the sort key.
/// `repositories/task_repo/mod.rs:201-205` documents that `updated_at`
/// (and `created_at`) are HLC-rewritten by sync-apply on conflict
/// resolution, so neither column is stable across peer writes — using
/// it as a pagination tiebreaker means the same logical row can shift
/// pages between OFFSET reads. The defer-count + id pair is fully
/// deterministic; for two rows with equal `defer_count`, ordering by
/// id is sufficient.
pub fn get_deferred_tasks(
    conn: &Connection,
    list_id: Option<&str>,
    page: Pagination,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<(String, String)> = std::sync::OnceLock::new();
    let (with_list, global) = SQL.get_or_init(|| {
        (
            build_deferred_sql(TASK_COLUMNS, true, true),
            build_deferred_sql(TASK_COLUMNS, false, true),
        )
    });
    if let Some(list_id) = list_id {
        let mut stmt = conn.prepare_cached(with_list)?;
        let rows = stmt
            .query_map(params![list_id, page.limit, page.offset], task_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    } else {
        let mut stmt = conn.prepare_cached(global)?;
        let rows = stmt
            .query_map(params![page.limit, page.offset], task_from_row)?
            .collect::<rusqlite::Result<_>>()?;
        Ok(rows)
    }
}

/// Count open tasks that have been deferred at least once.
pub fn count_deferred_tasks(conn: &Connection, list_id: Option<&str>) -> Result<i64, StoreError> {
    static SQL: std::sync::OnceLock<(String, String)> = std::sync::OnceLock::new();
    let (with_list, global) = SQL.get_or_init(|| {
        (
            build_deferred_sql("COUNT(*)", true, false),
            build_deferred_sql("COUNT(*)", false, false),
        )
    });
    if let Some(list_id) = list_id {
        Ok(conn
            .prepare_cached(with_list)?
            .query_row(params![list_id], |row| row.get(0))?)
    } else {
        Ok(conn
            .prepare_cached(global)?
            .query_row([], |row| row.get(0))?)
    }
}
