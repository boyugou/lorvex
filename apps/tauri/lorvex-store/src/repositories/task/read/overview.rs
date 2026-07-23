//! Overview-specific task row queries shared by app and MCP read models.

use rusqlite::Connection;

use crate::error::StoreError;

use super::{task_from_row, TaskRow, TASK_COLUMNS, TASK_ORDER_BY};

/// Open tasks in canonical overview priority order.
pub fn get_open_tasks_by_priority(
    conn: &Connection,
    limit: usize,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = 'open' AND tasks.archived_at IS NULL \
             ORDER BY {TASK_ORDER_BY} \
             LIMIT ?1"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map([limit as i64], task_from_row)?;
    Ok(rows.collect::<Result<Vec<_>, rusqlite::Error>>()?)
}

/// Recently completed tasks in deterministic overview order.
pub fn get_recently_completed_tasks(
    conn: &Connection,
    limit: usize,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_COLUMNS} FROM tasks \
             WHERE status = 'completed' AND tasks.archived_at IS NULL \
             ORDER BY completed_at DESC, id ASC \
             LIMIT ?1"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map([limit as i64], task_from_row)?;
    Ok(rows.collect::<Result<Vec<_>, rusqlite::Error>>()?)
}
