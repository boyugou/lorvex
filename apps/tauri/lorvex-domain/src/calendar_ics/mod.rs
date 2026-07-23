//! ICS (RFC 5545) calendar export.
//!
//! Splits the export pipeline into focused submodules so the contract for
//! each concern lives in one place:
//!
//! - [`model`] — the [`CalendarIcsEvent`] input struct, the [`CalendarIcsError`]
//!   typed-error enum, and the [`CalendarIcsWarning`] non-fatal diagnostic
//!   surface plus their `Display` / `Error` glue.
//! - [`validation`] — [`validate_export_range`] and the date-shape helpers
//!   ([`parse_required_date`](validation::parse_required_date),
//!   [`date_to_ics`](validation::date_to_ics),
//!   [`next_date`](validation::next_date)) that the rest of the pipeline
//!   reuses for `YYYY-MM-DD` validation and emission.
//! - [`emit`] — the public entry points [`export_calendar_ics`] /
//!   [`export_calendar_ics_with_warnings`], VEVENT assembly, timezone
//!   resolution, timestamp formatting, RFC 5545 TEXT escaping, and the
//!   75-octet line folder.
//! - [`recurrence`] — RRULE serialization
//!   ([`recurrence_to_rrule`](recurrence::recurrence_to_rrule)) and EXDATE
//!   emission ([`recurrence_exdates`](recurrence::recurrence_exdates)) with
//!   the per-VEVENT EXDATE cap that mirrors `MAX_CALENDAR_RECURRENCE_COUNT`.
//!
//! ## Re-export hub
//!
//! External callers (`lorvex-store::repositories::calendar_event_export`,
//! `mcp-server::server_calendar_ics`,
//! `app/src-tauri::commands::calendar_events::ics_export`,
//! `lorvex-cli::db_ops::calendar`) use both
//! `lorvex_domain::calendar_ics::*` AND the top-level re-exports
//! (`lorvex_domain::{export_calendar_ics, validate_export_range,
//! CalendarIcsEvent}`). The re-exports below keep both surfaces
//! byte-identical with the pre-decomposition flat module.

pub mod emit;
pub mod model;
pub mod recurrence;
pub mod validation;

#[cfg(test)]
mod tests;

pub use emit::{export_calendar_ics, export_calendar_ics_with_warnings};
pub use model::{CalendarIcsError, CalendarIcsEvent, CalendarIcsEventFields, CalendarIcsWarning};
pub use recurrence::{
    parse_ics_rrule_to_recurrence_json, parse_ics_rrule_to_recurrence_json_with_warnings,
    CalendarRruleParseWarning,
};
pub use validation::validate_export_range;
