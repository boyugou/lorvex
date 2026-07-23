//! `lorvex calendar …` dispatcher.

use std::borrow::Cow;

use lorvex_domain::Patch;

use crate::cli::{AttendeesPatch, CalendarCommand};
use crate::commands::mutate::calendar::effects::{
    CalendarEventCreateFields, CalendarEventUpdateFields, CliAttendeeInput,
};
use crate::commands::mutate::{
    run_calendar_add_exception, run_calendar_batch_create, run_calendar_create,
    run_calendar_delete, run_calendar_link, run_calendar_links_for_event,
    run_calendar_links_for_task, run_calendar_provider_link, run_calendar_provider_links_for_task,
    run_calendar_provider_unlink, run_calendar_remove_exception, run_calendar_unlink,
    run_calendar_update,
};
use crate::commands::query::{
    run_calendar_export_ics, run_calendar_list, run_calendar_search, run_calendar_show,
    run_calendar_today,
};
use crate::error::CliError;

pub(super) fn dispatch_calendar(command: CalendarCommand) -> Result<(), CliError> {
    match command {
        CalendarCommand::List { limit, format } => {
            println!("{}", run_calendar_list(limit, format)?);
        }
        CalendarCommand::Show { event_id, format } => {
            println!("{}", run_calendar_show(&event_id, format)?);
        }
        CalendarCommand::Today { format } => println!("{}", run_calendar_today(format)?),
        CalendarCommand::Create {
            title,
            start_date,
            start_time,
            end_date,
            end_time,
            all_day,
            description,
            location,
            url,
            color,
            recurrence,
            timezone,
            event_type,
            person_name,
            format,
        } => println!(
            "{}",
            run_calendar_create(
                &CalendarEventCreateFields {
                    title: Cow::Borrowed(&title),
                    start_date: Cow::Borrowed(&start_date),
                    start_time: start_time.as_deref().map(Cow::Borrowed),
                    end_date: end_date.as_deref().map(Cow::Borrowed),
                    end_time: end_time.as_deref().map(Cow::Borrowed),
                    all_day,
                    description: description.as_deref().map(Cow::Borrowed),
                    location: location.as_deref().map(Cow::Borrowed),
                    url: url.as_deref().map(Cow::Borrowed),
                    color: color.as_deref().map(Cow::Borrowed),
                    recurrence: recurrence.as_deref().map(Cow::Borrowed),
                    timezone: timezone.as_deref().map(Cow::Borrowed),
                    event_type: event_type.as_deref().map(Cow::Borrowed),
                    person_name: person_name.as_deref().map(Cow::Borrowed),
                },
                format,
            )?
        ),
        CalendarCommand::BatchCreate {
            events_json,
            format,
        } => println!("{}", run_calendar_batch_create(&events_json, format)?),
        CalendarCommand::Update {
            event_id,
            title,
            start_date,
            start_time,
            end_date,
            end_time,
            all_day,
            description,
            location,
            url,
            color,
            recurrence,
            timezone,
            event_type,
            person_name,
            attendees,
            format,
        } => {
            let attendees_patch = parse_attendees_patch(attendees)?;
            println!(
                "{}",
                run_calendar_update(
                    &event_id,
                    &CalendarEventUpdateFields {
                        title: title.as_deref(),
                        start_date: start_date.as_deref(),
                        start_time: start_time.as_deref(),
                        end_date: end_date.as_deref(),
                        end_time: end_time.as_deref(),
                        all_day,
                        description: description.as_deref(),
                        location: location.as_deref(),
                        url: url.as_deref(),
                        color: color.as_deref(),
                        recurrence: recurrence.as_deref(),
                        timezone: timezone.as_deref(),
                        event_type: event_type.as_deref(),
                        person_name: person_name.as_deref(),
                        attendees: attendees_patch,
                    },
                    format,
                )?
            );
        }
        CalendarCommand::Delete { event_id, format } => {
            println!("{}", run_calendar_delete(&event_id, format)?);
        }
        CalendarCommand::Link {
            event_id,
            task_ids,
            format,
        } => println!("{}", run_calendar_link(&event_id, &task_ids, format)?),
        CalendarCommand::Unlink {
            event_id,
            task_id,
            format,
        } => println!("{}", run_calendar_unlink(&event_id, &task_id, format)?),
        CalendarCommand::LinksForTask { task_id, format } => {
            println!("{}", run_calendar_links_for_task(&task_id, format)?);
        }
        CalendarCommand::LinksForEvent { event_id, format } => {
            println!("{}", run_calendar_links_for_event(&event_id, format)?);
        }
        CalendarCommand::AddException {
            event_id,
            date,
            format,
        } => println!("{}", run_calendar_add_exception(&event_id, &date, format)?),
        CalendarCommand::RemoveException {
            event_id,
            date,
            format,
        } => println!(
            "{}",
            run_calendar_remove_exception(&event_id, &date, format)?
        ),
        CalendarCommand::ProviderLink {
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
            format,
        } => println!(
            "{}",
            run_calendar_provider_link(
                &task_id,
                &provider_kind,
                &provider_scope,
                &provider_event_key,
                format,
            )?
        ),
        CalendarCommand::ProviderUnlink {
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
            format,
        } => println!(
            "{}",
            run_calendar_provider_unlink(
                &task_id,
                &provider_kind,
                &provider_scope,
                &provider_event_key,
                format,
            )?
        ),
        CalendarCommand::ProviderLinksForTask { task_id, format } => println!(
            "{}",
            run_calendar_provider_links_for_task(&task_id, format)?
        ),
        CalendarCommand::ExportIcs { from, to, format } => {
            println!("{}", run_calendar_export_ics(&from, &to, format)?);
        }
        CalendarCommand::Search {
            query,
            from,
            to,
            limit,
            format,
        } => println!(
            "{}",
            run_calendar_search(&query, from.as_deref(), to.as_deref(), limit, format)?
        ),
    }
    Ok(())
}

#[derive(serde::Deserialize)]
struct AttendeeJsonItem {
    email: String,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    status: Option<String>,
}

fn parse_attendees_patch(raw: AttendeesPatch) -> Result<Patch<Vec<CliAttendeeInput>>, CliError> {
    match raw {
        AttendeesPatch::Unset => Ok(Patch::Unset),
        // `--clear-attendees` is the explicit "clear" intent — emit
        // `Patch::Clear` so the audit-log signal matches the user's
        // which round-tripped the same row write but obscured the
        // intent in changelog).
        AttendeesPatch::Clear => Ok(Patch::Clear),
        AttendeesPatch::Json(payload) => {
            let parsed: Vec<AttendeeJsonItem> = serde_json::from_str(&payload).map_err(|err| {
                CliError::Validation(format!("--attendees-json: invalid JSON: {err}"))
            })?;
            Ok(Patch::Set(
                parsed
                    .into_iter()
                    .map(|item| CliAttendeeInput {
                        email: item.email,
                        name: item.name,
                        status: item.status,
                    })
                    .collect(),
            ))
        }
    }
}
