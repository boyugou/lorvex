//! `lorvex reminders …` dispatcher (task reminders).

use crate::cli::RemindersCommand;
use crate::commands::mutate::{
    run_task_reminder_add, run_task_reminder_clear, run_task_reminder_remove, run_task_reminder_set,
};
use crate::commands::query::{run_due_task_reminders, run_upcoming_task_reminders};
use crate::error::CliError;

pub(super) fn dispatch_reminders(command: RemindersCommand) -> Result<(), CliError> {
    match command {
        RemindersCommand::Due { limit, format } => {
            println!("{}", run_due_task_reminders(limit, format)?);
        }
        RemindersCommand::Upcoming {
            hours,
            limit,
            format,
        } => println!("{}", run_upcoming_task_reminders(hours, limit, format)?),
        RemindersCommand::Set {
            task_id,
            reminders,
            format,
        } => println!("{}", run_task_reminder_set(&task_id, &reminders, format)?),
        RemindersCommand::Clear { task_id, format } => {
            println!("{}", run_task_reminder_clear(&task_id, format)?);
        }
        RemindersCommand::Add {
            task_id,
            reminder_at,
            format,
        } => println!("{}", run_task_reminder_add(&task_id, &reminder_at, format)?),
        RemindersCommand::Remove {
            task_id,
            reminder_id,
            format,
        } => println!(
            "{}",
            run_task_reminder_remove(&task_id, &reminder_id, format)?
        ),
    }
    Ok(())
}
