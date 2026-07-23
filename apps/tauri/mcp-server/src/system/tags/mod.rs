use crate::contract::{RenameTagArgs, MAX_SHORT_TEXT_LENGTH};
use crate::error::McpError;
use crate::json_row::{query_all_as_json, query_one_as_json};
use crate::runtime::change_tracking::{
    enqueue_relation_sync, enqueue_relation_sync_with_snapshot,
    execute_mcp_mutation_with_skip_sync_audit_finalizer,
};
use crate::system::handler_support::utc_now_iso;
use crate::tasks::lww::execute_task_lww_update;
use crate::tasks::validation::validate_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_TAG, ENTITY_TASK, OP_DELETE, OP_UPSERT};
use lorvex_domain::tag::normalize_lookup_key;
use lorvex_store::repositories::tag_repo;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::{TAG_RENAME_RESPONSE, TAG_RENAME_SYNC_ACTIONS};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::HashSet;

fn tag_mcp_error_to_store_error(error: McpError) -> StoreError {
    match error {
        McpError::Store(store_error) => *store_error,
        McpError::Sql(sql_error) => StoreError::from(*sql_error),
        McpError::Validation(message) => StoreError::Validation(message),
        McpError::NotFound(message) => StoreError::NotFound {
            entity: ENTITY_TAG,
            id: message,
        },
        McpError::Serialization(message) => StoreError::Serialization(message),
        other => StoreError::Invariant(other.to_string()),
    }
}

