//! Timezone-aware date/time helpers for MCP tool handlers.
//!
//! Only the substantive `bounds` adapter (with its own struct + field
//! mapping) needs to live here. The pass-through wrappers that
//! sit alongside it (`active_timezone_name_from_conn`,
//! `anchored_timezone_name_from_conn`, `today_ymd_for_conn`,
//! `date_plus_days_ymd_for_conn`, `today_ymd_for_conn_at`) were deleted —
//! they did nothing beyond `lorvex_workflow::timezone::X(conn)?`,
//! which `?` already routes through the `From<StoreError> for McpError`
//! impl. Callers now `use lorvex_workflow::timezone::*` directly.
//!
//! : this lived in a `time_support/bounds.rs`
//! sub-module, but with only one tiny child file the indirection added
//! no structure — inlined into a single flat file.

use crate::error::McpError;
use chrono::{DateTime, Utc};
use rusqlite::Connection;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TrailingDayWindowUtcBounds {
    pub(crate) from_day: String,
    pub(crate) to_day: String,
    pub(crate) start_utc: String,
    pub(crate) end_utc: String,
}

pub(crate) fn trailing_day_window_bounds_for_conn(
    conn: &Connection,
    span_days: i64,
) -> Result<TrailingDayWindowUtcBounds, McpError> {
    trailing_day_window_bounds_for_conn_at(conn, Utc::now(), span_days)
}

pub(crate) fn trailing_day_window_bounds_for_conn_at(
    conn: &Connection,
    now: DateTime<Utc>,
    span_days: i64,
) -> Result<TrailingDayWindowUtcBounds, McpError> {
    let bounds = lorvex_workflow::timezone::trailing_day_window_utc_bounds_for_conn_at(
        conn, now, span_days,
    )?;
    Ok(TrailingDayWindowUtcBounds {
        from_day: bounds.from_day,
        to_day: bounds.to_day,
        start_utc: bounds.start_utc,
        end_utc: bounds.end_utc,
    })
}
