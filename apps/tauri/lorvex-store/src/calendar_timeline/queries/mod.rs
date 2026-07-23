//! Shared SQL queries for calendar timeline and blocking-range retrieval.
//!
//! These functions read from both `calendar_events` (canonical, synced) and
//! `provider_calendar_events` (device-local mirror) and apply recurrence
//! expansion before returning results.
//!
//! # Module layout
//!
//! Shared helpers used by every public entry point live here in `mod.rs`
//! (`extend_with_tolerant_expansion`, `redact_provider_details`,
//! `calendar_event_from_row`). Per-surface entry points live in dedicated
//! submodules — `timeline.rs` for the timeline range projection,
//! `blocking.rs` for daily blocking-range derivation, and `search.rs` for
//! FTS5/LIKE text search. The submodule public functions are re-exported
//! here so callers continue to import from
//! `calendar_timeline::queries::{...}`.

use crate::error::StoreError;
use chrono::NaiveDate;
use lorvex_domain::CanonicalCalendarEventType;
use rusqlite::{Connection, OptionalExtension};

use super::expansion::{expand_row_for_range, RawCalendarRow, MAX_EXPANSION_STEPS};
use super::types::CalendarTimelineItem;

mod blocking;
mod search;
mod timeline;

#[cfg(test)]
mod tests;

pub use blocking::get_day_blocking_ranges;
pub use search::search_calendar_events;
pub use timeline::get_calendar_timeline;

const CALENDAR_EVENT_READ_COLUMNS: &[&str] = &[
    "id",
    "title",
    "description",
    "recurrence",
    "recurrence_exceptions",
    "timezone",
    "start_date",
    "start_time",
    "end_date",
    "end_time",
    "all_day",
    "location",
    "color",
    "event_type",
    "person_name",
    "url",
    "created_at",
    "updated_at",
    "version",
];

pub(super) fn calendar_event_read_projection(table_alias: Option<&str>) -> String {
    // The `recurrence_exceptions` registry lives in a child table.
    // The read projection rebuilds the wire form via a correlated
    // `json_group_array` subquery so every row mapper still sees the
    // JSON-array string at the same tuple position; an empty registry
    // collapses to `NULL` (via `NULLIF(..., '[]')`), the canonical
    // "no exceptions" representation shared with the sync payload
    // builders and the Apple app. The owner column qualifier follows
    // the caller's table alias (or the table name when bare).
    let owner_prefix: String = match table_alias {
        Some(alias) => alias.to_string(),
        None => "calendar_events".to_string(),
    };
    let exceptions_expr = format!(
        "(SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM calendar_event_recurrence_exceptions \
         WHERE event_id = {owner_prefix}.id) AS recurrence_exceptions",
    );
    CALENDAR_EVENT_READ_COLUMNS
        .iter()
        .map(|column| {
            if *column == "recurrence_exceptions" {
                exceptions_expr.clone()
            } else {
                match table_alias {
                    Some(alias) => format!("{alias}.{column}"),
                    None => (*column).to_string(),
                }
            }
        })
        .collect::<Vec<_>>()
        .join(", ")
}

pub fn get_calendar_event(
    conn: &Connection,
    id: &str,
) -> Result<Option<super::types::CalendarEventRow>, rusqlite::Error> {
    let sql = format!(
        "SELECT {} FROM calendar_events WHERE id = ?1",
        calendar_event_read_projection(None),
    );
    conn.query_row(&sql, [id], calendar_event_from_row)
        .optional()
}

pub fn list_calendar_events(
    conn: &Connection,
    from: &str,
    to: &str,
    limit: u32,
    offset: u32,
) -> Result<Vec<super::types::CalendarEventRow>, rusqlite::Error> {
    let sql = format!(
        "SELECT {} \
         FROM calendar_events \
         WHERE start_date <= ?1 \
           AND (recurrence IS NOT NULL OR COALESCE(end_date, start_date) >= ?2) \
         ORDER BY start_date ASC, start_time ASC, id ASC \
         LIMIT ?3 OFFSET ?4",
        calendar_event_read_projection(None),
    );
    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(
        rusqlite::params![to, from, i64::from(limit), i64::from(offset)],
        calendar_event_from_row,
    )?;
    rows.collect()
}

