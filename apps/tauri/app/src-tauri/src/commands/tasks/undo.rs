use rusqlite::{params, Connection};
use serde_json::Value;
use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{TaskStatus, ENTITY_TASK, OP_DELETE};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};

use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;
use crate::error::AppError;

use super::{
    enqueue_affected_dependents, enqueue_current_focus_upsert_for_date,
    enqueue_dependency_edge_upsert, enqueue_focus_schedule_upsert_for_date,
    enqueue_task_reminder_upsert, enqueue_task_upsert, event_bus, fetch_task_by_id, get_conn,
    sync_timestamp_now, with_immediate_transaction, Task,
};

mod tokens;
mod update;

use tokens::{
    build_redo_token, parse_and_validate_redo_token, parse_and_validate_undo_token, RedoToken,
};
pub(crate) use tokens::{
    build_undo_token, build_update_undo_token, compute_undo_expiry, LifecycleAction, UndoToken,
};
#[cfg(test)]
use tokens::{validate_lifecycle_token_expiry, LifecycleTokenKind};
pub use tokens::{TaskWithRedo, TaskWithUndo};
use update::apply_update_undo;

/// Test-only entry point into `apply_single_undo` — lets sibling
/// modules drive the undo pipeline from their own unit tests without
/// parsing the token through the IPC boundary (#2538).
#[cfg(test)]
pub(crate) fn apply_single_undo_for_tests(
    conn: &Connection,
    undo: &UndoToken,
    now: &str,
) -> Result<Task, AppError> {
    apply_single_undo(conn, undo, now)
}

