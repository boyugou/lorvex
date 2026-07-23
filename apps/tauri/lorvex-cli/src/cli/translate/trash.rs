use super::super::args::{TaskIdsArgs, TrashCmd, TrashDeleteArgs};
use super::super::command::{Command, OutputFormat, TrashCommand};

pub(in crate::cli) fn translate_trash(cmd: TrashCmd) -> Command {
    Command::Trash(match cmd {
        TrashCmd::Move(TaskIdsArgs { task_ids }) => TrashCommand::Move {
            task_ids,
            format: OutputFormat::default(),
        },
        TrashCmd::Restore(TaskIdsArgs { task_ids }) => TrashCommand::Restore {
            task_ids,
            format: OutputFormat::default(),
        },
        TrashCmd::Delete(TrashDeleteArgs {
            task_id,
            extra_task_ids,
            dry_run,
        }) => {
            let mut task_ids = vec![task_id];
            task_ids.extend(extra_task_ids);
            TrashCommand::Delete {
                task_ids,
                dry_run,
                format: OutputFormat::default(),
            }
        }
    })
}
