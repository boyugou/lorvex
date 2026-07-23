//! Tauri-side implementation of [`TaskUpdateFlushBackend`] for the
//! canonical task-update workflow.
//!
//! The sequencing of the `TaskUpdateSyncEffects` categories lives in
//! [`lorvex_workflow::task_update::flush_with_backend`]. This module is
//! the Tauri backend that satisfies that trait by translating each
//! category into outbox enqueues via the Tauri sync helpers
//! (`enqueue_*` family).
//!
//! Differences from MCP's `McpTaskUpdateFlush`:
//!   * No `ai_changelog` writes — the Tauri surface intentionally never
//!     authors audit rows (Core Design Rule 2). The `*_successor` and
//!     `flush_focus_rewires` audit-log branches that MCP runs become
//!     pure entity-bump enqueues on this side.
//!   * No undo bookkeeping — the outer `update_task_inner_with_conn`
//!     boundary builds the undo token from the pre-mutation snapshot;
//!     outbox rows enqueued here are immediately dispatchable.

use rusqlite::{params, Connection};

use lorvex_domain::naming::{
    EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_TAG, OP_DELETE, OP_UPSERT,
};
use lorvex_workflow::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};
use lorvex_workflow::task_update::{
    MutationFlushBackend, TaskTagEdgeDelete, TaskUpdateFlushBackend, TaskUpdateSyncEffects,
    UpdateTaskCancelledSuccessor, UpdateTaskFocusRewireAudit, UpdateTaskSpawnedSuccessor,
};

use crate::commands::{
    enqueue_current_focus_upsert_for_date, enqueue_dependency_edge_upsert,
    enqueue_focus_schedule_upsert_for_date, enqueue_task_reminder_upsert, enqueue_task_upsert,
    enqueue_to_outbox_typed, fetch_task_by_id,
};
use crate::error::{AppError, AppResult};

/// Tauri backend for [`TaskUpdateFlushBackend`].
///
/// `executor_handled_ids` lists primary task ids whose upsert envelope
/// is already scheduled by the surrounding writer (currently always
/// empty for Tauri because the IPC executor does not auto-enqueue
/// entity rows — the finalizer does). Kept as a slice for parity with
/// `McpTaskUpdateFlush` and to leave the future `execute_ipc_entity_mutation`
/// migration room.
pub(super) struct IpcTaskUpdateFlush<'a> {
    pub(super) executor_handled_ids: &'a [String],
}

impl<'a> MutationFlushBackend<TaskUpdateSyncEffects> for IpcTaskUpdateFlush<'a> {
    type Error = AppError;
}

impl<'a> TaskUpdateFlushBackend for IpcTaskUpdateFlush<'a> {
    fn flush_tag_effects(
        &self,
        conn: &Connection,
        tag_upsert_ids: &[String],
        edge_upsert_ids: &[String],
        edge_deletes: &[TaskTagEdgeDelete],
    ) -> Result<(), Self::Error> {
        for tag_id in tag_upsert_ids {
            enqueue_tag_upsert_by_id(conn, tag_id)?;
        }
        for composite in edge_upsert_ids {
            enqueue_task_tag_edge_upsert(conn, composite)?;
        }
        for edge in edge_deletes {
            let task_id = lorvex_domain::TaskId::from_trusted_str(&edge.task_id);
            let tag_id = lorvex_domain::TagId::from_trusted_str(&edge.tag_id);
            let payload = lorvex_store::payload_loaders::task_tag_payload(
                &task_id,
                &tag_id,
                &edge.version,
                &edge.created_at,
            );
            let entity_id = lorvex_domain::TaskTagEdgeId::new(&task_id, &tag_id);
            enqueue_to_outbox_typed(conn, EDGE_TASK_TAG, entity_id.as_str(), OP_DELETE, &payload)?;
        }
        Ok(())
    }

    fn flush_dependency_edges(
        &self,
        conn: &Connection,
        edge_upsert_ids: &[String],
        edge_deletes: &[DeletedDependencyEdge],
    ) -> Result<(), Self::Error> {
        for composite in edge_upsert_ids {
            enqueue_dependency_edge_upsert(conn, composite)?;
        }
        for edge in edge_deletes {
            let task_id = lorvex_domain::TaskId::from_trusted_str(&edge.task_id);
            let depends_on_task_id =
                lorvex_domain::TaskId::from_trusted_str(&edge.depends_on_task_id);
            let payload = lorvex_store::payload_loaders::task_dependency_payload(
                &task_id,
                &depends_on_task_id,
                &edge.version,
                &edge.created_at,
            );
            let entity_id = lorvex_domain::TaskDependencyEdgeId::new(&task_id, &depends_on_task_id);
            enqueue_to_outbox_typed(
                conn,
                EDGE_TASK_DEPENDENCY,
                entity_id.as_str(),
                OP_DELETE,
                &payload,
            )?;
        }
        Ok(())
    }

