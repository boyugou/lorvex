use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use lorvex_domain::naming::{EDGE_TASK_CALENDAR_EVENT_LINK, OP_DELETE};
use lorvex_domain::{EventId, TaskId};
use lorvex_store::repositories::task::calendar_links::{self, TaskCalendarEventLink};

use crate::contract::{
    BatchLinkTasksToEventArgs, GetLinkedEventsForTaskArgs, GetLinkedTasksForEventArgs,
    LinkTaskToEventArgs, UnlinkTaskFromEventArgs,
};
use crate::runtime::change_tracking::{
    execute_mcp_mutation_with_audit_entries_finalizer,
    execute_mcp_mutation_with_skippable_audit_finalizer,
    execute_mcp_mutation_with_tombstone_audit_finalizer, MutationAuditEntry,
};
use crate::system::handler_support::utc_now_iso;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::{
    TASK_CALENDAR_EVENT_LINK_APPLIED, TASK_CALENDAR_EVENT_LINK_APPLIED_ROWS,
};
use rusqlite::{params, params_from_iter, Connection};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

struct LinkTaskToEventMutation<'a> {
    task_id: &'a TaskId,
    event_id: &'a EventId,
}

impl<'a> Mutation for LinkTaskToEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_CALENDAR_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        "link"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        calendar_links::get_link(conn, self.task_id, self.event_id)?
            .map(serde_json::to_value)
            .transpose()
            .map_err(|error| StoreError::Serialization(error.to_string()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = utc_now_iso();
        let version = hlc.next_version_string();
        let (link, applied) =
            calendar_links::insert_link(conn, self.task_id, self.event_id, &version, &now)?;
        let mut output = MutationOutput::new(
            serde_json::to_value(&link)
                .map_err(|error| StoreError::Serialization(error.to_string()))?,
            format!(
                "Linked task {} to event {}",
                link.task_id, link.calendar_event_id
            ),
        );
        output.set_extra(&TASK_CALENDAR_EVENT_LINK_APPLIED, Value::Bool(applied));
        Ok(output)
    }
}

struct UnlinkTaskFromEventMutation<'a> {
    task_id: &'a TaskId,
    event_id: &'a EventId,
    before: Option<Value>,
}

impl<'a> Mutation for UnlinkTaskFromEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_CALENDAR_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let deleted = calendar_links::delete_link(conn, self.task_id, self.event_id)?;
        if deleted > 0 && self.before.is_none() {
            return Err(StoreError::Invariant(format!(
                "task_calendar_event_links row {}:{} was deleted but no pre-delete snapshot was loaded",
                self.task_id, self.event_id
            )));
        }
        let links = calendar_links::get_links_for_task(conn, self.task_id)?;
        let payload = json!({
            "deleted": deleted > 0,
            "task_id": self.task_id,
            "event_id": self.event_id,
            "links": links,
        });

        Ok(MutationOutput::new(
            payload,
            format!(
                "Unlinked task {} from event {}",
                self.task_id, self.event_id
            ),
        ))
    }
}

struct BatchLinkTasksToEventMutation<'a> {
    task_ids: &'a [TaskId],
    event_id: &'a EventId,
}

impl<'a> Mutation for BatchLinkTasksToEventMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_CALENDAR_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        "link"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = utc_now_iso();
        let mut links: Vec<TaskCalendarEventLink> = Vec::new();
        let mut applied_rows: Vec<Value> = Vec::new();

        for task_id in self.task_ids {
            let version = hlc.next_version_string();
            let (link, applied) =
                calendar_links::insert_link(conn, task_id, self.event_id, &version, &now)?;
            let link_json = serde_json::to_value(&link)
                .map_err(|error| StoreError::Serialization(error.to_string()))?;
            if applied {
                applied_rows.push(link_json);
            }
            links.push(link);
        }

        let mut output = MutationOutput::new(
            json!({
                "linked_count": links.len(),
                "links": links,
            }),
            format!(
                "Linked {} tasks to event {}",
                self.task_ids.len(),
                self.event_id
            ),
        );
        output.set_extra(
            &TASK_CALENDAR_EVENT_LINK_APPLIED_ROWS,
            Value::Array(applied_rows),
        );
        Ok(output)
    }
}

