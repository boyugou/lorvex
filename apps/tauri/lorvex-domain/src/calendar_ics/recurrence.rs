//! RRULE serialization and EXDATE emission.
//!
//! [`recurrence_to_rrule`] funnels a stored recurrence JSON payload
//! through [`crate::validation::normalize_task_recurrence_with_warnings`]
//! and then assembles the RFC 5545 `RRULE:` line. [`recurrence_exdates`]
//! deduplicates and caps the per-VEVENT EXDATE list, sharing the
//! DTSTART-shape decision and UTC-conversion helpers from
//! [`super::emit`] so EXDATE shape always matches DTSTART.

use serde_json::Value;

use crate::validation::MAX_CALENDAR_RECURRENCE_COUNT;

use super::emit::{is_date_value_event, local_to_utc_ics_timestamp};
use super::model::{CalendarIcsError, CalendarIcsEvent, CalendarIcsWarning};
use super::validation::date_str_to_ics;
use crate::time::Date;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarRruleParseWarning {
    pub message: String,
    pub details: String,
}

impl CalendarRruleParseWarning {
    fn new(message: impl Into<String>, details: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            details: details.into(),
        }
    }
}

fn parse_rrule_i64(
    raw: &str,
    key: &str,
    value: &str,
    warnings: &mut Vec<CalendarRruleParseWarning>,
) -> Option<i64> {
    if let Ok(n) = value.parse::<i64>() {
        Some(n)
    } else {
        warnings.push(CalendarRruleParseWarning::new(
            "malformed RRULE dropped",
            format!("rrule={raw}; field={key}; value={value:?}"),
        ));
        None
    }
}

fn parse_rrule_i64_list(
    raw: &str,
    key: &str,
    value: &str,
    warnings: &mut Vec<CalendarRruleParseWarning>,
) -> Option<Vec<serde_json::Value>> {
    let mut values = Vec::new();
    for part in value.split(',') {
        let trimmed = part.trim();
        if trimmed.is_empty() {
            warnings.push(CalendarRruleParseWarning::new(
                "empty RRULE numeric list dropped",
                format!("rrule={raw}; field={key}"),
            ));
            return None;
        }
        values.push(serde_json::Value::Number(
            parse_rrule_i64(raw, key, trimmed, warnings)?.into(),
        ));
    }
    if values.is_empty() {
        warnings.push(CalendarRruleParseWarning::new(
            "empty RRULE numeric list dropped",
            format!("rrule={raw}; field={key}"),
        ));
        return None;
    }
    Some(values)
}

/// Convert a raw ICS `RRULE` value into the canonical recurrence JSON
/// shape used by calendar-event storage and expansion.
///
/// The parser only translates RFC 5545 wire syntax into the JSON field
/// shape; acceptance is delegated to
/// [`crate::validation::normalize_calendar_recurrence`] so imported
/// subscriptions, stored calendar events, and exported ICS rules share
/// the same recurrence contract.
pub fn parse_ics_rrule_to_recurrence_json(raw: &str) -> Option<String> {
    let mut warnings = Vec::new();
    parse_ics_rrule_to_recurrence_json_with_warnings(raw, &mut warnings)
}

