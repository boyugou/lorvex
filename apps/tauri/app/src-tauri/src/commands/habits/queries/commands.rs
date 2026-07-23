use lorvex_domain::naming::{EDGE_HABIT_COMPLETION, OP_DELETE, OP_UPSERT};

use crate::commands::with_immediate_transaction;
use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use crate::event_bus;
use chrono::NaiveDate;
use rusqlite::{params, OptionalExtension};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

#[cfg(test)]
use std::sync::atomic::{AtomicUsize, Ordering};

use super::streaks::{compute_best_streak, compute_streak_for_frequency};
use super::{HabitSummary, HabitWithStats};

mod cache;
pub(crate) mod completion_adjust;
mod helpers;
pub(crate) mod stats;
mod streak_queries;
#[cfg(test)]
mod tests;
pub(crate) mod today;

pub(crate) use cache::clear_best_streak_cache;
pub(crate) use cache::invalidate_best_streak_cache;
pub use completion_adjust::adjust_habit_completion;
pub use stats::get_habits_with_stats;
pub use today::get_todays_habits;

use cache::{
    best_streak_cache, record_best_streak_full_history_scan_for_test, BEST_STREAK_CACHE_TTL,
};
use helpers::{
    cadence_from_columns, frequency_type_from_row, load_existing_completion_value,
    parse_habit_completion_date, parse_weekdays_json, progress_kind_for, HabitRow,
};
use streak_queries::{compute_all_streaks, compute_current_streak};
