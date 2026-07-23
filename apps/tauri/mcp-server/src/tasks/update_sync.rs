//! MCP-side implementation of [`TaskUpdateFlushBackend`] for the
//! canonical task-update workflow.
//!
//! The sequencing of the 17 `TaskUpdateSyncEffects` categories lives in
//! `lorvex_workflow::task_update::flush_with_backend`. This module is
//! the MCP backend that satisfies that trait by translating each
//! category into outbox enqueues + `ai_changelog` rows via the
//! MCP runtime's `change_tracking` primitives.
//!
//! Two thin shims preserve the historical call sites:
//! [`flush_task_update_effects`] (single + batch shared) and
//! [`flush_batch_update_effects`] (re-exported through
//! `tasks::batch::update::effects`). Both build an
//! [`McpTaskUpdateFlush`] and hand it to the workflow sequencer.

use crate::error::McpError;
use crate::runtime::change_tracking::{
    enqueue_deleted_task_dependency_syncs, enqueue_relation_sync,
    enqueue_relation_sync_with_snapshot, enqueue_task_reminder_syncs, enqueue_task_tag_edge_syncs,
    log_change, LogChangeParams,
};
use crate::tasks::dependencies::{sync_dep_affected_tasks, DepAffectedSnapshot};
use lorvex_domain::naming::{
    EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TAG,
    ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER, OP_DELETE, OP_UPSERT,
};
use lorvex_domain::{TagId, TaskId};
use lorvex_workflow::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};
use lorvex_workflow::task_update::{
    flush_with_backend, MutationFlushBackend, TaskTagEdgeDelete, TaskUpdateFlushBackend,
    TaskUpdateSyncEffects, UpdateTaskCancelledSuccessor, UpdateTaskFocusRewireAudit,
    UpdateTaskSpawnedSuccessor,
};
use rusqlite::Connection;

/// MCP backend for [`TaskUpdateFlushBackend`]. Holds the per-call
/// context the trait methods need but the workflow layer cannot supply:
/// the list of task ids already covered by the surrounding mutation
/// executor's own audit + sync envelope, and the `mcp_tool` label that
/// goes into per-row `ai_changelog` entries.
pub(crate) struct McpTaskUpdateFlush<'a> {
    pub(crate) executor_handled_ids: &'a [String],
    pub(crate) mcp_tool: &'static str,
}

impl<'a> MutationFlushBackend<TaskUpdateSyncEffects> for McpTaskUpdateFlush<'a> {
    type Error = McpError;
}

impl<'a> TaskUpdateFlushBackend for McpTaskUpdateFlush<'a> {
    fn flush_tag_effects(
        &self,
        conn: &Connection,
        tag_upsert_ids: &[String],
        edge_upsert_ids: &[String],
        edge_deletes: &[TaskTagEdgeDelete],
    ) -> Result<(), Self::Error> {
        for tag_id in tag_upsert_ids {
            enqueue_relation_sync(conn, ENTITY_TAG, tag_id, OP_UPSERT)?;
        }
        for edge_id in edge_upsert_ids {
            enqueue_relation_sync(conn, EDGE_TASK_TAG, edge_id, OP_UPSERT)?;
        }
        for edge in edge_deletes {
            let task_id = TaskId::from_trusted(edge.task_id.clone());
            let tag_id = TagId::from_trusted(edge.tag_id.clone());
            let snapshot = lorvex_store::payload_loaders::task_tag_payload(
                &task_id,
                &tag_id,
                &edge.version,
                &edge.created_at,
            );
            enqueue_relation_sync_with_snapshot(
                conn,
                EDGE_TASK_TAG,
                &format!("{}:{}", edge.task_id, edge.tag_id),
                OP_DELETE,
                Some(snapshot),
            )?;
        }
        Ok(())
    }

    fn flush_dependency_edges(
        &self,
        conn: &Connection,
        edge_upsert_ids: &[String],
        edge_deletes: &[DeletedDependencyEdge],
    ) -> Result<(), Self::Error> {
        for edge_id in edge_upsert_ids {
            enqueue_relation_sync(conn, EDGE_TASK_DEPENDENCY, edge_id, OP_UPSERT)?;
        }
        enqueue_deleted_task_dependency_syncs(conn, edge_deletes)?;
        Ok(())
    }

