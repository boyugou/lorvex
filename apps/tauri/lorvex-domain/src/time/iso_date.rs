//! `parse_iso_date` — the canonical hyphenated-date parser shared by
//! every domain caller that reads a calendar date column.

use chrono::NaiveDate;

use crate::validation::ValidationError;

/// Parse an ISO `YYYY-MM-DD` date string into a [`NaiveDate`].
///
/// This is the canonical hyphenated-date parser for the workspace.
/// Every site that reads a calendar date column
/// (`canonical_occurrence_date`, `start_date`, `due_date`,
/// `planned_date`, …) — and every CLI / MCP arg parser that wants the
/// parsed value, not just the validation outcome — routes through this
/// helper instead of calling `chrono::NaiveDate::parse_from_str(s,
/// "%Y-%m-%d")` directly. One definition, one `ValidationError` shape,
/// and the validator (`validate_date_format`) becomes a thin wrapper.
///
/// Note: this only accepts the canonical hyphenated form. The RFC 5545
/// compact `%Y%m%d` and DATE-TIME forms accepted by `parse_until_to_ymd`
/// in `validation::recurrence` are an explicit RFC-compatibility layer
/// and remain there — `parse_iso_date` is the schema-storage shape.
pub fn parse_iso_date(s: &str) -> Result<NaiveDate, ValidationError> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| ValidationError::InvalidFormat {
        field: "date",
        expected: "YYYY-MM-DD",
        actual: s.to_string(),
    })
}
