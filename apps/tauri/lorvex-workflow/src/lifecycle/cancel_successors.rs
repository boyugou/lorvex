//! Cancel any outstanding recurring successors when reopening a
//! completed parent task. Used by the reopen path to keep the timeline
//! consistent: a successor that was already auto-spawned for the next
//! occurrence has to retire when the user reopens the original.

use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

use lorvex_store::StoreError;

use super::snapshot::TaskSnapshot;
use super::status::cancel_task;
use super::types::SuccessorCancelSideEffects;

pub(super) struct SuccessorCancelResult {
    pub(super) ids: Vec<String>,
    pub(super) side_effects: SuccessorCancelSideEffects,
}

pub(super) fn cancel_recurring_successors(
    conn: &Connection,
    task_id: &TaskId,
    snap: &TaskSnapshot,
    now: &str,
    reminder_version: &str,
) -> Result<SuccessorCancelResult, StoreError> {
    let Some(due_date) = snap.due_date else {
        return Ok(SuccessorCancelResult {
            ids: vec![],
            side_effects: SuccessorCancelSideEffects {
                cancelled_reminder_ids: Vec::new(),
                deleted_dependency_edges: Vec::new(),
                affected_dependent_ids: Vec::new(),
            },
        });
    };

    // Find current successors by explicit spawned_from lineage.
    let successor_ids: Vec<String> = conn
        .prepare_cached(
            "SELECT id FROM tasks WHERE spawned_from = ?1 AND status = 'open' AND due_date > ?2",
        )?
        .query_map(params![task_id, due_date], |row| row.get(0))?
        .collect::<Result<_, _>>()?;

    // Cancel each successor via the shared cancel_task op, collecting all sync side effects.
    let mut agg = SuccessorCancelSideEffects {
        cancelled_reminder_ids: Vec::new(),
        deleted_dependency_edges: Vec::new(),
        affected_dependent_ids: Vec::new(),
    };
    for sid in &successor_ids {
        let sid_typed = TaskId::from_trusted(sid.clone());
        let result = cancel_task(conn, &sid_typed, now, reminder_version)?;
        agg.cancelled_reminder_ids
            .extend(result.cancelled_reminder_ids);
        agg.deleted_dependency_edges
            .extend(result.deleted_dependency_edges);
        agg.affected_dependent_ids
            .extend(result.affected_dependent_ids);
    }

    Ok(SuccessorCancelResult {
        ids: successor_ids,
        side_effects: agg,
    })
}
