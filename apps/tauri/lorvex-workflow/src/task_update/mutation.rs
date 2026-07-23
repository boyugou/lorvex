//! Orchestrator for the canonical single-row task-update mutation.
//!
//! Owns the cross-surface `TaskUpdateSyncEffects` shape, the patch
//! sanitizer (`sanitize_input`), the cross-row dependency-cycle
//! revalidator (`revalidate_dependency_cycles`), and the per-row apply
//! entry point (`apply_single_update_in_savepoint`) both `update_task`
//! (single) and `batch_update_tasks` (multi) call inside their own
//! savepoints.
//!
//! The per-effect SQL writes (row patch, tags, dependencies, recurrence
//! skeleton, status transition + lifecycle plan collection) live under
//! [`super::effects`] — each submodule owns one concern and a slice of
//! [`TaskUpdateSyncEffects`]. The orchestrator runs them in the fixed
//! order the cross-surface contract requires:
//!
//! 1. Primary row patch (no-op when no row-level field is touched).
//! 2. Recurrence skeleton co-application when the RRULE is being
//!    REPLACED (`Patch::Set` on `new_recurrence`). Runs before the
//!    status-reopen lifecycle pass so a joint reopen-plus-rule-swap
//!    patch spawns the next occurrence using the replacement rule,
//!    not the rule the row carried entering this mutation.
//! 3. Status-reopen lifecycle pass (only when `open` follows a non-open
//!    pre-state). Reads the parent's current due-date snapshot to
//!    cancel already-spawned successors via the
//!    `due_date > parent.due_date` filter; the pre-patch occurrence
//!    date must still be observable here, which is why due-date-only
//!    recurrence patches AND `Patch::Clear` of the rule both run
//!    AFTER this step — see the ordering rationale in step 4.
//! 4. Recurrence skeleton co-application for rule clears
//!    (`Patch::Clear`) and due-date-only re-anchors (rule unchanged).
//!    Deferred past the reopen pass for the reason in step 3.
//! 5. Status transition for the non-reopen direction.
//! 6. Dependency edge replace (skipped when the same patch cancels the
//!    row, since the cancel cascade already cleared the edge set).
//! 7. Tag edge replace.
//! 8. Push the row's id onto `task_upsert_ids` so every surface emits a
//!    `tasks` outbox upsert for the row this mutation is keyed on —
//!    gated on the patch actually touching a row-visible field so
//!    empty patches produce zero outbox enqueues.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::STATUS_CANCELLED;
use lorvex_domain::naming::STATUS_OPEN;
use lorvex_domain::{Patch, TaskId};
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

use crate::dependency_validation::validate_no_dependency_cycle;
use crate::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};

use super::effects::dependencies::{find_task_dependencies, replace_dependency_edges};
use super::effects::preparation::prepare_task_update;
use super::effects::recurrence::{apply_recurrence_patch, recurrence_patch_present};
use super::effects::row::{apply_primary_row_patch, has_primary_row_patch};
use super::effects::status::apply_status_transition;
use super::effects::tags::replace_task_tags;
use super::input::TaskUpdateInput;

pub(crate) use super::effects::preparation::validate_task_id_shape;

#[derive(Debug, Clone)]
pub struct TaskTagEdgeDelete {
    pub task_id: String,
    pub tag_id: String,
    pub version: String,
    pub created_at: String,
}

#[derive(Debug, Clone)]
pub struct UpdateTaskSpawnedSuccessor {
    pub successor_id: String,
    pub summary: String,
    pub after_task: Value,
}

#[derive(Debug, Clone)]
pub struct UpdateTaskCancelledSuccessor {
    pub successor_id: String,
    pub summary: String,
    pub after_task: Value,
}

#[derive(Debug, Clone)]
pub struct UpdateTaskFocusRewireAudit {
    pub parent_task_id: String,
    pub successor_id: String,
    pub focus_schedule_dates: Vec<String>,
    pub current_focus_dates: Vec<String>,
}

