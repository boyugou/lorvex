//! CLI-side implementation of [`BatchCancelFlushBackend`].
//!
//! Translates each `BatchCancelSyncEffects` category into the CLI's
//! outbox enqueues + `ai_changelog` rows. The MCP backend lives at
//! `mcp-server/src/tasks/batch/cancel/effects.rs`; ordering is owned by
//! the canonical sequencer
//! [`lorvex_workflow::task_batch_cancel::flush_batch_cancel_with_backend`]
//! so both surfaces emit byte-identical sync envelopes for the same
//! batch.
//!
//! The whole-operation `batch_cancel` audit row (with `before_states`
//! / `after_states` and the cancelled task ids) is written by the
//! surrounding caller (`run_batch_cancel_in_list_workflow`), not by
//! this backend — that row consumes the [`BatchCancelInListResult`],
//! not the effects bundle alone.

use std::cell::RefCell;

use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_workflow::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};
use lorvex_workflow::task_batch_cancel::{
    BatchCancelFlushBackend, BatchCancelSyncEffects, MutationFlushBackend, SpawnedSuccessorLog,
};
use rusqlite::Connection;

use crate::commands::workflow::tasks::shared_flush::{
    enqueue_focus_rewires, enqueue_spawned_children, enqueue_successors, enqueue_upserts,
    SuccessorView,
};
use crate::error::CliError;

/// CLI backend for [`BatchCancelFlushBackend`].
///
/// `hlc_state` is borrowed mutably across every flush call so the
/// changelog rows and outbox envelopes share the same HLC counter run
/// as the surrounding mutation.
pub(super) struct CliBatchCancelFlush<'a> {
    device_id: &'a str,
    hlc_state: RefCell<&'a mut HlcState>,
}

impl<'a> CliBatchCancelFlush<'a> {
    pub(super) const fn new(device_id: &'a str, hlc_state: &'a mut HlcState) -> Self {
        Self {
            device_id,
            hlc_state: RefCell::new(hlc_state),
        }
    }
}

impl<'a> MutationFlushBackend<BatchCancelSyncEffects> for CliBatchCancelFlush<'a> {
    type Error = CliError;
}

impl<'a> BatchCancelFlushBackend for CliBatchCancelFlush<'a> {
    fn flush_cancelled_task_upserts(
        &self,
        conn: &Connection,
        task_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        enqueue_upserts(conn, self.device_id, *state, ENTITY_TASK, task_ids)
    }

    fn flush_cancelled_reminders(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        use lorvex_domain::naming::ENTITY_TASK_REMINDER;
        let mut state = self.hlc_state.borrow_mut();
        enqueue_upserts(
            conn,
            self.device_id,
            *state,
            ENTITY_TASK_REMINDER,
            reminder_ids,
        )
    }

    fn flush_deleted_dependency_edges(
        &self,
        conn: &Connection,
        edges: &[DeletedDependencyEdge],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        crate::commands::mutate::tasks::dependencies::enqueue_deleted_dependency_edges(
            conn,
            *state,
            self.device_id,
            edges,
        )
    }

    fn flush_affected_dependents(
        &self,
        conn: &Connection,
        affected_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        enqueue_upserts(conn, self.device_id, *state, ENTITY_TASK, affected_ids)
    }

    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        successors: &[SpawnedSuccessorLog],
        tag_edges: &[CopiedTagEdge],
        checklist_item_ids: &[String],
        reminder_ids: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        enqueue_successors(
            conn,
            self.device_id,
            *state,
            "create",
            successors.iter().map(|s| SuccessorView {
                successor_id: s.successor_id.as_str(),
                summary: &s.summary,
                after_task: &s.after_task,
            }),
        )?;
        enqueue_spawned_children(
            conn,
            self.device_id,
            *state,
            tag_edges,
            checklist_item_ids,
            reminder_ids,
        )
    }

    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        focus_schedule_dates: &[String],
        current_focus_dates: &[String],
    ) -> Result<(), Self::Error> {
        let mut state = self.hlc_state.borrow_mut();
        enqueue_focus_rewires(
            conn,
            self.device_id,
            *state,
            focus_schedule_dates,
            current_focus_dates,
        )
    }
}
