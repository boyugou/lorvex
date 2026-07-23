use crate::error::McpError;
use chrono::NaiveDate;
use lorvex_domain::habits::{
    compute_habit_current_streak, compute_habit_longest_streak, HabitStreakFrequency,
};

pub(super) fn compute_streak(
    dates: &[String],
    today: &str,
    frequency_type: &str,
    target_count: i64,
) -> Result<i64, McpError> {
    let parsed = parse_ymd_values(dates)?;
    let today_date = parse_ymd(today)?;
    Ok(compute_habit_current_streak(
        &parsed,
        today_date,
        HabitStreakFrequency::from_wire_str(frequency_type),
        target_count,
    ))
}

pub(super) fn compute_longest_streak(
    dates: &[String],
    frequency_type: &str,
    target_count: i64,
) -> Result<i64, McpError> {
    let parsed = parse_ymd_values(dates)?;
    Ok(compute_habit_longest_streak(
        &parsed,
        HabitStreakFrequency::from_wire_str(frequency_type),
        target_count,
    ))
}

fn parse_ymd_values(dates: &[String]) -> Result<Vec<NaiveDate>, McpError> {
    dates
        .iter()
        .map(|value| parse_ymd(value))
        .collect::<Result<Vec<_>, _>>()
}

fn parse_ymd(date: &str) -> Result<NaiveDate, McpError> {
    lorvex_domain::time::parse_iso_date(date).map_err(|error| {
        McpError::Validation(format!("invalid habit completion date '{date}': {error}"))
    })
}