/// Aggregated sync side-effects from one or more single-row updates.
/// Used by both `update_task` (single-element fields) and
/// `batch_update_tasks` (multi-row aggregation).
#[derive(Debug, Default)]
pub struct TaskUpdateSyncEffects {
    pub task_upsert_ids: Vec<String>,
    pub reminder_upsert_ids: Vec<String>,
    pub dependency_edge_upsert_ids: Vec<String>,
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
    pub affected_dependent_ids: Vec<String>,
    pub tag_upsert_ids: Vec<String>,
    pub task_tag_edge_upsert_ids: Vec<String>,
    pub task_tag_edge_delete_ids: Vec<String>,
    pub deleted_task_tag_edges: Vec<TaskTagEdgeDelete>,
    pub spawned_successors: Vec<UpdateTaskSpawnedSuccessor>,
    pub cancelled_successors: Vec<UpdateTaskCancelledSuccessor>,
    pub spawned_successor_tag_edges: Vec<CopiedTagEdge>,
    pub spawned_successor_checklist_item_ids: Vec<String>,
    pub spawned_successor_reminder_ids: Vec<String>,
    pub focus_rewire_audits: Vec<UpdateTaskFocusRewireAudit>,
    pub rewired_focus_schedule_dates: Vec<String>,
    pub rewired_current_focus_dates: Vec<String>,
}

/// Sanitize free-text fields in an update patch in-place. Mirrors the
/// MCP server's Unicode hygiene gate.
pub(crate) fn sanitize_input(patch: &mut TaskUpdateInput) {
    patch.title = patch
        .title
        .clone()
        .map(|title| lorvex_domain::sanitize_user_text(&title));
    patch.body = patch
        .body
        .clone()
        .map(|body| lorvex_domain::sanitize_user_text(&body));
    patch.raw_input = patch
        .raw_input
        .clone()
        .map(|raw_input| lorvex_domain::sanitize_user_text(&raw_input));
    patch.ai_notes = patch
        .ai_notes
        .clone()
        .map(|notes| lorvex_domain::sanitize_user_text(&notes));
    patch.tags_set = sanitize_vec(patch.tags_set.take());
    patch.tags_add = sanitize_vec(patch.tags_add.take());
    patch.tags_remove = sanitize_vec(patch.tags_remove.take());
}

fn sanitize_vec(values: Option<Vec<String>>) -> Option<Vec<String>> {
    values.map(|items| {
        items
            .into_iter()
            .map(|item| lorvex_domain::sanitize_user_text(&item))
            .collect()
    })
}

