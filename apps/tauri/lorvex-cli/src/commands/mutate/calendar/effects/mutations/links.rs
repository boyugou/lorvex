use super::*;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::{EventId, TaskId};
use lorvex_store::repositories::task::calendar_links::TaskCalendarEventLink;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use serde_json::Value;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

struct LinkCliTasksToCalendarEventMutation {
    event_id: EventId,
    task_ids: Vec<TaskId>,
}

impl Mutation for LinkCliTasksToCalendarEventMutation {
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
        let now = lorvex_domain::sync_timestamp_now();
        let mut links = Vec::with_capacity(self.task_ids.len());
        for task_id in &self.task_ids {
            let link_version = hlc.next_version_string();
            let (link, applied) =
                calendar_links::insert_link(conn, task_id, &self.event_id, &link_version, &now)?;
            if !applied {
                return Err(StoreError::StaleVersion {
                    entity: EDGE_TASK_CALENDAR_EVENT_LINK,
                    id: format!("{}:{}", task_id.as_str(), self.event_id.as_str()),
                });
            }
            links.push(link);
        }
        Ok(MutationOutput::new(
            serde_json::to_value(&links)?,
            format!(
                "Linked {} task(s) to calendar event '{}'",
                self.task_ids.len(),
                self.event_id.as_str()
            ),
        ))
    }
}

struct UnlinkCliTaskFromCalendarEventMutation {
    task_id: TaskId,
    event_id: EventId,
    tombstone_payload: Value,
}

impl Mutation for UnlinkCliTaskFromCalendarEventMutation {
    fn entity_kind(&self) -> &'static str {
        EDGE_TASK_CALENDAR_EVENT_LINK
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.tombstone_payload.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let deleted = calendar_links::delete_link(conn, &self.task_id, &self.event_id)?;
        if deleted == 0 {
            return Err(StoreError::NotFound {
                entity: EDGE_TASK_CALENDAR_EVENT_LINK,
                id: format!("{}:{}", self.task_id.as_str(), self.event_id.as_str()),
            });
        }
        let now = lorvex_domain::sync_timestamp_now();
        let parent_version = hlc.next_version_string();
        lorvex_workflow::task_reminders::touch_parent_task_op(
            conn,
            &self.task_id,
            &parent_version,
            &now,
        )?;
        let remaining_links = calendar_links::get_links_for_task(conn, &self.task_id)?;
        Ok(MutationOutput::new(
            serde_json::to_value(&remaining_links)?,
            format!(
                "Unlinked task '{}' from calendar event '{}'",
                self.task_id.as_str(),
                self.event_id.as_str()
            ),
        ))
    }
}

pub(crate) fn link_tasks_to_calendar_event_with_conn(
    conn: &mut Connection,
    event_id: &EventId,
    task_ids: &[String],
) -> Result<CalendarLinkTasksResult, crate::error::CliError> {
    let event_id_str = event_id.as_str();
    let task_ids = normalize_calendar_link_task_ids(task_ids)?;
    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;

    ensure_calendar_event_exists(&tx, event_id_str)?;
    for task_id in &task_ids {
        ensure_task_exists(&tx, task_id)?;
    }
    // Issue #3285: clap already validated UUID shape at the CLI
    // boundary (`parse_uuid_id`); reuse the validated strings as
    // typed ids without re-parsing.
    let typed_task_ids: Vec<TaskId> = task_ids
        .iter()
        .map(|s| TaskId::from_trusted(s.clone()))
        .collect();
    let mutation = LinkCliTasksToCalendarEventMutation {
        event_id: event_id.clone(),
        task_ids: typed_task_ids,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let after_links = execution.output.after.as_array().ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: calendar task link returns link array".to_string(),
                )
            })?;
            for (task_id, after_json) in task_ids.iter().zip(after_links.iter()) {
                let link: TaskCalendarEventLink = serde_json::from_value(after_json.clone())?;
                let entity_id = format!("{task_id}:{event_id_str}");
                let created_at = link.created_at.as_string();
                let updated_at = link.updated_at.as_string();
                let payload = lorvex_store::payload_loaders::task_calendar_event_link_payload(
                    &TaskId::from_trusted(link.task_id),
                    &EventId::from_trusted(link.calendar_event_id),
                    &link.version,
                    &created_at,
                    &updated_at,
                );
                let outbox_version = hlc_state.generate().to_string();
                enqueue_payload_upsert(
                    &tx,
                    execution.entity_kind,
                    &entity_id,
                    &payload,
                    crate::commands::shared::bare_outbox_ctx(&outbox_version, &device_id),
                )?;
                log_cli_changelog_with_state(
                    &tx,
                    hlc_state,
                    crate::commands::shared::CliChangelogParams {
                        operation: execution.operation,
                        entity_type: execution.entity_kind,
                        entity_id: &entity_id,
                        summary: &format!(
                            "Linked task '{task_id}' to calendar event '{event_id_str}'"
                        ),
                        before_json: None,
                        after_json: Some(after_json.clone()),
                    },
                )?;
            }
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let links: Vec<TaskCalendarEventLink> = serde_json::from_value(output.after)?;
    drop(hlc_guard);
    tx.commit()?;

    Ok(CalendarLinkTasksResult {
        event_id: event_id_str.to_string(),
        linked_count: links.len(),
        links,
    })
}

