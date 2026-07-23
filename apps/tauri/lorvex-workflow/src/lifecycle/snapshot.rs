//! Pre-mutation snapshot of the task fields the lifecycle orchestrator
//! needs.
//!
//! Read directly from the DB rather than threaded through adapter-specific
//! types so the same orchestrator works for both MCP and Tauri callers.

use lorvex_domain::time::Date;
use lorvex_domain::TaskId;
use rusqlite::{params, Connection, OptionalExtension};

use lorvex_store::StoreError;

/// `due_date`, `planned_date`, and
/// `canonical_occurrence_date` use the typed [`Date`] newtype so the
/// schema-storage `YYYY-MM-DD` invariant is type-system enforced
/// across the lifecycle orchestrator. The orchestrator never
/// serializes the snapshot — it's a pre-mutation read used by the
/// successor-spawn / cancel-successor / side-effect helpers — so
/// the wrapper is purely a compile-time gate.
#[derive(Clone)]
pub(super) struct TaskSnapshot {
    pub(super) recurrence: Option<String>,
    pub(super) recurrence_exceptions: Option<String>,
    pub(super) recurrence_group_id: Option<String>,
    pub(super) due_date: Option<Date>,
    pub(super) planned_date: Option<Date>,
    pub(super) available_from: Option<Date>,
    pub(super) canonical_occurrence_date: Option<Date>,
}

pub(super) fn read_active_task_reminder_times(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<String>, StoreError> {
    conn.prepare_cached(
        "SELECT reminder_at FROM task_reminders \
         WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL \
         ORDER BY id ASC",
    )?
    .query_map(params![task_id], |row| row.get(0))?
    .collect::<Result<Vec<_>, _>>()
    .map_err(StoreError::from)
}

pub(super) fn read_task_snapshot(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Option<TaskSnapshot>, StoreError> {
    conn.query_row(
        "SELECT recurrence, \
         (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
          FROM task_recurrence_exceptions WHERE task_id = tasks.id), \
         recurrence_group_id, due_date, planned_date, available_from, canonical_occurrence_date \
         FROM tasks WHERE id = ?1",
        params![task_id],
        |row| {
            Ok(TaskSnapshot {
                recurrence: row.get(0)?,
                recurrence_exceptions: row.get(1)?,
                recurrence_group_id: row.get(2)?,
                due_date: row.get(3)?,
                planned_date: row.get(4)?,
                available_from: row.get(5)?,
                canonical_occurrence_date: row.get(6)?,
            })
        },
    )
    .optional()
    .map_err(StoreError::from)
}
