//! Consolidated recurrence-expansion primitives.
//!
//! Merged from two prior implementations:
//! - `mcp-server/src/tasks/recurrence/date_math.rs`
//! - `app/src-tauri/src/commands/task_recurrence/{support,range_queries,count_end,next_occurrence}.rs`
//!
//! This module is the single source of truth for recurrence date math.

mod month_year;
mod mutation;
mod occurrence;
mod parse;
mod weekly;

pub use month_year::add_months_clamped;
pub use mutation::{decrement_recurrence_count, inject_bymonthday};
pub use occurrence::{
    calculate_next_occurrence_date, count_end_date, first_occurrence_on_or_after,
    next_occurrence_strictly_after, overlaps_calendar_range, recurs_on_date,
};
pub use parse::{parse_ymd, MAX_RECURRENCE_COUNT};
pub use weekly::{first_weekly_byday_occurrence_on_or_after, weekly_target_dows};

#[cfg(test)]
mod tests;
