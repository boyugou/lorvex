use lorvex_domain::{EventId, Patch};
use lorvex_sync_payload::CalendarEventUpdateWire;
use lorvex_workflow::calendar_event::CalendarEventUpdateInput;
use lorvex_workflow::calendar_recurrence_scope::{
    rebase_date_range_to_occurrence, truncate_recurrence_before, TruncateRecurrenceResult,
};
use serde::{Deserialize, Serialize};

use crate::commands::sync_timestamp_now;
use crate::error::{AppError, AppResult};
use crate::event_bus;

use super::create::{create_calendar_event_with_conn, CreateCalendarEventArgs};
use super::delete::{
    delete_calendar_event_result_from_outcome, delete_calendar_event_with_conn,
    DeleteCalendarEventResult,
};
use super::exceptions::add_event_exception_with_conn;
use super::update::command::wire_into_workflow_input;
use super::update::update_calendar_event_with_conn;
use super::{load_calendar_event, with_immediate_transaction, CalendarEvent};

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum RecurringCalendarEventScope {
    AllInSeries,
    ThisOnly,
    ThisAndFollowing,
}

#[derive(Debug, Deserialize)]
pub struct ScopedCalendarEventEditInput {
    pub id: String,
    pub occurrence_date: String,
    pub scope: RecurringCalendarEventScope,
    pub payload: serde_json::Value,
}

#[derive(Debug, Deserialize)]
pub struct ScopedCalendarEventDeleteInput {
    pub id: String,
    pub occurrence_date: String,
    pub scope: RecurringCalendarEventScope,
}

#[derive(Debug, Serialize)]
pub struct ScopedCalendarEventEditResult {
    pub original_event: Option<CalendarEvent>,
    pub replacement_event: Option<CalendarEvent>,
    pub delete_result: Option<DeleteCalendarEventResult>,
    pub noop: bool,
}

#[derive(Debug, Serialize)]
pub struct ScopedCalendarEventDeleteResult {
    pub event: Option<CalendarEvent>,
    pub delete_result: Option<DeleteCalendarEventResult>,
    pub noop: bool,
}

fn edit_payload_to_create_args(payload: serde_json::Value) -> AppResult<CreateCalendarEventArgs> {
    serde_json::from_value(payload)
        .map_err(|err| AppError::Validation(format!("Invalid scoped calendar edit payload: {err}")))
}

fn edit_payload_to_update_input(
    id: String,
    payload: serde_json::Value,
) -> AppResult<CalendarEventUpdateInput> {
    let mut value = payload;
    let Some(obj) = value.as_object_mut() else {
        return Err(AppError::Validation(
            "Invalid scoped calendar edit payload: expected object".to_string(),
        ));
    };
    obj.insert("id".to_string(), serde_json::Value::String(id));
    let wire: CalendarEventUpdateWire = serde_json::from_value(value).map_err(|err| {
        AppError::Validation(format!("Invalid scoped calendar update payload: {err}"))
    })?;
    wire_into_workflow_input(wire).map_err(AppError::Validation)
}

fn rebase_create_args_to_occurrence(
    mut args: CreateCalendarEventArgs,
    occurrence_date: &str,
) -> AppResult<CreateCalendarEventArgs> {
    let (start_date, end_date) = rebase_date_range_to_occurrence(
        &args.start_date,
        args.end_date.as_deref(),
        occurrence_date,
    )
    .ok_or_else(|| AppError::Validation("Invalid scoped calendar occurrence date".to_string()))?;
    args.start_date = start_date;
    args.end_date = end_date;
    Ok(args)
}

fn recurrence_update_input(id: String, recurrence: String) -> CalendarEventUpdateInput {
    CalendarEventUpdateInput {
        id,
        title: None,
        recurrence: Patch::Set(recurrence),
        timezone: Patch::Unset,
        start_date: Patch::Unset,
        start_time: Patch::Unset,
        end_date: Patch::Unset,
        end_time: Patch::Unset,
        all_day: None,
        description: Patch::Unset,
        location: Patch::Unset,
        url: Patch::Unset,
        color: Patch::Unset,
        event_type: Patch::Unset,
        person_name: Patch::Unset,
        attendees: Patch::Unset,
    }
}

#[allow(clippy::needless_pass_by_value)]
#[tauri::command]
pub fn apply_scoped_calendar_event_edit(
    input: ScopedCalendarEventEditInput,
) -> Result<ScopedCalendarEventEditResult, String> {
    let id = crate::commands::shared::validate_uuid_id(&input.id, "id")?;
    lorvex_domain::validation::validate_date_format(&input.occurrence_date)
        .map_err(|err| err.to_string())?;
    let conn = super::get_conn()?;
    let now = sync_timestamp_now();
    let result = apply_scoped_calendar_event_edit_with_conn(&conn, &id, input, &now)
        .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    Ok(result)
}

