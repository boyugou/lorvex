use chrono::NaiveDate;
use lorvex_domain::habits::{
    compute_habit_current_streak, compute_habit_longest_streak, HabitStreakFrequency,
};

/// Dispatch shared streak computation based on frequency_type.
pub(crate) fn compute_streak_for_frequency(
    dates: &[NaiveDate],
    today: NaiveDate,
    frequency_type: &str,
    target_count: i64,
) -> i64 {
    compute_habit_current_streak(
        dates,
        today,
        HabitStreakFrequency::from_wire_str(frequency_type),
        target_count,
    )
}

/// Compute the best (longest) streak ever for a habit.
pub(super) fn compute_best_streak(
    dates: &[NaiveDate],
    frequency_type: &str,
    target_count: i64,
) -> i64 {
    compute_habit_longest_streak(
        dates,
        HabitStreakFrequency::from_wire_str(frequency_type),
        target_count,
    )
}
