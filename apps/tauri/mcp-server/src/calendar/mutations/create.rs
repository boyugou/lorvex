use super::*;
use crate::contract::AttendeeStatusArg;
use crate::runtime::change_tracking::{
    execute_mcp_batch_mutation_with_audit_finalizer, execute_mcp_mutation,
};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::StoreError;
use lorvex_workflow::calendar_event::{
    AttendeeShadowInput, CalendarEventCreateInput, CalendarEventOpError,
    CreateCalendarEventMutation,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};

fn map_op_error(error: CalendarEventOpError) -> McpError {
    match error {
        CalendarEventOpError::Validation(message) => McpError::Validation(message),
        CalendarEventOpError::Store(store_error) => McpError::Store(Box::new(store_error)),
    }
}

fn shadow_attendees(input: Option<Vec<AttendeeInput>>) -> Option<Vec<AttendeeShadowInput>> {
    input.map(|list| {
        list.into_iter()
            .map(|a| AttendeeShadowInput {
                email: a.email,
                name: a.name,
                status: a.status.map(|s| {
                    let arg: AttendeeStatusArg = s;
                    lorvex_domain::AttendeeStatus::from(arg)
                }),
            })
            .collect()
    })
}

fn workflow_create_input(args: CreateCalendarEventArgs) -> CalendarEventCreateInput {
    let CreateCalendarEventArgs {
        title,
        recurrence,
        timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        description,
        location,
        url,
        color,
        event_type,
        person_name,
        attendees,
    } = args;
    CalendarEventCreateInput {
        title,
        recurrence,
        timezone,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        description,
        location,
        url,
        color,
        event_type: event_type.map(Into::into),
        person_name,
        attendees: shadow_attendees(attendees),
    }
}

fn record_create_dst_warning(
    conn: &Connection,
    mutation: &CreateCalendarEventMutation,
    after: &Value,
) {
    let title = after
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    record_dst_ambiguity_warning(conn, mutation.event_id(), title, mutation.dst_guard());
}

struct BatchCreateCalendarEventsMutation {
    mutations: Vec<CreateCalendarEventMutation>,
}

impl Mutation for BatchCreateCalendarEventsMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "batch_create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut created_events: Vec<Value> = Vec::with_capacity(self.mutations.len());
        for sub in &self.mutations {
            let output = sub.apply(conn, hlc)?;
            // DST diagnostic per child event so the ambiguity warning
            // surfaces just like the single-create path.
            record_create_dst_warning(conn, sub, &output.after);
            created_events.push(output.after);
        }
        let titles = created_events
            .iter()
            .map(|event| {
                let title = event
                    .get("title")
                    .and_then(Value::as_str)
                    .unwrap_or("calendar event");
                format!("'{title}'")
            })
            .collect::<Vec<_>>()
            .join(", ");
        let summary = format!(
            "Created {} calendar event{}: {}",
            created_events.len(),
            plural_s(created_events.len()),
            titles
        );
        Ok(MutationOutput::new(
            json!({ "after_states": created_events }),
            summary,
        ))
    }
}

pub(crate) fn create_calendar_event(
    conn: &Connection,
    args: CreateCalendarEventArgs,
) -> Result<String, McpError> {
    let input = workflow_create_input(args);
    let event_id = new_uuid();
    let mutation =
        CreateCalendarEventMutation::new(event_id.clone(), input).map_err(map_op_error)?;
    let output = execute_mcp_mutation(conn, &mutation, "create_calendar_event", event_id)?;
    record_create_dst_warning(conn, &mutation, &output.after);
    Ok(serde_json::to_string(&output.after)?)
}

pub(crate) fn batch_create_calendar_events(
    conn: &Connection,
    args: BatchCreateCalendarEventsArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchCreateCalendarEventsArgs {
        events,
        dry_run: _,
        idempotency_key,
    } = args;
    if events.is_empty() {
        return Err(McpError::Validation(
            "events must contain at least one item".to_string(),
        ));
    }
    if events.len() > 500 {
        return Err(McpError::Validation(format!(
            "batch_create_calendar_events supports at most 500 items, got {}",
            events.len()
        )));
    }
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_create_calendar_events",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    let mut mutations: Vec<CreateCalendarEventMutation> = Vec::with_capacity(events.len());
    for event in events {
        let event_id = new_uuid();
        let input = workflow_create_input(event);
        mutations.push(CreateCalendarEventMutation::new(event_id, input).map_err(map_op_error)?);
    }
    let created_ids: Vec<String> = mutations.iter().map(|m| m.event_id().to_string()).collect();
    let mutation = BatchCreateCalendarEventsMutation { mutations };
    let output = execute_mcp_batch_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "batch_create_calendar_events",
        created_ids,
        McpError::from,
        |_, _| Ok(()),
    )?;
    let created_events = output
        .after
        .get("after_states")
        .and_then(Value::as_array)
        .cloned()
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: calendar event batch create stamped after_states".to_string(),
            )
        })?;

    let response = serde_json::to_string(&json!({
        "created_count": created_events.len(),
        "calendar_events": created_events,
    }))?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_create_calendar_events",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
