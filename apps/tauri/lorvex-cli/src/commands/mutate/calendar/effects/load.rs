//! Read-only DB helpers for the calendar surface: row loaders, link
//! existence probes, and the public read entry points (link lookups,
//! provider-link resolution, calendar search, ICS export).
//!
//! All write paths live in `super::mutations`. Splitting reads from
//! writes keeps each side easy to audit independently — readers don't
//! mutate `(version, updated_at)` or enqueue outbox rows, so the bar
//! for "did this introduce a sync regression?" never trips here.

use lorvex_store::repositories::provider_repo::{self, ProviderEventLinkWithResolution};
use lorvex_store::repositories::task::calendar_links::{self, TaskCalendarEventLink};
use rusqlite::Connection;

use super::validation::normalize_nonempty_cli_id;
use crate::commands::shared::{ensure_task_exists, validate_calendar_date};

pub(super) fn load_calendar_event_row(
    conn: &Connection,
    event_id: &str,
) -> Result<Option<lorvex_store::calendar_timeline::CalendarEventRow>, crate::error::CliError> {
    lorvex_store::calendar_timeline::queries::get_calendar_event(conn, event_id).map_err(Into::into)
}

pub(super) fn ensure_calendar_event_exists(
    conn: &Connection,
    event_id: &str,
) -> Result<(), crate::error::CliError> {
    let exists = conn
        .prepare_cached("SELECT 1 FROM calendar_events WHERE id = ?1")?
        .exists([event_id])?;
    if exists {
        Ok(())
    } else {
        Err(crate::error::CliError::NotFound(format!(
            "calendar event '{event_id}' not found"
        )))
    }
}

pub(crate) fn get_calendar_links_for_task_with_conn(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
) -> Result<Vec<TaskCalendarEventLink>, crate::error::CliError> {
    ensure_task_exists(conn, task_id.as_str())?;
    calendar_links::get_links_for_task(conn, task_id).map_err(Into::into)
}

pub(crate) fn get_calendar_links_for_event_with_conn(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
) -> Result<Vec<TaskCalendarEventLink>, crate::error::CliError> {
    ensure_calendar_event_exists(conn, event_id.as_str())?;
    calendar_links::get_links_for_event(conn, event_id).map_err(Into::into)
}

pub(crate) fn get_provider_event_links_for_task_with_conn(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
) -> Result<Vec<ProviderEventLinkWithResolution>, crate::error::CliError> {
    let task_id_str = normalize_nonempty_cli_id(task_id.as_str(), "task id")?;
    ensure_task_exists(conn, &task_id_str)?;
    provider_repo::get_resolved_provider_links_for_task(conn, task_id).map_err(Into::into)
}

pub(crate) fn export_calendar_ics_with_conn(
    conn: &Connection,
    from: &str,
    to: &str,
) -> Result<String, crate::error::CliError> {
    lorvex_domain::validate_export_range(from, to)
        .map_err(|error| crate::error::CliError::Validation(error.to_string()))?;
    let rows = lorvex_store::repositories::calendar_event_export::list_calendar_events_for_ics(
        conn, from, to,
    )?;
    let events = rows
        .iter()
        .map(|row| row.as_ics_event())
        .collect::<Vec<_>>();
    lorvex_domain::export_calendar_ics(&events)
        .map_err(|error| crate::error::CliError::Internal(error.to_string()))
}

/// CLI mirror of MCP `search_calendar_events`. Validates
/// the optional from/to range at the trust boundary, then delegates to
/// the canonical store query (FTS5 with a CJK-aware LIKE fallback
/// baked in).
pub(crate) fn search_calendar_events_with_conn(
    conn: &Connection,
    query: &str,
    from: Option<&str>,
    to: Option<&str>,
    limit: u32,
) -> Result<Vec<lorvex_store::calendar_timeline::CalendarEventRow>, crate::error::CliError> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(crate::error::CliError::Validation(
            "search query must not be empty".to_string(),
        ));
    }
    if let Some(from) = from {
        validate_calendar_date(from)?;
    }
    if let Some(to) = to {
        validate_calendar_date(to)?;
    }
    let pred = lorvex_domain::query::CalendarSearchPredicate {
        query: trimmed.to_string(),
        from: from.map(std::string::ToString::to_string),
        to: to.map(std::string::ToString::to_string),
    };
    Ok(lorvex_store::calendar_timeline::queries::search_calendar_events(conn, &pred, limit)?)
}
