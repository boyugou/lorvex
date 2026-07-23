use super::gate::require_memory_unlocked;
use super::key::{normalize_mcp_memory_key, reject_human_owned_ai_memory_key};
use crate::contract::DeleteMemoryArgs;
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::runtime::change_tracking::{
    enqueue_relation_sync, execute_mcp_mutation_with_tombstone_audit_finalizer,
};
use crate::system::handler_support::utc_now_iso;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION, OP_DELETE, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::MEMORY_REVISION_ID;
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::HashMap;

struct DeleteMemoryMutation<'a> {
    key: &'a str,
    now: &'a str,
    before: &'a Value,
}

impl<'a> Mutation for DeleteMemoryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let Some(result) = lorvex_workflow::memory_ops::delete_memory_entry(
            conn, self.key, "ai", &version, self.now,
        )?
        else {
            return Ok(MutationOutput::new(
                json!({
                    "deleted": false,
                    "key": self.key,
                    "previous": self.before,
                }),
                format!("Skipped stale memory delete for \"{}\"", self.key),
            ));
        };

        let mut output = MutationOutput::new(
            json!({
                "deleted": true,
                "key": self.key,
                "previous": self.before,
            }),
            format!("Deleted memory section \"{}\"", self.key),
        );
        output.set_extra(&MEMORY_REVISION_ID, Value::String(result.revision_id));
        Ok(output)
    }
}

pub(crate) fn delete_memory(conn: &Connection, args: DeleteMemoryArgs) -> Result<String, McpError> {
    require_memory_unlocked(conn)?;
    // `dry_run` is consumed at the router layer;
    // the body itself is unaware of preview mode and the savepoint
    // around `with_conn` decides whether the writes commit.
    let mut args = args;
    args.key = normalize_mcp_memory_key(&args.key)?;
    reject_human_owned_ai_memory_key(&args.key)?;

    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "delete_memory",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    let DeleteMemoryArgs {
        key,
        dry_run: _,
        idempotency_key,
    } = args;

    let before = query_one_as_json(conn, "SELECT * FROM memories WHERE key = ?", [key.clone()])?;

    let Some(before) = before else {
        let response = serde_json::to_string(&json!({ "key": key, "found": false }))?;
        crate::runtime::idempotency::record_if_keyed(
            conn,
            idempotency_key.as_deref(),
            "delete_memory",
            &request_repr,
            &response,
        )?;
        return Ok(response);
    };

    let mut tombstone_payloads = HashMap::with_capacity(1);
    tombstone_payloads.insert(key.clone(), before.clone());

    let now = utc_now_iso();
    let mutation = DeleteMemoryMutation {
        key: key.as_str(),
        now: now.as_str(),
        before: &before,
    };

    let output = execute_mcp_mutation_with_tombstone_audit_finalizer(
        conn,
        &mutation,
        "delete_memory",
        key.clone(),
        tombstone_payloads,
        McpError::from,
        |conn, execution| {
            if execution
                .output
                .after
                .get("deleted")
                .and_then(Value::as_bool)
                != Some(true)
            {
                return Ok(());
            }
            let revision_id = execution
                .output
                .get_extra(&MEMORY_REVISION_ID)
                .and_then(Value::as_str)
                .expect("Mutation contract: delete_memory must stamp memory:revision_id");
            enqueue_relation_sync(conn, ENTITY_MEMORY_REVISION, revision_id, OP_UPSERT)
        },
    )?;

    // #3029-M6: canonical delete-response shape
    // `{deleted: bool, previous: snapshot}`.
    // returned `before_state` while sibling deletes returned
    // `previous` — three different shapes for the same concept.
    // Standardize on `previous`.
    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "delete_memory",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
