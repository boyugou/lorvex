use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::shared::{render_mutation_envelope, render_query_envelope};

pub(crate) mod effects;
use effects::{
    add_calendar_event_exception_with_conn, create_calendar_event_with_conn,
    create_calendar_events_with_conn, delete_calendar_event_with_conn,
    get_calendar_links_for_event_with_conn, get_calendar_links_for_task_with_conn,
    get_provider_event_links_for_task_with_conn, link_task_to_provider_event_with_conn,
    link_tasks_to_calendar_event_with_conn, remove_calendar_event_exception_with_conn,
    unlink_task_from_calendar_event_with_conn, unlink_task_from_provider_event_with_conn,
    update_calendar_event_with_conn, CalendarEventCreateFields, CalendarEventCreateInput,
    CalendarEventUpdateFields,
};

pub(crate) fn run_calendar_create(
    fields: &CalendarEventCreateFields<'_>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let event = create_calendar_event_with_conn(&mut conn, fields)?;
    match format {
        OutputFormat::Text => crate::render::render_calendar_event_detail(&event, &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("calendar.create", &db_path, json!({ "event": event }))
        }
    }
}

pub(crate) fn run_calendar_batch_create(
    events_json: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let inputs: Vec<CalendarEventCreateInput> = serde_json::from_str(events_json)?;
    let result = create_calendar_events_with_conn(&mut conn, &inputs)?;

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Batch created Lorvex calendar events\nDB: {}\nCreated: {}\n",
                db_path.display(),
                result.created_count,
            );
            for event in &result.calendar_events {
                let _ = writeln!(output, "- {}: {}", event.id, event.title);
            }
            Ok(output)
        }
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "calendar.batch_create",
            &db_path,
            json!({
                "created_count": result.created_count,
                "calendar_events": result.calendar_events,
            }),
        ),
    }
}

pub(crate) fn run_calendar_update(
    event_id: &str,
    fields: &CalendarEventUpdateFields<'_>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let event = update_calendar_event_with_conn(&mut conn, &event_id, fields)?;
    match format {
        OutputFormat::Text => crate::render::render_calendar_event_detail(&event, &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("calendar.update", &db_path, json!({ "event": event }))
        }
    }
}

pub(crate) fn run_calendar_delete(
    event_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let deleted = delete_calendar_event_with_conn(&mut conn, &event_id)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Deleted Lorvex calendar event\nDB: {}\nID: {}\nTitle: {}\nUnlinked tasks: {}\n",
            db_path.display(),
            deleted.id,
            deleted.title,
            deleted.unlinked_task_ids.len(),
        )),
        // canonical CLI delete envelope shape.
        OutputFormat::Json => {
            render_mutation_envelope("calendar.delete", &db_path, json!({ "deleted": deleted }))
        }
    }
}

pub(crate) fn run_calendar_link(
    event_id: &str,
    task_ids: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = link_tasks_to_calendar_event_with_conn(&mut conn, &event_id, task_ids)?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Linked task(s) to Lorvex calendar event\nDB: {}\nEvent: {}\nLinked: {}\n",
            db_path.display(),
            result.event_id,
            result.linked_count,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("calendar.link", &db_path, json!({ "result": result }))
        }
    }
}

pub(crate) fn run_calendar_unlink(
    event_id: &str,
    task_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let task_id = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = unlink_task_from_calendar_event_with_conn(&mut conn, &event_id, &task_id)?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Unlinked task from Lorvex calendar event\nDB: {}\nEvent: {}\nTask: {}\nDeleted: {}\nRemaining task links: {}\n",
            db_path.display(),
            result.event_id,
            result.task_id,
            crate::render::yes_no(result.deleted),
            result.remaining_links.len(),
        )),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("calendar.unlink", &db_path, json!({ "result": result }))
        }
    }
}

