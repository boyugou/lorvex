//! Habit `frequency_type` wire constants — must match the schema CHECK
//! on `habits.frequency_type`. The closed vocabulary is owned by the
//! typed `HabitCadence` enum (`lorvex_domain::habits`); these constants
//! are the wire-format string the typed enum serializes to via
//! `HabitCadence::to_fields()`.

pub const HABIT_FREQUENCY_DAILY: &str = "daily";
pub const HABIT_FREQUENCY_WEEKLY: &str = "weekly";
pub const HABIT_FREQUENCY_MONTHLY: &str = "monthly";
pub const HABIT_FREQUENCY_TIMES_PER_WEEK: &str = "times_per_week";
