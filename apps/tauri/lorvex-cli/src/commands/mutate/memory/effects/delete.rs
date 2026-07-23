//! `memory delete` — soft-delete a memory section while emitting a
//! tombstone revision so a future `restore` can recover the value.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_MEMORY, OP_DELETE};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Value};

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

use super::{
    enqueue_memory_delete, enqueue_memory_revision_upsert, validate_memory_key, MemoryDeleteResult,
};

struct DeleteCliMemoryMutation<'a> {
    key: &'a str,
    before_json: Value,
    now: &'a str,
}

impl<'a> Mutation for DeleteCliMemoryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let result = lorvex_workflow::memory_ops::delete_memory_entry(
            conn, self.key, "ai", &version, self.now,
        )?;
        Ok(MutationOutput::new(
            json!({
                "key": self.key,
                "deleted": result.is_some(),
                "revision_id": result.map(|value| value.revision_id),
            }),
            format!("Deleted memory section \"{}\"", self.key),
        ))
    }
}

pub(crate) fn delete_memory_with_conn(
    conn: &mut Connection,
    key: &str,
) -> Result<MemoryDeleteResult, crate::error::CliError> {
    // shadow `key` with the sanitized form so we
    // never query the DB with raw bidi-tainted input.
    let key = validate_memory_key(key)?;
    let key = key.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;

    let before: Option<(String, String, String)> = tx
        .query_row(
            "SELECT content, version, updated_at FROM memories WHERE key = ?1",
            [key],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;
    let Some((before_content, before_version, before_updated_at)) = before else {
        // rollback the empty transaction rather than
        // committing a no-op. Same rationale as the matching branch
        // in `commands::mutate::preferences::effects`.
        tx.rollback()?;
        return Ok(MemoryDeleteResult {
            key: key.to_string(),
            deleted: false,
            revision_id: None,
            before_content: None,
            before_updated_at: None,
        });
    };

    let before_json = lorvex_store::payload_loaders::memory_payload(
        key,
        &before_content,
        &before_version,
        &before_updated_at,
    );
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = DeleteCliMemoryMutation {
        key,
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
            let deleted = execution
                .output
                .after
                .get("deleted")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if !deleted {
                return Ok(());
            }
            let revision_id = execution
                .output
                .after
                .get("revision_id")
                .and_then(Value::as_str)
                .expect("Mutation contract: delete_memory must surface revision_id");
            enqueue_memory_delete(
                &tx,
                hlc_state,
                &device_id,
                key,
                &before_content,
                &before_version,
                &before_updated_at,
            )?;
            enqueue_memory_revision_upsert(&tx, hlc_state, &device_id, revision_id)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: key,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let deleted = output
        .after
        .get("deleted")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let revision_id = output
        .after
        .get("revision_id")
        .and_then(Value::as_str)
        .map(str::to_string);
    drop(hlc_guard);
    if !deleted {
        tx.rollback()?;
        return Ok(MemoryDeleteResult {
            key: key.to_string(),
            deleted: false,
            revision_id: None,
            before_content: Some(before_content),
            before_updated_at: Some(before_updated_at),
        });
    }
    let revision_id =
        revision_id.expect("Mutation contract: delete_memory must surface revision_id");
    tx.commit()?;

    Ok(MemoryDeleteResult {
        key: key.to_string(),
        deleted: true,
        revision_id: Some(revision_id),
        before_content: Some(before_content),
        before_updated_at: Some(before_updated_at),
    })
}
