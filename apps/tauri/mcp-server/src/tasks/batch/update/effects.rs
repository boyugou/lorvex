use crate::error::McpError;
use crate::tasks::update_sync::flush_task_update_effects;
use lorvex_workflow::task_batch_update::BatchUpdateTasksResult;
use rusqlite::Connection;

pub(super) fn flush_batch_update_effects(
    conn: &Connection,
    result: &BatchUpdateTasksResult,
) -> Result<(), McpError> {
    flush_task_update_effects(
        conn,
        &result.sync_effects,
        &result.updated_ids,
        "batch_update_tasks",
    )
}
