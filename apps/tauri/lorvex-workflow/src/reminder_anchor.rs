//! Shared task-reminder local wall-clock anchor resolution.
//!
//! Reminder rows store `reminder_at` as a UTC instant, but timezone
//! preference changes need to preserve the user's local wall-clock intent
//! ("9 AM") rather than keep the old UTC instant fixed. The anchor columns
//! (`original_local_time`, `original_tz`) capture that local intent at write
//! time for every task reminder writer.

use chrono::{DateTime, TimeZone, Utc};
use lorvex_store::StoreError;
use rusqlite::Connection;

use crate::timezone::active_timezone_name;

pub fn resolve_task_reminder_local_anchor(
    conn: &Connection,
    reminder_at_rfc3339: &str,
) -> Result<(Option<String>, Option<String>), StoreError> {
    let reminder_utc = match DateTime::parse_from_rfc3339(reminder_at_rfc3339) {
        Ok(dt) => dt.with_timezone(&Utc),
        Err(_) => return Ok((None, None)),
    };
    resolve_task_reminder_local_anchor_for_utc(conn, &reminder_utc)
}

pub fn resolve_task_reminder_local_anchor_for_utc(
    conn: &Connection,
    reminder_utc: &DateTime<Utc>,
) -> Result<(Option<String>, Option<String>), StoreError> {
    let Some(tz_name) = active_timezone_name(conn)? else {
        return Ok((None, None));
    };
    let Some(tz) = lorvex_domain::parse_timezone_name(&tz_name) else {
        return Ok((None, None));
    };
    let local = tz.from_utc_datetime(&reminder_utc.naive_utc());
    Ok((Some(local.format("%H:%M").to_string()), Some(tz_name)))
}
