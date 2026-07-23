use super::gate::require_memory_unlocked;
use super::key::{normalize_mcp_memory_key, reject_human_owned_ai_memory_key};
use crate::contract::{WriteMemoryArgs, MAX_MEMORY_CONTENT_LENGTH};
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::runtime::change_tracking::{
    enqueue_relation_sync, execute_mcp_mutation_with_finalizer, log_change, LogChangeParams,
};
use crate::system::handler_support::{load_failed_error, utc_now_iso};
use crate::tasks::validation::validate_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;

/// Mutation descriptor for the MCP `write_memory` tool — Phase 2
/// migration of #3452. The descriptor owns the parent `memories` row
/// upsert (delegated to `lorvex_workflow::memory_ops::upsert_memory_entry`)
/// and threads the freshly-inserted revision id + post-stamp version
/// back to the surrounding handler through `MutationOutput.extra`
/// (#3481) so the sibling `memory_revision` outbox enqueue can fire
/// after the orchestrator returns. The trait deliberately covers a
/// single entity per `apply`; the revision is a cascaded child row
/// written by the same workflow helper, so its enqueue stays out of
/// the descriptor (Phase 3 will tackle multi-entity cascades).
struct WriteMemoryMutation<'a> {
    key: &'a str,
    content: &'a str,
    now: &'a str,
    operation: &'static str,
    /// Captured pre-mutation row so `pre_snapshot` is a pure value
    /// accessor and the orchestrator does not re-issue the SELECT.
    before: Option<&'a serde_json::Value>,
}

// #3497: side-channel keys are typed `<entity>:<field>` constants
// from `lorvex_workflow::mutation_extras` so two descriptors that both
// stamp `MutationOutput.extra` cannot collide on a bare `"version"`.
// See the playbook in `mutation.rs` (Sibling-entity outputs flow
// through `MutationOutput.extra`) for the namespacing rule.
use lorvex_workflow::mutation_extras::{MEMORY_REVISION_ID, MEMORY_VERSION};

impl<'a> Mutation for WriteMemoryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(self.before.cloned())
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
        .ok_or_else(|| StoreError::StaleVersion {
            entity: ENTITY_MEMORY,
            id: self.key.to_string(),
        })?;

        // Capture the post-write row pre-stamp shape for `after_json`
        // (#2373). The handler patches the post-stamp HLC version onto
        // this snapshot for the response below.
        let after = crate::json_row::query_one_as_json(
            conn,
            "SELECT * FROM memories WHERE key = ?",
            [self.key.to_string()],
        )
        .map_err(|e| StoreError::Invariant(format!("query_one_as_json: {e}")))?
        .ok_or_else(|| {
            StoreError::Invariant(format!("memory '{}' vanished after write", self.key))
        })?;

        let summary = format!(
            "{} memory section \"{}\"",
            if self.operation == "update" {
                "Updated"
            } else {
                "Created"
            },
            self.key
        );
        // #3481: surface revision id + post-stamp version through the
        // uniform `extra` map instead of per-descriptor `Cell` out-params.
        let mut output = MutationOutput::new(after, summary);
        output.set_extra(
            &MEMORY_REVISION_ID,
            serde_json::Value::String(result.revision_id),
        );
        output.set_extra(&MEMORY_VERSION, serde_json::Value::String(version));
        Ok(output)
    }
}

pub(crate) fn write_memory(conn: &Connection, args: WriteMemoryArgs) -> Result<String, McpError> {
    require_memory_unlocked(conn)?;
    let mut args = args;
    args.key = normalize_mcp_memory_key(&args.key)?;
    args.content = lorvex_domain::sanitize_user_text(&args.content);
    validate_string_length(&args.content, "content", MAX_MEMORY_CONTENT_LENGTH)?;
    reject_human_owned_ai_memory_key(&args.key)?;

    // capture the canonical request fingerprint
    // after key/content normalization for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale. `write_memory`
    // creates an immutable revision row on every call — without
    // the cache, a retry produces a duplicate revision in
    // `get_memory_history`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "write_memory",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let WriteMemoryArgs {
        key,
        content,
        idempotency_key,
    } = args;

    let before = query_one_as_json(conn, "SELECT * FROM memories WHERE key = ?", [key.clone()])?;
    let now = utc_now_iso();
    let operation: &'static str = if before.is_some() { "update" } else { "create" };

    let mutation = WriteMemoryMutation {
        key: key.as_str(),
        content: content.as_str(),
        now: now.as_str(),
        operation,
        before: before.as_ref(),
    };

    let output = execute_mcp_mutation_with_finalizer(
        conn,
        &mutation,
        |e| {
            match e {
            StoreError::StaleVersion { id, .. } => McpError::Validation(format!(
                "memory key '{id}' was updated by another writer between version generation and write; retry the call"
            )),
            other => McpError::from(other),
        }
        },
        |execution| {
            let revision_id = execution
                .output
                .get_extra(&MEMORY_REVISION_ID)
                .and_then(|v| v.as_str())
                .map(str::to_string)
                .expect("Mutation contract: write_memory must stamp memory:revision_id");

            // The parent `memory` envelope is emitted by `log_change`
            // below. The revision is a separate syncable entity that
            // the single-entity trait does not cover, so it still
            // needs an explicit enqueue here (Phase 3 of #3841 will
            // tackle multi-entity cascades).
            enqueue_relation_sync(conn, ENTITY_MEMORY_REVISION, &revision_id, OP_UPSERT)?;

            log_change(
                conn,
                LogChangeParams::new(
                    execution.operation,
                    execution.entity_kind,
                    "write_memory",
                    execution.output.summary,
                )
                .with_entity_id(key.clone())
                .with_before_opt(execution.before)
                .with_after(execution.output.after),
                None,
            )
        },
    )?;
    // #3481: pull the side-channel values from the uniform `extra`
    // map instead of per-descriptor `Cell` out-params. #3497: the
    // `WriteMemoryMutation::apply` impl above unconditionally stamps
    // both keys before returning `Ok`, so reading them back can never
    // see `None` for an honest descriptor — convert the dead defensive
    // `ok_or_else` branches to `expect` so a contract violation
    // panics loudly instead of being misreported as a runtime error.
    let post_stamp_version = output
        .get_extra(&MEMORY_VERSION)
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .expect("Mutation contract: write_memory must stamp memory:version");

    // Reuse the pre-stamp row JSON for the response, patching only
    // the `version` field with the post-stamp HLC. #3471: the post-
    // stamp version is exactly the HLC we minted inside `apply` — so
    // instead of a re-SELECT to read it back, the descriptor surfaces
    // it through `MutationOutput.extra` (#3481 / #3486 — replaced the
    // earlier `Cell<Option<T>>` out-param shape with the uniform JSON
    // map keyed by descriptor-defined string keys).
    let mut after = output.after;
    if let Some(obj) = after.as_object_mut() {
        obj.insert(
            "version".to_string(),
            serde_json::Value::String(post_stamp_version),
        );
    } else {
        return Err(McpError::NotFound(load_failed_error("memory key", &key)));
    }

    let response = serde_json::to_string(&after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "write_memory",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
