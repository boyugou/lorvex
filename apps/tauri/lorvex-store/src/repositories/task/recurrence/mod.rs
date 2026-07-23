//! Recurrence-exception operations for `tasks`.
//!
//! Public API kept stable for callers
//! (`add_task_recurrence_exception` / `remove_task_recurrence_exception`);
//! the body delegates to [`super::super::recurrence_exceptions_common`] which
//! carries the shared validation, transaction, and LWW-gated UPDATE
//! pipeline (#3022 H1).

use rusqlite::Connection;

use super::super::recurrence_exceptions_common::{
    add_exception, remove_exception, ExceptionOwner, ExceptionTableConfig,
};
use crate::error::StoreError;
use lorvex_domain::naming::ENTITY_TASK;

const CONFIG: ExceptionTableConfig = ExceptionTableConfig {
    entity: ENTITY_TASK,
    entity_noun: "Task",
    anchor_label: "task canonical occurrence date",
    select_anchor_sql: "SELECT recurrence, \
                (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                 FROM task_recurrence_exceptions WHERE task_id = tasks.id), \
                canonical_occurrence_date \
         FROM tasks WHERE id = ?1",
    bump_version_sql: "UPDATE tasks SET version = ?1, updated_at = ?2 \
         WHERE id = ?3 AND ?1 > version",
    exception_owner: ExceptionOwner::Task,
};

/// Add a recurrence exception date to a task.
///
/// Validates: task exists, task is recurring, date is valid YYYY-MM-DD,
/// date >= canonical_occurrence_date, date is an actual occurrence of the
/// recurrence rule, and date is not already in the exceptions list.
/// Returns the updated exceptions JSON string.
pub fn add_task_recurrence_exception(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<String, StoreError> {
    add_exception(
        conn,
        &CONFIG,
        task_id.as_str(),
        exception_date,
        version,
        now,
    )
}

/// Remove a recurrence exception date from a task.
///
/// Validates: task exists, date is valid YYYY-MM-DD, and date is in the
/// current exceptions list. Returns the updated exceptions JSON string,
/// or `None` if the list is now empty.
pub fn remove_task_recurrence_exception(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<Option<String>, StoreError> {
    remove_exception(
        conn,
        &CONFIG,
        task_id.as_str(),
        exception_date,
        version,
        now,
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
