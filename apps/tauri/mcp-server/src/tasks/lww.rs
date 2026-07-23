use crate::error::McpError;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use rusqlite::{Connection, Params};

pub(crate) fn stale_task_version(task_id: &str) -> McpError {
    McpError::Store(Box::new(StoreError::StaleVersion {
        entity: ENTITY_TASK,
        id: task_id.to_string(),
    }))
}

/// Execute a task-row `UPDATE ... WHERE id = ? AND ? > version RETURNING 1`.
///
/// MCP handlers mint local HLCs at the boundary. If sync has already
/// applied a strictly newer remote HLC to the row, the local mutation must
/// reject before emitting audit/outbox side effects instead of overwriting
/// the newer row or surfacing a late outbox-superseded error.
pub(crate) fn execute_task_lww_update<P: Params>(
    conn: &Connection,
    sql: &str,
    params: P,
    task_id: &str,
) -> Result<(), McpError> {
    match conn.prepare_cached(sql)?.query_row(params, |_row| Ok(())) {
        Ok(()) => Ok(()),
        Err(rusqlite::Error::QueryReturnedNoRows) => Err(stale_task_version(task_id)),
        Err(error) => Err(McpError::from(error)),
    }
}

pub(crate) fn touch_task_lww(
    conn: &Connection,
    task_id: &str,
    version: &str,
    now: &str,
) -> Result<(), McpError> {
    execute_task_lww_update(
        conn,
        "UPDATE tasks
         SET version = ?1, updated_at = ?2
         WHERE id = ?3 AND ?1 > version
         RETURNING 1",
        rusqlite::params![version, now, task_id],
        task_id,
    )
}
