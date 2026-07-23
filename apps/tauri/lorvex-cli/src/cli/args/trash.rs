//! Trash lifecycle argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::parse_task_id;
use super::TaskIdsArgs;

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum TrashCmd {
    /// Soft-delete a live task into Trash.
    Move(TaskIdsArgs),
    /// Restore a task from Trash.
    Restore(TaskIdsArgs),
    /// Permanently delete an already-Trashed task.
    Delete(TrashDeleteArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TrashDeleteArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Additional task IDs. Batch permanent delete is dry-run only.
    #[arg(
        num_args = 0..,
        requires = "dry_run",
        value_parser = parse_task_id
    )]
    pub(in crate::cli) extra_task_ids: Vec<String>,
    /// Preview the hard delete without mutating the database.
    #[arg(long = "dry-run")]
    pub(in crate::cli) dry_run: bool,
}