pub fn parse_ics_rrule_to_recurrence_json_with_warnings(
    raw: &str,
    warnings: &mut Vec<CalendarRruleParseWarning>,
) -> Option<String> {
    let mut map = serde_json::Map::new();
    for part in raw.split(';') {
        let (key, value) = part.split_once('=')?;
        let key = key.trim().to_ascii_uppercase();
        let value = value.trim();
        match key.as_str() {
            "INTERVAL" | "COUNT" => {
                let n = parse_rrule_i64(raw, &key, value, warnings)?;
                if n < 1 {
                    warnings.push(CalendarRruleParseWarning::new(
                        "non-positive RRULE dropped",
                        format!("rrule={raw}; field={key}; value={n}"),
                    ));
                    return None;
                }
                map.insert(key, serde_json::Value::Number(n.into()));
            }
            "BYMONTHDAY" | "BYMONTH" | "BYSETPOS" => {
                // RFC 5545 lets these carry a comma list (`BYMONTHDAY=1,15`);
                // all three are canonically arrays of integers.
                let values = parse_rrule_i64_list(raw, &key, value, warnings)?;
                map.insert(key, serde_json::Value::Array(values));
            }
            "BYDAY" => {
                let days: Vec<serde_json::Value> = value
                    .split(',')
                    .map(|d| serde_json::Value::String(d.trim().to_ascii_uppercase()))
                    .collect();
                if !days.is_empty() {
                    map.insert(key, serde_json::Value::Array(days));
                }
            }
            // `UNTIL` is pinned as a named arm even though the body is
            // identical to the wildcard: the explicit arm documents
            // that the value flows verbatim into the JSON projection
            // and `normalize_calendar_recurrence` is the validation
            // owner. Future tightening (e.g. parsing the ICS DATE-TIME
            // shape here) only needs to mutate one named arm.
            #[allow(clippy::match_same_arms)]
            "UNTIL" => {
                map.insert(key, serde_json::Value::String(value.to_string()));
            }
            _ => {
                map.insert(key, serde_json::Value::String(value.to_string()));
            }
        }
    }
    if map.is_empty() || !map.contains_key("FREQ") {
        return None;
    }
    let raw_json = serde_json::to_string(&map).ok()?;
    match crate::validation::normalize_calendar_recurrence(Some(&raw_json)) {
        Ok(normalized) => normalized,
        Err(error) => {
            warnings.push(CalendarRruleParseWarning::new(
                "unsupported RRULE dropped",
                format!("rrule={raw}; error={error}"),
            ));
            None
        }
    }
}