pub(crate) fn apply_scoped_calendar_event_edit_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    input: ScopedCalendarEventEditInput,
    now: &str,
) -> AppResult<ScopedCalendarEventEditResult> {
    with_immediate_transaction(conn, |conn| {
        let original = load_calendar_event(conn, id).map_err(AppError::Internal)?;
        match input.scope {
            RecurringCalendarEventScope::AllInSeries => {
                let update_input = edit_payload_to_update_input(id.to_string(), input.payload)?;
                let updated = update_calendar_event_with_conn(conn, update_input, now)?;
                Ok(ScopedCalendarEventEditResult {
                    original_event: Some(updated),
                    replacement_event: None,
                    delete_result: None,
                    noop: false,
                })
            }
            RecurringCalendarEventScope::ThisOnly => {
                add_event_exception_with_conn(
                    conn,
                    &EventId::from_trusted(id.to_string()),
                    &input.occurrence_date,
                    now,
                )?;
                let replacement_args = rebase_create_args_to_occurrence(
                    edit_payload_to_create_args(input.payload)?,
                    &input.occurrence_date,
                )?;
                let replacement_args = CreateCalendarEventArgs {
                    recurrence: None,
                    ..replacement_args
                };
                let replacement =
                    create_calendar_event_with_conn(conn, replacement_args, now.to_string())?;
                Ok(ScopedCalendarEventEditResult {
                    original_event: Some(
                        load_calendar_event(conn, id).map_err(AppError::Internal)?,
                    ),
                    replacement_event: Some(replacement),
                    delete_result: None,
                    noop: false,
                })
            }
            RecurringCalendarEventScope::ThisAndFollowing => {
                let truncation = truncate_recurrence_before(
                    original.recurrence.as_deref(),
                    &input.occurrence_date,
                    Some(&original.start_date),
                );
                if truncation == TruncateRecurrenceResult::Noop {
                    return Ok(ScopedCalendarEventEditResult {
                        original_event: Some(original),
                        replacement_event: None,
                        delete_result: None,
                        noop: true,
                    });
                }
                let replacement_args = rebase_create_args_to_occurrence(
                    edit_payload_to_create_args(input.payload)?,
                    &input.occurrence_date,
                )?;
                let replacement =
                    create_calendar_event_with_conn(conn, replacement_args, now.to_string())?;
                let (original_event, delete_result) = match truncation {
                    TruncateRecurrenceResult::Truncated(recurrence)
                        if input.occurrence_date > original.start_date =>
                    {
                        let updated = update_calendar_event_with_conn(
                            conn,
                            recurrence_update_input(id.to_string(), recurrence),
                            now,
                        )?;
                        (Some(updated), None)
                    }
                    TruncateRecurrenceResult::Truncated(_)
                    | TruncateRecurrenceResult::Collapse
                    | TruncateRecurrenceResult::Noop => {
                        let outcome = delete_calendar_event_with_conn(conn, id)?;
                        (
                            None,
                            Some(delete_calendar_event_result_from_outcome(outcome)),
                        )
                    }
                };
                Ok(ScopedCalendarEventEditResult {
                    original_event,
                    replacement_event: Some(replacement),
                    delete_result,
                    noop: false,
                })
            }
        }
    })
}

#[allow(clippy::needless_pass_by_value)]
#[tauri::command]
pub fn delete_scoped_calendar_event(
    input: ScopedCalendarEventDeleteInput,
) -> Result<ScopedCalendarEventDeleteResult, String> {
    let id = crate::commands::shared::validate_uuid_id(&input.id, "id")?;
    lorvex_domain::validation::validate_date_format(&input.occurrence_date)
        .map_err(|err| err.to_string())?;
    let conn = super::get_conn()?;
    let now = sync_timestamp_now();
    let result =
        delete_scoped_calendar_event_with_conn(&conn, &id, &input, &now).map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    Ok(result)
}

