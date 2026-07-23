use chrono::{DateTime, Local};

use crate::error::{AppError, AppResult};

#[cfg(any(target_os = "windows", test))]
pub(crate) const WINDOWS_TICKS_PER_SECOND: i64 = 10_000_000;
#[cfg(any(target_os = "windows", test))]
pub(crate) const UNIX_TO_FILETIME_OFFSET: i64 = 116_444_736_000_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct LocalEventTimeProjection {
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: String,
    pub end_time: Option<String>,
}

pub(crate) fn resolve_provider_source_timezone_name(
    timezone_lookup: Result<String, String>,
) -> AppResult<String> {
    let timezone = timezone_lookup.map_err(|error| {
        AppError::Validation(format!(
            "provider sync requires a resolvable system IANA timezone: {error}"
        ))
    })?;
    lorvex_domain::normalize_timezone_name(Some(&timezone)).ok_or_else(|| {
        AppError::Validation(format!(
            "provider sync requires a valid IANA timezone, got '{timezone}'"
        ))
    })
}

#[cfg(target_os = "windows")]
pub(crate) fn current_provider_source_timezone_name() -> AppResult<String> {
    resolve_provider_source_timezone_name(
        iana_time_zone::get_timezone().map_err(|error| error.to_string()),
    )
}

pub(crate) fn project_epoch_seconds_to_local(
    start_secs: i64,
    end_secs: i64,
    all_day: bool,
) -> AppResult<LocalEventTimeProjection> {
    if end_secs < start_secs {
        return Err(AppError::Validation(format!(
            "provider event end precedes start: start={start_secs}, end={end_secs}"
        )));
    }

    let start_dt = local_timestamp(start_secs, "start")?;
    let end_dt = local_timestamp(end_secs, "end")?;

    Ok(LocalEventTimeProjection {
        start_date: start_dt.format("%Y-%m-%d").to_string(),
        start_time: (!all_day).then(|| start_dt.format("%H:%M").to_string()),
        end_date: end_dt.format("%Y-%m-%d").to_string(),
        end_time: (!all_day).then(|| end_dt.format("%H:%M").to_string()),
    })
}

#[cfg(any(target_os = "windows", test))]
pub(crate) fn project_windows_filetime_range_to_local(
    start_filetime: i64,
    duration_ticks: i64,
    all_day: bool,
) -> AppResult<LocalEventTimeProjection> {
    if duration_ticks < 0 {
        return Err(AppError::Validation(format!(
            "provider event duration is negative: {duration_ticks}"
        )));
    }

    let start_secs = (start_filetime - UNIX_TO_FILETIME_OFFSET) / WINDOWS_TICKS_PER_SECOND;
    let duration_secs = duration_ticks / WINDOWS_TICKS_PER_SECOND;
    let end_secs = start_secs
        .checked_add(duration_secs)
        .ok_or_else(|| AppError::Validation("provider event end overflowed".to_string()))?;

    project_epoch_seconds_to_local(start_secs, end_secs, all_day)
}

fn local_timestamp(epoch_seconds: i64, label: &str) -> AppResult<DateTime<Local>> {
    let utc = DateTime::from_timestamp(epoch_seconds, 0).ok_or_else(|| {
        AppError::Validation(format!(
            "provider event {label} timestamp is out of range: {epoch_seconds}"
        ))
    })?;
    Ok(utc.with_timezone(&Local))
}

#[cfg(test)]
mod tests;