pub(crate) fn link_task_to_event(
    conn: &Connection,
    args: LinkTaskToEventArgs,
) -> Result<String, McpError> {
    // #3029-M4: capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let LinkTaskToEventArgs {
        task_id,
        event_id,
        idempotency_key,
        // #3033-H5: dry_run is consumed at the router layer via
        // `dispatch_dry_run`; the body sees a normal call and the
        // savepoint rolls back if the flag was true.
        dry_run: _,
    } = args;
    // UUID-shape validation already ran at the MCP contract boundary;
    // lift the canonical strings to typed newtypes for the store call.
    let task_id = TaskId::from_trusted(task_id);
    let event_id = EventId::from_trusted(event_id);
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "link_task_to_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    if !lorvex_store::task_exists_active(conn, &task_id)? {
        return Err(McpError::NotFound(format!("task not found: {task_id}")));
    }

    // Verify event exists
    let event_exists: bool = conn
        .prepare_cached("SELECT 1 FROM calendar_events WHERE id = ?1")
        .and_then(|mut stmt| stmt.exists(params![event_id]))?;
    if !event_exists {
        return Err(McpError::NotFound(format!(
            "calendar event not found: {event_id}"
        )));
    }

    let mutation = LinkTaskToEventMutation {
        task_id: &task_id,
        event_id: &event_id,
    };
    let output = execute_mcp_mutation_with_skippable_audit_finalizer(
        conn,
        &mutation,
        "link_task_to_event",
        format!("{task_id}:{event_id}"),
        McpError::from,
        |execution| {
            execution
                .output
                .get_extra(&TASK_CALENDAR_EVENT_LINK_APPLIED)
                .and_then(Value::as_bool)
                .unwrap_or(true)
        },
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;

    // #3033-M12: changelog write runs at line 94 BEFORE the cache
    // record below, and BOTH ride the outer `with_conn` BEGIN
    // IMMEDIATE + `mcp_tool` savepoint that wraps every MCP write.
    // A panic or rollback between them rolls back BOTH the cache
    // row and the changelog row atomically — there is no surface
    // where the cache could promise a write that never made the
    // audit log. Audit comment, no behavior change.
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "link_task_to_event",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

pub(crate) fn unlink_task_from_event(
    conn: &Connection,
    args: UnlinkTaskFromEventArgs,
) -> Result<String, McpError> {
    // #3029-M4: idempotency cache. Cf. `link_task_to_event`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let UnlinkTaskFromEventArgs {
        task_id,
        event_id,
        idempotency_key,
        // #3033-H5: dry_run is consumed at the router layer via
        // `dispatch_dry_run`; the body sees a normal call.
        dry_run: _,
    } = args;
    let task_id = TaskId::from_trusted(task_id);
    let event_id = EventId::from_trusted(event_id);
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "unlink_task_from_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let pre_delete_edge: Option<TaskCalendarEventLink> =
        calendar_links::get_link(conn, &task_id, &event_id)?;
    let before_json = pre_delete_edge
        .as_ref()
        .map(serde_json::to_value)
        .transpose()?;
    let entity_id = format!("{task_id}:{event_id}");
    let tombstones = before_json
        .as_ref()
        .map(|snapshot| {
            let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
            tombstones.insert(entity_id.clone(), snapshot.clone());
            tombstones
        })
        .unwrap_or_default();

    let mutation = UnlinkTaskFromEventMutation {
        task_id: &task_id,
        event_id: &event_id,
        before: before_json,
    };
    let output = execute_mcp_mutation_with_tombstone_audit_finalizer(
        conn,
        &mutation,
        "unlink_task_from_event",
        entity_id,
        tombstones,
        McpError::from,
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "unlink_task_from_event",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

pub(crate) fn get_linked_events_for_task(
    conn: &Connection,
    args: GetLinkedEventsForTaskArgs,
) -> Result<String, McpError> {
    args.validate_shape()?;
    let task_id = TaskId::from_trusted(args.task_id);
    let links = calendar_links::get_links_for_task(conn, &task_id)?;

    Ok(serde_json::to_string(&links)?)
}

pub(crate) fn get_linked_tasks_for_event(
    conn: &Connection,
    args: GetLinkedTasksForEventArgs,
) -> Result<String, McpError> {
    args.validate_shape()?;
    let event_id = EventId::from_trusted(args.event_id);
    let links = calendar_links::get_links_for_event(conn, &event_id)?;

    Ok(serde_json::to_string(&links)?)
}

pub(crate) fn batch_link_tasks_to_event(
    conn: &Connection,
    args: BatchLinkTasksToEventArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let BatchLinkTasksToEventArgs {
        task_ids,
        event_id,
        idempotency_key,
    } = args;
    let event_id = EventId::from_trusted(event_id);
    let task_ids: Vec<TaskId> = task_ids.into_iter().map(TaskId::from_trusted).collect();
    // see batch_complete_tasks for rationale.
    if task_ids.is_empty() {
        return Err(McpError::Validation(
            "task_ids must contain at least one item".to_string(),
        ));
    }
    if task_ids.len() > 500 {
        return Err(McpError::Validation(format!(
            "batch_link_tasks_to_event supports at most 500 items, got {}",
            task_ids.len()
        )));
    }

    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_link_tasks_to_event",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // Verify event exists.
    let event_exists: bool = conn
        .prepare_cached("SELECT 1 FROM calendar_events WHERE id = ?1")
        .and_then(|mut stmt| stmt.exists(params![event_id]))?;
    if !event_exists {
        return Err(McpError::NotFound(format!(
            "calendar event not found: {event_id}"
        )));
    }

    // Verify all task ids exist with a single SELECT ... IN (...) roundtrip
    // instead of one query per id (#2751).
    let placeholders = lorvex_domain::sql_csv_placeholders(task_ids.len());
    let existence_sql =
        format!("SELECT id FROM tasks WHERE id IN ({placeholders}) AND archived_at IS NULL");
    let mut existence_stmt = conn.prepare(&existence_sql)?;
    let found: HashSet<String> = existence_stmt
        .query_map(params_from_iter(task_ids.iter()), |row| {
            row.get::<_, String>(0)
        })?
        .collect::<Result<_, _>>()?;
    drop(existence_stmt);
    for task_id in &task_ids {
        if !found.contains(task_id.as_str()) {
            return Err(McpError::NotFound(format!("task not found: {task_id}")));
        }
    }

    let mutation = BatchLinkTasksToEventMutation {
        task_ids: &task_ids,
        event_id: &event_id,
    };
    let output = execute_mcp_mutation_with_audit_entries_finalizer(
        conn,
        &mutation,
        "batch_link_tasks_to_event",
        McpError::from,
        |execution| {
            let rows = execution
                .output
                .get_extra(&TASK_CALENDAR_EVENT_LINK_APPLIED_ROWS)
                .and_then(Value::as_array)
                .ok_or_else(|| {
                    McpError::Internal(format!(
                        "Mutation contract: {} stamped by batch link apply",
                        TASK_CALENDAR_EVENT_LINK_APPLIED_ROWS.as_str()
                    ))
                })?;
            rows.iter()
                .map(|row| {
                    let task_id = row.get("task_id").and_then(Value::as_str).ok_or_else(|| {
                        McpError::Internal(
                            "task_calendar_event_link audit row missing task_id".to_string(),
                        )
                    })?;
                    let event_id = row
                        .get("calendar_event_id")
                        .and_then(Value::as_str)
                        .ok_or_else(|| {
                            McpError::Internal(
                                "task_calendar_event_link audit row missing calendar_event_id"
                                    .to_string(),
                            )
                        })?;
                    Ok(MutationAuditEntry::new(
                        format!("{task_id}:{event_id}"),
                        row.clone(),
                        format!("Linked task {task_id} to event {event_id}"),
                    ))
                })
                .collect()
        },
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_link_tasks_to_event",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

#[cfg(test)]
mod tests;