/// Apply a single undo within an existing transaction. Does NOT emit events
/// (the caller is responsible for emitting once after all undos complete).
///
/// Undo is a plain reverse write: every local restore is paired with a
/// fresh sync envelope (a newer-HLC upsert, or a delete for the spawned
/// recurrence successor) so peers converge on the restored state via
/// ordinary LWW — regardless of whether the forward mutation's
/// envelopes have already been pushed.
fn apply_single_undo(conn: &Connection, undo: &UndoToken, now: &str) -> Result<Task, AppError> {
    // The `Update` action (#2538) takes a separate path — it doesn't
    // revert a status transition, it restores every updatable field
    // from a full pre-mutation snapshot by re-issuing the update path.
    let lifecycle = match undo.action {
        LifecycleAction::Update => {
            return apply_update_undo(conn, undo, now);
        }
        LifecycleAction::Complete => TaskStatus::Completed,
        LifecycleAction::Cancel => TaskStatus::Cancelled,
    };

    // 1. Verify the task still exists and is in the expected post-mutation state.
    let current = fetch_task_by_id(conn, &undo.task_id)?;
    let expected_status = lifecycle.as_str();
    if current.status != expected_status {
        return Err(AppError::Validation(format!(
            "Cannot undo: task {} status is '{}', expected '{}'",
            undo.task_id, current.status, expected_status
        )));
    }

    // 2. Restore the task to pre-mutation state.
    let version = crate::hlc::generate_version_result()?;
    let typed_task_id = lorvex_domain::TaskId::from_trusted(undo.task_id.clone());
    lorvex_workflow::task_lifecycle_undo::restore_op(
        conn,
        &typed_task_id,
        &lorvex_workflow::task_lifecycle_undo::LifecycleUndoFields {
            // persist the canonical wire form of the typed
            // `TaskStatus` so the SQL CHECK on `tasks.status` sees
            // byte-identical input regardless of how the token was
            // deserialized.
            status: undo.pre_status.as_str(),
            completed_at: undo.pre_completed_at.as_deref(),
            planned_date: undo.pre_planned_date.as_deref(),
            defer_count: undo.pre_defer_count,
            last_deferred_at: undo.pre_last_deferred_at.as_deref(),
            last_defer_reason: undo.pre_last_defer_reason.as_deref(),
        },
        &version,
        now,
    )
    .map_err(AppError::from)?;

    // 3. Delete the spawned successor (if any) and publish the reverse
    //    writes peers need to drop it: explicit delete envelopes for the
    //    successor's independently synced child rows (enqueued BEFORE the
    //    local rows disappear, mirroring the permanent-delete cascade),
    //    then a task delete envelope + tombstone under the hard-delete
    //    mutation's own HLC stamp.
    let mut restored_focus_schedule_dates = Vec::new();
    let mut restored_current_focus_dates = Vec::new();
    if let Some(ref successor_id) = undo.spawned_successor_id {
        let restored_focus_refs =
            restore_focus_plan_refs_from_successor(conn, successor_id, &undo.task_id)?;
        restored_focus_schedule_dates = restored_focus_refs.focus_schedule_dates;
        restored_current_focus_dates = restored_focus_refs.current_focus_dates;

        // Snapshot the successor row + enqueue child delete envelopes
        // while the rows still exist.
        let successor_before = crate::commands::fetch_task_row_unenriched(conn, successor_id).ok();
        super::lifecycle::enqueue_cascaded_task_child_deletes(conn, successor_id, now)?;

        conn.prepare_cached("DELETE FROM task_tags WHERE task_id = ?1")?
            .execute(params![successor_id])
            .map_err(AppError::from)?;
        // Same OR-predicate split as the `cleanup_task_dependencies`
        // helper in lorvex-workflow/src/lifecycle/primitives/
        // dependencies.rs: two prepared DELETEs (one per direction)
        // each use their own index — the PK on (task_id,
        // depends_on_task_id) and the secondary on
        // (depends_on_task_id) — instead of forcing the planner to
        // OR-by-rowid union. The pair runs inside the same
        // transaction so atomicity is preserved.
        conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")?
            .execute(params![successor_id])
            .map_err(AppError::from)?;
        conn.prepare_cached("DELETE FROM task_dependencies WHERE depends_on_task_id = ?1")?
            .execute(params![successor_id])
            .map_err(AppError::from)?;
        conn.prepare_cached("DELETE FROM task_checklist_items WHERE task_id = ?1")?
            .execute(params![successor_id])
            .map_err(AppError::from)?;
        conn.prepare_cached("DELETE FROM task_reminders WHERE task_id = ?1")?
            .execute(params![successor_id])
            .map_err(AppError::from)?;
        let successor_task_id = lorvex_domain::TaskId::from_trusted(successor_id.clone());
        // Route the successor hard-delete + tombstone through the
        // canonical IPC mutation executor so the per-mutation
        // `HlcSession` mints the delete version, the
        // `local_change_seq++` bump runs, and the event_bus broadcast
        // fires alongside every other Tauri task delete. The undo
        // pipeline's outer `version` continues to drive the parent
        // restore + reminder unsuspend + dep-edge re-insert; the
        // successor delete is its own conceptual write and gets a
        // fresh monotonic stamp from the surface HLC runtime.
        let mutation = UndoSuccessorHardDeleteMutation {
            task_id: &successor_task_id,
            now,
            delete_version: RefCell::new(None),
        };
        execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
            let delete_version = mutation
                .delete_version
                .borrow_mut()
                .take()
                .expect("successor hard-delete mutation must populate its delete version");
            crate::commands::enqueue_task_delete_with_version(
                conn,
                successor_id,
                successor_before.as_ref(),
                &delete_version,
            )
        })?;
    }

    // 4. Restore cancelled reminders and re-publish each restored row.
    // Lift the prepare out of the loop so a task with N cancelled
    // reminders pays one prepare instead of N.
    if !undo.cancelled_reminder_ids.is_empty() {
        let mut stmt = conn.prepare_cached(
            "UPDATE task_reminders SET cancelled_at = NULL, version = ?1 WHERE id = ?2",
        )?;
        for rid in &undo.cancelled_reminder_ids {
            stmt.execute(params![version, rid])
                .map_err(AppError::from)?;
        }
        drop(stmt);
        for rid in &undo.cancelled_reminder_ids {
            enqueue_task_reminder_upsert(conn, rid)?;
        }
    }

    // 5. Restore deleted dependency edges (cancel undo) — batched per
    //    task_id — and re-publish each edge as an upsert so peers that
    //    applied the forward mutation's edge deletes re-create them.
    if !undo.deleted_dep_edges.is_empty() {
        use lorvex_domain::TaskId;
        use lorvex_store::repositories::task::dependencies;
        use std::collections::HashMap;

        let mut grouped: HashMap<&str, Vec<TaskId>> = HashMap::new();
        for (tid, dep_id) in &undo.deleted_dep_edges {
            grouped
                .entry(tid.as_str())
                .or_default()
                .push(TaskId::from_trusted(dep_id.clone()));
        }
        for (tid, dep_ids) in &grouped {
            dependencies::insert_dependency_edges_batch(
                conn,
                &TaskId::from_trusted((*tid).to_string()),
                dep_ids,
                &version,
                now,
            )
            .map_err(AppError::from)?;
        }
        for (tid, dep_id) in &undo.deleted_dep_edges {
            enqueue_dependency_edge_upsert(conn, &format!("{tid}:{dep_id}"))?;
        }
    }

    // 6. Re-publish dependents whose forward-mutation upserts reflected
    //    the deleted edges, so peers converge on the restored rows.
    enqueue_affected_dependents(conn, &undo.affected_dependent_ids)?;

    for date in &restored_focus_schedule_dates {
        enqueue_focus_schedule_upsert_for_date(conn, date)?;
    }
    for date in &restored_current_focus_dates {
        enqueue_current_focus_upsert_for_date(conn, date)?;
    }

    // 7. Re-enqueue the restored task state for sync.
    let restored = fetch_task_by_id(conn, &undo.task_id)?;
    enqueue_task_upsert(conn, &restored)?;
    // Mirror the forward mutation helpers: enqueue_task_upsert stamps a
    // fresh HLC onto the task row, so re-read after enqueue to return the
    // canonical post-sync version instead of a stale pre-enqueue snapshot.
    let restored = fetch_task_by_id(conn, &undo.task_id)?;

    Ok(restored)
}

