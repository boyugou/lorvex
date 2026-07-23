//! Overdue-task read paths backing the `OverduePredicate` query.

use lorvex_domain::naming::STATUS_OPEN;
use lorvex_domain::query::*;
use rusqlite::{params, Connection};

use crate::error::StoreError;

use super::buckets::overdue_bucket_predicate;
use super::{task_from_row, TaskRow, TASK_COLUMNS, TASK_ORDER_BY};

/// Get overdue tasks.
///
/// Returns open tasks where `due_date < as_of_date`.
/// Ordered by `priority_effective ASC, due_date ASC`.
pub fn get_overdue_tasks(
    conn: &Connection,
    pred: &OverduePredicate,
    page: Pagination,
) -> Result<Vec<TaskRow>, StoreError> {
    // The format inputs (`overdue_bucket_predicate("tasks", "?1")`,
    // `TASK_COLUMNS`, `STATUS_OPEN`, `TASK_ORDER_BY`) are all
    // deterministic for the lifetime of the process, so cache the
    // rendered SQL and feed `&'static str` straight into
    // `prepare_cached`.
    // fresh ~400-byte format!.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let date_str = pred.as_of_date.format("%Y-%m-%d").to_string();
    let sql = SQL.get_or_init(|| {
        let overdue = overdue_bucket_predicate("tasks", "?1");
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE {overdue} AND status = '{STATUS_OPEN}' AND tasks.archived_at IS NULL \
             ORDER BY {TASK_ORDER_BY} \
             LIMIT ?2 OFFSET ?3"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params![date_str, page.limit, page.offset], task_from_row)?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}

/// Count overdue tasks.
pub fn count_overdue_tasks(conn: &Connection, pred: &OverduePredicate) -> Result<i64, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let date_str = pred.as_of_date.format("%Y-%m-%d").to_string();
    let sql = SQL.get_or_init(|| {
        let overdue = overdue_bucket_predicate("tasks", "?1");
        format!(
            "SELECT COUNT(*) FROM tasks \
             WHERE {overdue} AND status = '{STATUS_OPEN}' AND tasks.archived_at IS NULL"
        )
    });
    Ok(conn
        .prepare_cached(sql)?
        .query_row(params![date_str], |row| row.get(0))?)
}
