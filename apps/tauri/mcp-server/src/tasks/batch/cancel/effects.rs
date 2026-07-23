//! MCP-side implementation of [`BatchCancelFlushBackend`] for the
//! canonical batch-cancel workflow.
//!
//! The sequencing of the [`BatchCancelSyncEffects`] categories lives in
//! `lorvex_workflow::task_batch_cancel::flush_batch_cancel_with_backend`.
//! This module is the MCP backend that satisfies that trait by
//! translating each category into outbox enqueues + `ai_changelog` rows
//! via the MCP runtime's `change_tracking` primitives.
//!
//! The whole-operation `batch_cancel` audit row (with `before_states`
//! / `after_states` and the cancelled task ids) is written here outside
//! the sequencer — it consumes the surrounding [`BatchCancelInListResult`],
//! not the sync-effects bundle alone.

use crate::error::McpError;
use crate::runtime::change_tracking::{
    enqueue_deleted_task_dependency_syncs, enqueue_relation_sync, enqueue_task_reminder_syncs,
    enqueue_task_tag_edge_syncs, log_change, LogChangeParams,
};
use crate::tasks::dependencies::{sync_dep_affected_tasks, DepAffectedSnapshot};
use lorvex_domain::naming::{
    ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER, OP_UPSERT,
};
use lorvex_workflow::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};
use lorvex_workflow::task_batch_cancel::{
    flush_batch_cancel_with_backend, BatchCancelFlushBackend, BatchCancelInListResult,
    BatchCancelSyncEffects, MutationFlushBackend, SpawnedSuccessorLog,
};
use rusqlite::Connection;

/// MCP backend for [`BatchCancelFlushBackend`]. Holds the `mcp_tool`
/// label that goes into per-row `ai_changelog` entries.
pub(super) struct McpBatchCancelFlush {
    pub(super) mcp_tool: &'static str,
}

impl MutationFlushBackend<BatchCancelSyncEffects> for McpBatchCancelFlush {
    type Error = McpError;
}

impl BatchCancelFlushBackend for McpBatchCancelFlush {
    fn flush_cancelled_task_upserts(
        &self,
        _conn: &Connection,
        _task_ids: &[String],
    ) -> Result<(), Self::Error> {
        // MCP's whole-operation `batch_cancel` audit row carries the
        // full `entity_ids` list and runs through `log_change`'s default
        // sync path, so each cancelled task row is already enqueued by
        // the surrounding finalizer. Re-emitting here would produce a
        // duplicate coalesce-replace on the same outbox row.
        Ok(())
    }

    fn flush_cancelled_reminders(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        enqueue_task_reminder_syncs(conn, reminder_ids)
    }

    fn flush_deleted_dependency_edges(
        &self,
        conn: &Connection,
        edges: &[DeletedDependencyEdge],
    ) -> Result<(), Self::Error> {
        enqueue_deleted_task_dependency_syncs(conn, edges)?;
        Ok(())
    }

    fn flush_affected_dependents(
        &self,
        conn: &Connection,
        affected_ids: &[String],
    ) -> Result<(), Self::Error> {
        if affected_ids.is_empty() {
            return Ok(());
        }
        let snapshot = DepAffectedSnapshot::from_ids_only(affected_ids.to_vec());
        sync_dep_affected_tasks(conn, &snapshot, "cancelled tasks", self.mcp_tool)
    }

    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        successors: &[SpawnedSuccessorLog],
        tag_edges: &[CopiedTagEdge],
        checklist_item_ids: &[String],
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        for successor in successors {
            log_change(
                conn,
                LogChangeParams::new(
                    "create",
                    ENTITY_TASK,
                    self.mcp_tool,
                    successor.summary.clone(),
                )
                .with_entity_id(successor.successor_id.clone())
                .with_after(successor.after_task.clone()),
                None,
            )?;
        }
        enqueue_task_tag_edge_syncs(conn, tag_edges)?;
        for item_id in checklist_item_ids {
            enqueue_relation_sync(conn, ENTITY_TASK_CHECKLIST_ITEM, item_id, OP_UPSERT)?;
        }
        for reminder_id in reminder_ids {
            enqueue_relation_sync(conn, ENTITY_TASK_REMINDER, reminder_id, OP_UPSERT)?;
        }
        Ok(())
    }

    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        focus_schedule_dates: &[String],
        current_focus_dates: &[String],
    ) -> Result<(), Self::Error> {
        for date in focus_schedule_dates {
            enqueue_relation_sync(conn, ENTITY_FOCUS_SCHEDULE, date, OP_UPSERT)?;
        }
        for date in current_focus_dates {
            enqueue_relation_sync(conn, ENTITY_CURRENT_FOCUS, date, OP_UPSERT)?;
        }
        Ok(())
    }
}

/// Flush every cross-surface sync effect produced by a batch-cancel
/// workflow call, then write the whole-operation `batch_cancel` audit
/// row capturing the cancelled task ids + before/after snapshots.
///
/// Thin wrapper around `flush_batch_cancel_with_backend` with an
/// [`McpBatchCancelFlush`] backend, plus the trailing parent audit row
/// (which sits outside the sequencer because it consumes the surrounding
/// [`BatchCancelInListResult`] rather than the effects bundle alone).
pub(super) fn flush_batch_cancel_effects(
    conn: &Connection,
    result: &BatchCancelInListResult,
) -> Result<(), McpError> {
    let backend = McpBatchCancelFlush {
        mcp_tool: "batch_cancel_tasks_in_list",
    };
    flush_batch_cancel_with_backend(conn, &result.sync_effects, &backend)?;

    if let Some(summary) = &result.summary {
        log_change(
            conn,
            LogChangeParams::new(
                "batch_cancel",
                ENTITY_TASK,
                "batch_cancel_tasks_in_list",
                summary.clone(),
            )
            .with_entity_ids(
                result
                    .task_ids
                    .iter()
                    .map(|id| id.as_str().to_string())
                    .collect(),
            )
            .with_before(serde_json::json!({ "before_states": result.before_tasks }))
            .with_after(serde_json::json!({ "after_states": result.after_tasks })),
            None,
        )?;
    }
    Ok(())
}
