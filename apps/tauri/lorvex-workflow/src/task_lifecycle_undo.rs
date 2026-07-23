//! Canonical pre-mutation-state restore used by the Tauri app's undo
//! pipeline.
//!
//! Lifecycle undos (`complete`, `cancel`) carry a multi-field snapshot
//! of the row's pre-mutation state in their token: `status`,
//! `completed_at`, `planned_date`, `defer_count`, `last_deferred_at`,
//! `last_defer_reason`. Applying an undo means stamping each of these
//! fields back, alongside a fresh `version` + `updated_at` so peers'
//! LWW reconciliation accepts the restoration as a forward write.
//!
//! Co-located in `lorvex-workflow` so the canonical UPDATE site is
//! visible alongside `archive` and the other
//! same-shape ops. The caller (Tauri `apply_single_undo`) owns the
//! surrounding token validation, sync-already-dispatched gating, and
//! the cascading side effects (successor cleanup, reminder restore,
//! dependency edge restore, outbox retraction).

use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::{params, Connection};

/// Multi-field pre-mutation snapshot that a lifecycle-undo restores
/// onto a task row. Mirrors the corresponding fields on the
/// `UndoToken` payload but without the surface-specific typing — the
/// op only needs string-typed projections.
#[derive(Debug)]
pub struct LifecycleUndoFields<'a> {
    pub status: &'a str,
    pub completed_at: Option<&'a str>,
    pub planned_date: Option<&'a str>,
    pub defer_count: i64,
    pub last_deferred_at: Option<&'a str>,
    pub last_defer_reason: Option<&'a str>,
}

/// Restore the row to its pre-mutation state. Returns
/// [`StoreError::NotFound`] when the task id has no row. The UPDATE
/// is intentionally **not** version-gated: the caller has already
/// rejected the undo when a peer mutation has been dispatched (see
/// the surface's `lifecycle_undo_group_already_synced` check), and the
/// undo path needs to overwrite the row's current state regardless of
/// whether the new HLC sorts above the pre-undo stamp.
pub fn restore_op(
    conn: &Connection,
    task_id: &TaskId,
    fields: &LifecycleUndoFields<'_>,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let rows = conn
        .prepare_cached(
            "UPDATE tasks SET status = ?1, completed_at = ?2, planned_date = ?3, \
             defer_count = ?4, last_deferred_at = ?5, last_defer_reason = ?6, \
             version = ?7, updated_at = ?8 \
             WHERE id = ?9",
        )?
        .execute(params![
            fields.status,
            fields.completed_at,
            fields.planned_date,
            fields.defer_count,
            fields.last_deferred_at,
            fields.last_defer_reason,
            version,
            now,
            task_id,
        ])?;
    if rows == 0 {
        return Err(StoreError::NotFound {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }
    Ok(())
}
