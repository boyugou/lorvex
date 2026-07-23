use super::super::args::{
    ReminderAddArgs, ReminderCmd, ReminderDueArgs, ReminderRemoveArgs, ReminderSetArgs,
    ReminderTaskArgs, ReminderUpcomingArgs,
};
use super::super::command::{Command, OutputFormat, RemindersCommand};

pub(in crate::cli) fn translate_reminder(cmd: ReminderCmd) -> Command {
    Command::Reminders(match cmd {
        ReminderCmd::Due(ReminderDueArgs { limit }) => RemindersCommand::Due {
            limit,
            format: OutputFormat::default(),
        },
        ReminderCmd::Upcoming(ReminderUpcomingArgs { hours, limit }) => {
            RemindersCommand::Upcoming {
                hours,
                limit,
                format: OutputFormat::default(),
            }
        }
        ReminderCmd::Set(ReminderSetArgs { task_id, reminders }) => RemindersCommand::Set {
            task_id,
            reminders,
            format: OutputFormat::default(),
        },
        ReminderCmd::Clear(ReminderTaskArgs { task_id }) => RemindersCommand::Clear {
            task_id,
            format: OutputFormat::default(),
        },
        ReminderCmd::Add(ReminderAddArgs {
            task_id,
            reminder_at,
        }) => RemindersCommand::Add {
            task_id,
            reminder_at,
            format: OutputFormat::default(),
        },
        ReminderCmd::Remove(ReminderRemoveArgs {
            task_id,
            reminder_id,
        }) => RemindersCommand::Remove {
            task_id,
            reminder_id,
            format: OutputFormat::default(),
        },
    })
}
