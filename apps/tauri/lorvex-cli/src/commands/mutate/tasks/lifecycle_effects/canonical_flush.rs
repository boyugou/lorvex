//! CLI-side implementation of [`TaskUpdateFlushBackend`].
//!
//! Translates each `TaskUpdateSyncEffects` category into the CLI's
//! outbox enqueues + `ai_changelog` rows. The MCP and Tauri backends
//! live at `mcp-server/src/tasks/update_sync.rs` and
//! `app/src-tauri/src/commands/tasks/updates/flush.rs`; their ordering
//! rules are owned by the canonical sequencer
//! [`lorvex_workflow::task_update::flush_with_backend`] so all three
//! surfaces emit byte-identical sync envelopes for the same patch.
//!
//! Differences from the Tauri impl:
//!   * Audit rows for spawned and cancelled recurrence successors are
//!     written here. The CLI surface owns `ai_changelog` writes
//!     (Core Design Rule 2 applies to MCP-originated rows; the CLI
//!     mirrors MCP for symmetry); Tauri intentionally skips them.
//!   * No focus-rewire audit rows. MCP writes per-rewire `recurrence_rewire`
//!     entries; the CLI follows the existing lifecycle-effect convention
//!     of bumping the aggregate root entity without an audit row.

use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{
    EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TAG,
    ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use lorvex_sync::outbox_enqueue::{
    enqueue_entity_upsert, enqueue_payload_delete, enqueue_payload_upsert,
};
use lorvex_workflow::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};
use lorvex_workflow::task_update::{
    MutationFlushBackend, TaskTagEdgeDelete, TaskUpdateFlushBackend, TaskUpdateSyncEffects,
    UpdateTaskCancelledSuccessor, UpdateTaskFocusRewireAudit, UpdateTaskSpawnedSuccessor,
};
use rusqlite::params;
use rusqlite::Connection;
use std::cell::RefCell;

use crate::commands::mutate::tags::effects as tags;
use crate::commands::mutate::tasks::dependencies;
use crate::commands::shared::{bare_outbox_ctx, log_cli_changelog_with_state, CliChangelogParams};

/// CLI backend for [`TaskUpdateFlushBackend`].
///
/// `executor_handled_ids` lists primary task ids whose upsert envelope
/// is already scheduled by the surrounding writer (currently always
/// the keyed task id, enqueued by the `update_task_with_conn`
/// finalizer). Held in a slice so the canonical effects' duplicate
/// `task_upsert_ids` for the same row don't double-enqueue.
///
/// `hlc_state` is borrowed mutably across every flush call so the
/// changelog rows and outbox envelopes share the same HLC counter run
/// as the surrounding mutation.
pub(super) struct CliTaskUpdateFlush<'a> {
    pub(super) device_id: &'a str,
    pub(super) executor_handled_ids: &'a [String],
    pub(super) hlc_state: RefCell<&'a mut HlcState>,
}

impl<'a> CliTaskUpdateFlush<'a> {
    pub(super) const fn new(
        device_id: &'a str,
        executor_handled_ids: &'a [String],
        hlc_state: &'a mut HlcState,
    ) -> Self {
        Self {
            device_id,
            executor_handled_ids,
            hlc_state: RefCell::new(hlc_state),
        }
    }
}

impl<'a> MutationFlushBackend<TaskUpdateSyncEffects> for CliTaskUpdateFlush<'a> {
    type Error = crate::error::CliError;
}