    fn flush_reminder_upserts(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        for reminder_id in reminder_ids {
            enqueue_task_reminder_upsert(conn, reminder_id)?;
        }
        Ok(())
    }

    fn flush_task_upserts(
        &self,
        conn: &Connection,
        task_ids: &[String],
    ) -> Result<(), Self::Error> {
        for task_id in task_ids {
            if self.executor_handled_ids.iter().any(|id| id == task_id) {
                continue;
            }
            let task = fetch_task_by_id(conn, task_id)?;
            enqueue_task_upsert(conn, &task)?;
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
        let dep_tasks = crate::commands::fetch_ordered_tasks_by_ids(
            conn,
            affected_ids,
            "IpcTaskUpdateFlush::flush_affected_dependents",
        )?;
        for dep in &dep_tasks {
            enqueue_task_upsert(conn, dep)?;
        }
        Ok(())
    }

    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        _successors: &[UpdateTaskSpawnedSuccessor],
        tag_edges: &[CopiedTagEdge],
        checklist_item_ids: &[String],
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        // Successor task rows are covered by `flush_task_upserts`
        // (the workflow pushes each spawned successor id into
        // `effects.task_upsert_ids`). Here we only emit the inherited
        // child entities and edges, plus skip the audit-row writes that
        // MCP would emit — Tauri does not author `ai_changelog`.
        for te in tag_edges {
            let entity_id = lorvex_domain::TaskTagEdgeId::new(
                &lorvex_domain::TaskId::from_trusted_str(&te.task_id),
                &lorvex_domain::TagId::from_trusted_str(&te.tag_id),
            );
            let payload = serde_json::json!({
                "task_id": te.task_id,
                "tag_id": te.tag_id,
                "version": te.version,
                "created_at": te.created_at,
            });
            enqueue_to_outbox_typed(conn, EDGE_TASK_TAG, entity_id.as_str(), OP_UPSERT, &payload)?;
        }
        for item_id in checklist_item_ids {
            crate::commands::enqueue_task_checklist_item_upsert(conn, item_id)?;
        }
        for reminder_id in reminder_ids {
            enqueue_task_reminder_upsert(conn, reminder_id)?;
        }
        Ok(())
    }

    fn flush_cancelled_successors(
        &self,
        _conn: &Connection,
        _successors: &[UpdateTaskCancelledSuccessor],
    ) -> Result<(), Self::Error> {
        // Cancelled successor task rows are covered by `flush_task_upserts`
        // (their ids are in `effects.task_upsert_ids`). The MCP backend
        // also writes a `cancel` audit row per successor; the Tauri
        // surface intentionally skips audit rows.
        Ok(())
    }

    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        rewired_focus_schedule_dates: &[String],
        rewired_current_focus_dates: &[String],
        _audits: &[UpdateTaskFocusRewireAudit],
    ) -> Result<(), Self::Error> {
        for date in rewired_focus_schedule_dates {
            enqueue_focus_schedule_upsert_for_date(conn, date)?;
        }
        for date in rewired_current_focus_dates {
            enqueue_current_focus_upsert_for_date(conn, date)?;
        }
        // MCP writes per-rewire audit rows under `recurrence_rewire`;
        // Tauri skips audit rows by design.
        Ok(())
    }
}

/// Enqueue a `tag` row sync upsert by id. Loads the canonical payload
/// from the shared `payload_loaders::load_tag_sync_payload` helper.
fn enqueue_tag_upsert_by_id(conn: &Connection, tag_id: &str) -> AppResult<()> {
    let typed = lorvex_domain::TagId::from_trusted(tag_id.to_string());
    let payload = lorvex_store::payload_loaders::load_tag_sync_payload(conn, &typed)
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("tag '{tag_id}' not found for sync snapshot")))?;
    enqueue_to_outbox_typed(conn, ENTITY_TAG, tag_id, OP_UPSERT, &payload)
}

/// Enqueue a `task_tag` edge upsert from a composite `task_id:tag_id`
/// entity id. The row is loaded fresh from the join table so the
/// payload's `version` and `created_at` reflect the value the workflow
/// just wrote.
fn enqueue_task_tag_edge_upsert(conn: &Connection, composite: &str) -> AppResult<()> {
    let (task_id, tag_id) = lorvex_domain::TaskTagEdgeId::try_parse(composite)
        .map_err(|err| AppError::Internal(err.to_string()))?;
    let payload =
        lorvex_store::payload_loaders::load_task_tag_sync_payload(conn, &task_id, &tag_id)
            .map_err(AppError::from)?
            .ok_or_else(|| {
                AppError::NotFound(format!(
                    "task_tag edge '{composite}' not found for sync snapshot"
                ))
            })?;
    enqueue_to_outbox_typed(conn, EDGE_TASK_TAG, composite, OP_UPSERT, &payload)
}
