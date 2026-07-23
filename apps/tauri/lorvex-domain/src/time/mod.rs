//! Time / date / timezone primitives shared across the workspace.
//!
//! a single 790-line `time.rs`; split per-primitive so each
//! file holds one typed family and its associated impls. The public
//! surface is preserved verbatim through the re-exports below — every
//! external `use lorvex_domain::time::*` continues to compile, and the
//! crate-root re-exports in `lib.rs` (which import from
//! `crate::time::...`) are unaffected.

mod date;
mod due_at;
mod iso_date;
mod sync_timestamp;
mod time_of_day;
mod timezone;

pub use date::Date;
pub use due_at::{DueAt, DueAtFlat};
pub use iso_date::parse_iso_date;
pub use sync_timestamp::{
    canonicalize_rfc3339_instant, format_sync_timestamp, format_sync_timestamp_from_unix_ms,
    normalize_sync_timestamp, sync_timestamp_now, SyncTimestamp, SyncTimestampParseError,
};
pub use time_of_day::TimeOfDay;
pub use timezone::{
    date_plus_days_ymd_for_timezone_name, normalize_timezone_name, parse_json_timezone_preference,
    parse_required_timezone_preference, parse_timezone_name, resolve_anchored_timezone_name,
    today_ymd_for_timezone_name,
};

#[cfg(test)]
mod tests;
