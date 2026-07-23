//! Tests for the task recurrence-exception helpers.
//!
//! The renderer-facing `add_task_recurrence_exception` /
//! `remove_task_recurrence_exception` Tauri commands were removed in
//! issue #2940-H1 — no UI surface called them. The transactional
//! `_with_conn` helpers below stay so the existing regression tests
//! continue to pin the exception lifecycle (write into outbox + invariants
//! changelog + re-fetched stamped version), and so the same helpers can
//! be re-exposed if a future feature needs them.

#[cfg(test)]
use lorvex_domain::hlc_session::HlcSession;
#[cfg(test)]
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT};
#[cfg(test)]
use lorvex_store::repositories::task::recurrence;
#[cfg(test)]
use lorvex_store::StoreError;
#[cfg(test)]
use lorvex_workflow::mutation::{Mutation, MutationOutput};
#[cfg(test)]
use rusqlite::Connection;
#[cfg(test)]
use serde_json::Value;

#[cfg(test)]
use super::{fetch_task_by_id, Task};
#[cfg(test)]
use crate::commands::enqueue_task_upsert;
#[cfg(test)]
use crate::commands::shared::effects::execute_ipc_entity_mutation;
#[cfg(test)]
use crate::error::AppResult;

/// `Mutation` descriptor for adding (or removing) a recurrence
/// exception on a task. The `removal` flag selects between
/// `add_task_recurrence_exception` and `remove_task_recurrence_exception`
/// inside `apply` so the executor pipeline (HLC stamp, event_bus
/// broadcast, `local_change_seq` bump) is identical for both.
#[cfg(test)]
struct TaskRecurrenceExceptionMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    exception_date: &'a str,
    now: &'a str,
    removal: bool,
}

#[cfg(test)]
impl<'a> Mutation for TaskRecurrenceExceptionMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }
    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }
    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        if self.removal {
            recurrence::remove_task_recurrence_exception(
                conn,
                self.task_id,
                self.exception_date,
                &version,
                self.now,
            )?;
        } else {
            recurrence::add_task_recurrence_exception(
                conn,
                self.task_id,
                self.exception_date,
                &version,
                self.now,
            )?;
        }
        let summary = if self.removal {
            format!(
                "Removed recurrence exception '{}' from task '{}'",
                self.exception_date,
                self.task_id.as_str()
            )
        } else {
            format!(
                "Added recurrence exception '{}' to task '{}'",
                self.exception_date,
                self.task_id.as_str()
            )
        };
        Ok(MutationOutput::new(
            serde_json::json!({ "id": self.task_id.as_str() }),
            summary,
        ))
    }
}

#[cfg(test)]
fn run_task_recurrence_exception(
    conn: &Connection,
    task_id: &str,
    exception_date: &str,
    now: &str,
    removal: bool,
) -> AppResult<Task> {
    let typed_task_id = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let mutation = TaskRecurrenceExceptionMutation {
        task_id: &typed_task_id,
        exception_date,
        now,
        removal,
    };
    execute_ipc_entity_mutation(conn, &mutation, |conn, _execution| {
        let task = fetch_task_by_id(conn, task_id)?;
        enqueue_task_upsert(conn, &task)?;
        Ok(())
    })?;
    // Re-fetch after enqueue (enqueue stamps the version column via HLC).
    fetch_task_by_id(conn, task_id)
}

#[cfg(test)]
fn add_task_exception_with_conn(
    conn: &rusqlite::Connection,
    task_id: &str,
    exception_date: &str,
    now: &str,
) -> AppResult<Task> {
    run_task_recurrence_exception(conn, task_id, exception_date, now, false)
}

#[cfg(test)]
fn remove_task_exception_with_conn(
    conn: &rusqlite::Connection,
    task_id: &str,
    exception_date: &str,
    now: &str,
) -> AppResult<Task> {
    run_task_recurrence_exception(conn, task_id, exception_date, now, true)
}

#[cfg(test)]
mod tests;
