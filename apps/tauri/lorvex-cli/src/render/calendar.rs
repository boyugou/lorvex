//! Calendar render helpers (timeline + event detail).

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::render::format::{style_empty_hint, yes_no};

pub(crate) fn render_calendar_timeline(
    label: &str,
    db_path: &Path,
    items: &[lorvex_store::calendar_timeline::CalendarTimelineItem],
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!("Lorvex {label}\nDB: {}\n", db_path.display());
            if items.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No calendar items in window — add an event with `lorvex calendar add \"<title>\" --start <iso>` or subscribe to a calendar.",
                ));
            } else {
                for item in items {
                    let time_str = item
                        .start_time()
                        .map(|t| format!(" {t}"))
                        .unwrap_or_default();
                    let loc_str = item
                        .location()
                        .map(|loc| format!(" @ {loc}"))
                        .unwrap_or_default();
                    let _ = writeln!(
                        rendered,
                        "  - {}{}: {}{}",
                        item.start_date(),
                        time_str,
                        item.title(),
                        loc_str
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.calendar.timeline",
            db_path,
            json!({
                "label": label,
                "events": items,
            }),
        ),
    }
}

pub(crate) fn render_calendar_event_detail(
    event: &lorvex_store::calendar_timeline::CalendarEventRow,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let time_str = event
                .start_time()
                .map(|t| format!(" {t}"))
                .unwrap_or_default();
            // The typed `CalendarEventTiming` collapses same-day timed
            // events into `TimedSingleDay { date, .. }`, leaving
            // `end_date() == None` even when the event carries a real
            // `end_time`. Falling back to `start_date()` here keeps the
            // human-facing "End: <date> <time>" line meaningful for
            // single-day timed events instead of rendering "End: none"
            // any time the user didn't redundantly set end_date.
            let end_date = event.end_date().unwrap_or_else(|| event.start_date());
            let end_str = match (event.end_date(), event.end_time()) {
                (None, None) => "none".to_string(),
                (_, Some(et)) => format!("{end_date} {et}"),
                (Some(ed), None) => ed.to_string(),
            };
            Ok(format!(
                "Lorvex Calendar Event\nDB: {}\nID: {}\nTitle: {}\nStart: {}{}\nEnd: {}\nAll-day: {}\nType: {}\nLocation: {}\nDescription: {}\n",
                db_path.display(),
                event.id,
                event.title,
                event.start_date(),
                time_str,
                end_str,
                yes_no(event.all_day()),
                event.event_type,
                // `as_deref().unwrap_or("none")` avoids cloning the
                // `Option<String>` only to immediately format it; the
                // borrowed form passes a `&str` directly into the format
                // machinery on both arms.
                event.location.as_deref().unwrap_or("none"),
                event.description.as_deref().unwrap_or("none"),
            ))
        }
        // wrap the event in the query envelope.
        OutputFormat::Json => render_query_envelope(
            "query.calendar.event_detail",
            db_path,
            json!({ "event": event }),
        ),
    }
}
