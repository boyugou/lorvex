//! `memory restore` — replay a stored revision back onto the live row,
//! minting a fresh revision for the restored state.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_MEMORY;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Value};

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

use super::{
    enqueue_memory_revision_upsert, enqueue_memory_upsert, validate_memory_key, MemoryRestoreResult,
};

struct RestoreCliMemoryMutation<'a> {
    revision_id: &'a str,
    before_json: Option<Value>,
    now: &'a str,
}

impl<'a> Mutation for RestoreCliMemoryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before_json.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let result = lorvex_workflow::memory_ops::restore_memory_revision(
            conn,
            self.revision_id,
            "ai",
            &version,
            self.now,
        )?
        .ok_or_else(|| {
            StoreError::Validation(format!(
                "memory revision '{}' could not be restored — the live row was updated by another writer; retry the command",
                self.revision_id
            ))
        })?;
        let restored_content: String = conn.query_row(
            "SELECT content FROM memories WHERE key = ?1",
            [&result.memory_key],
            |row| row.get(0),
        )?;
        Ok(MutationOutput::new(
            json!({
                "key": result.memory_key,
                "content": restored_content,
                "version": version,
                "updated_at": self.now,
                "revision_id": result.revision_id,
            }),
            format!(
                "Restored memory section \"{}\" from revision {}",
                result.memory_key, self.revision_id
            ),
        ))
    }
}

pub(crate) fn restore_memory_with_conn(
    conn: &mut Connection,
    revision_id: &str,
) -> Result<MemoryRestoreResult, crate::error::CliError> {
    if revision_id.is_empty() {
        return Err(crate::error::CliError::Validation(
            "memory revision id must not be empty".to_string(),
        ));
    }

    let revision =
        lorvex_store::repositories::memory_revision_repo::get_revision(conn, revision_id)?
            .ok_or_else(|| {
                crate::error::CliError::NotFound(format!(
                    "memory revision '{revision_id}' not found"
                ))
            })?;
    // validate the persisted key the revision
    // points at — defense-in-depth against a peer envelope landing a
    // touch via the human entry point.
    let _validated_key = validate_memory_key(&revision.memory_key)?;

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    // snapshot the live row BEFORE the restore overwrites
    // it so the audit trail captures the pre-restore state.
    let before_row: Option<(String, String, String)> = tx
        .query_row(
            "SELECT content, version, updated_at FROM memories WHERE key = ?1",
            [&revision.memory_key],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;
    let before_json = before_row.as_ref().map(|(content, version, updated_at)| {
        lorvex_store::payload_loaders::memory_payload(
            &revision.memory_key,
            content,
            version,
            updated_at,
        )
    });
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = RestoreCliMemoryMutation {
        revision_id,
        before_json,
        now: &now,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let key = execution
                .output
                .after
                .get("key")
                .and_then(Value::as_str)
                .expect("Mutation contract: restore_memory must surface key");
            let content = execution
                .output
                .after
                .get("content")
                .and_then(Value::as_str)
                .expect("Mutation contract: restore_memory must surface content");
            let version = execution
                .output
                .after
                .get("version")
                .and_then(Value::as_str)
                .expect("Mutation contract: restore_memory must surface version");
            let updated_at = execution
                .output
                .after
                .get("updated_at")
                .and_then(Value::as_str)
                .expect("Mutation contract: restore_memory must surface updated_at");
            let revision_id = execution
                .output
                .after
                .get("revision_id")
                .and_then(Value::as_str)
                .expect("Mutation contract: restore_memory must surface revision_id");
            enqueue_memory_upsert(&tx, &device_id, key, content, version, updated_at)?;
            enqueue_memory_revision_upsert(&tx, hlc_state, &device_id, revision_id)?;
            let after_json =
                lorvex_store::payload_loaders::memory_payload(key, content, version, updated_at);
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: key,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(after_json),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let key = output
        .after
        .get("key")
        .and_then(Value::as_str)
        .expect("Mutation contract: restore_memory must surface key")
        .to_string();
    let new_revision_id = output
        .after
        .get("revision_id")
        .and_then(Value::as_str)
        .expect("Mutation contract: restore_memory must surface revision_id")
        .to_string();
    drop(hlc_guard);
    tx.commit()?;

    Ok(MemoryRestoreResult {
        key,
        from_revision_id: revision_id.to_string(),
        new_revision_id,
    })
}