pub(crate) fn run_calendar_links_for_task(
    task_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let links = get_calendar_links_for_task_with_conn(&conn, &task_id_typed)?;

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Lorvex calendar links for task\nDB: {}\nTask: {}\nLinks: {}\n",
                db_path.display(),
                task_id,
                links.len(),
            );
            for link in links {
                let _ = writeln!(
                    output,
                    "- {} (created {})",
                    link.calendar_event_id, link.created_at
                );
            }
            Ok(output)
        }
        OutputFormat::Json => render_query_envelope(
            "query.calendar.links_for_task",
            &db_path,
            json!({
                "task_id": task_id,
                "links": links,
            }),
        ),
    }
}

pub(crate) fn run_calendar_links_for_event(
    event_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let event_id_typed = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let links = get_calendar_links_for_event_with_conn(&conn, &event_id_typed)?;

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Lorvex calendar links for event\nDB: {}\nEvent: {}\nLinks: {}\n",
                db_path.display(),
                event_id,
                links.len(),
            );
            for link in links {
                let _ = writeln!(output, "- {} (created {})", link.task_id, link.created_at);
            }
            Ok(output)
        }
        OutputFormat::Json => render_query_envelope(
            "query.calendar.links_for_event",
            &db_path,
            json!({
                "event_id": event_id,
                "links": links,
            }),
        ),
    }
}

pub(crate) fn run_calendar_provider_link(
    task_id: &str,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let link = link_task_to_provider_event_with_conn(
        &mut conn,
        &task_id_typed,
        provider_kind,
        provider_scope,
        provider_event_key,
    )?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Linked task to provider calendar event\nDB: {}\nTask: {}\nProvider: {}:{}\nEvent key: {}\n",
            db_path.display(),
            link.task_id,
            link.provider_kind,
            link.provider_scope,
            link.provider_event_key,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "calendar.provider_link",
            &db_path,
            json!({ "link": link }),
        ),
    }
}

pub(crate) fn run_calendar_provider_unlink(
    task_id: &str,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let result = unlink_task_from_provider_event_with_conn(
        &mut conn,
        &task_id_typed,
        provider_kind,
        provider_scope,
        provider_event_key,
    )?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Unlinked task from provider calendar event\nDB: {}\nTask: {}\nProvider: {}:{}\nEvent key: {}\nRemaining provider links: {}\n",
            db_path.display(),
            result.task_id,
            result.provider_kind,
            result.provider_scope,
            result.provider_event_key,
            result.remaining_links.len(),
        )),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "calendar.provider_unlink",
            &db_path,
            json!({ "result": result }),
        ),
    }
}

pub(crate) fn run_calendar_provider_links_for_task(
    task_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let links = get_provider_event_links_for_task_with_conn(&conn, &task_id_typed)?;

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Lorvex provider calendar links for task\nDB: {}\nTask: {}\nLinks: {}\n",
                db_path.display(),
                task_id,
                links.len(),
            );
            for link in links {
                let _ = writeln!(
                    output,
                    "- {}:{} {} [{}]",
                    link.provider_kind,
                    link.provider_scope,
                    link.provider_event_key,
                    link.resolution_state,
                );
            }
            Ok(output)
        }
        OutputFormat::Json => render_query_envelope(
            "query.calendar.provider_links_for_task",
            &db_path,
            json!({
                "task_id": task_id,
                "links": links,
            }),
        ),
    }
}

pub(crate) fn run_calendar_add_exception(
    event_id: &str,
    date: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let event = add_calendar_event_exception_with_conn(&mut conn, &event_id, date)?;
    match format {
        OutputFormat::Text => crate::render::render_calendar_event_detail(&event, &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "calendar.add_exception",
            &db_path,
            json!({ "event": event }),
        ),
    }
}

pub(crate) fn run_calendar_remove_exception(
    event_id: &str,
    date: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let event = remove_calendar_event_exception_with_conn(&mut conn, &event_id, date)?;
    match format {
        OutputFormat::Text => crate::render::render_calendar_event_detail(&event, &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "calendar.remove_exception",
            &db_path,
            json!({ "event": event }),
        ),
    }
}
