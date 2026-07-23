use super::*;
use crate::runtime::change_tracking::{
    execute_mcp_mutation_with_tombstone_audit_finalizer, log_change, LogChangeParams,
};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK;
use lorvex_store::repositories::calendar_event_write;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::tombstone_edges_for_calendar_event_delete;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES;
use std::collections::HashMap;

struct DeleteCalendarEventMutation {
    id: String,
    before: Value,
}

impl Mutation for DeleteCalendarEventMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let title = self
            .before
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("unknown");

        let edge_tombstone_version = hlc.next_version_string();
        let event_id_typed = lorvex_domain::EventId::from_trusted(self.id.clone());
        let orphaned_edges = tombstone_edges_for_calendar_event_delete(
            conn,
            &event_id_typed,
            &edge_tombstone_version,
        )
        .map_err(|error| {
            StoreError::Invariant(format!(
                "calendar event delete edge tombstone write failed: {error}"
            ))
        })?;
        let orphaned_task_ids: Vec<String> = orphaned_edges
            .iter()
            .map(|snapshot| snapshot.task_id.as_str().to_string())
            .collect();

        let delete_version = hlc.next_version_string();
        calendar_event_write::delete_calendar_event_lww(conn, &self.id, &delete_version)?;

        let link_part = if orphaned_task_ids.is_empty() {
            String::new()
        } else {
            format!(
                " ({} task link{} removed)",
                orphaned_task_ids.len(),
                if orphaned_task_ids.len() == 1 {
                    ""
                } else {
                    "s"
                }
            )
        };
        let mut output = MutationOutput::new(
            json!({
                "id": self.id,
                "deleted": true,
                "unlinked_task_ids": orphaned_task_ids,
                "previous": self.before,
            }),
            format!("Deleted calendar event '{title}'{link_part}"),
        );
        output.set_extra(
            &CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES,
            Value::Array(
                orphaned_edges
                    .iter()
                    .map(|edge| {
                        json!({
                            "entity_id": edge.entity_id(),
                            "task_id": edge.task_id.as_str(),
                            "payload": edge.payload(),
                        })
                    })
                    .collect(),
            ),
        );
        Ok(output)
    }
}

fn log_calendar_event_delete_edge_tombstones(
    conn: &Connection,
    execution: &MutationExecution,
) -> Result<(), McpError> {
    let Some(edge_tombstones) = execution
        .output
        .get_extra(&CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES)
    else {
        return Ok(());
    };
    let edges = edge_tombstones.as_array().ok_or_else(|| {
        McpError::Internal(
            "Mutation contract: calendar event delete edge tombstones extra is an array"
                .to_string(),
        )
    })?;
    let title = execution
        .output
        .after
        .get("previous")
        .and_then(|previous| previous.get("title"))
        .and_then(Value::as_str)
        .unwrap_or("unknown");

    for edge in edges {
        let edge_entity_id = edge
            .get("entity_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "Mutation contract: calendar event delete edge tombstone has entity_id"
                        .to_string(),
                )
            })?;
        let task_id = edge.get("task_id").and_then(Value::as_str).ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: calendar event delete edge tombstone has task_id".to_string(),
            )
        })?;
        let edge_snapshot = edge.get("payload").cloned().ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: calendar event delete edge tombstone has payload".to_string(),
            )
        })?;
        let mut edge_tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        edge_tombstones.insert(edge_entity_id.to_string(), edge_snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                EDGE_TASK_CALENDAR_EVENT_LINK,
                "delete_calendar_event",
                format!("Unlinked task '{task_id}' from calendar event '{title}' (cascade)"),
            )
            .with_entity_id(edge_entity_id.to_string())
            .with_before(edge_snapshot),
            Some(&edge_tombstones),
        )?;
    }
    Ok(())
}

pub(crate) fn delete_calendar_event(
    conn: &Connection,
    args: DeleteCalendarEventArgs,
) -> Result<String, McpError> {
    // capture canonical idempotency
    // Fingerprint BEFORE destructure so a retry returns the cached
    // response without re-emitting parent + per-edge tombstone
    // envelopes. Without the idempotency_key, a retry after the
    // response leg dropped in flight would surface `NotFound` cleanly
    // on the second call (the row is gone), but the FIRST call's
    // per-edge tombstones plus the parent envelope would still emit,
    // and the retry would produce another set that raced peers.
    // Aligns with `update_calendar_event`, `add_event_exception`,
    // `remove_event_exception`, `link_task_to_event`,
    // `unlink_task_from_event`, `batch_link_tasks_to_event`, and
    // `batch_create_calendar_events`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // dry_run is consumed by the router-level
    // `dispatch_dry_run` wrapper before this body runs. The body
    // itself is unaware of preview semantics — it must execute
    // identically in real and preview modes.
    let DeleteCalendarEventArgs {
        id,
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "delete_calendar_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let before = load_calendar_event_json(conn, &id)?;
    let Some(before) = before else {
        return Err(McpError::NotFound(format!(
            "Calendar event '{id}' not found"
        )));
    };

    // also thread the pre-delete event row through
    // the parent's outbox tombstone payload. The funnel was already
    // logging `before_json` here, but the per-entity
    // outbox loop's read-or-default fallback was producing a
    // degenerate envelope after the row had been deleted.
    let mut event_tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
    event_tombstones.insert(id.clone(), before.clone());
    // Carry the pre-delete snapshot into the changelog so the UI
    // diff renderer can show what was deleted, and so the
    // assistant has the full prior state to narrate (RRULE
    // config, attendees, links). Mirrors `delete_habit` /
    // `delete_list`.
    let mutation = DeleteCalendarEventMutation {
        id: id.clone(),
        before,
    };
    let output = execute_mcp_mutation_with_tombstone_audit_finalizer(
        conn,
        &mutation,
        "delete_calendar_event",
        id,
        event_tombstones,
        McpError::from,
        log_calendar_event_delete_edge_tombstones,
    )?;

    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "delete_calendar_event",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
