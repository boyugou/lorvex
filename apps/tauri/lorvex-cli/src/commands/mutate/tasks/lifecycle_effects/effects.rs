use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{
    ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER,
};
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_upsert};
use lorvex_workflow::lifecycle::{
    CancelLifecycleTransitionResult, CompletionLifecycleTransitionResult, LifecycleSyncPlan,
    LifecycleTransitionResult, ReopenLifecycleTransitionResult,
};
use rusqlite::Connection;

use super::dependencies;
use crate::commands::mutate::tags::effects as tags;

pub(super) fn flush_lifecycle_sync_plan_with_state(
    conn: &Connection,
    device_id: &str,
    plan: LifecycleSyncPlan<'_>,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    for reminder_id in plan.reopened_reminder_ids {
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK_REMINDER,
            reminder_id,
            hlc_state,
            device_id,
        )?;
    }
    for reminder_id in plan.status.cancelled_reminder_ids {
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK_REMINDER,
            reminder_id,
            hlc_state,
            device_id,
        )?;
    }
    dependencies::enqueue_deleted_dependency_edges(
        conn,
        hlc_state,
        device_id,
        plan.status.deleted_dependency_edges,
    )?;
    for affected_task_id in plan.status.affected_dependent_ids {
        enqueue_entity_upsert(conn, ENTITY_TASK, affected_task_id, hlc_state, device_id)?;
    }

    if let Some(successor_id) = plan.spawned_successor_id {
        enqueue_entity_upsert(conn, ENTITY_TASK, successor_id, hlc_state, device_id)?;
    }
    tags::enqueue_copied_tag_edges(conn, hlc_state, device_id, plan.spawned_successor_tag_edges)?;
    for item_id in plan.spawned_successor_checklist_item_ids {
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK_CHECKLIST_ITEM,
            item_id,
            hlc_state,
            device_id,
        )?;
    }
    for reminder_id in plan.spawned_successor_reminder_ids {
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK_REMINDER,
            reminder_id,
            hlc_state,
            device_id,
        )?;
    }

    for successor_id in plan.cancelled_successor_ids {
        enqueue_entity_upsert(conn, ENTITY_TASK, successor_id, hlc_state, device_id)?;
    }
    for reminder_id in plan.successor_cancel.cancelled_reminder_ids {
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK_REMINDER,
            reminder_id,
            hlc_state,
            device_id,
        )?;
    }
    dependencies::enqueue_deleted_dependency_edges(
        conn,
        hlc_state,
        device_id,
        plan.successor_cancel.deleted_dependency_edges,
    )?;
    for affected_task_id in plan.successor_cancel.affected_dependent_ids {
        enqueue_entity_upsert(conn, ENTITY_TASK, affected_task_id, hlc_state, device_id)?;
    }

    for date in plan.rewired_focus_schedule_dates {
        enqueue_aggregate_root_upsert_if_present_with_state(
            conn,
            device_id,
            ENTITY_FOCUS_SCHEDULE,
            date,
            hlc_state,
        )?;
    }
    for date in plan.rewired_current_focus_dates {
        enqueue_aggregate_root_upsert_if_present_with_state(
            conn,
            device_id,
            ENTITY_CURRENT_FOCUS,
            date,
            hlc_state,
        )?;
    }
    Ok(())
}

pub(super) fn flush_completion_effects_with_state(
    conn: &Connection,
    device_id: &str,
    result: &CompletionLifecycleTransitionResult,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    flush_lifecycle_sync_plan_with_state(
        conn,
        device_id,
        LifecycleSyncPlan::from_completion(result),
        hlc_state,
    )
}

pub(super) fn flush_cancel_effects_with_state(
    conn: &Connection,
    device_id: &str,
    result: &CancelLifecycleTransitionResult,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    flush_lifecycle_sync_plan_with_state(
        conn,
        device_id,
        LifecycleSyncPlan::from_cancel(result),
        hlc_state,
    )
}

#[allow(dead_code)] // generic status-change CLI wrapper retained for lifecycle flusher parity
pub(super) fn flush_status_change_effects_with_state(
    conn: &Connection,
    device_id: &str,
    result: &LifecycleTransitionResult,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    flush_lifecycle_sync_plan_with_state(
        conn,
        device_id,
        LifecycleSyncPlan::from_transition(result),
        hlc_state,
    )
}

pub(super) fn flush_reopen_effects_with_state(
    conn: &Connection,
    device_id: &str,
    result: &ReopenLifecycleTransitionResult,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    flush_lifecycle_sync_plan_with_state(
        conn,
        device_id,
        LifecycleSyncPlan::from_reopen(result),
        hlc_state,
    )
}

fn enqueue_aggregate_root_upsert_if_present_with_state(
    conn: &Connection,
    device_id: &str,
    entity_type: &'static str,
    entity_id: &str,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    let Some(payload) = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        entity_type,
        entity_id,
    )?
    else {
        return Ok(());
    };
    let version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        entity_type,
        entity_id,
        &payload,
        crate::commands::shared::bare_outbox_ctx(&version, device_id),
    )
    .map_err(|e| crate::error::CliError::Internal(format!("{entity_type} enqueue failed: {e}")))?;
    Ok(())
}