pub(crate) fn rename_tag(conn: &Connection, args: RenameTagArgs) -> Result<String, McpError> {
    // #3033-M2: idempotency cache. capture the canonical request
    // fingerprint before destructure so a retry of the same rename
    // (which fans out to per-task sync envelopes + a tag audit row)
    // short-circuits to the cached response.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let RenameTagArgs {
        old_name,
        new_name,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "rename_tag",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // scrub both inputs through `sanitize_user_text`
    // BEFORE any length / equality / lookup checks. The sibling
    // tag-write path at `prepared.rs:113-117` already sanitized; the
    // rename surface lagged behind, so a smuggled bidi character in
    // `old_name` would fail the lookup even though the corresponding
    // tag row had been stored sanitized, and a smuggled `new_name`
    // would land verbatim in the renamed row.
    let old_name_sanitized = lorvex_domain::sanitize_user_text(&old_name);
    let new_name_sanitized = lorvex_domain::sanitize_user_text(&new_name);
    let old_lookup_key = normalize_lookup_key(&old_name_sanitized);
    let new_display_name = new_name_sanitized.trim().to_string();
    let new_lookup_key = normalize_lookup_key(&new_display_name);

    if old_name_sanitized.trim().is_empty() {
        return Err(McpError::Validation(
            "old_name must not be empty".to_string(),
        ));
    }
    if new_display_name.is_empty() {
        return Err(McpError::Validation(
            "new_name must not be empty".to_string(),
        ));
    }
    validate_string_length(&old_name_sanitized, "old_name", MAX_SHORT_TEXT_LENGTH)?;
    validate_string_length(&new_display_name, "new_name", MAX_SHORT_TEXT_LENGTH)?;
    if old_lookup_key == new_lookup_key {
        return Err(McpError::Validation(
            "old_name and new_name are the same (case-insensitive)".to_string(),
        ));
    }

    let now = utc_now_iso();

    // Look up the tag by its lookup_key (via shared repo)
    // Use the sanitized form for the lookup so a smuggled bidi /
    // zero-width character in `old_name` still resolves to a tag row
    // whose `lookup_key` was computed from the sanitized form.
    let old_tag = tag_repo::get_tag_by_name(conn, &old_name_sanitized)?
        .ok_or_else(|| McpError::NotFound(format!("tag '{old_name_sanitized}' not found")))?;
    let old_tag_id = old_tag.id;

    // capture the full pre-rename tag row so the
    // primary changelog entry below can carry it as `before_json`.
    // The rename / merge branches both mutate the row (or delete it +
    // re-point edges to the survivor), so the snapshot must be taken
    // here, before any branch-specific work runs.
    let pre_rename_tag_row =
        query_one_as_json(conn, "SELECT * FROM tags WHERE id = ?", [&old_tag_id])?;

    // Check if the new name already exists as a different tag
    let conflict_tag = tag_repo::get_tag_by_name(conn, &new_display_name)?;
    let conflict_tag_id = conflict_tag.as_ref().map(|tag| tag.id.clone());

    // Collect task_ids that reference the old tag (for changelog / sync).
    // Uses `prepare_cached` so the same statement is reused for the
    // conflict-branch lookup of the surviving tag's edges below — both
    // sites share the cache slot keyed on this exact SQL string.
    let updated_ids: Vec<String> = {
        let mut stmt = conn.prepare_cached("SELECT task_id FROM task_tags WHERE tag_id = ?1")?;
        let rows = stmt.query_map([&old_tag_id], |row| row.get::<_, String>(0))?;
        rows.collect::<Result<Vec<_>, _>>()?
    };

    // Capture the structured pre-state so the changelog row carries
    // the merge metadata. The collision branch deletes a tag row and
    // re-points task_tags edges; without this snapshot the audit log
    // can't reconstruct which two tags merged or how many edges
    // moved.
    let (merge_metadata, survivor_tag_id) = if let Some(conflict_id) = conflict_tag_id.as_deref() {
        let target_task_ids = collect_task_ids_for_tag(conn, conflict_id)?;
        let moved_task_ids = updated_ids
            .iter()
            .filter(|task_id| !target_task_ids.contains(*task_id))
            .cloned()
            .collect::<Vec<_>>();
        let dropped_edge_count = updated_ids.len() - moved_task_ids.len();
        (
            json!({
                "kind": "merge",
                "old_name": old_name_sanitized,
                "new_name": new_display_name,
                "old_tag_id": old_tag_id,
                "conflict_tag_id": conflict_id,
                "moved_edge_count": moved_task_ids.len(),
                "dropped_duplicate_edge_count": dropped_edge_count,
            }),
            conflict_id.to_string(),
        )
    } else {
        (
            json!({
                "kind": "rename",
                "old_name": old_name_sanitized,
                "new_name": new_display_name,
                "tag_id": old_tag_id,
            }),
            old_tag_id.clone(),
        )
    };
    let mut before_json_value = pre_rename_tag_row.clone().unwrap_or_else(|| json!({}));
    if let Some(obj) = before_json_value.as_object_mut() {
        obj.insert("_rename_meta".to_string(), merge_metadata);
    }

    let mutation = RenameTagMutation {
        old_tag_id,
        conflict_tag_id,
        survivor_tag_id: survivor_tag_id.clone(),
        old_name_sanitized,
        new_display_name,
        updated_ids,
        pre_rename_tag_row,
        audit_before: before_json_value,
        now,
    };
    let output = execute_mcp_mutation_with_skip_sync_audit_finalizer(
        conn,
        &mutation,
        "rename_tag",
        survivor_tag_id,
        McpError::from,
        enqueue_rename_tag_sync_actions,
    )?;
    let payload = output
        .get_extra(&TAG_RENAME_RESPONSE)
        .cloned()
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: rename_tag response extra is present".to_string(),
            )
        })?;
    let response = serde_json::to_string(&payload)?;

    // #3033-M2: record the response so a retry against the same
    // request body returns the cached response without re-running
    // the per-task fan-out. The cache row is an INSERT-only audit;
    // a stale entry expires after the configured TTL.
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "rename_tag",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

#[derive(Clone)]
struct RenameTagMutation {
    old_tag_id: String,
    conflict_tag_id: Option<String>,
    survivor_tag_id: String,
    old_name_sanitized: String,
    new_display_name: String,
    updated_ids: Vec<String>,
    pre_rename_tag_row: Option<Value>,
    audit_before: Value,
    now: String,
}