    fn flush_reminder_upserts(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        enqueue_task_reminder_syncs(conn, reminder_ids)
    }

    fn flush_task_upserts(
        &self,
        conn: &Connection,
        task_ids: &[String],
    ) -> Result<(), Self::Error> {
        for task_id in task_ids {
            if !self.executor_handled_ids.iter().any(|id| id == task_id) {
                enqueue_relation_sync(conn, ENTITY_TASK, task_id, OP_UPSERT)?;
            }
        }
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
        sync_dep_affected_tasks(conn, &snapshot, "task", self.mcp_tool)
    }

    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        successors: &[UpdateTaskSpawnedSuccessor],
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
                .with_after(successor.after_task.clone())
                // The successor task row is already enqueued for sync
                // by `flush_task_upserts` (the workflow pushes each
                // spawned successor id into `task_upsert_ids` so every
                // surface — MCP, Tauri, CLI — flushes it identically;
                // see issue #4473). Skip the per-entity sync that
                // `log_change` would otherwise fire to avoid a
                // redundant coalesce-replace on the same outbox row.
                .skip_sync(),
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

    fn flush_cancelled_successors(
        &self,
        conn: &Connection,
        successors: &[UpdateTaskCancelledSuccessor],
    ) -> Result<(), Self::Error> {
        for successor in successors {
            log_change(
                conn,
                LogChangeParams::new(
                    "cancel",
                    ENTITY_TASK,
                    self.mcp_tool,
                    successor.summary.clone(),
                )
                .with_entity_id(successor.successor_id.clone())
                .with_after(successor.after_task.clone())
                // Cancelled successor's task row is already enqueued
                // for sync by `flush_task_upserts`; see the parallel
                // note in `flush_spawned_successors` and issue #4473.
                .skip_sync(),
                None,
            )?;
        }
        Ok(())
    }

    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        rewired_focus_schedule_dates: &[String],
        rewired_current_focus_dates: &[String],
        audits: &[UpdateTaskFocusRewireAudit],
    ) -> Result<(), Self::Error> {
        for date in rewired_focus_schedule_dates {
            enqueue_relation_sync(conn, ENTITY_FOCUS_SCHEDULE, date, OP_UPSERT)?;
        }
        for date in rewired_current_focus_dates {
            enqueue_relation_sync(conn, ENTITY_CURRENT_FOCUS, date, OP_UPSERT)?;
        }
        for audit in audits {
            for date in &audit.focus_schedule_dates {
                let summary = format!(
                    "Rewired focus schedule {date} references from updated recurring task {} to successor {}",
                    audit.parent_task_id, audit.successor_id
                );
                log_change(
                    conn,
                    LogChangeParams::new(
                        "recurrence_rewire",
                        ENTITY_FOCUS_SCHEDULE,
                        self.mcp_tool,
                        summary,
                    )
                    .with_entity_id(date.clone())
                    .skip_sync(),
                    None,
                )?;
            }
            for date in &audit.current_focus_dates {
                let summary = format!(
                    "Rewired current focus {date} references from updated recurring task {} to successor {}",
                    audit.parent_task_id, audit.successor_id
                );
                log_change(
                    conn,
                    LogChangeParams::new(
                        "recurrence_rewire",
                        ENTITY_CURRENT_FOCUS,
                        self.mcp_tool,
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
}

/// Flush every cross-surface sync effect produced by a task-update
/// workflow call. `executor_handled_ids` lists primary task ids whose
/// upsert is already covered by the executor's own audit + sync path
/// (the row this mutation is keyed on); other entries in
/// `effects.task_upsert_ids` are siblings (re-stamped during a status
/// transition, dependency-affected rows, etc.) that need their own
/// outbox entry.
///
/// Thin wrapper around `lorvex_workflow::task_update::flush_with_backend`
/// with an [`McpTaskUpdateFlush`] backend.
pub(crate) fn flush_task_update_effects(
    conn: &Connection,
    effects: &TaskUpdateSyncEffects,
    executor_handled_ids: &[String],
    mcp_tool: &'static str,
) -> Result<(), McpError> {
    let backend = McpTaskUpdateFlush {
        executor_handled_ids,
        mcp_tool,
    };
    flush_with_backend(conn, effects, &backend)
}
