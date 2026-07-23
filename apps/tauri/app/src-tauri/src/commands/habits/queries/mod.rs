#![allow(unused_imports)] // facade re-exports Tauri command entry points

pub(crate) mod commands;
mod streaks;
pub(crate) mod writes;

use lorvex_domain::{HabitFrequencyType, HabitProgressKind};
use serde::Serialize;

pub(crate) use commands::clear_best_streak_cache;
pub use commands::{adjust_habit_completion, get_habits_with_stats, get_todays_habits};

#[derive(Debug, Serialize)]
pub struct HabitWithStats {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub cue: Option<String>,
    pub frequency_type: HabitFrequencyType,
    /// `weekly` weekday set, Monday-first (0=Mon … 6=Sun). Empty for every
    /// non-weekly cadence and for weekly-every-day.
    pub weekdays: Vec<i64>,
    /// Completions required per week for a `times_per_week` cadence.
    pub per_period_target: i64,
    /// Reminder day-of-month for a `monthly` cadence (1–31), or `None`.
    pub day_of_month: Option<i64>,
    pub target_count: i64,
    // was missing archived/created_at/updated_at even
    // though the shared TS type (extends Habit) guarantees them.
    // Added now so the Tauri IPC shape is a strict superset of Habit
    // + the stats fields — matches both shared TS and the MCP flatten.
    pub archived: bool,
    pub created_at: String,
    pub updated_at: String,
    pub progress_kind: HabitProgressKind,
    pub completions_today: i64,
    pub current_streak: i64,
    pub best_streak: i64,
    pub total_completions: i64,
    pub completions_last_30: i64,
    pub completion_rate_30d: f64,
    /// Completion dates within the last 90 days, ISO YYYY-MM-DD format.
    pub recent_completion_dates: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct HabitSummary {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub cue: Option<String>,
    pub frequency_type: HabitFrequencyType,
    /// `weekly` weekday set, Monday-first (0=Mon … 6=Sun). Empty for every
    /// non-weekly cadence and for weekly-every-day.
    pub weekdays: Vec<i64>,
    /// Completions required per week for a `times_per_week` cadence.
    pub per_period_target: i64,
    /// Reminder day-of-month for a `monthly` cadence (1–31), or `None`.
    pub day_of_month: Option<i64>,
    pub target_count: i64,
    pub progress_kind: HabitProgressKind,
    pub completions_today: i64,
    pub current_streak: i64,
}
