//! Thin CLI adapter for calendar-event updates.
//!
//! Translates the CLI's borrowed-`Patch<&str>` field bundle into the
//! canonical [`lorvex_workflow::calendar_event::CalendarEventUpdateInput`]
//! and delegates validation, normalization, EXDATE preservation, and the
//! row UPDATE to [`UpdateCalendarEventMutation`]. The CLI owns the
//! per-surface finalizer pieces (transaction handling, outbox enqueue,
//! `ai_changelog` write, `local_change_seq` bump).
//!
//! ## CLI-specific quirk: start_date reanchors recurrence
//!
//! Unlike MCP and Tauri clients, CLI callers can patch `start_date`
//! without re-sending `recurrence`, and the CLI's contract is that the
//! existing recurrence rule re-anchors onto the new anchor (e.g. a
//! `MONTHLY` rule with `BYMONTHDAY=10` becomes `BYMONTHDAY=22` when the
//! start_date moves to the 22nd). The workflow op does not synthesize
//! this — it only re-anchors when `recurrence` itself is in
//! `Patch::Set`. To preserve the contract, this adapter forwards the
//! existing recurrence as `Patch::Set` whenever `start_date` is patched
//! and `recurrence` is `Patch::Unset`.

use super::*;
use lorvex_domain::{AttendeeStatus, Patch};
use lorvex_workflow::calendar_event::{
    AttendeeShadowInput, CalendarEventOpError, CalendarEventUpdateInput as WorkflowUpdateInput,
    UpdateCalendarEventMutation,
};
use lorvex_workflow::calendar_normalization::CalendarUpdateExisting;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

fn map_op_error(error: CalendarEventOpError) -> crate::error::CliError {
    match error {
        CalendarEventOpError::Validation(message) => crate::error::CliError::Validation(message),
        CalendarEventOpError::Store(store_error) => store_error.into(),
    }
}

fn patch_to_owned(patch: &Patch<&str>) -> Patch<String> {
    patch.clone().map(str::to_string)
}

/// Strip `BYMONTHDAY` from a canonical recurrence JSON so the workflow's
/// `normalize_recurrence_patch` re-injects a fresh anchor from the new
/// `start_date`. Returns the rule unchanged when it doesn't parse as a
/// JSON object — `normalize_calendar_recurrence` will surface the same
/// shape error.
fn strip_bymonthday_for_reanchor(recurrence_json: &str) -> Result<String, crate::error::CliError> {
    let mut rule = serde_json::from_str::<serde_json::Value>(recurrence_json)
        .map_err(|e| crate::error::CliError::Validation(e.to_string()))?;
    if let Some(object) = rule.as_object_mut() {
        object.remove("BYMONTHDAY");
    }
    Ok(rule.to_string())
}

fn existing_from_row(
    row: &lorvex_store::calendar_timeline::CalendarEventRow,
) -> CalendarUpdateExisting {
    CalendarUpdateExisting {
        start_date: row.start_date().to_string(),
        start_time: row.start_time().map(|t| t.to_string()),
        end_date: row.end_date().map(|d| d.to_string()),
        end_time: row.end_time().map(|t| t.to_string()),
        all_day: row.all_day(),
        timezone: row.timezone.clone(),
    }
}