pub(crate) fn unlink_task_from_calendar_event_with_conn(
    conn: &mut Connection,
    event_id: &EventId,
    task_id: &TaskId,
) -> Result<CalendarUnlinkTaskResult, crate::error::CliError> {
    let event_id_str = event_id.as_str();
    let task_id_str = task_id.as_str().trim();
    if task_id_str.is_empty() {
        return Err(crate::error::CliError::Validation(
            "task id must not be empty".to_string(),
        ));
    }
    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;

    ensure_calendar_event_exists(&tx, event_id_str)?;
    ensure_task_exists(&tx, task_id_str)?;

    let existing = calendar_links::get_link(&tx, task_id, event_id)?;
    // if no link exists for `(task_id, event_id)`,
    // rollback the immediate-mode tx instead of committing an empty
    // one.
    // DELETE, captured `deleted = false`, and then `tx.commit()`-ed
    // — same M11 class as preferences (#2905-M11) and habit-reminder
    // policy (#2969-H7).
    let Some(existing) = existing else {
        tx.rollback()?;
        let remaining_links = calendar_links::get_links_for_task(conn, task_id)?;
        return Ok(CalendarUnlinkTaskResult {
            task_id: task_id_str.to_string(),
            event_id: event_id_str.to_string(),
            deleted: false,
            remaining_links,
        });
    };
    let entity_id = format!("{task_id_str}:{event_id_str}");
    let tombstone_payload = lorvex_store::payload_loaders::task_calendar_event_link_payload(
        &TaskId::from_trusted(existing.task_id.clone()),
        &EventId::from_trusted(existing.calendar_event_id.clone()),
        &existing.version,
        &existing.created_at.as_string(),
        &existing.updated_at.as_string(),
    );
    let mutation = UnlinkCliTaskFromCalendarEventMutation {
        task_id: task_id.clone(),
        event_id: event_id.clone(),
        tombstone_payload,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(&tx, ENTITY_TASK, task_id_str, hlc_state, &device_id)?;
            let tombstone_version = hlc_state.generate().to_string();
            let tombstone_payload = execution.before.clone().ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: calendar task unlink has tombstone payload".to_string(),
                )
            })?;
            enqueue_payload_delete(
                &tx,
                execution.entity_kind,
                &entity_id,
                &tombstone_payload,
                crate::commands::shared::bare_outbox_ctx(&tombstone_version, &device_id),
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &entity_id,
                    summary: &execution.output.summary,
                    before_json: Some(tombstone_payload),
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let remaining_links: Vec<TaskCalendarEventLink> = serde_json::from_value(output.after)?;
    drop(hlc_guard);
    tx.commit()?;

    Ok(CalendarUnlinkTaskResult {
        task_id: task_id_str.to_string(),
        event_id: event_id_str.to_string(),
        deleted: true,
        remaining_links,
    })
}