pub(crate) fn delete_scoped_calendar_event_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    input: &ScopedCalendarEventDeleteInput,
    now: &str,
) -> AppResult<ScopedCalendarEventDeleteResult> {
    with_immediate_transaction(conn, |conn| {
        let original = load_calendar_event(conn, id).map_err(AppError::Internal)?;
        match input.scope {
            RecurringCalendarEventScope::AllInSeries => {
                let outcome = delete_calendar_event_with_conn(conn, id)?;
                Ok(ScopedCalendarEventDeleteResult {
                    event: None,
                    delete_result: Some(delete_calendar_event_result_from_outcome(outcome)),
                    noop: false,
                })
            }
            RecurringCalendarEventScope::ThisOnly => {
                let event = add_event_exception_with_conn(
                    conn,
                    &EventId::from_trusted(id.to_string()),
                    &input.occurrence_date,
                    now,
                )?;
                Ok(ScopedCalendarEventDeleteResult {
                    event: Some(event),
                    delete_result: None,
                    noop: false,
                })
            }
            RecurringCalendarEventScope::ThisAndFollowing => {
                match truncate_recurrence_before(
                    original.recurrence.as_deref(),
                    &input.occurrence_date,
                    Some(&original.start_date),
                ) {
                    TruncateRecurrenceResult::Noop => Ok(ScopedCalendarEventDeleteResult {
                        event: Some(original),
                        delete_result: None,
                        noop: true,
                    }),
                    TruncateRecurrenceResult::Truncated(recurrence)
                        if input.occurrence_date > original.start_date =>
                    {
                        let event = update_calendar_event_with_conn(
                            conn,
                            recurrence_update_input(id.to_string(), recurrence),
                            now,
                        )?;
                        Ok(ScopedCalendarEventDeleteResult {
                            event: Some(event),
                            delete_result: None,
                            noop: false,
                        })
                    }
                    TruncateRecurrenceResult::Truncated(_) | TruncateRecurrenceResult::Collapse => {
                        let outcome = delete_calendar_event_with_conn(conn, id)?;
                        Ok(ScopedCalendarEventDeleteResult {
                            event: None,
                            delete_result: Some(delete_calendar_event_result_from_outcome(outcome)),
                            noop: false,
                        })
                    }
                }
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use rusqlite::params;

    use super::*;
    use crate::test_support::{fixture_uuid, test_conn};

    fn seed_recurring_event(conn: &rusqlite::Connection, id: &str) {
        conn.execute(
            "INSERT INTO calendar_events (
                id, title, description, recurrence, timezone,
                start_date, start_time, end_date, end_time, all_day, location, url, color,
                event_type, version, created_at, updated_at
            )
            VALUES (
                ?1, 'Daily standup', NULL, ?2, 'UTC',
                '2026-03-16', NULL, NULL, NULL, 1, NULL, NULL, NULL,
                'event', '0000000000000_0000_seedcalseedcalse',
                '2026-03-15T08:00:00Z', '2026-03-15T08:00:00Z'
            )",
            params![id, r#"{"FREQ":"DAILY","INTERVAL":1}"#],
        )
        .expect("seed recurring calendar event");
    }

    fn replacement_payload() -> serde_json::Value {
        let recurrence = serde_json::json!({"FREQ":"DAILY","INTERVAL":1}).to_string();
        serde_json::json!({
            "title": "Shifted standup",
            "recurrence": recurrence,
            "timezone": "UTC",
            "start_date": "2026-03-16",
            "start_time": null,
            "end_date": null,
            "end_time": null,
            "all_day": true,
            "description": null,
            "location": null,
            "url": null,
            "color": null,
            "event_type": "event",
            "person_name": null
        })
    }

    #[test]
    fn this_and_following_edit_rolls_back_replacement_when_original_truncation_fails() {
        let conn = test_conn();
        let original_id = fixture_uuid("calendar-scope-original");
        seed_recurring_event(&conn, &original_id);
        let trigger = format!(
            "CREATE TRIGGER fail_original_recurrence_update
             BEFORE UPDATE OF recurrence ON calendar_events
             WHEN OLD.id = '{}'
             BEGIN
               SELECT RAISE(ABORT, 'injected original recurrence update failure');
             END",
            original_id
        );
        conn.execute(&trigger, [])
            .expect("install failure-injection trigger");

        let result = apply_scoped_calendar_event_edit_with_conn(
            &conn,
            &original_id,
            ScopedCalendarEventEditInput {
                id: original_id.clone(),
                occurrence_date: "2026-03-20".to_string(),
                scope: RecurringCalendarEventScope::ThisAndFollowing,
                payload: replacement_payload(),
            },
            "2026-03-19T08:00:00Z",
        );

        assert!(
            result.is_err(),
            "trigger should fail after the replacement insert path"
        );
        let original_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
                params![original_id],
                |row| row.get(0),
            )
            .expect("count original event");
        assert_eq!(original_count, 1);
        let replacement_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM calendar_events WHERE title = 'Shifted standup'",
                [],
                |row| row.get(0),
            )
            .expect("count replacement events");
        assert_eq!(
            replacement_count, 0,
            "transaction rollback must remove the replacement created before the failure"
        );
        let recurrence: String = conn
            .query_row(
                "SELECT recurrence FROM calendar_events WHERE id = ?1",
                params![original_id],
                |row| row.get(0),
            )
            .expect("load original recurrence");
        assert_eq!(recurrence, r#"{"FREQ":"DAILY","INTERVAL":1}"#);
    }
}
