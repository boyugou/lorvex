//! Pure validation helpers — shape checks (date/time/length/url/color),
//! recurrence-UNTIL ordering, DST-gap rejection. No `Patch` plumbing
//! (see `patches`).

use chrono::{NaiveDate, NaiveDateTime, NaiveTime};
use lorvex_domain::dst::{resolve_local_datetime, DstResolution};

use super::{CalendarDstGuard, CalendarNormalizationError, CalendarNormalizationResult};

pub(super) fn validate_length(
    value: &str,
    field: &'static str,
    max: usize,
) -> CalendarNormalizationResult<()> {
    let actual = value.chars().count();
    if actual > max {
        return Err(CalendarNormalizationError::validation(format!(
            "{field} exceeds maximum length of {max}"
        )));
    }
    Ok(())
}

pub(super) fn validate_date(
    value: &str,
    field: &'static str,
) -> CalendarNormalizationResult<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| CalendarNormalizationError::validation(format!("{field} must be YYYY-MM-DD")))
}

pub(super) fn validate_time(
    value: &str,
    field: &'static str,
) -> CalendarNormalizationResult<NaiveTime> {
    NaiveTime::parse_from_str(value, "%H:%M")
        .map_err(|_| CalendarNormalizationError::validation(format!("{field} must be HH:MM (24h)")))
}

pub(super) fn validate_optional_color(value: Option<&str>) -> CalendarNormalizationResult<()> {
    if let Some(value) = value {
        lorvex_domain::validation::validate_hex_color(value)
            .map_err(|e| CalendarNormalizationError::validation(e.to_string()))?;
    }
    Ok(())
}

pub(super) fn validate_field_shape(
    start_date: &str,
    start_time: Option<&str>,
    end_date: Option<&str>,
    end_time: Option<&str>,
    all_day: bool,
) -> CalendarNormalizationResult<()> {
    let start_day = validate_date(start_date, "start_date")?;
    let end_day = match end_date {
        Some(value) => {
            let parsed = validate_date(value, "end_date")?;
            if parsed < start_day {
                return Err(CalendarNormalizationError::validation(format!(
                    "end_date ({value}) cannot be before start_date ({start_date})"
                )));
            }
            Some(parsed)
        }
        None => None,
    };
    let parsed_start_time = start_time
        .map(|value| validate_time(value, "start_time"))
        .transpose()?;
    let parsed_end_time = end_time
        .map(|value| validate_time(value, "end_time"))
        .transpose()?;
    if all_day {
        return Ok(());
    }
    // The domain layer's `CalendarEventTiming::from_flat_fields` rejects
    // non-all-day events with no `start_time` as a typed
    // `ValidationError`. That error surfaces from the storage writer
    // wrapped in a `StoreError` boundary, which the IPC envelope then
    // routes through the `Internal` arm — the user sees only "An
    // internal error occurred." with no hint that they forgot to set a
    // time. Hoist the check up here so the failure becomes a
    // `Validation` error with a clear message at the workflow layer,
    // and the form's toast renders an actionable hint instead of the
    // sanitized generic.
    if parsed_start_time.is_none() {
        // Covers the end-time-without-start-time case too: a timed event with
        // an end time but no start time trips this same check.
        return Err(CalendarNormalizationError::validation(
            "Pick a start time, or mark this event as all-day.",
        ));
    }
    if let (Some(start), Some(end)) = (parsed_start_time, parsed_end_time) {
        let same_day = end_day.unwrap_or(start_day) == start_day;
        if same_day && end <= start {
            return Err(CalendarNormalizationError::validation(
                "end_time must be after start_time for same-day events",
            ));
        }
    }
    Ok(())
}

pub(super) fn validate_recurrence_until_after_start(
    recurrence: Option<&str>,
    start_date: &str,
) -> CalendarNormalizationResult<()> {
    let Some(recurrence) = recurrence else {
        return Ok(());
    };
    let parsed: serde_json::Value = serde_json::from_str(recurrence).map_err(|e| {
        CalendarNormalizationError::validation(format!(
            "post-normalization recurrence not parseable as JSON: {e}"
        ))
    })?;
    let Some(until) = parsed.get("UNTIL").and_then(serde_json::Value::as_str) else {
        return Ok(());
    };
    if until < start_date {
        return Err(CalendarNormalizationError::validation(format!(
            "recurrence.UNTIL ({until}) cannot be before start_date ({start_date})"
        )));
    }
    Ok(())
}

pub(super) fn check_calendar_event_dst(
    start_date: &str,
    start_time: Option<&str>,
    timezone: Option<&str>,
    all_day: bool,
) -> CalendarNormalizationResult<CalendarDstGuard> {
    if all_day {
        return Ok(CalendarDstGuard::Ok);
    }
    let Some(start_time) = start_time else {
        return Ok(CalendarDstGuard::Ok);
    };
    let Some(tz_name) = timezone.filter(|name| !name.is_empty()) else {
        return Ok(CalendarDstGuard::Ok);
    };
    let Some(tz) = lorvex_domain::parse_timezone_name(tz_name) else {
        return Ok(CalendarDstGuard::Ok);
    };
    let parsed_date = validate_date(start_date, "start_date")?;
    let parsed_time = validate_time(start_time, "start_time")?;
    let local = NaiveDateTime::new(parsed_date, parsed_time);
    match resolve_local_datetime(tz, local) {
        DstResolution::Valid(_) => Ok(CalendarDstGuard::Ok),
        DstResolution::Ambiguous { .. } => Ok(CalendarDstGuard::Ambiguous {
            wall_clock: format!("{start_date} {start_time}"),
            timezone: tz_name.to_string(),
        }),
        DstResolution::Skipped { .. } => Err(CalendarNormalizationError::validation(format!(
            "The selected time {start_time} on {start_date} does not exist in \
             {tz_name} - a daylight-saving spring-forward transition skipped \
             over it. Please pick a wall-clock time before or after the gap \
             (typically one hour earlier or later)."
        ))),
    }
}
