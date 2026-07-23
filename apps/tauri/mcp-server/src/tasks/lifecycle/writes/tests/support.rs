//! Shared helpers and re-exports for the task-lifecycle write-tool
//! test suite. Each per-domain split file pulls in the same
//! production primitives via `use super::support::*;`.

pub(super) use super::super::*;
pub(super) use crate::contract::{
    AddTaskChecklistItemArgs, CancelTaskArgs, CompleteTaskArgs, DeferTaskArgs,
    PermanentDeleteTaskArgs, RemoveTaskChecklistItemArgs, RemoveTaskReminderArgs,
    ReorderTaskChecklistItemsArgs, SetTaskAiNotesArgs, ToggleTaskChecklistItemArgs,
    UpdateTaskChecklistItemArgs,
};
pub(super) use crate::db::open_database_for_path;
pub(super) use crate::error::McpError;
pub(super) use rusqlite::Connection;
pub(super) use serde_json::Value;
pub(super) use tempfile::tempdir;

pub(super) fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

/// Read the `(version, updated_at)` pair currently persisted on a task
/// row. Used by the #2975 regression suite to confirm parent-task
/// version-bump fixes actually advance `version`, not just `updated_at`.
pub(super) fn read_task_version_updated(conn: &Connection, task_id: &str) -> (String, String) {
    conn.query_row(
        "SELECT version, updated_at FROM tasks WHERE id = ?1",
        [task_id],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .expect("read task (version, updated_at)")
}

pub(super) fn seed_task_with_version(
    conn: &Connection,
    id: &str,
    title: &str,
    version: &str,
    now: &str,
) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::TaskBuilder::new(id)
        .title(title)
        .version(version)
        .created_at(now)
        .insert(conn);
}