impl Mutation for RenameTagMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TAG
    }

    fn operation(&self) -> &'static str {
        "rename_tag"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.audit_before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        // Preflight the per-task version bumps before mutating tag/task_tags.
        // If any affected task is stale, the rename exits with no tag changes.
        for task_id in &self.updated_ids {
            let task_version = hlc.next_version_string();
            execute_task_lww_update(
                conn,
                "UPDATE tasks
                 SET updated_at = ?1, version = ?2
                 WHERE id = ?3 AND ?2 > version
                 RETURNING 1",
                rusqlite::params![self.now.as_str(), task_version.as_str(), task_id.as_str()],
                task_id,
            )
            .map_err(tag_mcp_error_to_store_error)?;
        }

        let mut sync_actions = if let Some(conflict_id) = self.conflict_tag_id.as_deref() {
            apply_tag_merge(
                conn,
                hlc,
                &self.old_tag_id,
                conflict_id,
                &self.updated_ids,
                &self.pre_rename_tag_row,
                &self.now,
            )?
        } else {
            let version = hlc.next_version_string();
            let typed_old_tag_id = lorvex_domain::TagId::from_trusted(self.old_tag_id.clone());
            tag_repo::rename_tag(
                conn,
                &typed_old_tag_id,
                &self.new_display_name,
                &version,
                &self.now,
            )?;
            vec![RenameTagSyncAction::upsert(
                ENTITY_TAG,
                self.old_tag_id.clone(),
            )]
        };

        // Emit a per-task upsert envelope for every task whose parent-task
        // version bump passed the stale-version preflight above.
        sync_actions.extend(
            self.updated_ids
                .iter()
                .cloned()
                .map(|task_id| RenameTagSyncAction::upsert(ENTITY_TASK, task_id)),
        );

        let post_rename_tag_row = query_one_as_json(
            conn,
            "SELECT * FROM tags WHERE id = ?",
            [&self.survivor_tag_id],
        )?
        .unwrap_or_else(|| json!({ "id": self.survivor_tag_id }));
        let summary = format!(
            "Renamed tag '{}' to '{}' across {} task(s)",
            self.old_name_sanitized,
            self.new_display_name,
            self.updated_ids.len()
        );
        let mut output = MutationOutput::new(post_rename_tag_row, summary);
        output.set_extra(
            &TAG_RENAME_RESPONSE,
            json!({
                "old_name": self.old_name_sanitized,
                "new_name": self.new_display_name,
                "tasks_updated": self.updated_ids.len(),
                "task_ids": self.updated_ids,
            }),
        );
        output.set_extra(
            &TAG_RENAME_SYNC_ACTIONS,
            Value::Array(
                sync_actions
                    .into_iter()
                    .map(RenameTagSyncAction::into_json)
                    .collect(),
            ),
        );
        Ok(output)
    }
}

#[derive(Clone)]
struct RenameTagSyncAction {
    entity_type: &'static str,
    entity_id: String,
    operation: &'static str,
    snapshot: Option<Value>,
}

impl RenameTagSyncAction {
    const fn upsert(entity_type: &'static str, entity_id: String) -> Self {
        Self {
            entity_type,
            entity_id,
            operation: OP_UPSERT,
            snapshot: None,
        }
    }

    const fn delete(entity_type: &'static str, entity_id: String, snapshot: Option<Value>) -> Self {
        Self {
            entity_type,
            entity_id,
            operation: OP_DELETE,
            snapshot,
        }
    }

    fn into_json(self) -> Value {
        json!({
            "entity_type": self.entity_type,
            "entity_id": self.entity_id,
            "operation": self.operation,
            "snapshot": self.snapshot,
        })
    }
}

fn enqueue_rename_tag_sync_actions(
    conn: &Connection,
    execution: &MutationExecution,
) -> Result<(), McpError> {
    let Some(actions_value) = execution.output.get_extra(&TAG_RENAME_SYNC_ACTIONS) else {
        return Ok(());
    };
    let actions = actions_value.as_array().ok_or_else(|| {
        McpError::Internal(
            "Mutation contract: rename_tag sync actions extra is an array".to_string(),
        )
    })?;
    for action in actions {
        let entity_type = action
            .get("entity_type")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "Mutation contract: rename_tag sync action has entity_type".to_string(),
                )
            })?;
        let entity_id = action
            .get("entity_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "Mutation contract: rename_tag sync action has entity_id".to_string(),
                )
            })?;
        let operation = action
            .get("operation")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "Mutation contract: rename_tag sync action has operation".to_string(),
                )
            })?;
        let snapshot = action
            .get("snapshot")
            .filter(|value| !value.is_null())
            .cloned();
        if snapshot.is_some() {
            enqueue_relation_sync_with_snapshot(conn, entity_type, entity_id, operation, snapshot)?;
        } else {
            enqueue_relation_sync(conn, entity_type, entity_id, operation)?;
        }
    }
    Ok(())
}

fn collect_task_ids_for_tag(conn: &Connection, tag_id: &str) -> Result<HashSet<String>, McpError> {
    let mut stmt = conn.prepare_cached("SELECT task_id FROM task_tags WHERE tag_id = ?1")?;
    let rows = stmt.query_map([tag_id], |row| row.get::<_, String>(0))?;
    Ok(rows.collect::<Result<HashSet<_>, _>>()?)
}