struct RestoredFocusPlanRefs {
    focus_schedule_dates: Vec<String>,
    current_focus_dates: Vec<String>,
}

fn restore_focus_plan_refs_from_successor(
    conn: &Connection,
    successor_id: &str,
    parent_id: &str,
) -> Result<RestoredFocusPlanRefs, AppError> {
    let rewired_focus_schedule_dates: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT schedule_date FROM focus_schedule_blocks \
                 WHERE task_id = ?1 ORDER BY schedule_date ASC",
            )
            .map_err(AppError::from)?;
        let rows = stmt
            .query_map(params![successor_id], |row| row.get::<_, String>(0))
            .map_err(AppError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?;
        rows
    };
    let rewired_current_focus_dates: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT date FROM current_focus_items \
                 WHERE task_id = ?1 ORDER BY date ASC",
            )
            .map_err(AppError::from)?;
        let rows = stmt
            .query_map(params![successor_id], |row| row.get::<_, String>(0))
            .map_err(AppError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?;
        rows
    };

    if !rewired_focus_schedule_dates.is_empty() {
        conn.prepare_cached("UPDATE focus_schedule_blocks SET task_id = ?1 WHERE task_id = ?2")?
            .execute(params![parent_id, successor_id])
            .map_err(AppError::from)?;
    }
    if !rewired_current_focus_dates.is_empty() {
        conn.prepare_cached(
            "UPDATE OR IGNORE current_focus_items SET task_id = ?1 WHERE task_id = ?2",
        )?
        .execute(params![parent_id, successor_id])
        .map_err(AppError::from)?;
        conn.prepare_cached("DELETE FROM current_focus_items WHERE task_id = ?1")?
            .execute(params![successor_id])
            .map_err(AppError::from)?;
    }

    Ok(RestoredFocusPlanRefs {
        focus_schedule_dates: rewired_focus_schedule_dates,
        current_focus_dates: rewired_current_focus_dates,
    })
}

/// `Mutation` descriptor for the spawned-successor hard delete that
/// runs while undoing a recurrence-spawning lifecycle transition
/// (complete or cancel with `cancel_series=false`). `apply` mints the
/// delete version from the per-mutation [`HlcSession`], hard-deletes
/// the successor task via the canonical LWW-gated store helper, and
/// writes the successor's task tombstone (the authoritative
/// peer-side delete marker) under the same stamp. The minted version
/// is stashed in `delete_version` so the surface finalizer can
/// enqueue the matching task delete envelope with the same HLC.
struct UndoSuccessorHardDeleteMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    now: &'a str,
    delete_version: RefCell<Option<String>>,
}

