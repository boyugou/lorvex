//! Hard-delete — physically remove a task row.
//!
//! This bypasses the Trash lifecycle (`archived_at`) and is reserved for
//! callers that have already gone through the soft-delete / Trash review
//! and now need the row gone (permanent purge, undo of an archived
//! create, sync conflict resolution that drops a duplicate row).
//!
//! Cascading child tables (`task_tags`, `task_dependencies`,
//! `task_checklist_items`, etc.) are wiped via SQLite `ON DELETE CASCADE`
//! foreign keys, so this is a single-statement operation.

use rusqlite::Connection;

use crate::error::StoreError;
use lorvex_domain::TaskId;

pub fn hard_delete_task_lww(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
) -> Result<usize, StoreError> {
    crate::repositories::lww_delete::execute_lww_delete_by_id(
        conn,
        "tasks",
        "id",
        lorvex_domain::naming::ENTITY_TASK,
        task_id.as_str(),
        version,
    )
}
