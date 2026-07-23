use super::super::args::{RecurrenceExceptionArgs, RecurrenceExceptionCmd};
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_recurrence_exception(cmd: RecurrenceExceptionCmd) -> Command {
    match cmd {
        RecurrenceExceptionCmd::Add(RecurrenceExceptionArgs { task_id, date }) => {
            Command::Tasks(TasksCommand::AddRecurrenceException {
                task_id,
                date,
                format: OutputFormat::default(),
            })
        }
        RecurrenceExceptionCmd::Remove(RecurrenceExceptionArgs { task_id, date }) => {
            Command::Tasks(TasksCommand::RemoveRecurrenceException {
                task_id,
                date,
                format: OutputFormat::default(),
            })
        }
    }
}