impl<'a> Mutation for UndoSuccessorHardDeleteMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let delete_version = hlc.next_version_string();
        lorvex_store::repositories::task::write::hard_delete_task_lww(
            conn,
            self.task_id,
            &delete_version,
        )?;
        lorvex_sync::tombstone::create_tombstone(
            conn,
            ENTITY_TASK,
            self.task_id.as_str(),
            &delete_version,
            self.now,
            None,
            None,
        )?;
        let summary = format!(
            "Undo: hard-deleted spawned successor '{}'",
            self.task_id.as_str()
        );
        let after = serde_json::json!({ "id": self.task_id.as_str(), "deleted": true });
        *self.delete_version.borrow_mut() = Some(delete_version);
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn undo_task_lifecycle(token: String) -> Result<TaskWithRedo, String> {
    let conn = get_conn()?;
    let now = sync_timestamp_now();
    let result = undo_task_lifecycle_with_conn(&conn, &token, &now).map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Task);
    Ok(result)
}

fn undo_task_lifecycle_with_conn(
    conn: &Connection,
    token: &str,
    now: &str,
) -> Result<TaskWithRedo, AppError> {
    let undo = parse_and_validate_undo_token(token)?;

    // Build the redo token before applying the undo. Update undos are
    // intentionally one-way and return `None`; complete/cancel undos
    // get a redo token unless token construction fails before state is
    // mutated.
    let expires_at = compute_undo_expiry();
    let redo_token = build_redo_token(&undo, &expires_at)?;
    let restored = with_immediate_transaction(conn, |conn| apply_single_undo(conn, &undo, now))?;

    Ok(TaskWithRedo {
        task: restored,
        redo_token,
    })
}

#[cfg(test)]
pub(crate) fn undo_task_lifecycle_with_conn_for_tests(
    conn: &Connection,
    token: &str,
    now: &str,
) -> Result<TaskWithRedo, AppError> {
    undo_task_lifecycle_with_conn(conn, token, now)
}

/// Re-apply an undone lifecycle mutation. Returns a fresh
/// `TaskWithUndo` so the user can immediately undo the redo — one step
/// of back-and-forth, intentionally non-stacking per #2536.
///
/// The redo re-runs `complete_task_inner` / `cancel_task_inner`, which
/// means it goes through the normal outbox pipeline and produces a
/// brand-new `undo_token`. Recurrence successors spawned by the
/// forward mutation get fresh IDs — the redo reproduces the *semantic*
/// effect of the original mutation, not a bit-identical replay.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn redo_task_lifecycle(token: String) -> Result<TaskWithUndo, String> {
    let redo = parse_and_validate_redo_token(&token).map_err(String::from)?;

    // typed `LifecycleAction` enum makes the
    // dispatch exhaustive — adding a future variant fails compilation
    // here instead of silently routing into the previous string-based
    // default arm. The sum-typed `RedoToken` makes
    // the `(action, cancel_series)` coupling enforced at the wire
    // boundary, so the dispatch only has to walk the variants — no
    // runtime `Option::unwrap_or` defaulting that could mask a
    // tampered token's coupling violation.
    match redo {
        RedoToken::Complete { task_id, .. } => {
            super::completion::complete_task_inner(task_id).map_err(String::from)
        }
        RedoToken::Cancel {
            task_id,
            cancel_series,
            ..
        } => super::lifecycle::cancel_task_inner(task_id, cancel_series).map_err(String::from),
    }
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn undo_task_lifecycle_batch(tokens: Vec<String>) -> Result<Vec<Task>, String> {
    if tokens.is_empty() {
        return Err("No undo tokens provided".to_string());
    }

    // Phase 1: Parse and validate ALL tokens before starting the transaction.
    let undos: Vec<UndoToken> = tokens
        .iter()
        .map(|t| parse_and_validate_undo_token(t))
        .collect::<Result<Vec<_>, _>>()
        .map_err(String::from)?;

    let conn = get_conn()?;
    let now = sync_timestamp_now();

    let restored_tasks = with_immediate_transaction(&conn, |conn| {
        // Phase 2: Apply all undos within the same transaction.
        let mut restored_tasks = Vec::with_capacity(undos.len());
        for undo in &undos {
            let restored = apply_single_undo(conn, undo, &now)?;
            restored_tasks.push(restored);
        }
        Ok(restored_tasks)
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Task);
    Ok(restored_tasks)
}

#[cfg(test)]
mod tests;
