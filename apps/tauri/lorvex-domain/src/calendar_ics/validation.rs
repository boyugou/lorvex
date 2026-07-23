//! Date-shape validation and `YYYY-MM-DD` <-> `YYYYMMDD` conversion helpers.
//!
//! [`validate_export_range`] is the public entry point; the rest of the
//! helpers ([`parse_required_date`], [`date_to_ics`], [`next_date`]) are
//! shared by the emitter and the recurrence serializer.

use chrono::NaiveDate;

use super::model::CalendarIcsError;
use crate::time::Date;

pub fn validate_export_range(from: &str, to: &str) -> Result<(), CalendarIcsError> {
    parse_required_date("from", from)?;
    parse_required_date("to", to)?;
    if to < from {
        return Err(CalendarIcsError::InvalidRange {
            from: from.to_string(),
            to: to.to_string(),
        });
    }
    Ok(())
}

pub(super) fn parse_required_date(
    field: &'static str,
    raw: &str,
) -> Result<NaiveDate, CalendarIcsError> {
    NaiveDate::parse_from_str(raw, "%Y-%m-%d").map_err(|_| CalendarIcsError::InvalidDate {
        field,
        value: raw.to_string(),
    })
}

/// Render a typed [`Date`] as the RFC 5545 `YYYYMMDD` form for DTSTART /
/// DTEND / EXDATE. Infallible because the typed value is already validated
/// at construction.
pub(super) fn date_to_ics(date: Date) -> String {
    date.as_naive_date().format("%Y%m%d").to_string()
}

/// String-input variant of [`date_to_ics`] reserved for the recurrence
/// JSON parse path (RRULE `UNTIL=`, EXDATE source dates) where the
/// value is plucked from JSON and not yet routed through the typed
/// [`Date`] wrapper. Validates the `YYYY-MM-DD` shape and returns the
/// `YYYYMMDD` ICS form.
pub(super) fn date_str_to_ics(field: &'static str, raw: &str) -> Result<String, CalendarIcsError> {
    Ok(parse_required_date(field, raw)?
        .format("%Y%m%d")
        .to_string())
}

/// Compute the calendar day after `date` as a typed [`Date`]. Returns a
/// typed `DateOverflow` error when the input is at chrono's representable
/// upper bound (e.g. `9999-12-31`). derive the inclusive-DTEND
/// for all-day VEVENTs (RFC 5545 requires DTEND = day-after the last
/// occurrence for VALUE=DATE events).
pub(super) fn next_date(field: &'static str, date: Date) -> Result<Date, CalendarIcsError> {
    // Use `checked_add_days` (not `+ Duration::days(1)`) so a
    // far-future end_date like `"9999-12-31"` surfaces as a proper
    // error rather than panicking on chrono overflow — `+
    // Duration::days(1)` would be a craftable ICS-export DOS for any
    // input that lets the user pass a far-future date.
    date.as_naive_date()
        .checked_add_days(chrono::Days::new(1))
        .map(Date::from)
        .ok_or_else(|| CalendarIcsError::DateOverflow {
            field,
            value: date.to_string(),
        })
}