/// Expand a single calendar row's recurrences into the output list,
/// tolerating per-row malformed RRULEs by logging + skipping the row
/// rather than aborting the whole query (#2864).
///
/// `Validation` errors (e.g. malformed JSON, out-of-range recurrence
/// modifiers, or unsupported RRULE fields) and `Invariant` errors (e.g.
/// expansion-step ceiling, non-advancing rule) propagate via
/// `?` and blank the entire timeline UI for the user. Other
/// `StoreError` kinds (Sql, Io, DiskFull, etc.) still propagate
/// — those genuinely indicate the entire query cannot proceed.
pub(super) fn extend_with_tolerant_expansion(
    conn: &Connection,
    items: &mut Vec<CalendarTimelineItem>,
    row: &RawCalendarRow,
    from_date: NaiveDate,
    to_date: NaiveDate,
    anchor_timezone: &str,
) -> Result<(), StoreError> {
    let event_id_for_log = row.item.id.as_str();
    match expand_row_for_range(row, from_date, to_date, anchor_timezone) {
        Ok(expanded) => {
            if expanded.truncated_at_step_cap {
                // Long-running daily series (e.g. a 14-year habit) and
                // 100-year-window UI queries can legitimately exceed
                // the per-row expansion budget. Surface a warn-level
                // breadcrumb so operators can spot the truncation in
                // diagnostics, but keep the partial results we already
                // computed so the user still sees their event in the
                // entirely after the inner function raised Invariant).
                crate::error::log::append_error_log_best_effort(
                    conn,
                    "calendar_timeline.expansion_truncated",
                    &format!(
                        "calendar event {event_id_for_log} expansion truncated at \
                         {MAX_EXPANSION_STEPS} steps; rendering partial occurrences",
                    ),
                    Some(&format!("event_id={event_id_for_log}")),
                    Some("warn"),
                );
            }
            items.extend(expanded.items);
            Ok(())
        }
        Err(StoreError::Validation(msg)) | Err(StoreError::Invariant(msg)) => {
            // Best-effort log; never let logging failures cascade.
            // The remaining `Invariant` arm covers the genuinely-bad
            // cases (e.g. non-advancing RRULE) where we cannot return
            // partial results because the loop would never terminate.
            crate::error::log::append_error_log_best_effort(
                conn,
                "calendar_timeline.expansion",
                &format!("skipped unsupported recurrence on event {event_id_for_log}"),
                Some(&msg),
                Some("warn"),
            );
            Ok(())
        }
        Err(other) => Err(other),
    }
}

/// Redact detail fields on a provider timeline item for `BusyOnly` mode.
/// Replaces title, location, person_name, and attendees with opaque placeholders.
pub(super) fn redact_provider_details(item: &mut CalendarTimelineItem) {
    item.title = "Busy".to_string();
    item.location = None;
    item.person_name = None;
    item.attendees_json = None;
}

/// Shared row mapper for calendar event SELECT results.
pub(super) fn calendar_event_from_row(
    row: &rusqlite::Row<'_>,
) -> Result<super::types::CalendarEventRow, rusqlite::Error> {
    let event_type_raw: String = row.get(13)?;
    let event_type = event_type_raw
        .parse::<CanonicalCalendarEventType>()
        .map_err(|message| {
            rusqlite::Error::FromSqlConversionFailure(
                13,
                rusqlite::types::Type::Text,
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    message,
                )),
            )
        })?;
    super::types::CalendarEventRow::new(super::types::CalendarEventRowFields {
        id: row.get(0)?,
        title: row.get(1)?,
        description: row.get(2)?,
        recurrence: row.get(3)?,
        recurrence_exceptions: row.get(4)?,
        timezone: row.get(5)?,
        start_date: row.get(6)?,
        start_time: row.get(7)?,
        end_date: row.get(8)?,
        end_time: row.get(9)?,
        all_day: row.get(10)?,
        location: row.get(11)?,
        color: row.get(12)?,
        event_type,
        person_name: row.get(14)?,
        url: row.get(15)?,
        created_at: row.get(16)?,
        updated_at: row.get(17)?,
        version: row.get(18)?,
    })
    // Surface the typed-timing validation error in the same shape as
    // the `event_type` parse failure above (column index 6 == start_date,
    // the first column of the temporal quintuple). The row mapper
    // signature is `fn(&Row) -> Result<_, rusqlite::Error>`, so we lift
    // the `ValidationError` into `FromSqlConversionFailure`; downstream
    // collectors propagate it through `Result<Vec<_>, _>::collect()`
    // exactly as they did for the legacy direct `row.get` failures.
    .map_err(|err| {
        rusqlite::Error::FromSqlConversionFailure(
            6,
            rusqlite::types::Type::Text,
            Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                err.to_string(),
            )),
        )
    })
}