pub(super) fn recurrence_to_rrule(
    recurrence: Option<&str>,
    warnings: &mut Vec<CalendarIcsWarning>,
) -> Result<Option<String>, CalendarIcsError> {
    use std::fmt::Write as _;
    let raw = match recurrence.map(str::trim) {
        Some(raw) if !raw.is_empty() => raw,
        _ => return Ok(None),
    };

    // Route through `normalize_task_recurrence_with_warnings`
    // before splicing into the RRULE so the accept/reject set stays
    // identical across surfaces — every key the validator preserves
    // lands in the exported RRULE. A bespoke validator here would
    // drift from the canonical one (the seven-code BYDAY check,
    // BYSETPOS / WKST, etc.) and let a sync peer or imported feed
    // land payloads in storage that the serializer would then
    // re-emit as `BYDAY=garbage` or drop entirely.
    let Some((canonical, recurrence_warnings)) =
        crate::validation::normalize_task_recurrence_with_warnings(raw)
            .map_err(|err| CalendarIcsError::InvalidRecurrenceRule(err.to_string()))?
    else {
        return Ok(None);
    };

    for w in recurrence_warnings {
        warnings.push(CalendarIcsWarning::Recurrence(w));
    }

    let parsed: Value = serde_json::from_str(&canonical)
        .map_err(|_| CalendarIcsError::InvalidRecurrenceJson(canonical.clone()))?;
    let object = parsed.as_object().ok_or_else(|| {
        CalendarIcsError::InvalidRecurrenceRule(
            "recurrence payload must be a JSON object".to_string(),
        )
    })?;

    // FREQ is guaranteed to be present and valid post-normalize.
    // a contract violation here means the
    // normalizer pass upstream of `format_rrule` did not run or did
    // not produce its canonical shape. Surface the typed error
    // instead of panicking inside the export pipeline.
    let freq = object.get("FREQ").and_then(|v| v.as_str()).ok_or(
        CalendarIcsError::InternalContractViolation {
            field: "FREQ",
            detail: "normalize_recurrence_rule must populate FREQ before format_rrule runs",
        },
    )?;

    // Stream every part directly into a single `String` instead of
    // collecting `Vec<String>` of parts (and inner `Vec<String>` for
    // each comma-list) and then `format!("RRULE:{}", parts.join(";"))`.
    // The previous shape allocated a fresh `String` per part plus one
    // backing vec per BY* list — a constant-allocation tax on every
    // recurrence-bearing VEVENT export.
    let mut rrule = String::with_capacity(64);
    rrule.push_str("RRULE:FREQ=");
    rrule.push_str(freq);

    // INTERVAL is canonicalized to always be present; only emit
    // when greater than the RFC default of 1 to keep the RRULE compact.
    // same contract as FREQ above.
    let interval = object
        .get("INTERVAL")
        .and_then(serde_json::Value::as_i64)
        .ok_or(CalendarIcsError::InternalContractViolation {
            field: "INTERVAL",
            detail: "normalize_recurrence_rule must populate INTERVAL before format_rrule runs",
        })?;
    if interval > 1 {
        let _ = write!(rrule, ";INTERVAL={interval}");
    }

    if let Some(byday) = object.get("BYDAY").and_then(|v| v.as_array()) {
        append_csv_part(
            &mut rrule,
            ";BYDAY=",
            byday.iter().filter_map(|v| v.as_str()),
        );
    }

    // BYMONTH is the most common YEARLY modifier in
    // real calendar feeds (leap-year birthdays, "every February"). It
    // emits before BYMONTHDAY so the RRULE reads in RFC 5545's
    // broader-filter-first order: month-of-year first, then
    // day-of-month inside that month.
    if let Some(bymonth) = object.get("BYMONTH").and_then(|v| v.as_array()) {
        append_csv_int_part(
            &mut rrule,
            ";BYMONTH=",
            bymonth.iter().filter_map(serde_json::Value::as_i64),
        );
    }
    if let Some(bymonthday) = object.get("BYMONTHDAY").and_then(|v| v.as_array()) {
        append_csv_int_part(
            &mut rrule,
            ";BYMONTHDAY=",
            bymonthday.iter().filter_map(serde_json::Value::as_i64),
        );
    } else if let Some(day) = object.get("BYMONTHDAY").and_then(serde_json::Value::as_i64) {
        // Back-compat: a scalar BYMONTHDAY stored before the array form.
        let _ = write!(rrule, ";BYMONTHDAY={day}");
    }

    if let Some(bysetpos) = object.get("BYSETPOS").and_then(|v| v.as_array()) {
        append_csv_int_part(
            &mut rrule,
            ";BYSETPOS=",
            bysetpos.iter().filter_map(serde_json::Value::as_i64),
        );
    }

    if let Some(count) = object.get("COUNT").and_then(serde_json::Value::as_i64) {
        let _ = write!(rrule, ";COUNT={count}");
    }

    if let Some(until) = object.get("UNTIL").and_then(|v| v.as_str()) {
        let _ = write!(rrule, ";UNTIL={}", date_str_to_ics("UNTIL", until)?);
    }

    if let Some(start) = object.get("WKST").and_then(|v| v.as_str()) {
        rrule.push_str(";WKST=");
        rrule.push_str(start);
    }

    Ok(Some(rrule))
}

/// Append `prefix` followed by a comma-separated list of `&str` items
/// to `out`. Skips entirely when the iterator yields no items so a
/// `BYDAY=[]` survival (defense-in-depth against an upstream that emits
/// an empty array) does not leave a dangling `;BYDAY=`.
fn append_csv_part<'a, I: IntoIterator<Item = &'a str>>(out: &mut String, prefix: &str, items: I) {
    let mut iter = items.into_iter();
    let Some(first) = iter.next() else {
        return;
    };
    out.push_str(prefix);
    out.push_str(first);
    for item in iter {
        out.push(',');
        out.push_str(item);
    }
}

/// Variant of [`append_csv_part`] for integer items — formats each into
/// the buffer in place rather than materializing a `Vec<String>` of
/// stringified ints.
fn append_csv_int_part<I: IntoIterator<Item = i64>>(out: &mut String, prefix: &str, items: I) {
    use std::fmt::Write as _;
    let mut iter = items.into_iter();
    let Some(first) = iter.next() else {
        return;
    };
    out.push_str(prefix);
    let _ = write!(out, "{first}");
    for item in iter {
        let _ = write!(out, ",{item}");
    }
}

