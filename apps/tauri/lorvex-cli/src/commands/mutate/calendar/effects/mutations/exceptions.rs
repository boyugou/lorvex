use super::*;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use serde_json::Value;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

#[derive(Debug, Clone, Copy)]
enum ExceptionOp {
    Add,
    Remove,
}

struct AddCliCalendarEventExceptionMutation {
    event_id: lorvex_domain::EventId,
    date: String,
    now: String,
    before_json: Option<Value>,
}

impl Mutation for AddCliCalendarEventExceptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before_json.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        calendar_event_exceptions::add_recurrence_exception(
            conn,
            &self.event_id,
            &self.date,
            &version,
            &self.now,
        )?;
        calendar_event_after_output(
            conn,
            self.event_id.as_str(),
            &format!("Added recurrence exception {}", self.date),
        )
    }
}

struct RemoveCliCalendarEventExceptionMutation {
    event_id: lorvex_domain::EventId,
    date: String,
    now: String,
    before_json: Option<Value>,
}

impl Mutation for RemoveCliCalendarEventExceptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before_json.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        calendar_event_exceptions::remove_recurrence_exception(
            conn,
            &self.event_id,
            &self.date,
            &version,
            &self.now,
        )?;
        calendar_event_after_output(
            conn,
            self.event_id.as_str(),
            &format!("Removed recurrence exception {}", self.date),
        )
    }
}

fn calendar_event_after_output(
    conn: &Connection,
    event_id: &str,
    summary: &str,
) -> Result<MutationOutput, StoreError> {
    let event = lorvex_store::calendar_timeline::queries::get_calendar_event(conn, event_id)?
        .ok_or_else(|| StoreError::NotFound {
            entity: ENTITY_CALENDAR_EVENT,
            id: event_id.to_string(),
        })?;
    Ok(MutationOutput::new(serde_json::to_value(&event)?, summary))
}

fn mutate_recurrence_exception(
    conn: &mut Connection,
    event_id: &lorvex_domain::EventId,
    date: &str,
    op: ExceptionOp,
) -> Result<lorvex_store::calendar_timeline::CalendarEventRow, crate::error::CliError> {
    validate_calendar_date(date)?;
    let event_id_str = event_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;
    // snapshot pre-mutation row for the audit trail.
    let before = load_calendar_event_row(&tx, event_id_str)?;
    let before_json = before.as_ref().map(serde_json::to_value).transpose()?;
    let now = lorvex_domain::sync_timestamp_now();
    let mut hlc_guard = lock_shared(&tx)?;
    match op {
        ExceptionOp::Add => {
            let mutation = AddCliCalendarEventExceptionMutation {
                event_id: event_id.clone(),
                date: date.to_string(),
                now,
                before_json,
            };
            execute_calendar_event_exception_mutation(
                &tx,
                &mut hlc_guard,
                &device_id,
                event_id_str,
                &mutation,
            )?;
        }
        ExceptionOp::Remove => {
            let mutation = RemoveCliCalendarEventExceptionMutation {
                event_id: event_id.clone(),
                date: date.to_string(),
                now,
                before_json,
            };
            execute_calendar_event_exception_mutation(
                &tx,
                &mut hlc_guard,
                &device_id,
                event_id_str,
                &mutation,
            )?;
        }
    }
    let event = load_calendar_event_row(&tx, event_id_str)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!(
            "calendar event '{event_id_str}' not found after update"
        ))
    })?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(event)
}

fn execute_calendar_event_exception_mutation<M: Mutation>(
    tx: &Connection,
    hlc_guard: &mut crate::hlc_guard::SharedHlcGuard,
    device_id: &str,
    event_id: &str,
    mutation: &M,
) -> Result<(), crate::error::CliError> {
    execute_cli_mutation_with_finalizer(
        tx,
        hlc_guard,
        mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(tx, ENTITY_CALENDAR_EVENT, event_id, hlc_state, device_id)?;
            log_cli_changelog_with_state(
                tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: event_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(tx)?;
            Ok(())
        },
    )?;
    Ok(())
}

pub(crate) fn add_calendar_event_exception_with_conn(
    conn: &mut Connection,
    event_id: &lorvex_domain::EventId,
    date: &str,
) -> Result<lorvex_store::calendar_timeline::CalendarEventRow, crate::error::CliError> {
    mutate_recurrence_exception(conn, event_id, date, ExceptionOp::Add)
}

pub(crate) fn remove_calendar_event_exception_with_conn(
    conn: &mut Connection,
    event_id: &lorvex_domain::EventId,
    date: &str,
) -> Result<lorvex_store::calendar_timeline::CalendarEventRow, crate::error::CliError> {
    mutate_recurrence_exception(conn, event_id, date, ExceptionOp::Remove)
}
