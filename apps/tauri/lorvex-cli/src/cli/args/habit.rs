//! Habit and habit reminder argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{
    parse_cli_date_arg, parse_habit_frequency_type, parse_habit_id, parse_hex_color,
    parse_policy_id, parse_positive_i64, parse_time,
};
#[derive(Subcommand, Debug)]
pub(in crate::cli) enum HabitCmd {
    /// Create a habit.
    Create(HabitCreateArgs),
    /// Update habit metadata.
    Update(HabitUpdateArgs),
    /// Delete a habit and cascade its completion/reminder-policy children.
    Delete(HabitIdArgs),
    /// Record one completion increment for a habit.
    Complete(HabitCompleteArgs),
    /// Record one completion increment for multiple habits.
    BatchComplete(HabitBatchCompleteArgs),
    /// Remove all completions for a habit on a date.
    Uncomplete(HabitUncompleteArgs),
    /// Show habit completion statistics.
    Stats(HabitStatsArgs),
    /// Manage habit reminder policy slots.
    #[command(subcommand)]
    Reminder(HabitReminderCmd),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitCreateArgs {
    /// One or more words for the habit name (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) name: Vec<String>,
    #[arg(long = "icon")]
    pub(in crate::cli) icon: Option<String>,
    #[arg(long = "color", value_parser = parse_hex_color)]
    pub(in crate::cli) color: Option<String>,
    #[arg(long = "cue")]
    pub(in crate::cli) cue: Option<String>,
    #[arg(long = "frequency-type", value_parser = parse_habit_frequency_type)]
    pub(in crate::cli) frequency_type: Option<String>,
    /// Weekday for a `weekly` cadence (repeatable): mon/tue/wed/thu/fri/sat/sun.
    #[arg(long = "weekday")]
    pub(in crate::cli) weekday: Vec<String>,
    /// Completions required per week for a `times_per_week` cadence.
    #[arg(long = "per-period-target", value_parser = parse_positive_i64)]
    pub(in crate::cli) per_period_target: Option<i64>,
    /// Reminder day-of-month (1-31) for a `monthly` cadence.
    #[arg(long = "day-of-month", value_parser = parse_positive_i64)]
    pub(in crate::cli) day_of_month: Option<i64>,
    #[arg(long = "target-count", value_parser = parse_positive_i64)]
    pub(in crate::cli) target_count: Option<i64>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitUpdateArgs {
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
    #[arg(short = 'n', long = "name")]
    pub(in crate::cli) name: Option<String>,
    #[arg(long = "icon", conflicts_with = "clear_icon")]
    pub(in crate::cli) icon: Option<String>,
    #[arg(long = "clear-icon")]
    pub(in crate::cli) clear_icon: bool,
    #[arg(long = "color", value_parser = parse_hex_color, conflicts_with = "clear_color")]
    pub(in crate::cli) color: Option<String>,
    #[arg(long = "clear-color")]
    pub(in crate::cli) clear_color: bool,
    #[arg(long = "cue", conflicts_with = "clear_cue")]
    pub(in crate::cli) cue: Option<String>,
    #[arg(long = "clear-cue")]
    pub(in crate::cli) clear_cue: bool,
    /// Replace the cadence rhythm. Providing this (with any of
    /// `--weekday`/`--per-period-target`/`--day-of-month`) replaces the
    /// entire cadence atomically.
    #[arg(long = "frequency-type", value_parser = parse_habit_frequency_type)]
    pub(in crate::cli) frequency_type: Option<String>,
    /// Weekday for a `weekly` cadence (repeatable): mon..sun.
    #[arg(long = "weekday")]
    pub(in crate::cli) weekday: Vec<String>,
    /// Completions required per week for a `times_per_week` cadence.
    #[arg(long = "per-period-target", value_parser = parse_positive_i64)]
    pub(in crate::cli) per_period_target: Option<i64>,
    /// Reminder day-of-month (1-31) for a `monthly` cadence.
    #[arg(long = "day-of-month", value_parser = parse_positive_i64)]
    pub(in crate::cli) day_of_month: Option<i64>,
    #[arg(long = "target-count", value_parser = parse_positive_i64)]
    pub(in crate::cli) target_count: Option<i64>,
    #[arg(long = "archive", conflicts_with = "unarchive")]
    pub(in crate::cli) archive: bool,
    #[arg(long = "unarchive")]
    pub(in crate::cli) unarchive: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitIdArgs {
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitCompleteArgs {
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
    #[arg(long = "note")]
    pub(in crate::cli) note: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitBatchCompleteArgs {
    /// One or more habit ids to complete.
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_habit_id
    )]
    pub(in crate::cli) habit_ids: Vec<String>,
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitUncompleteArgs {
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitStatsArgs {
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
    /// Window size in days for the stats computation.
    #[arg(short = 'd', long = "days", value_parser = parse_positive_i64)]
    pub(in crate::cli) days: Option<i64>,
}

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum HabitReminderCmd {
    /// List habit reminder policies.
    List,
    /// Create or update a reminder policy slot.
    Upsert(HabitReminderUpsertArgs),
    /// Delete a reminder policy slot.
    Delete(HabitReminderDeleteArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitReminderUpsertArgs {
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
    #[arg(value_parser = parse_time)]
    pub(in crate::cli) reminder_time: String,
    #[arg(long = "id", value_parser = parse_policy_id)]
    pub(in crate::cli) policy_id: Option<String>,
    #[arg(long = "disabled")]
    pub(in crate::cli) disabled: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitReminderDeleteArgs {
    #[arg(value_parser = parse_policy_id)]
    pub(in crate::cli) policy_id: String,
}
