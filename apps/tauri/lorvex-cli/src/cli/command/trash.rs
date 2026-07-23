//! Trash lifecycle arms (move/restore/delete on tasks).

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum TrashCommand {
    Move {
        task_ids: Vec<String>,
        format: OutputFormat,
    },
    Restore {
        task_ids: Vec<String>,
        format: OutputFormat,
    },
    Delete {
        task_ids: Vec<String>,
        dry_run: bool,
        format: OutputFormat,
    },
}
