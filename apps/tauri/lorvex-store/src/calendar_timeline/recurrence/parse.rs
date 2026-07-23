use crate::error::StoreError;
use chrono::{Datelike, Duration, NaiveDate};
use serde_json::Value;

pub const MAX_RECURRENCE_COUNT: i64 = 1000;

/// Parse a `"YYYY-MM-DD"` string into a `NaiveDate`.
///
/// returned `Option<NaiveDate>` and was used at
/// `calendar_timeline::temporal::overlaps_item_range` to filter calendar
/// rows by date range — a corrupted `start_date` column silently
/// dropped the row from `false` overlap checks, so the calendar view
/// quietly stopped showing rows that should have been visible (or at
/// minimum surfaced as malformed). We now return `Result<NaiveDate,
/// StoreError>` so corrupt-DB-row signals propagate. Call sites that
/// have a legitimate reason to tolerate a parse failure (e.g.
/// user-typed query parameters) explicitly `.ok()` the result and
/// continue, making the lossy-vs-strict distinction visible at every
/// boundary.
pub fn parse_ymd(value: &str) -> Result<NaiveDate, StoreError> {
    lorvex_domain::time::parse_iso_date(value).map_err(|error| {
        StoreError::Validation(format!("invalid YYYY-MM-DD date string `{value}`: {error}"))
    })
}

pub(super) fn parse_required_ymd(value: &str, field: &str) -> Result<NaiveDate, StoreError> {
    parse_ymd(value).map_err(|_| StoreError::Validation(format!("invalid {field}: {value}")))
}

pub(super) fn parse_rule_object(recurrence_json: &str) -> Result<Value, StoreError> {
    match serde_json::from_str::<Value>(recurrence_json)? {
        Value::Object(rule) => Ok(Value::Object(rule)),
        _ => Err(StoreError::Serialization(
            "invalid recurrence rule: recurrence must be a JSON object".to_string(),
        )),
    }
}

pub(super) fn parse_freq(rule: &Value) -> Result<&str, StoreError> {
    rule.get("FREQ")
        .and_then(Value::as_str)
        .ok_or_else(|| StoreError::Validation("invalid recurrence rule: missing FREQ".to_string()))
}

pub(super) fn parse_interval(rule: &Value) -> Result<i64, StoreError> {
    match rule.get("INTERVAL") {
        None | Some(Value::Null) => Ok(1),
        Some(value) => match value.as_i64() {
            Some(interval) if interval >= 1 => Ok(interval),
            _ => Err(StoreError::Validation(
                "invalid recurrence rule: INTERVAL must be a positive integer".to_string(),
            )),
        },
    }
}

pub(super) fn parse_until(rule: &Value) -> Result<Option<NaiveDate>, StoreError> {
    match rule.get("UNTIL") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => {
            let until = value.as_str().ok_or_else(|| {
                StoreError::Validation(
                    "invalid recurrence rule: UNTIL must be a YYYY-MM-DD string".to_string(),
                )
            })?;
            Ok(Some(parse_required_ymd(until, "UNTIL")?))
        }
    }
}

pub(super) fn parse_positive_count(rule: &Value) -> Result<Option<i64>, StoreError> {
    match rule.get("COUNT") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => match value.as_i64() {
            Some(count) if count >= 1 => Ok(Some(count)),
            _ => Err(StoreError::Validation(
                "invalid recurrence rule: COUNT must be a positive integer".to_string(),
            )),
        },
    }
}

pub(super) fn parse_bounded_count_for_expansion(rule: &Value) -> Result<Option<i64>, StoreError> {
    let Some(count) = parse_positive_count(rule)? else {
        return Ok(None);
    };
    if count > MAX_RECURRENCE_COUNT {
        return Err(StoreError::Validation(format!(
            "invalid recurrence rule: COUNT {count} exceeds maximum {MAX_RECURRENCE_COUNT}"
        )));
    }
    Ok(Some(count))
}

/// RFC 5545 BYMONTHDAY anchor. Positive values count from month start
/// (1-31). Negative values count from month end (-1 = last day, -2 =
/// second-to-last, …). Subscribed ICS feeds commonly use `-1` for
/// "last day of month" (rent, payroll, month-end reports).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ByMonthDayAnchor {
    FromStart(u32),
    FromEnd(u32),
}

