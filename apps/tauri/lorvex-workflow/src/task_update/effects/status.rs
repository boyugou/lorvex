//! Status transition + lifecycle plan collection for a single-row task
//! update.
//!
//! [`apply_status_transition`] dispatches to the canonical lifecycle
//! owner (`lifecycle::effects::run_reopen` /
//! `lifecycle::effects::run_status_change`) and folds the resulting
//! [`crate::lifecycle::LifecycleSyncPlan`] into the row's accumulating
//! [`TaskUpdateSyncEffects`] — cancelled reminders, dependency-edge
//! tombstones, affected-dependent ids, spawned + cancelled successor
//! envelopes, focus-rewire audits, and the inherited child entities
//! every successor copies from its parent.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{TaskStatus, STATUS_OPEN};
use lorvex_domain::TaskId;
use lorvex_store::repositories::task::write;
use lorvex_store::StoreError;
use rusqlite::Connection;

use super::super::mutation::{
    TaskUpdateSyncEffects, UpdateTaskCancelledSuccessor, UpdateTaskFocusRewireAudit,
    UpdateTaskSpawnedSuccessor,
};
use crate::lifecycle::{self, CopiedTagEdge, DeletedDependencyEdge};

pub(in crate::task_update) fn apply_status_transition(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &TaskId,
    next_status: Option<&str>,
    before_status: &str,
    now: &str,
    effects: &mut TaskUpdateSyncEffects,
) -> Result<(), StoreError> {
    let Some(status) = next_status else {
        return Ok(());
    };
    let before = write::parse_task_status_for_update(task_id.as_str(), before_status)?;
    if status == STATUS_OPEN && before_status != STATUS_OPEN {
        let reopen = lifecycle::effects::run_reopen(conn, task_id, before, now, hlc)?;
        collect_lifecycle_plan(
            conn,
            task_id.as_str(),
            "Spawned recurrence successor from status transition",
            "Cancelled recurring successor (task reopened via update)",
            lifecycle::LifecycleSyncPlan::from_reopen(&reopen),
            effects,
        )?;
    } else {
        let next = TaskStatus::parse(status).ok_or_else(|| {
            StoreError::Validation(format!(
                "Invalid status '{status}'. Expected one of: open, completed, cancelled, someday"
            ))
        })?;
        let transition =
            lifecycle::effects::run_status_change(conn, task_id, before, next, now, hlc)?;
        collect_lifecycle_plan(
            conn,
            task_id.as_str(),
            "Spawned recurrence successor from status transition",
            "Cancelled recurring successor (task reopened via update)",
            lifecycle::LifecycleSyncPlan::from_transition(&transition),
            effects,
        )?;
    }
    Ok(())
}

fn collect_lifecycle_plan(
    conn: &Connection,
    parent_task_id: &str,
    spawned_summary: &str,
    cancelled_summary: &str,
    plan: lifecycle::LifecycleSyncPlan<'_>,
    effects: &mut TaskUpdateSyncEffects,
) -> Result<(), StoreError> {
    effects
        .reminder_upsert_ids
        .extend(plan.status.cancelled_reminder_ids.iter().cloned());
    effects
        .reminder_upsert_ids
        .extend(plan.reopened_reminder_ids.iter().cloned());
    effects
        .affected_dependent_ids
        .extend(plan.status.affected_dependent_ids.iter().cloned());
    effects
        .deleted_dependency_edges
        .extend(
            plan.status
                .deleted_dependency_edges
                .iter()
                .map(|edge| DeletedDependencyEdge {
                    task_id: edge.task_id.clone(),
                    depends_on_task_id: edge.depends_on_task_id.clone(),
                    created_at: edge.created_at.clone(),
                    version: edge.version.clone(),
                }),
        );
    effects
        .affected_dependent_ids
        .extend(plan.successor_cancel.affected_dependent_ids.iter().cloned());
    effects.deleted_dependency_edges.extend(
        plan.successor_cancel
            .deleted_dependency_edges
            .iter()
            .map(|edge| DeletedDependencyEdge {
                task_id: edge.task_id.clone(),
                depends_on_task_id: edge.depends_on_task_id.clone(),
                created_at: edge.created_at.clone(),
                version: edge.version.clone(),
            }),
    );
    effects
        .spawned_successor_tag_edges
        .extend(
            plan.spawned_successor_tag_edges
                .iter()
                .map(|edge| CopiedTagEdge {
                    task_id: edge.task_id.clone(),
                    tag_id: edge.tag_id.clone(),
                    version: edge.version.clone(),
                    created_at: edge.created_at.clone(),
                }),
        );
    effects
        .spawned_successor_checklist_item_ids
        .extend(plan.spawned_successor_checklist_item_ids.iter().cloned());
    effects
        .spawned_successor_reminder_ids
        .extend(plan.spawned_successor_reminder_ids.iter().cloned());
    effects.rewired_focus_schedule_dates.extend(
        plan.rewired_focus_schedule_dates
            .iter()
            .map(|date| (*date).to_string()),
    );
    effects.rewired_current_focus_dates.extend(
        plan.rewired_current_focus_dates
            .iter()
            .map(|date| (*date).to_string()),
    );
    if let Some(successor_id) = plan.spawned_successor_id {
        let successor = crate::task_response::load_enriched_task_json(
            conn,
            &TaskId::from_trusted_str(successor_id),
        )?;
        // The newly written successor task row must reach peers via the
        // `tasks` outbox channel. The MCP surface relied on
        // `log_change`'s implicit per-entity sync enqueue, but the Tauri
        // surface skips changelog writes entirely, so the only
        // surface-agnostic place to schedule the upsert is the shared
        // `task_upsert_ids` channel that every backend already flushes
        // via `flush_task_upserts` (issue).
        effects.task_upsert_ids.push(successor_id.to_string());
        effects.spawned_successors.push(UpdateTaskSpawnedSuccessor {
            successor_id: successor_id.to_string(),
            summary: spawned_summary.to_string(),
            after_task: successor,
        });
        effects
            .focus_rewire_audits
            .push(UpdateTaskFocusRewireAudit {
                parent_task_id: parent_task_id.to_string(),
                successor_id: successor_id.to_string(),
                focus_schedule_dates: plan
                    .rewired_focus_schedule_dates
                    .iter()
                    .map(|date| (*date).to_string())
                    .collect(),
                current_focus_dates: plan
                    .rewired_current_focus_dates
                    .iter()
                    .map(|date| (*date).to_string())
                    .collect(),
            });
    }
    for successor_id in plan.cancelled_successor_ids {
        let successor = crate::task_response::load_enriched_task_json(
            conn,
            &TaskId::from_trusted_str(successor_id),
        )?;
        // Same reasoning as the spawned case: the cancelled successor's
        // task row has had its status flipped and must be re-synced.
        // Routing through the shared `task_upsert_ids` channel keeps
        // every surface (MCP / Tauri / CLI / future) symmetric without
        // depending on `log_change`'s per-entity fallback.
        effects.task_upsert_ids.push(successor_id.to_string());
        effects
            .cancelled_successors
            .push(UpdateTaskCancelledSuccessor {
                successor_id: successor_id.to_string(),
                summary: cancelled_summary.to_string(),
                after_task: successor,
            });
    }
    Ok(())
}
