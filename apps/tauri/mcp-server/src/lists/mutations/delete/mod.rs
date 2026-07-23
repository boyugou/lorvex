use super::*;
use crate::runtime::change_tracking::execute_mcp_mutation_with_undo_tombstone_audit_finalizer;
use crate::runtime::undo::{compute_undo_expiry, McpUndoKind, McpUndoToken};
use crate::tasks::validation::validate_list_exists;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::repositories::list_repo;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use std::collections::HashMap;

struct DeleteListMutation {
    id: lorvex_domain::ListId,
    before: Value,
    list_name: String,
}

impl Mutation for DeleteListMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let delete_version = hlc.next_version_string();
        let deleted = list_repo::delete_list_lww(conn, &self.id, &delete_version)?;
        if deleted == 0 {
            return Err(StoreError::NotFound {
                entity: ENTITY_LIST,
                id: self.id.to_string(),
            });
        }
        Ok(MutationOutput::new(
            json!({
                "deleted": true,
                "deleted_list_id": self.id.as_str(),
                "previous": self.before,
            }),
            format!("Deleted list \"{}\"", self.list_name),
        ))
    }
}

pub(crate) fn delete_list(conn: &Connection, args: DeleteListArgs) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint before destructure so a retry returns the cached
    // response without re-emitting tombstone + audit envelopes.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let DeleteListArgs {
        id,
        // `dry_run` is consumed at the router layer (#2370).
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "delete_list",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // #3684 — defense-in-depth pre-check that the list exists before
    // we acquire the write lock. The SELECT below would also surface
    // a NotFound, but routing through `validate_list_exists` keeps the
    // runtime contract consistent with #3607 audit's claim
    // ("membership-based via validate_list_exists") — every list-ID
    // mutation surface flows through the same membership predicate.
    validate_list_exists(conn, Some(&id))?;

    // Force the SQLite write lock early within the caller's SAVEPOINT.
    // Without this, the deferred transaction only acquires the write lock
    // on the first actual write (the DELETE below), leaving our guard reads
    // (list existence, last-list check, active-task count) unprotected
    // against concurrent Tauri app transactions that could invalidate them.
    // This no-op UPDATE is the lightest way to acquire exclusive write access.
    conn.prepare_cached("UPDATE lists SET updated_at = updated_at WHERE id = ?1")?
        .execute([&id])?;

    let before = query_one_as_json(conn, "SELECT * FROM lists WHERE id = ?", [id.clone()])?
        .ok_or_else(|| McpError::NotFound(format!("List '{id}' not found")))?;
    let list_name = before
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("unknown")
        .to_string();

    // Prevent deleting the last list — at least one must exist for task creation.
    let total_lists: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM lists")?
        .query_row([], |row| row.get(0))?;
    if total_lists <= 1 {
        return Err(McpError::Validation(
            "Cannot delete the last list. At least one list must exist for task creation."
                .to_string(),
        ));
    }

    let id_typed = lorvex_domain::ListId::from_trusted(id.clone());
    let assigned_task_count = list_repo::count_assigned_tasks_in_list(conn, &id_typed)?;
    if assigned_task_count > 0 {
        return Err(McpError::Validation(format!(
            "Cannot delete list \"{list_name}\" while {assigned_task_count} task(s) are still assigned. Reassign or permanently delete those tasks first."
        )));
    }
    // Build an undo token snapshotting the pre-delete list row so a
    // reverse write can re-insert it. `expires_at` bounds the window in
    // which the token stays actionable.
    let expires_at = compute_undo_expiry();
    let undo = McpUndoToken::delete_entity(
        McpUndoKind::DeleteList,
        "delete_list",
        id.clone(),
        before.clone(),
        expires_at,
    );
    let undo_token_json = undo.to_json_string()?;

    // thread the pre-delete row through the
    // outbox tombstone payload AND the changelog `before_json` slot.
    // Without this, the per-entity outbox loop in the funnel would
    // re-read the (now-deleted) row and ship `{"id": id}` — a
    // degenerate envelope peers cannot reconstruct from for their own
    // before_json audit row.
    let mut tombstones: HashMap<String, serde_json::Value> = HashMap::with_capacity(1);
    tombstones.insert(id.clone(), before.clone());

    let mutation = DeleteListMutation {
        id: id_typed,
        before,
        list_name,
    };
    let mut output = execute_mcp_mutation_with_undo_tombstone_audit_finalizer(
        conn,
        &mutation,
        "delete_list",
        id,
        undo_token_json.clone(),
        tombstones,
        McpError::from,
        |_, _| Ok(()),
    )?;

    // #3029-M6: canonical delete-response shape
    // `{deleted: bool, previous: snapshot}`.
    // overloaded `deleted` as the snapshot (truthy object) while
    // sibling deletes (`delete_calendar_event`, `delete_habit`,
    // `permanent_delete_task`) returned a boolean — three different
    // shapes for the same concept. Now every delete tool reports
    // `{deleted: true, previous: <pre-delete row>, ...}`.
    if let Some(object) = output.after.as_object_mut() {
        // Return the serialized undo token so a caller can drive a
        // reverse write; `expires_at` within the token bounds how long
        // it stays actionable.
        object.insert("undo_token".to_string(), json!(undo_token_json));
    }
    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "delete_list",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

#[cfg(test)]
mod tests;