pub(crate) fn update_calendar_event_with_conn(
    conn: &mut Connection,
    event_id: &lorvex_domain::EventId,
    // pass by reference: every field on `CalendarEventUpdateFields`
    // is `Option<&'a str>` / `Option<bool>` (Copy), so the body
    // doesn't need to consume the struct — and at ~330 bytes,
    // moving the struct by value triggers clippy's
    // `large_types_passed_by_value` on the pedantic profile.
    // Borrowing copies an 8-byte pointer instead.
    fields: &CalendarEventUpdateFields<'_>,
) -> Result<lorvex_store::calendar_timeline::CalendarEventRow, crate::error::CliError> {
    let has_patch = fields.title.is_some()
        || fields.start_date.is_some()
        || fields.start_time.is_set_or_clear()
        || fields.end_date.is_set_or_clear()
        || fields.end_time.is_set_or_clear()
        || fields.all_day.is_some()
        || fields.description.is_set_or_clear()
        || fields.location.is_set_or_clear()
        || fields.url.is_set_or_clear()
        || fields.color.is_set_or_clear()
        || fields.recurrence.is_set_or_clear()
        || fields.timezone.is_set_or_clear()
        || fields.event_type.is_set_or_clear()
        || fields.person_name.is_set_or_clear()
        || fields.attendees.is_set_or_clear();
    if !has_patch {
        return Err(crate::error::CliError::Validation(
            "calendar update requires at least one field flag".to_string(),
        ));
    }

    let event_id_str = event_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = calendar_write_tx(conn)?;
    let before = load_calendar_event_row(&tx, event_id_str)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("calendar event '{event_id_str}' not found"))
    })?;

    let title = fields.title.map(normalize_calendar_title).transpose()?;
    let event_type: Patch<lorvex_domain::CanonicalCalendarEventType> = fields
        .event_type
        .clone()
        .try_map(|raw| normalize_calendar_event_type(Some(raw)))?;
    let attendees: Patch<Vec<AttendeeShadowInput>> = fields.attendees.clone().try_map(|list| {
        list.iter()
            .map(|a| {
                let status = match a.status.as_deref() {
                    Some(raw) => Some(AttendeeStatus::parse_strict(raw).ok_or_else(|| {
                        crate::error::CliError::Validation(format!(
                            "unknown attendee status: {raw}"
                        ))
                    })?),
                    None => None,
                };
                Ok::<_, crate::error::CliError>(AttendeeShadowInput {
                    email: a.email.clone(),
                    name: a.name.clone(),
                    status,
                })
            })
            .collect::<Result<Vec<_>, _>>()
    })?;

    // CLI reanchor contract: when start_date is patched but recurrence
    // isn't, forward the existing recurrence (with any prior
    // `BYMONTHDAY` stripped) as `Patch::Set` so the workflow's
    // `normalize_recurrence_patch` re-injects `BYMONTHDAY` from the
    // new anchor. `inject_bymonthday` is a no-op when the rule already
    // carries `BYMONTHDAY`, so the strip is what lets the new anchor
    // take effect. Positional rules (`BYDAY` / `BYSETPOS`) survive
    // untouched because `inject_bymonthday` declines to add
    // `BYMONTHDAY` when either field is present. See the module-level
    // comment.
    let recurrence: Patch<String> = match (&fields.recurrence, fields.start_date) {
        (Patch::Unset, Some(_)) => match before.recurrence.as_deref() {
            Some(existing) => Patch::Set(strip_bymonthday_for_reanchor(existing)?),
            None => Patch::Unset,
        },
        (patch, _) => patch_to_owned(patch),
    };

    let existing = existing_from_row(&before);
    let before_recurrence = before.recurrence.clone();
    let before_json = serde_json::to_value(&before)?;

    let input = WorkflowUpdateInput {
        id: event_id_str.to_string(),
        title,
        recurrence,
        timezone: patch_to_owned(&fields.timezone),
        // CLI doesn't expose a "clear start_date" flag (it would be
        // a row-state error anyway — see `CalendarEventUpdateInput`
        // doc). Lift `Option<&str>` into `Patch::Set` / `Patch::Unset`.
        start_date: match fields.start_date {
            Some(value) => Patch::Set(value.to_string()),
            None => Patch::Unset,
        },
        start_time: patch_to_owned(&fields.start_time),
        end_date: patch_to_owned(&fields.end_date),
        end_time: patch_to_owned(&fields.end_time),
        all_day: fields.all_day,
        description: patch_to_owned(&fields.description),
        location: patch_to_owned(&fields.location),
        url: patch_to_owned(&fields.url),
        color: patch_to_owned(&fields.color),
        event_type,
        person_name: patch_to_owned(&fields.person_name),
        attendees,
    };

    let mutation =
        UpdateCalendarEventMutation::new(input, existing, before_json, before_recurrence)
            .map_err(map_op_error)?;

    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(
                &tx,
                ENTITY_CALENDAR_EVENT,
                event_id_str,
                hlc_state,
                &device_id,
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: event_id_str,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let event = load_calendar_event_row(&tx, event_id_str)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!(
            "updated calendar event '{event_id_str}' not found"
        ))
    })?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(event)
}