/// Apply a single task update inside an already-open savepoint /
/// transaction. The caller owns: outer savepoint open + commit,
/// pre-loading the `before` snapshot, and the cross-row dependency
/// cycle re-validation that runs after every row's edges land.
///
/// Pushes the row's id onto `dep_changed_ids` when the patch mutates
/// the `task_dependencies` edge set so the caller can re-run the cycle
/// validator with the final, post-update edge state.
///
/// production_api: orchestrator threads conn + HLC session + update payload +
/// before snapshot + before status + now + sync effects accumulator + dep-changed
/// id list, each load-bearing and distinct from the others.
#[allow(clippy::too_many_arguments)]
pub(crate) fn apply_single_update_in_savepoint(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    update: &TaskUpdateInput,
    before: &Value,
    before_status: &str,
    now: &str,
    sync_effects: &mut TaskUpdateSyncEffects,
    dep_changed_ids: &mut Vec<String>,
) -> Result<(), StoreError> {
    let prepared = prepare_task_update(conn, update, before, before_status)?;
    let typed_id = TaskId::from_trusted_str(&update.id);

    apply_primary_row_patch(conn, hlc, &update.id, &prepared, now)?;

    // Apply the recurrence patch BEFORE the reopen-side lifecycle
    // owner WHEN the recurrence rule is being REPLACED — so a joint
    // patch that both swaps the rule and reopens the task spawns
    // the next occurrence using the replacement rule.
    //
    // `Patch::Clear` is NOT treated as a rule change for ordering
    // purposes: clearing the recurrence would wipe the rule + the
    // parent anchor BEFORE the reopen-cancel-successor cascade runs,
    // leaving the already-spawned successor as an orphan because the
    // cancel SQL's `due_date > parent.due_date` filter would match
    // nothing against a null parent due-date. Routing `Clear` through
    // the post-reopen branch lets the cancel pass observe the
    // pre-patch due-date, cancel the successor, and only then drop
    // the recurrence rule.
    //
    // Due-date-only recurrence patches (rule unchanged) also defer
    // past the reopen pass for the same reason; the joint-reopen-
    // plus-due-date regression
    // (`update_task_with_conn_status_open_cancels_successor_before_due_date_patch`)
    // pins the contract.
    let rule_is_changing = matches!(prepared.new_recurrence, Patch::Set(_));
    let recurrence_patch_active = recurrence_patch_present(&prepared);
    if rule_is_changing {
        apply_recurrence_patch(conn, hlc, &typed_id, &prepared, now)?;
    }

    let status_reopens_task =
        prepared.new_status.as_deref() == Some(STATUS_OPEN) && before_status != STATUS_OPEN;
    if status_reopens_task {
        apply_status_transition(
            conn,
            hlc,
            &typed_id,
            prepared.new_status.as_deref(),
            before_status,
            now,
            sync_effects,
        )?;
    }
    // Recurrence patches whose rule is NOT being replaced
    // (`Patch::Clear` and due-date-only re-anchors) run after the
    // reopen pass for the reason in the comment above. They still
    // run before the non-reopen status transition because the
    // due-date / rule columns are part of the row's canonical
    // post-patch state and downstream effects (depending status, tag
    // cascade) must observe the final values.
    if recurrence_patch_active && !rule_is_changing {
        apply_recurrence_patch(conn, hlc, &typed_id, &prepared, now)?;
    }
    apply_status_transition(
        conn,
        hlc,
        &typed_id,
        prepared
            .new_status
            .as_deref()
            .filter(|_| !status_reopens_task),
        before_status,
        now,
        sync_effects,
    )?;

    let status_became_cancelled = prepared.new_status.as_deref() == Some(STATUS_CANCELLED)
        && before_status != STATUS_CANCELLED;
    if prepared.changed_deps && !status_became_cancelled {
        if let Some(deps) = prepared.new_depends_on.as_deref() {
            replace_dependency_edges(conn, hlc, &typed_id, deps, sync_effects)?;
        }
        dep_changed_ids.push(update.id.clone());
    }
    if prepared.changed_tags {
        if let Some(tags) = prepared.new_tags.as_deref() {
            replace_task_tags(conn, hlc, &typed_id, tags, sync_effects)?;
        }
    }
    // Gate the row's `tasks` outbox enqueue on the patch actually
    // touching a row-visible field. An empty patch (every field
    // `Unset`, no status / tags / deps / recurrence) leaves the row
    // identical and must not produce a phantom upsert that wakes
    // every peer to re-fetch an unchanged row.
    let touches_row = has_primary_row_patch(&prepared)
        || prepared.changed_tags
        || prepared.changed_deps
        || prepared.new_status.is_some()
        || recurrence_patch_active;
    if touches_row {
        sync_effects.task_upsert_ids.push(update.id.clone());
    }
    Ok(())
}

/// Run the cross-row dependency cycle re-validation. Both `update_task`
/// (single) and `batch_update_tasks` (multi) defer the cycle check
/// until after every row's new edge set has landed so the validator
/// sees the final state of the graph.
pub(crate) fn revalidate_dependency_cycles(
    conn: &Connection,
    dep_changed_ids: &[String],
    error_context: &str,
) -> Result<(), StoreError> {
    for task_id in dep_changed_ids {
        let task_id_typed = TaskId::from_trusted_str(task_id);
        let new_deps = find_task_dependencies(conn, &task_id_typed)?;
        if let Err(error) = validate_no_dependency_cycle(conn, &task_id_typed, &new_deps) {
            return Err(StoreError::Validation(format!(
                "{error_context} for task {task_id}: {error}"
            )));
        }
    }
    Ok(())
}