impl ByMonthDayAnchor {
    /// Resolve the anchor to a concrete day number in the given
    /// `(year, month)`. Clamps against the month's actual length so
    /// `FromStart(31)` in February resolves to 28/29 just like the
    /// legacy `target_day.min(max_day)` path.
    pub(crate) fn resolve(self, year: i32, month: u32) -> Option<u32> {
        let max_day = days_in_month(year, month)?;
        match self {
            ByMonthDayAnchor::FromStart(day) => Some(day.min(max_day)),
            ByMonthDayAnchor::FromEnd(offset) => {
                let clamped = offset.min(max_day);
                Some(max_day - clamped + 1)
            }
        }
    }
}

/// Parse `BYMONTHDAY` into the set of day-of-month anchors a period
/// expands to.
///
/// Absent / null / empty falls back to `[FromStart(fallback_day)]` (the
/// base day-of-month). A scalar (`15`, stored before the array form)
/// yields one anchor; an array (`[1, 15]` — "1st and 15th") yields one
/// anchor per entry. Each entry must be in `[-31, -1] ∪ [1, 31]`. The
/// returned anchors are not pre-sorted; callers resolve each to a date
/// and sort/dedup the resulting dates.
pub(super) fn parse_bymonthday(
    rule: &Value,
    fallback_day: u32,
) -> Result<Vec<ByMonthDayAnchor>, StoreError> {
    let raws: Vec<i64> = match rule.get("BYMONTHDAY") {
        None | Some(Value::Null) => return Ok(vec![ByMonthDayAnchor::FromStart(fallback_day)]),
        Some(value) => {
            if let Some(scalar) = value.as_i64() {
                vec![scalar]
            } else if let Some(arr) = value.as_array() {
                let mut xs = Vec::with_capacity(arr.len());
                for item in arr {
                    let n = item.as_i64().ok_or_else(|| {
                        StoreError::Validation(
                            "invalid recurrence rule: BYMONTHDAY entries must be integers in [-31, -1] or [1, 31]"
                                .to_string(),
                        )
                    })?;
                    xs.push(n);
                }
                xs
            } else {
                return Err(StoreError::Validation(
                    "invalid recurrence rule: BYMONTHDAY must be an integer or array of integers in [-31, -1] or [1, 31]"
                        .to_string(),
                ));
            }
        }
    };
    if raws.is_empty() {
        return Ok(vec![ByMonthDayAnchor::FromStart(fallback_day)]);
    }
    let mut anchors = Vec::with_capacity(raws.len());
    for day in raws {
        if (1..=31).contains(&day) {
            anchors.push(ByMonthDayAnchor::FromStart(day as u32));
        } else if (-31..=-1).contains(&day) {
            // RFC 5545 §3.3.10 BYMONTHDAY: "Valid values are 1 to 31
            // or -31 to -1." -1 == last day of month, -2 ==
            // second-to-last, and so on.
            anchors.push(ByMonthDayAnchor::FromEnd(day.unsigned_abs() as u32));
        } else {
            return Err(StoreError::Validation(
                "invalid recurrence rule: BYMONTHDAY must be an integer in [-31, -1] or [1, 31]"
                    .to_string(),
            ));
        }
    }
    Ok(anchors)
}

/// Map an iCalendar BYDAY two-letter code to `num_days_from_sunday`.
pub(super) fn byday_code_to_num(value: &str) -> Option<u32> {
    match value {
        "SU" => Some(0),
        "MO" => Some(1),
        "TU" => Some(2),
        "WE" => Some(3),
        "TH" => Some(4),
        "FR" => Some(5),
        "SA" => Some(6),
        _ => None,
    }
}

/// Number of days in the given calendar month.
pub(super) fn days_in_month(year: i32, month: u32) -> Option<u32> {
    let next_month_first = if month == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)?
    } else {
        NaiveDate::from_ymd_opt(year, month + 1, 1)?
    };
    Some((next_month_first - Duration::days(1)).day())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ByDayToken {
    pub(super) ordinal: Option<i32>,
    pub(super) dow: u32,
}