/// Merge `old_tag_id` into `conflict_id`: re-point `task_tags` edges
/// from the loser tag to the survivor (dropping duplicate edges that
/// already exist on the survivor), delete the loser tag row, bump the
/// survivor's `updated_at`/`version`, and enqueue the matching
/// sync envelopes (loser-tag DELETE + per-edge DELETE/UPSERT pairs +
/// survivor-tag UPSERT).
///
/// Returns the sync fan-out actions that the MCP finalizer must enqueue
/// after the skip-sync parent audit row lands.
fn apply_tag_merge(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    old_tag_id: &str,
    conflict_id: &str,
    updated_ids: &[String],
    pre_rename_tag_row: &Option<serde_json::Value>,
    now: &str,
) -> Result<Vec<RenameTagSyncAction>, StoreError> {
    let target_task_ids =
        collect_task_ids_for_tag(conn, conflict_id).map_err(tag_mcp_error_to_store_error)?;
    let moved_task_ids = updated_ids
        .iter()
        .filter(|task_id| !target_task_ids.contains(*task_id))
        .cloned()
        .collect::<Vec<_>>();

    // The new name already exists as a different tag.
    // Merge: re-point task_tags from old_tag_id to conflict_id,
    // using batch SQL instead of per-task queries.

    // snapshot the pre-delete state for both the
    // task_tags edges that will be deleted/rewritten AND the
    // tag row itself BEFORE running any DELETE / UPDATE so the
    // sync envelopes carry the full row, not a degenerate
    // `{"id":...}` payload.
    let edge_rows = query_all_as_json(
        conn,
        "SELECT * FROM task_tags WHERE tag_id = ?1",
        [old_tag_id],
    )?;
    let edge_snapshots: std::collections::HashMap<String, serde_json::Value> = edge_rows
        .into_iter()
        .filter_map(|row| {
            let task_id = row.get("task_id").and_then(|v| v.as_str())?.to_string();
            Some((task_id, row))
        })
        .collect();
    let old_tag_snapshot = pre_rename_tag_row.clone();

    // 1. Remove conflict edges (tasks that already have the target tag)
    conn.execute(
        "DELETE FROM task_tags WHERE tag_id = ?1 AND task_id IN \
         (SELECT task_id FROM task_tags WHERE tag_id = ?2)",
        rusqlite::params![old_tag_id, conflict_id],
    )?;

    // 2. Move remaining edges to the new tag
    let moved_edge_version = hlc.next_version_string();
    conn.execute(
        "UPDATE task_tags SET tag_id = ?1, version = ?2 WHERE tag_id = ?3",
        rusqlite::params![conflict_id, moved_edge_version, old_tag_id],
    )?;

    // Delete the now-orphaned old tag row
    conn.execute("DELETE FROM tags WHERE id = ?1", [old_tag_id])?;
    // Update timestamp on the surviving tag
    let conflict_version = hlc.next_version_string();
    conn.execute(
        "UPDATE tags SET updated_at = ?1, version = ?2 WHERE id = ?3",
        rusqlite::params![now, conflict_version, conflict_id],
    )?;

    // Enqueue sync: edge rewrites first, then tag delete/upsert.
    // Each delete envelope carries the pre-delete snapshot
    // captured above (#2818); the upserts on the surviving tag
    // and re-pointed edges read the post-write state.
    let mut sync_actions = Vec::new();
    for task_id in updated_ids {
        let entity_id = format!("{task_id}:{old_tag_id}");
        sync_actions.push(RenameTagSyncAction::delete(
            EDGE_TASK_TAG,
            entity_id,
            edge_snapshots.get(task_id).cloned(),
        ));
    }
    for task_id in &moved_task_ids {
        let entity_id = format!("{task_id}:{conflict_id}");
        sync_actions.push(RenameTagSyncAction::upsert(EDGE_TASK_TAG, entity_id));
    }
    sync_actions.push(RenameTagSyncAction::delete(
        ENTITY_TAG,
        old_tag_id.to_string(),
        old_tag_snapshot,
    ));
    sync_actions.push(RenameTagSyncAction::upsert(
        ENTITY_TAG,
        conflict_id.to_string(),
    ));

    Ok(sync_actions)
}

#[cfg(test)]
mod tests;
