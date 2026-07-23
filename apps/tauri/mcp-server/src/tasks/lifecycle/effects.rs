use lorvex_domain::naming::{
    ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER, OP_UPSERT,
};
use lorvex_workflow::lifecycle::LifecycleSyncPlan;
use rusqlite::Connection;
use serde_json::Value;

use crate::error::McpError;
use crate::runtime::change_tracking::{
    enqueue_deleted_task_dependency_syncs, enqueue_relation_sync, enqueue_task_reminder_syncs,
    enqueue_task_tag_edge_syncs, log_change, LogChangeParams,
};

pub(crate) struct LifecycleSyncLogContext {
    pub(crate) mcp_tool: &'static str,
    pub(crate) spawned_successor_summary: Option<String>,
    pub(crate) cancelled_successor_summary: Option<String>,
    pub(crate) affected_dependent_reason: String,
    pub(crate) successor_affected_reason: String,
    pub(crate) rewire_parent_task_id: Option<String>,
    pub(crate) rewire_parent_description: &'static str,
}

pub(crate) fn flush_sync_plan(
    conn: &Connection,
    plan: LifecycleSyncPlan<'_>,
    context: LifecycleSyncLogContext,
) -> Result<Option<Value>, McpError> {
    enqueue_task_reminder_syncs(conn, plan.reopened_reminder_ids)?;
    enqueue_task_reminder_syncs(conn, plan.status.cancelled_reminder_ids)?;
    enqueue_deleted_task_dependency_syncs(conn, plan.status.deleted_dependency_edges)?;
    if !plan.status.affected_dependent_ids.is_empty() {
        let snapshot = crate::tasks::dependencies::DepAffectedSnapshot::from_ids_only(
            plan.status.affected_dependent_ids.to_vec(),
        );
        crate::tasks::dependencies::sync_dep_affected_tasks(
            conn,
            &snapshot,
            &context.affected_dependent_reason,
            context.mcp_tool,
        )?;
    }

    let spawned_successor = if let Some(successor_id) = plan.spawned_successor_id {
        let successor_json = crate::system::handler_support::reload_task_json(
            conn,
            successor_id,
            "spawned successor",
        )?;
        if let Some(summary) = context.spawned_successor_summary.as_deref() {
            log_change(
                conn,
                LogChangeParams::new("create", ENTITY_TASK, context.mcp_tool, summary.to_string())
                    .with_entity_id(successor_id.to_string())
                    .with_after(successor_json),
                None,
            )?;
            Some(crate::system::handler_support::reload_task_json(
                conn,
                successor_id,
                "spawned successor",
            )?)
        } else {
            Some(successor_json)
        }
    } else {
        None
    };

    enqueue_task_tag_edge_syncs(conn, plan.spawned_successor_tag_edges)?;
    for item_id in plan.spawned_successor_checklist_item_ids {
        enqueue_relation_sync(conn, ENTITY_TASK_CHECKLIST_ITEM, item_id, OP_UPSERT)?;
    }
    for reminder_id in plan.spawned_successor_reminder_ids {
        enqueue_relation_sync(conn, ENTITY_TASK_REMINDER, reminder_id, OP_UPSERT)?;
    }

    for successor_id in plan.cancelled_successor_ids {
        if let Some(summary) = context.cancelled_successor_summary.as_deref() {
            let successor_after = crate::system::handler_support::reload_task_json(
                conn,
                successor_id,
                "cancelled successor (post)",
            )?;
            log_change(
                conn,
                LogChangeParams::new("cancel", ENTITY_TASK, context.mcp_tool, summary.to_string())
                    .with_entity_id(successor_id.to_string())
                    .with_after(successor_after),
                None,
            )?;
        }
    }

    enqueue_task_reminder_syncs(conn, plan.successor_cancel.cancelled_reminder_ids)?;
    enqueue_deleted_task_dependency_syncs(conn, plan.successor_cancel.deleted_dependency_edges)?;
    if !plan.successor_cancel.affected_dependent_ids.is_empty() {
        let snapshot = crate::tasks::dependencies::DepAffectedSnapshot::from_ids_only(
            plan.successor_cancel.affected_dependent_ids.to_vec(),
        );
        crate::tasks::dependencies::sync_dep_affected_tasks(
            conn,
            &snapshot,
            &context.successor_affected_reason,
            context.mcp_tool,
        )?;
    }

    for date in plan.rewired_focus_schedule_dates {
        enqueue_relation_sync(conn, ENTITY_FOCUS_SCHEDULE, date, OP_UPSERT)?;
    }
    for date in plan.rewired_current_focus_dates {
        enqueue_relation_sync(conn, ENTITY_CURRENT_FOCUS, date, OP_UPSERT)?;
    }
    log_focus_rewire_audit_rows(conn, plan, &context)?;

    Ok(spawned_successor)
}

fn log_focus_rewire_audit_rows(
    conn: &Connection,
    plan: LifecycleSyncPlan<'_>,
    context: &LifecycleSyncLogContext,
) -> Result<(), McpError> {
    let (Some(parent_id), Some(successor_id)) = (
        context.rewire_parent_task_id.as_deref(),
        plan.spawned_successor_id,
    ) else {
        return Ok(());
    };

    for date in plan.rewired_focus_schedule_dates {
        let summary = format!(
            "Rewired focus schedule {date} references from {} {parent_id} to successor {successor_id}",
            context.rewire_parent_description
        );
        log_change(
            conn,
            LogChangeParams::new(
                "recurrence_rewire",
                ENTITY_FOCUS_SCHEDULE,
                context.mcp_tool,
                summary,
            )
            .with_entity_id(date.to_string())
            .skip_sync(),
            None,
        )?;
    }
    for date in plan.rewired_current_focus_dates {
        let summary = format!(
            "Rewired current focus {date} references from {} {parent_id} to successor {successor_id}",
            context.rewire_parent_description
        );
        log_change(
            conn,
            LogChangeParams::new(
                "recurrence_rewire",
                ENTITY_CURRENT_FOCUS,
                context.mcp_tool,
                summary,
            )
            .with_entity_id(date.to_string())
            .skip_sync(),
            None,
        )?;
    }
    Ok(())
}
