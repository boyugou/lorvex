use super::*;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::hlc_state::HlcState;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::tombstone_edges_for_calendar_event_delete;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES;
use serde_json::{json, Value};

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

struct DeleteCliCalendarEventMutation {
    event_id: lorvex_domain::EventId,
    before: Value,
}

impl Mutation for DeleteCliCalendarEventMutation {
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
        let unlinked_edge_snapshots = tombstone_edges_for_calendar_event_delete(
            conn,
            &self.event_id,
            &edge_tombstone_version,
        )
        .map_err(|error| {
            StoreError::Invariant(format!(
                "calendar event delete edge tombstone write failed: {error}"
            ))
        })?;
        let unlinked_task_ids: Vec<String> = unlinked_edge_snapshots
            .iter()
            .map(|snapshot| snapshot.task_id.as_str().to_string())
            .collect();

        let delete_version = hlc.next_version_string();
        calendar_event_write::delete_calendar_event_lww(
            conn,
            self.event_id.as_str(),
            &delete_version,
        )?;

        let mut output = MutationOutput::new(
            json!({
                "id": self.event_id.as_str(),
                "deleted": true,
                "unlinked_task_ids": unlinked_task_ids,
                "previous": self.before,
            }),
            format!("Deleted calendar event '{title}'"),
        );
        output.set_extra(
            &CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES,
            Value::Array(
                unlinked_edge_snapshots
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

fn log_cli_calendar_event_delete_edge_tombstones(
    tx: &Connection,
    device_id: &str,
    execution: &MutationExecution,
    hlc_state: &mut HlcState,
) -> Result<(), crate::error::CliError> {
    let Some(edge_tombstones) = execution
        .output
        .get_extra(&CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES)
    else {
        return Ok(());
    };
    let edges = edge_tombstones.as_array().ok_or_else(|| {
        crate::error::CliError::Internal(
            "Mutation contract: calendar event delete edge tombstones extra is an array"
                .to_string(),
        )
    })?;
    for edge in edges {
        let edge_entity_id = edge
            .get("entity_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: calendar event delete edge tombstone has entity_id"
                        .to_string(),
                )
            })?;
        edge.get("task_id").and_then(Value::as_str).ok_or_else(|| {
            crate::error::CliError::Internal(
                "Mutation contract: calendar event delete edge tombstone has task_id".to_string(),
            )
        })?;
        let edge_before = edge.get("payload").cloned().ok_or_else(|| {
            crate::error::CliError::Internal(
                "Mutation contract: calendar event delete edge tombstone has payload".to_string(),
            )
        })?;
        let edge_version = hlc_state.generate().to_string();
        enqueue_payload_delete(
            tx,
            EDGE_TASK_CALENDAR_EVENT_LINK,
            edge_entity_id,
            &edge_before,
            crate::commands::shared::bare_outbox_ctx(&edge_version, device_id),
        )?;
        log_cli_changelog_with_state(
            tx,
            hlc_state,
            crate::commands::shared::CliChangelogParams {
                operation: OP_DELETE,
                entity_type: EDGE_TASK_CALENDAR_EVENT_LINK,
                entity_id: edge_entity_id,
                summary: "Unlinked task from calendar event (cascade from calendar event delete)",
                before_json: Some(edge_before),
                after_json: None,
            },
        )?;
    }
    Ok(())
}

pub(crate) fn delete_calendar_event_with_conn(
    conn: &mut Connection,
    event_id: &lorvex_domain::EventId,
) -> Result<DeletedCalendarEventResult, crate::error::CliError> {
    let event_id_str = event_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;
    let before = load_calendar_event_row(&tx, event_id_str)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("calendar event '{event_id_str}' not found"))
    })?;
    let title = before.title.clone();
    let before_payload = serde_json::to_value(&before)?;
    let mutation = DeleteCliCalendarEventMutation {
        event_id: event_id.clone(),
        before: before_payload,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            log_cli_calendar_event_delete_edge_tombstones(&tx, &device_id, &execution, hlc_state)?;
            let before_payload = execution.before.clone().ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: calendar event delete has before payload".to_string(),
                )
            })?;
            let event_version = hlc_state.generate().to_string();
            enqueue_payload_delete(
                &tx,
                execution.entity_kind,
                event_id_str,
                &before_payload,
                crate::commands::shared::bare_outbox_ctx(&event_version, &device_id),
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: event_id_str,
                    summary: &execution.output.summary,
                    before_json: Some(before_payload),
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let unlinked_task_ids = output
        .after
        .get("unlinked_task_ids")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            crate::error::CliError::Internal(
                "Mutation contract: calendar event delete returns unlinked_task_ids array"
                    .to_string(),
            )
        })?
        .iter()
        .map(|value| {
            value.as_str().map(str::to_string).ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: calendar event delete task id is a string".to_string(),
                )
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(DeletedCalendarEventResult {
        id: event_id.to_string(),
        title,
        deleted: true,
        unlinked_task_ids,
    })
}
