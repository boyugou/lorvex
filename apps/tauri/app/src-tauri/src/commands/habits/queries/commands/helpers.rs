use super::*;

/// Habit row fields used by `adjust_habit_completion`:
/// `(name, icon, color, cue, frequency_type, per_period_target,
///   day_of_month, weekdays_json, target_count)`. `weekdays_json` is the
/// Monday-first integer array materialized from the `habit_weekdays`
/// child (e.g. `"[0,2]"`).
pub(super) type HabitRow = (
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    String,
    i64,
    Option<i64>,
    String,
    i64,
);

pub(super) fn progress_kind_for(target_count: i64) -> lorvex_domain::HabitProgressKind {
    lorvex_domain::habit_progress_kind(target_count)
}

/// Parse a `frequency_type` string from a SQLite row into the typed
/// [`lorvex_domain::HabitFrequencyType`]. The schema CHECK on
/// `habits.frequency_type` already restricts the column to the four
/// canonical values, so an unknown variant on read indicates a foreign
/// peer wrote a future value before this binary was upgraded — surface
/// it as a Validation error so the UI shows a diagnostic instead of
/// rendering a silently-wrong row.
pub(super) fn frequency_type_from_row(raw: &str) -> AppResult<lorvex_domain::HabitFrequencyType> {
    lorvex_domain::HabitFrequencyType::parse(raw).ok_or_else(|| {
        AppError::Validation(format!(
            "habits.frequency_type carries unknown value '{raw}' (expected daily/weekly/monthly/times_per_week)"
        ))
    })
}

/// Parse the `habit_weekdays` JSON integer array (Monday-first 0=Mon …
/// 6=Sun) materialized by the `json_group_array` projection. Malformed
/// JSON degrades to an empty set rather than failing the read.
pub(super) fn parse_weekdays_json(raw: &str) -> Vec<i64> {
    serde_json::from_str::<Vec<i64>>(raw).unwrap_or_default()
}

/// Build the typed [`lorvex_domain::HabitCadence`] from a habit row's
/// typed cadence columns plus its materialized weekday set.
pub(super) fn cadence_from_columns(
    frequency_type: &str,
    weekdays: &[i64],
    per_period_target: i64,
    day_of_month: Option<i64>,
) -> AppResult<lorvex_domain::HabitCadence> {
    let weekdays = if weekdays.is_empty() {
        None
    } else {
        Some(
            weekdays
                .iter()
                .filter_map(|index| lorvex_domain::habits::WeekDay::from_index(*index))
                .collect(),
        )
    };
    lorvex_domain::HabitCadence::from_fields(&lorvex_domain::habits::HabitFrequencyFields {
        frequency_type: frequency_type.to_string(),
        weekdays,
        per_period_target,
        day_of_month,
    })
    .map_err(AppError::from)
}

pub(super) fn parse_habit_completion_date(date_str: &str) -> AppResult<NaiveDate> {
    NaiveDate::parse_from_str(date_str, "%Y-%m-%d").map_err(|e| {
        AppError::Validation(format!("Invalid habit completion date '{date_str}': {e}"))
    })
}

pub(super) fn load_existing_completion_value(
    conn: &rusqlite::Connection,
    habit_id: &lorvex_domain::HabitId,
    completed_date: &str,
) -> AppResult<Option<i64>> {
    conn.query_row(
        "SELECT CAST(value AS INTEGER) FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
        params![habit_id.as_str(), completed_date],
        |row| row.get(0),
    )
    .optional()
    .map_err(AppError::from)
}