/// cap on emitted `EXDATE` lines per VEVENT,
/// matching `MAX_CALENDAR_RECURRENCE_COUNT = 365` (the calendar
/// recurrence series cap). 366 leaves room for a leap-year series
/// that excludes every instance (one EXDATE per generated
/// occurrence). A peer envelope crafted with
/// `recurrence_exceptions = ["2026-03-25"]*10000` would otherwise
/// produce 10k EXDATE lines — a UI / parser DOS for any external
/// client that loads the `.ics`.
const MAX_RECURRENCE_EXDATES: usize = (MAX_CALENDAR_RECURRENCE_COUNT as usize) + 1;

/// error variant exposing the cap so a peer authoring
/// an over-long EXDATE list surfaces a typed diagnostic instead of
/// silently truncating.
pub(super) fn recurrence_exdates(
    event: &CalendarIcsEvent<'_>,
) -> Result<Vec<String>, CalendarIcsError> {
    let raw = match event.recurrence_exceptions.map(str::trim) {
        Some(raw) if !raw.is_empty() => raw,
        _ => return Ok(Vec::new()),
    };

    let dates: Vec<String> = serde_json::from_str(raw)
        .map_err(|_| CalendarIcsError::InvalidRecurrenceExceptionJson(raw.to_string()))?;

    // dedupe by canonicalized YYYY-MM-DD shape
    // BEFORE comparing against the cap so a malformed feed that
    // repeats the same date 10k times collapses to one line and a
    // legitimate 365-instance series with a few duplicates still
    // exports cleanly. Canonicalization also normalizes any
    // accepted-but-non-canonical input (e.g. `"2026-3-5"` would
    // round-trip into `"2026-03-05"`) so two textual variants of
    // the same calendar day collapse into one EXDATE.
    let mut seen: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    let mut canonical_dates: Vec<String> =
        Vec::with_capacity(dates.len().min(MAX_RECURRENCE_EXDATES));
    for date in &dates {
        let parsed = chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d")
            .map_err(|_| CalendarIcsError::InvalidRecurrenceExceptionDate(date.clone()))?;
        let canonical = parsed.format("%Y-%m-%d").to_string();
        if seen.insert(canonical.clone()) {
            canonical_dates.push(canonical);
        }
    }
    if canonical_dates.len() > MAX_RECURRENCE_EXDATES {
        return Err(CalendarIcsError::RecurrenceExdateLimitExceeded {
            count: canonical_dates.len(),
            limit: MAX_RECURRENCE_EXDATES,
        });
    }

    let is_date_value = is_date_value_event(event);

    canonical_dates
        .iter()
        .map(|date| {
            // Route the canonical date string through the typed
            // [`Date`] wrapper so the local→UTC emit helper takes
            // a typed value end-to-end. Since `canonical_dates` was
            // produced by `chrono::NaiveDate::format("%Y-%m-%d")`,
            // re-parsing through `Date::parse` always succeeds; the
            // map_err arm is defensive in case of a future code
            // change to the canonicalization step.
            let typed_date = Date::parse(date)
                .map_err(|_| CalendarIcsError::InvalidRecurrenceExceptionDate(date.clone()))?;
            let date_ics = super::validation::date_to_ics(typed_date);
            if is_date_value {
                Ok(format!("EXDATE;VALUE=DATE:{date_ics}"))
            } else {
                // same contract as the
                // DTSTART branch above — a non-date-value VEVENT
                // requires `start_time` to be `Some`. Route a
                // breach through the typed-error path so the
                // EXDATE producer fails fast on a malformed input
                // rather than panicking the writer.
                let start_time = event.start_time().ok_or(
                    CalendarIcsError::InternalContractViolation {
                        field: "start_time",
                        detail: "is_date_value_event=false requires start_time to be Some when emitting EXDATE",
                    },
                )?;
                // Use the same local→UTC conversion as DTSTART so the
                // EXDATE actually matches one of the generated recurrence
                // instances. Emitting naive-local-as-Z would leave
                // EXDATE floating an hours-offset away from the RRULE
                // expansion and no external client would cancel the
                // excluded occurrence.
                let utc_ts =
                    local_to_utc_ics_timestamp(typed_date, start_time, event.timezone, "start");
                Ok(format!("EXDATE:{utc_ts}"))
            }
        })
        .collect()
}
