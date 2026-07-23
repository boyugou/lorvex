use chrono::{Datelike, NaiveDate};

use super::cadence::{HabitCadence, WeekDay};

/// Whether a habit is tracked as a single yes/no completion per period
/// (`Binary`) or as an accumulating numeric count (`Accumulative`).
///
/// Mirrors the TypeScript `progress_kind: 'binary' | 'accumulative'`
/// field in `shared/src/types.ts`; the `snake_case` serde tag is the
/// canonical wire form for both Tauri IPC and MCP responses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HabitProgressKind {
    Binary,
    Accumulative,
}

pub fn habit_progress_kind(target_count: i64) -> HabitProgressKind {
    if target_count.max(1) > 1 {
        HabitProgressKind::Accumulative
    } else {
        HabitProgressKind::Binary
    }
}

/// True iff a habit with `cadence` is "scheduled" on `date` — i.e. a
/// completion on that day counts toward the period bucket.
///
/// A `Weekly` cadence with no pinned weekdays (None or an empty set) is
/// treated as "every day" so the habit surfaces rather than silently
/// never firing.
pub fn is_habit_scheduled_on_day(cadence: &HabitCadence, date: NaiveDate) -> bool {
    match cadence {
        HabitCadence::Daily | HabitCadence::Monthly { .. } => true,
        // Defend against `Weekly { days: Some(empty) }`. `from_fields`
        // normalizes an empty set to `None`, but a malformed peer payload
        // that constructed the variant directly would otherwise return
        // `false` on every weekday (silent never-scheduled). We extend the
        // "every day" fallback to empty Some so the habit still surfaces;
        // `debug_assert!` flags the upstream construction bug in dev builds.
        HabitCadence::Weekly { days } => match days {
            None => true,
            Some(configured) if configured.is_empty() => {
                debug_assert!(false, "Weekly cadence with Some(empty) days is malformed");
                true
            }
            Some(configured) => configured.contains(&WeekDay::from_naive_date(date)),
        },
        HabitCadence::TimesPerWeek { count } => *count > 0,
    }
}

/// True iff a habit's *reminders* should fire on `date`.
///
/// Identical to [`is_habit_scheduled_on_day`] for every cadence except
/// `Monthly`. A monthly habit is "scheduled" every day (a completion on
/// any day counts toward the month's target), but its reminder fires on
/// exactly one day — the configured `day_of_month`, clamped to the
/// month's last day, defaulting to the 1st. Reminder scheduling must gate
/// on this rather than [`is_habit_scheduled_on_day`] or a monthly reminder
/// would fire every day until the month's target was met.
pub fn is_habit_reminder_day(cadence: &HabitCadence, date: NaiveDate) -> bool {
    match cadence {
        HabitCadence::Monthly { day_of_month } => {
            date.day() as i64 == effective_monthly_day(*day_of_month, date.year(), date.month())
        }
        _ => is_habit_scheduled_on_day(cadence, date),
    }
}

/// The day-of-month a monthly habit's reminder fires on for a given month:
/// the configured `day_of_month` (defaulting to 1) clamped down to the
/// month's last day, so a habit set to day 31 fires on Feb 28/29, Apr 30,
/// and so on.
pub fn effective_monthly_day(day_of_month: Option<i64>, year: i32, month: u32) -> i64 {
    let requested = day_of_month.unwrap_or(1).max(1);
    requested.min(days_in_month(year, month))
}

/// Number of days in the given Gregorian calendar month (handles leap
/// February via chrono's date arithmetic).
fn days_in_month(year: i32, month: u32) -> i64 {
    let (next_year, next_month) = if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    };
    let first_of_next = NaiveDate::from_ymd_opt(next_year, next_month, 1);
    let first_of_this = NaiveDate::from_ymd_opt(year, month, 1);
    match (first_of_next, first_of_this) {
        (Some(next), Some(this)) => (next - this).num_days(),
        _ => 31,
    }
}

pub fn habit_required_completions_per_period(cadence: &HabitCadence, target_count: i64) -> i64 {
    let target_count = target_count.max(1);
    let scheduled_slots = match cadence {
        HabitCadence::Daily | HabitCadence::Monthly { .. } => 1,
        HabitCadence::Weekly { days } => days
            .as_ref()
            .map_or(1, |configured| configured.len().max(1) as i64),
        HabitCadence::TimesPerWeek { count } => (*count).max(1),
    };
    scheduled_slots * target_count
}

pub fn habit_expected_completions_in_days(
    cadence: &HabitCadence,
    target_count: i64,
    window_days: i64,
) -> f64 {
    let window_days = window_days.max(1) as f64;
    let per_period = habit_required_completions_per_period(cadence, target_count) as f64;
    match cadence {
        HabitCadence::Daily => per_period * window_days,
        HabitCadence::Monthly { .. } => per_period * (window_days / 30.0),
        HabitCadence::Weekly { .. } | HabitCadence::TimesPerWeek { .. } => {
            per_period * (window_days / 7.0)
        }
    }
}

pub const fn habit_uses_week_bucket(cadence: &HabitCadence) -> bool {
    !matches!(cadence, HabitCadence::Daily | HabitCadence::Monthly { .. })
}
