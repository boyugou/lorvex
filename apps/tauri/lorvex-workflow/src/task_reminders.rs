//! Parent-task touch op for edge-row mutations on a task.
//!
//! Adding or removing a reminder / calendar-event link / similar edge
//! row attached to a task is conceptually a write on the parent task
//! itself: peers reading via sync expect the task's `version` to
//! advance so LWW reconciliation treats their cached child set as
//! stale. CLI's `remove_task_reminder_with_conn` and
//! the calendar link unlink path stamped only `updated_at` without
//! bumping `version`, which left peer caches inconsistent (the child
//! DELETE envelope flowed, but the parent task's enqueued upsert
//! lex-sorted below any peer's recent write and LWW silently dropped
//! the change). This op centralizes the parent-row touch so every
//! surface stamps `version` consistently.
//!
//! Returns [`StoreError::NotFound`] when the task id has no row. The
//! UPDATE is intentionally **not** LWW-gated: the surrounding caller
//! has already loaded the row in the same transaction, so the gate
//! would only fire if a concurrent peer write committed mid-tx (which
//! the immediate-tx policy prevents) — and a forced-forward stamp on
//! the parent is required for the enqueue to flow.

use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::{params, Connection};

/// Bump the task's `version` + `updated_at` to reflect an edge-row
/// (reminder / calendar event link / …) mutation against the parent.
/// Caller is responsible for performing the child-row write itself
/// and for enqueueing the parent task's upsert envelope.
pub fn touch_parent_task_op(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let rows = conn.execute(
        "UPDATE tasks SET version = ?1, updated_at = ?2 WHERE id = ?3",
        params![version, now, task_id],
    )?;
    if rows == 0 {
        return Err(StoreError::NotFound {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }
    Ok(())
}
