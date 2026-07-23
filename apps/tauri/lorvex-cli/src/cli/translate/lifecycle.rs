//! Task lifecycle mutators: `complete`, `reopen`, `cancel`, `defer`.
//! All map onto `Command::Tasks` variants of the same name.

use super::super::args::{CancelArgs, DeferArgs, TaskIdsArgs};
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_complete(args: TaskIdsArgs) -> Command {
    let TaskIdsArgs { task_ids } = args;
    Command::Tasks(TasksCommand::Complete {
        task_ids,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_reopen(args: TaskIdsArgs) -> Command {
    let TaskIdsArgs { task_ids } = args;
    Command::Tasks(TasksCommand::Reopen {
        task_ids,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_cancel(args: CancelArgs) -> Command {
    let CancelArgs { task_ids, series } = args;
    Command::Tasks(TasksCommand::Cancel {
        task_ids,
        // Preserve the pre-migration contract: absence of
        // --series → `None` (not `Some(false)`) so downstream
        // code can distinguish "series opt-out" from "not asked".
        cancel_series: series.then_some(true),
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_defer(args: DeferArgs) -> Command {
    let DeferArgs {
        task_ids,
        days,
        reason,
        structured_reason,
    } = args;
    Command::Tasks(TasksCommand::Defer {
        task_ids,
        days,
        reason,
        structured_reason,
        format: OutputFormat::default(),
    })
}
