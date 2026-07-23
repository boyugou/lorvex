//! `lorvex trash …` dispatcher — soft-delete moves, restores, and the
//! eventual permanent purge.

use crate::cli::TrashCommand;
use crate::commands::mutate::{
    run_trash_delete_tasks, run_trash_move_tasks, run_trash_restore_tasks,
};
use crate::error::CliError;

pub(super) fn dispatch_trash(command: TrashCommand) -> Result<(), CliError> {
    match command {
        TrashCommand::Move { task_ids, format } => {
            println!("{}", run_trash_move_tasks(&task_ids, format)?);
        }
        TrashCommand::Restore { task_ids, format } => {
            println!("{}", run_trash_restore_tasks(&task_ids, format)?);
        }
        TrashCommand::Delete {
            task_ids,
            dry_run,
            format,
        } => println!("{}", run_trash_delete_tasks(&task_ids, dry_run, format)?),
    }
    Ok(())
}
