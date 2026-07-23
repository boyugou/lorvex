//! Pull a task back out of the Trash (`archived_at = NULL`).

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::TaskId;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::task::read;
use lorvex_store::repositories::task::write::{self, TaskUpdatePatch};
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::enqueue_entity_upsert;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, load_task_row};
use crate::commands::shared::{log_cli_changelog_with_state, CliChangelogParams};
use crate::hlc_guard::lock_shared;

struct RestoreCliTaskFromTrashMutation {
    task_id: TaskId,
    before: Value,
    before_status: String,
    title: String,
}

impl Mutation for RestoreCliTaskFromTrashMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "restore"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let task_id_str = self.task_id.as_str();
        let now = lorvex_domain::sync_timestamp_now();
        let version = hlc.next_version_string();
        let patch = TaskUpdatePatch {
            task_id: task_id_str,
            archived_at: lorvex_domain::Patch::Clear,
            version: &version,
            now: &now,
            before_status: Some(write::parse_task_status_for_update(
                task_id_str,
                &self.before_status,
            )?),
            ..Default::default()
        };
        write::apply_task_update(conn, &patch)?;
        let restored =
            read::get_task(conn, &self.task_id)?.ok_or_else(|| StoreError::NotFound {
                entity: ENTITY_TASK,
                id: task_id_str.to_string(),
            })?;
        Ok(MutationOutput::new(
            serde_json::to_value(&restored)?,
            format!("Restored task '{}' from Trash", self.title),
        ))
    }
}

/// Owned-tx wrapper. See `complete_task_with_conn` for the rationale.
#[cfg(test)]
pub(crate) fn restore_task_from_trash_with_conn(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<read::TaskRow, crate::error::CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        restore_task_from_trash_in_tx(conn, task_id)
    })
}

/// Inside-transaction body for `restore_task_from_trash_with_conn` (#3019-H3).
pub(crate) fn restore_task_from_trash_in_tx(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<read::TaskRow, crate::error::CliError> {
    let task_id_str = task_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let before = load_task_row(conn, task_id)?;
    if before.lifecycle().archived_at().is_none() {
        return Err(crate::error::CliError::Conflict(format!(
            "task '{task_id_str}' is not in the Trash"
        )));
    }

    let mutation = RestoreCliTaskFromTrashMutation {
        task_id: task_id.clone(),
        before: serde_json::to_value(&before)?,
        before_status: before.core().status().to_string(),
        title: before.core().title().to_string(),
    };

    let mut hlc_guard = lock_shared(conn)?;
    let output = execute_cli_mutation_with_finalizer(
        conn,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(
                conn,
                execution.entity_kind,
                task_id_str,
                hlc_state,
                &device_id,
            )?;
            log_cli_changelog_with_state(
                conn,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: task_id_str,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(conn)?;
            Ok(())
        },
    )?;
    let restored = serde_json::from_value(output.after)?;
    drop(hlc_guard);
    Ok(restored)
}