impl<'a> TaskUpdateFlushBackend for CliTaskUpdateFlush<'a> {
    fn flush_tag_effects(
        &self,
        conn: &Connection,
        tag_upsert_ids: &[String],
        edge_upsert_ids: &[String],
        edge_deletes: &[TaskTagEdgeDelete],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        for tag_id in tag_upsert_ids {
            enqueue_entity_upsert(conn, ENTITY_TAG, tag_id, *state, self.device_id)?;
        }
        for composite in edge_upsert_ids {
            let (task_id, tag_id) = lorvex_domain::TaskTagEdgeId::try_parse(composite)
                .map_err(|err| crate::error::CliError::Internal(err.to_string()))?;
            let payload =
                lorvex_store::payload_loaders::load_task_tag_sync_payload(conn, &task_id, &tag_id)?
                    .ok_or_else(|| {
                        crate::error::CliError::Internal(format!(
                            "task_tag edge '{composite}' not found for sync snapshot"
                        ))
                    })?;
            let version = state.generate().to_string();
            enqueue_payload_upsert(
                conn,
                EDGE_TASK_TAG,
                composite,
                &payload,
                bare_outbox_ctx(&version, self.device_id),
            )?;
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
            let version = state.generate().to_string();
            enqueue_payload_delete(
                conn,
                EDGE_TASK_TAG,
                entity_id.as_str(),
                &payload,
                bare_outbox_ctx(&version, self.device_id),
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
        let mut state = self.hlc_state.borrow_mut();
        for composite in edge_upsert_ids {
            let (task_id, depends_on_task_id) =
                lorvex_domain::TaskDependencyEdgeId::try_parse(composite)
                    .map_err(|err| crate::error::CliError::Internal(err.to_string()))?;
            let (version_row, created_at): (String, String) = conn
                .query_row(
                    "SELECT version, created_at FROM task_dependencies \
                     WHERE task_id = ?1 AND depends_on_task_id = ?2",
                    params![task_id.as_str(), depends_on_task_id.as_str()],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .map_err(|err| match err {
                    rusqlite::Error::QueryReturnedNoRows => crate::error::CliError::Internal(
                        format!("task_dependency edge '{composite}' not found for sync snapshot"),
                    ),
                    other => crate::error::CliError::from(lorvex_store::StoreError::from(other)),
                })?;
            let payload = lorvex_store::payload_loaders::task_dependency_payload(
                &task_id,
                &depends_on_task_id,
                &version_row,
                &created_at,
            );
            let envelope_version = state.generate().to_string();
            enqueue_payload_upsert(
                conn,
                EDGE_TASK_DEPENDENCY,
                composite,
                &payload,
                bare_outbox_ctx(&envelope_version, self.device_id),
            )?;
        }
        dependencies::enqueue_deleted_dependency_edges(conn, *state, self.device_id, edge_deletes)?;
        Ok(())
    }

    fn flush_reminder_upserts(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        for reminder_id in reminder_ids {
            enqueue_entity_upsert(
                conn,
                ENTITY_TASK_REMINDER,
                reminder_id,
                *state,
                self.device_id,
            )?;
        }
        Ok(())
    }

    fn flush_task_upserts(
        &self,
        conn: &Connection,
        task_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        for task_id in task_ids {
            if self.executor_handled_ids.iter().any(|id| id == task_id) {
                continue;
            }
            enqueue_entity_upsert(conn, ENTITY_TASK, task_id, *state, self.device_id)?;
        }
        Ok(())
    }

    fn flush_affected_dependents(
        &self,
        conn: &Connection,
        affected_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        for task_id in affected_ids {
            enqueue_entity_upsert(conn, ENTITY_TASK, task_id, *state, self.device_id)?;
        }
        Ok(())
    }

    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        successors: &[UpdateTaskSpawnedSuccessor],
        tag_edges: &[CopiedTagEdge],
        checklist_item_ids: &[String],
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        // Successor task rows are also pushed onto `task_upsert_ids` by
        // the workflow; `flush_task_upserts` will skip the
        // `executor_handled_ids` ones. The per-successor audit row is
        // CLI-side (mirrors MCP); Tauri skips audits by design.
        for successor in successors {
            log_cli_changelog_with_state(
                conn,
                *state,
                CliChangelogParams {
                    operation: "create",
                    entity_type: ENTITY_TASK,
                    entity_id: &successor.successor_id,
                    summary: &successor.summary,
                    before_json: None,
                    after_json: Some(successor.after_task.clone()),
                },
            )?;
        }
        tags::enqueue_copied_tag_edges(conn, *state, self.device_id, tag_edges)?;
        for item_id in checklist_item_ids {
            enqueue_entity_upsert(
                conn,
                ENTITY_TASK_CHECKLIST_ITEM,
                item_id,
                *state,
                self.device_id,
            )?;
        }
        for reminder_id in reminder_ids {
            enqueue_entity_upsert(
                conn,
                ENTITY_TASK_REMINDER,
                reminder_id,
                *state,
                self.device_id,
            )?;
        }
        Ok(())
    }

    fn flush_cancelled_successors(
        &self,
        conn: &Connection,
        successors: &[UpdateTaskCancelledSuccessor],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        for successor in successors {
            log_cli_changelog_with_state(
                conn,
                *state,
                CliChangelogParams {
                    operation: "cancel",
                    entity_type: ENTITY_TASK,
                    entity_id: &successor.successor_id,
                    summary: &successor.summary,
                    before_json: None,
                    after_json: Some(successor.after_task.clone()),
                },
            )?;
        }
        Ok(())
    }

    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        rewired_focus_schedule_dates: &[String],
        rewired_current_focus_dates: &[String],
        _audits: &[UpdateTaskFocusRewireAudit],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        for date in rewired_focus_schedule_dates {
            crate::commands::shared::effects::enqueue_aggregate_root_upsert(
                conn,
                *state,
                self.device_id,
                ENTITY_FOCUS_SCHEDULE,
                date,
            )?;
        }
        for date in rewired_current_focus_dates {
            crate::commands::shared::effects::enqueue_aggregate_root_upsert(
                conn,
                *state,
                self.device_id,
                ENTITY_CURRENT_FOCUS,
                date,
            )?;
        }
        // MCP writes per-rewire `recurrence_rewire` audit rows; the CLI
        // mirrors the existing lifecycle-effect convention of bumping
        // the aggregate root entity without an audit row.
        Ok(())
    }
}
