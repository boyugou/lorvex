//! Recurrence-exception operations for `calendar_events`.
//!
//! Public API kept stable for callers (`add_recurrence_exception` /
//! `remove_recurrence_exception`); the body delegates to
//! [`super::recurrence_exceptions_common`] which carries the shared
//! validation, transaction, and LWW-gated UPDATE pipeline so the
//! task and event adapters stay byte-identical (see #3022 H1).

use rusqlite::Connection;

use super::recurrence_exceptions_common::{
    add_exception, remove_exception, ExceptionOwner, ExceptionTableConfig,
};
use crate::error::StoreError;
use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;

const CONFIG: ExceptionTableConfig = ExceptionTableConfig {
    entity: ENTITY_CALENDAR_EVENT,
    entity_noun: "Event",
    anchor_label: "event start date",
    select_anchor_sql: "SELECT recurrence, \
                (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                 FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id), \
                start_date \
         FROM calendar_events WHERE id = ?1",
    bump_version_sql: "UPDATE calendar_events SET version = ?1, updated_at = ?2 \
         WHERE id = ?3 AND ?1 > version",
    exception_owner: ExceptionOwner::CalendarEvent,
};

/// Add a recurrence exception date to a calendar event.
///
/// Validates: event exists, event is recurring, date is valid YYYY-MM-DD,
/// date >= start_date, date is an actual occurrence of the recurrence rule,
/// and date is not already in the exceptions list. Returns the updated
/// exceptions JSON string.
pub fn add_recurrence_exception(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<String, StoreError> {
    add_exception(
        conn,
        &CONFIG,
        event_id.as_str(),
        exception_date,
        version,
        now,
    )
}

/// Remove a recurrence exception date from a calendar event.
///
/// Validates: event exists, date is valid YYYY-MM-DD, and date is in the
/// current exceptions list. Returns the updated exceptions JSON string,
/// or `None` if the list is now empty.
pub fn remove_recurrence_exception(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
    exception_date: &str,
    version: &str,
    now: &str,
) -> Result<Option<String>, StoreError> {
    remove_exception(
        conn,
        &CONFIG,
        event_id.as_str(),
        exception_date,
        version,
        now,
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
