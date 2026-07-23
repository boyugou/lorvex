use crate::error::McpError;
use crate::runtime::change_tracking::{enqueue_relation_sync, log_change, LogChangeParams};
use lorvex_domain::naming::{
    EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TAG,
    ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER, OP_UPSERT,
};
use rusqlite::Connection;

pub(super) fn flush_create_effects(
    conn: &Connection,
    result: &lorvex_workflow::task_create::CreateTaskResult,
) -> Result<(), McpError> {
    for tag_id in &result.sync_effects.tag_upsert_ids {
        enqueue_relation_sync(conn, ENTITY_TAG, tag_id, OP_UPSERT)?;
    }
    for edge_id in &result.sync_effects.task_tag_edge_upsert_ids {
        enqueue_relation_sync(conn, EDGE_TASK_TAG, edge_id, OP_UPSERT)?;
    }
    for edge_id in &result.sync_effects.dependency_edge_upsert_ids {
        enqueue_relation_sync(conn, EDGE_TASK_DEPENDENCY, edge_id, OP_UPSERT)?;
    }
    crate::runtime::change_tracking::enqueue_task_reminder_syncs(
        conn,
        &result.sync_effects.reminder_upsert_ids,
    )?;
    crate::runtime::change_tracking::enqueue_task_reminder_syncs(
        conn,
        &result.sync_effects.cancelled_reminder_ids,
    )?;
    for successor in &result.sync_effects.spawned_successors {
        log_change(
            conn,
            LogChangeParams::new(
                "create",
                ENTITY_TASK,
                "create_task",
                successor.summary.clone(),
            )
            .with_entity_id(successor.successor_id.clone())
            .with_after(successor.after_task.clone()),
            None,
        )?;
    }
    crate::runtime::change_tracking::enqueue_task_tag_edge_syncs(
        conn,
        &result.sync_effects.spawned_successor_tag_edges,
    )?;
    for item_id in &result.sync_effects.spawned_successor_checklist_item_ids {
        enqueue_relation_sync(conn, ENTITY_TASK_CHECKLIST_ITEM, item_id, OP_UPSERT)?;
    }
    for reminder_id in &result.sync_effects.spawned_successor_reminder_ids {
        enqueue_relation_sync(conn, ENTITY_TASK_REMINDER, reminder_id, OP_UPSERT)?;
    }
    for date in &result.sync_effects.rewired_focus_schedule_dates {
        enqueue_relation_sync(conn, ENTITY_FOCUS_SCHEDULE, date, OP_UPSERT)?;
    }
    for date in &result.sync_effects.rewired_current_focus_dates {
        enqueue_relation_sync(conn, ENTITY_CURRENT_FOCUS, date, OP_UPSERT)?;
    }
    for audit in &result.sync_effects.focus_rewire_audits {
        for date in &audit.focus_schedule_dates {
            let summary = format!(
                "Rewired focus schedule {date} references from pre-completed recurring task {} to successor {}",
                audit.parent_task_id, audit.successor_id
            );
            log_change(
                conn,
                LogChangeParams::new(
                    "recurrence_rewire",
                    ENTITY_FOCUS_SCHEDULE,
                    "create_task",
                    summary,
                )
                .with_entity_id(date.clone())
                .skip_sync(),
                None,
            )?;
        }
        for date in &audit.current_focus_dates {
            let summary = format!(
                "Rewired current focus {date} references from pre-completed recurring task {} to successor {}",
                audit.parent_task_id, audit.successor_id
            );
            log_change(
                conn,
                LogChangeParams::new(
                    "recurrence_rewire",
                    ENTITY_CURRENT_FOCUS,
                    "create_task",
                    summary,
                )
                .with_entity_id(date.clone())
                .skip_sync(),
                None,
            )?;
        }
    }
    Ok(())
}
