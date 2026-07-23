use crate::startup_maintenance::open_db_at_path;
use chrono::Duration;
use lorvex_domain::CalendarAiAccessMode;
use lorvex_runtime::resolve_db_path;
use lorvex_store::calendar_timeline;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::mutate::calendar::effects::{
    export_calendar_ics_with_conn, search_calendar_events_with_conn,
};
use crate::commands::shared::render_query_envelope;
use crate::commands::shared::{
    anchored_timezone_name_for_conn, today_naivedate_for_conn, today_ymd_for_conn,
};
use crate::render::{render_calendar_event_detail, render_calendar_timeline};

pub(crate) fn run_calendar_list(
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    // Query upcoming 90 days by default
    let today = today_naivedate_for_conn(&conn)?;
    let from = today.format("%Y-%m-%d").to_string();
    let to = (today + Duration::days(90)).format("%Y-%m-%d").to_string();
    let anchor_tz = anchored_timezone_name_for_conn(&conn)?;

    let mut items = calendar_timeline::get_calendar_timeline(
        &conn,
        &from,
        &to,
        CalendarAiAccessMode::FullDetails,
        &anchor_tz,
    )?;
    items.truncate(limit as usize);
    render_calendar_timeline("Calendar Events", &db_path, &items, format)
}

pub(crate) fn run_calendar_show(
    event_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let row = calendar_timeline::queries::get_calendar_event(&conn, event_id)?;

    row.map_or_else(
        || {
            Err(crate::error::CliError::NotFound(format!(
                "calendar event '{event_id}' not found"
            )))
        },
        |event| render_calendar_event_detail(&event, &db_path, format),
    )
}

pub(crate) fn run_calendar_today(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let today = today_ymd_for_conn(&conn)?;
    let anchor_tz = anchored_timezone_name_for_conn(&conn)?;

    let items = calendar_timeline::get_calendar_timeline(
        &conn,
        &today,
        &today,
        CalendarAiAccessMode::FullDetails,
        &anchor_tz,
    )?;
    render_calendar_timeline("Today's Calendar", &db_path, &items, format)
}

/// CLI mirror of MCP `search_calendar_events`. Uses the
/// canonical store query (FTS5 with CJK-aware LIKE fallback). Output
/// shape matches the JSON envelope of `run_calendar_list` so a `jq`
/// consumer can swap one query for the other.
pub(crate) fn run_calendar_search(
    query: &str,
    from: Option<&str>,
    to: Option<&str>,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let rows = search_calendar_events_with_conn(&conn, query, from, to, limit)?;

    match format {
        OutputFormat::Text => {
            let mut out = format!(
                "Lorvex Calendar Search\nDB: {}\nQuery: {}\nMatches: {}\n",
                db_path.display(),
                query,
                rows.len()
            );
            if rows.is_empty() {
                out.push_str("  - none\n");
            } else {
                for ev in &rows {
                    let time_str = ev.start_time().map(|t| format!(" {t}")).unwrap_or_default();
                    let _ = writeln!(
                        out,
                        "  - {}{}: {} ({})",
                        ev.start_date(),
                        time_str,
                        ev.title,
                        ev.id
                    );
                }
            }
            Ok(out)
        }
        OutputFormat::Json => render_query_envelope(
            "query.calendar.search",
            &db_path,
            json!({
                "query": query,
                "from": from,
                "to": to,
                "limit": limit,
                "events": rows,
            }),
        ),
    }
}

pub(crate) fn run_calendar_export_ics(
    from: &str,
    to: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let ics = export_calendar_ics_with_conn(&conn, from, to)?;

    match format {
        OutputFormat::Text => Ok(ics),
        OutputFormat::Json => render_query_envelope(
            "query.calendar.export_ics",
            &db_path,
            json!({
                "from": from,
                "to": to,
                "ics": ics,
            }),
        ),
    }
}
