use super::gate::require_memory_unlocked;
use super::key::normalize_mcp_memory_key;
use crate::contract::{GetMemoryHistoryArgs, RestoreMemoryRevisionArgs};
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::runtime::change_tracking::{
    enqueue_relation_sync, execute_mcp_mutation_with_audit_finalizer,
};
use crate::system::handler_support::{bounded_limit_or_default, utc_now_iso};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::memory::is_human_owned_memory_key;
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::MEMORY_REVISION_ID;
use rusqlite::Connection;
use serde_json::{json, Value};

struct RestoreMemoryRevisionMutation<'a> {
    revision_id: &'a str,
    memory_key: &'a str,
    before: Option<&'a Value>,
    now: &'a str,
}

impl<'a> Mutation for RestoreMemoryRevisionMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.cloned())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let result = lorvex_workflow::memory_ops::restore_memory_revision(
            conn,
            self.revision_id,
            "ai",
            &version,
            self.now,
        )?
        .ok_or_else(|| StoreError::StaleVersion {
            entity: ENTITY_MEMORY,
            id: self.revision_id.to_string(),
        })?;

        let after = query_one_as_json(
            conn,
            "SELECT * FROM memories WHERE key = ?",
            [result.memory_key.clone()],
        )
        .map_err(|error| StoreError::Invariant(format!("query_one_as_json: {error}")))?
        .ok_or_else(|| {
            StoreError::Invariant(format!(
                "memory '{}' vanished after restore",
                self.memory_key
            ))
        })?;

        let mut output = MutationOutput::new(
            after,
            format!(
                "Restored memory section \"{}\" from revision {}",
                result.memory_key, self.revision_id
            ),
        );
        output.set_extra(&MEMORY_REVISION_ID, Value::String(result.revision_id));
        Ok(output)
    }
}

fn map_restore_memory_revision_error(error: StoreError, revision_id: &str) -> McpError {
    match error {
        StoreError::StaleVersion { .. } => McpError::Validation(format!(
            "memory revision {revision_id} could not be restored — the live row was updated by another writer; retry the call"
        )),
        other => McpError::from(other),
    }
}

pub(crate) fn get_memory_history(
    conn: &Connection,
    args: &GetMemoryHistoryArgs,
) -> Result<String, McpError> {
    require_memory_unlocked(conn)?;
    // Route through the shared limit/cap helper so the `0 → default`
    // and `> cap → cap` clamps are consistent with every other MCP
    // paginated-read tool. The previous `unwrap_or(20).min(100)` chain
    // missed the `0` rebound (a `Some(0)` request slipped through and
    // returned an empty page), and a second drift would inevitably
    // appear the next time someone copy-pasted the snippet.
    let limit = bounded_limit_or_default(args.limit, 20, 100);
    let key = normalize_mcp_memory_key(&args.key)?;
    let typed_key = lorvex_domain::MemoryKey::from_trusted(key.clone());
    let revisions = lorvex_store::repositories::memory_revision_repo::get_revisions_for_key(
        conn, &typed_key, limit,
    )?;

    Ok(serde_json::to_string(&json!({
        "key": key,
        "count": revisions.len(),
        "revisions": revisions,
    }))?)
}

pub(crate) fn restore_memory_revision(
    conn: &Connection,
    args: RestoreMemoryRevisionArgs,
) -> Result<String, McpError> {
    require_memory_unlocked(conn)?;
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale. A retry without
    // the cache creates a second new revision row for the same
    // logical "go back to revision X" intent.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "restore_memory_revision",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // Pre-fetch the revision to check ownership before mutating.
    let revision =
        lorvex_store::repositories::memory_revision_repo::get_revision(conn, &args.revision_id)?
            .ok_or_else(|| {
                McpError::NotFound(format!("Revision {} not found", args.revision_id))
            })?;

    if is_human_owned_memory_key(&revision.memory_key) {
        return Err(McpError::Validation(format!(
            "Key '{}' is human-owned and cannot be changed through MCP. Ask the user to edit notes_for_ai in the app UI.",
            revision.memory_key
        )));
    }

    // Audit: capture the pre-restore memory row so the changelog row
    // carries `before_json`. `restore_memory_revision` mutates the
    // current row by replacing it with a historical revision; without
    // this snapshot the diagnostics diff renderer and any undo
    // affordance can't reconstruct what the memory looked like
    // before the restore.
    let memory_key = revision.memory_key.clone();
    let before = query_one_as_json(conn, "SELECT * FROM memories WHERE key = ?", [memory_key])?;

    let now = utc_now_iso();

    let mutation = RestoreMemoryRevisionMutation {
        revision_id: args.revision_id.as_str(),
        memory_key: revision.memory_key.as_str(),
        before: before.as_ref(),
        now: now.as_str(),
    };
    let revision_id_for_error = args.revision_id.clone();
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "restore_memory_revision",
        revision.memory_key.clone(),
        move |error| map_restore_memory_revision_error(error, revision_id_for_error.as_str()),
        |conn, execution| {
            let revision_id = execution
                .output
                .get_extra(&MEMORY_REVISION_ID)
                .and_then(Value::as_str)
                .expect("Mutation contract: restore_memory_revision must stamp memory:revision_id");
            enqueue_relation_sync(conn, ENTITY_MEMORY_REVISION, revision_id, OP_UPSERT)
        },
    )?;
    let new_revision_id = output
        .get_extra(&MEMORY_REVISION_ID)
        .and_then(Value::as_str)
        .expect("Mutation contract: restore_memory_revision must stamp memory:revision_id");
    let restored_key = output
        .after
        .get("key")
        .and_then(Value::as_str)
        .unwrap_or(revision.memory_key.as_str());

    let response = serde_json::to_string(&json!({
        "restored": true,
        "key": restored_key,
        "from_revision_id": args.revision_id,
        "new_revision_id": new_revision_id,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "restore_memory_revision",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