fn parse_byday_token(value: &str) -> Result<ByDayToken, StoreError> {
    // RFC 5545 BYDAY tokens are ASCII-only (`[+/-][0-9]+(MO|TU|...|SU)`).
    // char straddled the byte-2-from-end boundary (e.g. an MCP client
    // sent `"日MO"`); rejecting non-ASCII up front turns that into a
    // typed Validation error instead of a panic.
    if value.len() < 2 || !value.is_ascii() {
        return Err(StoreError::Validation(format!(
            "invalid recurrence rule: unsupported BYDAY code {value}"
        )));
    }
    let (prefix, code) = value.split_at(value.len() - 2);
    let dow = byday_code_to_num(code).ok_or_else(|| {
        StoreError::Validation(format!(
            "invalid recurrence rule: unsupported BYDAY code {value}"
        ))
    })?;
    let ordinal = if prefix.is_empty() {
        None
    } else {
        let ordinal = prefix.parse::<i32>().map_err(|_| {
            StoreError::Validation(format!(
                "invalid recurrence rule: unsupported BYDAY ordinal {value}"
            ))
        })?;
        if ordinal == 0 || !(-53..=53).contains(&ordinal) {
            return Err(StoreError::Validation(format!(
                "invalid recurrence rule: unsupported BYDAY ordinal {value}"
            )));
        }
        Some(ordinal)
    };
    Ok(ByDayToken { ordinal, dow })
}

pub(super) fn parse_byday_tokens(rule: &Value) -> Result<Option<Vec<ByDayToken>>, StoreError> {
    let Some(byday) = rule.get("BYDAY").and_then(Value::as_array) else {
        return Ok(None);
    };
    if byday.is_empty() {
        return Ok(None);
    }

    let mut tokens = Vec::with_capacity(byday.len());
    for raw in byday {
        let code = raw.as_str().ok_or_else(|| {
            StoreError::Validation(
                "invalid recurrence rule: BYDAY entries must be weekday codes".to_string(),
            )
        })?;
        tokens.push(parse_byday_token(code)?);
    }
    Ok(Some(tokens))
}

pub(super) fn parse_bymonth(rule: &Value) -> Result<Option<Vec<u32>>, StoreError> {
    let Some(bymonth) = rule.get("BYMONTH").and_then(Value::as_array) else {
        if rule.get("BYMONTH").is_some() {
            return Err(StoreError::Validation(
                "invalid recurrence rule: BYMONTH must be an array of months in 1..=12".to_string(),
            ));
        }
        return Ok(None);
    };
    if bymonth.is_empty() {
        return Ok(None);
    }

    let mut months = Vec::with_capacity(bymonth.len());
    for raw in bymonth {
        match raw.as_i64() {
            Some(month) if (1..=12).contains(&month) => months.push(month as u32),
            _ => {
                return Err(StoreError::Validation(
                    "invalid recurrence rule: BYMONTH entries must be integers in 1..=12"
                        .to_string(),
                ))
            }
        }
    }
    months.sort_unstable();
    months.dedup();
    Ok(Some(months))
}

pub(super) fn parse_bysetpos(rule: &Value) -> Result<Option<Vec<i64>>, StoreError> {
    let Some(bysetpos) = rule.get("BYSETPOS").and_then(Value::as_array) else {
        if rule.get("BYSETPOS").is_some() {
            return Err(StoreError::Validation(
                "invalid recurrence rule: BYSETPOS must be an array of integers".to_string(),
            ));
        }
        return Ok(None);
    };
    if bysetpos.is_empty() {
        return Ok(None);
    }

    let mut positions = Vec::with_capacity(bysetpos.len());
    for raw in bysetpos {
        match raw.as_i64() {
            Some(position) if position != 0 && (-366..=366).contains(&position) => {
                positions.push(position);
            }
            _ => {
                return Err(StoreError::Validation(
                    "invalid recurrence rule: BYSETPOS entries must be in -366..=-1 or 1..=366"
                        .to_string(),
                ))
            }
        }
    }
    positions.sort_unstable();
    positions.dedup();
    Ok(Some(positions))
}

pub(super) fn parse_wkst(rule: &Value) -> Result<u32, StoreError> {
    match rule.get("WKST") {
        None | Some(Value::Null) => Ok(1),
        Some(value) => {
            let code = value.as_str().ok_or_else(|| {
                StoreError::Validation(
                    "invalid recurrence rule: WKST must be a weekday code".to_string(),
                )
            })?;
            byday_code_to_num(code).ok_or_else(|| {
                StoreError::Validation(format!(
                    "invalid recurrence rule: unsupported WKST code {code}"
                ))
            })
        }
    }
}
