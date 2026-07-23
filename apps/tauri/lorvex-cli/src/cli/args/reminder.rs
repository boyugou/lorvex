//! Task reminder argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{
    parse_positive_u32, parse_reminder_id, parse_rfc3339_timestamp, parse_task_id,
};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum ReminderCmd {
    /// Reminders due now.
    Due(ReminderDueArgs),
    /// Reminders due within the next N hours.
    Upcoming(ReminderUpcomingArgs),
    /// Replace all pending reminders for a task.
    Set(ReminderSetArgs),
    /// Clear all pending reminders for a task.
    Clear(ReminderTaskArgs),
    /// Append one reminder without replacing existing reminders.
    Add(ReminderAddArgs),
    /// Remove one reminder by reminder id.
    Remove(ReminderRemoveArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReminderDueArgs {
    #[arg(short = 'l', long = "limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReminderUpcomingArgs {
    #[arg(long = "hours", default_value_t = 24, value_parser = parse_positive_u32)]
    pub(in crate::cli) hours: u32,
    #[arg(short = 'l', long = "limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReminderSetArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// RFC 3339 reminder timestamp. Repeat to set multiple reminders.
    #[arg(long = "at", required = true, value_parser = parse_rfc3339_timestamp)]
    pub(in crate::cli) reminders: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReminderTaskArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReminderAddArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    #[arg(value_parser = parse_rfc3339_timestamp)]
    pub(in crate::cli) reminder_at: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReminderRemoveArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    #[arg(value_parser = parse_reminder_id)]
    pub(in crate::cli) reminder_id: String,
}
