//! `memory write` — create or update a memory section and emit a fresh
//! revision row + outbox envelopes.

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
    enqueue_memory_revision_upsert, enqueue_memory_upsert, validate_memory_content,
    validate_memory_key, MemoryWriteResult,
};

struct WriteCliMemoryMutation<'a> {
    key: &'a str,
    content: &'a str,
    now: &'a str,
    operation: &'static str,
    before_json: Option<Value>,
}

impl<'a> Mutation for WriteCliMemoryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before_json.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let result = lorvex_workflow::memory_ops::upsert_memory_entry(
            conn,
            self.key,
            self.content,
            "ai",
            &version,
            self.now,
        )?
        .ok_or_else(|| {
            StoreError::Validation(format!(
                "memory key '{}' was updated by another writer; retry the command",
                self.key
            ))
        })?;
        Ok(MutationOutput::new(
            json!({
                "key": self.key,
                "content": self.content,
                "version": version,
                "updated_at": self.now,
                "revision_id": result.revision_id,
            }),
            format!(
                "{} memory section \"{}\"",
                if self.operation == "update" {
                    "Updated"
                } else {
                    "Created"
                },
                self.key
            ),
        ))
    }
}

pub(crate) fn write_memory_with_conn(
    conn: &mut Connection,
    key: &str,
    content: &str,
) -> Result<MemoryWriteResult, crate::error::CliError> {
    // persist the sanitized + trimmed key so the
    // DB row matches what consumers see. Shadowing `key` is
    // deliberate — the rest of the function must not touch the raw
    // input again.
    let key = validate_memory_key(key)?;
    let key = key.as_str();
    let content = validate_memory_content(content)?;
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;

    // capture pre-mutation snapshot. Mirrors MCP's
    // `server_change_tracking::log_change_and_enqueue_sync` shape so
    // the audit row carries enough state to drive Restore/Undo.
    let before_row: Option<(String, String, String)> = tx
        .query_row(
            "SELECT content, version, updated_at FROM memories WHERE key = ?1",
            [key],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;
    let existed = before_row.is_some();
    let before_json = before_row.as_ref().map(|(content, version, updated_at)| {
        lorvex_store::payload_loaders::memory_payload(key, content, version, updated_at)
    });
    let operation = if existed { "update" } else { "create" };
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = WriteCliMemoryMutation {
        key,
        content: &content,
        now: &now,
        operation,
        before_json,
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
                .expect("Mutation contract: write_memory must surface key");
            let content = execution
                .output
                .after
                .get("content")
                .and_then(Value::as_str)
                .expect("Mutation contract: write_memory must surface content");
            let version = execution
                .output
                .after
                .get("version")
                .and_then(Value::as_str)
                .expect("Mutation contract: write_memory must surface version");
            let updated_at = execution
                .output
                .after
                .get("updated_at")
                .and_then(Value::as_str)
                .expect("Mutation contract: write_memory must surface updated_at");
            let revision_id = execution
                .output
                .after
                .get("revision_id")
                .and_then(Value::as_str)
                .expect("Mutation contract: write_memory must surface revision_id");
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
    let version = output
        .after
        .get("version")
        .and_then(Value::as_str)
        .expect("Mutation contract: write_memory must surface version")
        .to_string();
    let revision_id = output
        .after
        .get("revision_id")
        .and_then(Value::as_str)
        .expect("Mutation contract: write_memory must surface revision_id")
        .to_string();
    drop(hlc_guard);
    tx.commit()?;

    Ok(MemoryWriteResult {
        key: key.to_string(),
        content,
        version,
        updated_at: now,
        revision_id,
        operation,
    })
}
