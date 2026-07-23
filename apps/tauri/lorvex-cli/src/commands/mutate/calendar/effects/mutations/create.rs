//! Thin CLI adapter for calendar-event creation.
//!
//! Translates the CLI's borrowed-`Cow` field bundle into the canonical
//! [`lorvex_workflow::calendar_event::CalendarEventCreateInput`] and
//! delegates validation, normalization, recurrence anchoring, and the
//! row insert to [`CreateCalendarEventMutation`]. The CLI owns the
//! per-surface finalizer pieces (transaction handling, outbox enqueue,
//! `ai_changelog` write, `local_change_seq` bump).

use super::*;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use lorvex_workflow::calendar_event::{
    CalendarEventCreateInput as WorkflowCreateInput, CalendarEventOpError,
    CreateCalendarEventMutation,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

fn map_op_error(error: CalendarEventOpError) -> crate::error::CliError {
    match error {
        CalendarEventOpError::Validation(message) => crate::error::CliError::Validation(message),
        CalendarEventOpError::Store(store_error) => store_error.into(),
    }
}

fn workflow_input_from_fields(
    fields: &CalendarEventCreateFields<'_>,
) -> Result<WorkflowCreateInput, crate::error::CliError> {
    let event_type = match fields.event_type.as_deref() {
        Some(value) => Some(normalize_calendar_event_type(Some(value))?),
        None => None,
    };
    Ok(WorkflowCreateInput {
        title: fields.title.to_string(),
        recurrence: fields.recurrence.as_deref().map(str::to_string),
        timezone: fields.timezone.as_deref().map(str::to_string),
        start_date: fields.start_date.to_string(),
        start_time: fields.start_time.as_deref().map(str::to_string),
        end_date: fields.end_date.as_deref().map(str::to_string),
        end_time: fields.end_time.as_deref().map(str::to_string),
        all_day: Some(fields.all_day),
        description: fields.description.as_deref().map(str::to_string),
        location: fields.location.as_deref().map(str::to_string),
        url: fields.url.as_deref().map(str::to_string),
        color: fields.color.as_deref().map(str::to_string),
        event_type,
        person_name: fields.person_name.as_deref().map(str::to_string),
        attendees: None,
    })
}

/// Batch wrapper that drives a sequence of [`CreateCalendarEventMutation`]s
/// inside a single mutation execution so they share one HLC counter run.
struct BatchCreateCliCalendarEventsMutation {
    mutations: Vec<CreateCalendarEventMutation>,
}

impl Mutation for BatchCreateCliCalendarEventsMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "batch_create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut events = Vec::with_capacity(self.mutations.len());
        for sub in &self.mutations {
            let output = sub.apply(conn, hlc)?;
            events.push(output.after);
        }
        Ok(MutationOutput::new(
            serde_json::Value::Array(events),
            format!("Created {} calendar event(s)", self.mutations.len()),
        ))
    }
}

pub(crate) fn create_calendar_event_with_conn(
    conn: &mut Connection,
    fields: &CalendarEventCreateFields<'_>,
) -> Result<lorvex_store::calendar_timeline::CalendarEventRow, crate::error::CliError> {
    let input = workflow_input_from_fields(fields)?;
    let event_id = lorvex_domain::new_entity_id_string();
    let mutation =
        CreateCalendarEventMutation::new(event_id.clone(), input).map_err(map_op_error)?;
    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(&tx, ENTITY_CALENDAR_EVENT, &event_id, hlc_state, &device_id)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &event_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let event = load_calendar_event_row(&tx, &event_id)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("created calendar event '{event_id}' not found"))
    })?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(event)
}

pub(crate) fn create_calendar_events_with_conn(
    conn: &mut Connection,
    inputs: &[CalendarEventCreateInput],
) -> Result<CalendarEventsCreateResult, crate::error::CliError> {
    const MAX_BATCH_CALENDAR_EVENTS: usize = 500;
    if inputs.is_empty() {
        return Err(crate::error::CliError::Validation(
            "events must contain at least one item".to_string(),
        ));
    }
    if inputs.len() > MAX_BATCH_CALENDAR_EVENTS {
        return Err(crate::error::CliError::Validation(format!(
            "calendar batch-create supports at most {MAX_BATCH_CALENDAR_EVENTS} events"
        )));
    }

    // Build the workflow mutations up-front so validation errors surface
    // before any DB write — `BatchCreateCliCalendarEventsMutation::apply`
    // would otherwise execute partial inserts before hitting a bad row.
    let mut mutations: Vec<CreateCalendarEventMutation> = Vec::with_capacity(inputs.len());
    let mut event_ids: Vec<String> = Vec::with_capacity(inputs.len());
    for input in inputs {
        let fields = CalendarEventCreateFields {
            title: Cow::Borrowed(&input.title),
            start_date: Cow::Borrowed(&input.start_date),
            start_time: input.start_time.as_deref().map(Cow::Borrowed),
            end_date: input.end_date.as_deref().map(Cow::Borrowed),
            end_time: input.end_time.as_deref().map(Cow::Borrowed),
            all_day: input.all_day,
            description: input.description.as_deref().map(Cow::Borrowed),
            location: input.location.as_deref().map(Cow::Borrowed),
            url: input.url.as_deref().map(Cow::Borrowed),
            color: input.color.as_deref().map(Cow::Borrowed),
            recurrence: input.recurrence.as_deref().map(Cow::Borrowed),
            timezone: input.timezone.as_deref().map(Cow::Borrowed),
            event_type: input.event_type.as_deref().map(Cow::Borrowed),
            person_name: input.person_name.as_deref().map(Cow::Borrowed),
        };
        let workflow_input = workflow_input_from_fields(&fields)?;
        let event_id = lorvex_domain::new_entity_id_string();
        mutations.push(
            CreateCalendarEventMutation::new(event_id.clone(), workflow_input)
                .map_err(map_op_error)?,
        );
        event_ids.push(event_id);
    }

    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;
    let mutation = BatchCreateCliCalendarEventsMutation { mutations };
    let mut hlc_guard = lock_shared(&tx)?;
    let captured_ids = event_ids.clone();
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let after_events = execution.output.after.as_array().ok_or_else(|| {
                crate::error::CliError::Internal(
                    "Mutation contract: batch calendar create returns event array".to_string(),
                )
            })?;
            for (event_id, after_json) in captured_ids.iter().zip(after_events.iter()) {
                enqueue_entity_upsert(&tx, ENTITY_CALENDAR_EVENT, event_id, hlc_state, &device_id)?;
                let title = after_json
                    .get("title")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or(event_id);
                log_cli_changelog_with_state(
                    &tx,
                    hlc_state,
                    crate::commands::shared::CliChangelogParams {
                        operation: execution.operation,
                        entity_type: execution.entity_kind,
                        entity_id: event_id,
                        summary: &format!("Created calendar event '{title}'"),
                        before_json: None,
                        after_json: Some(after_json.clone()),
                    },
                )?;
            }
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let mut events = Vec::with_capacity(event_ids.len());
    for event_id in &event_ids {
        events.push(load_calendar_event_row(&tx, event_id)?.ok_or_else(|| {
            crate::error::CliError::NotFound(format!(
                "created calendar event '{event_id}' not found"
            ))
        })?);
    }
    drop(hlc_guard);
    tx.commit()?;

    Ok(CalendarEventsCreateResult {
        created_count: events.len(),
        calendar_events: events,
    })
}
