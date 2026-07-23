//! Focus planning argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{parse_cli_date_arg, parse_task_id};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum FocusCmd {
    /// Show the focus list for a date (default when `lorvex focus` is run with no subcommand).
    Show(FocusDateArgs),
    /// Set the focus list to exactly these tasks (replaces current focus).
    Set(FocusMutationArgs),
    /// Add tasks to the current focus.
    Add(FocusMutationArgs),
    /// Remove one task from the current focus.
    Remove(FocusRemoveArgs),
    /// Clear the current focus.
    Clear(FocusDateArgs),
    /// Read or persist a time-blocked focus schedule.
    #[command(subcommand)]
    Schedule(FocusScheduleCmd),
}

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum FocusScheduleCmd {
    /// Show the saved focus schedule for a date.
    Get(FocusDateArgs),
    /// Propose a focus schedule from current-focus tasks and calendar blockers.
    Propose(FocusDateArgs),
    /// Save a focus schedule from a JSON blocks array.
    Save(FocusScheduleSaveArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct FocusScheduleSaveArgs {
    /// Focus schedule date in YYYY-MM-DD format. Defaults to today.
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
    /// JSON array of schedule blocks. Each block uses block_type, start_time, end_time, and optional task_id/event_id/title.
    #[arg(long = "blocks-json")]
    pub(in crate::cli) blocks_json: String,
    /// Optional AI explanation of the schedule reasoning.
    #[arg(long = "rationale")]
    pub(in crate::cli) rationale: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct FocusMutationArgs {
    /// Focus date in YYYY-MM-DD format. Defaults to today.
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
    /// One or more task ids.
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) task_ids: Vec<String>,
    /// Optional briefing text shown above the focus list.
    #[arg(long = "briefing")]
    pub(in crate::cli) briefing: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct FocusDateArgs {
    /// Focus date in YYYY-MM-DD format. Defaults to today.
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct FocusRemoveArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Focus date in YYYY-MM-DD format. Defaults to today.
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
}
