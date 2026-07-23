//! `lorvex habits …` dispatcher.

use crate::cli::HabitsCommand;
use crate::commands::mutate::{
    run_habit_batch_complete, run_habit_complete, run_habit_create, run_habit_delete,
    run_habit_reminder_delete, run_habit_reminder_upsert, run_habit_uncomplete, run_habit_update,
};
use crate::commands::query::{run_habit_reminder_policies, run_habit_stats, run_habits};
use crate::error::CliError;

pub(super) fn dispatch_habits(command: HabitsCommand) -> Result<(), CliError> {
    match command {
        HabitsCommand::List { format } => println!("{}", run_habits(format)?),
        HabitsCommand::Complete {
            habit_id,
            date,
            note,
            format,
        } => println!(
            "{}",
            run_habit_complete(&habit_id, date.as_deref(), note.as_deref(), format)?
        ),
        HabitsCommand::BatchComplete {
            habit_ids,
            date,
            format,
        } => println!(
            "{}",
            run_habit_batch_complete(&habit_ids, date.as_deref(), format)?
        ),
        HabitsCommand::Create {
            name,
            icon,
            color,
            cue,
            frequency_type,
            weekdays,
            per_period_target,
            day_of_month,
            target_count,
            format,
        } => println!(
            "{}",
            run_habit_create(
                &name,
                icon.as_deref(),
                color.as_deref(),
                cue.as_deref(),
                frequency_type.as_deref(),
                &weekdays,
                per_period_target,
                day_of_month,
                target_count,
                format,
            )?
        ),
        HabitsCommand::Update {
            habit_id,
            name,
            icon,
            color,
            cue,
            frequency_type,
            weekdays,
            per_period_target,
            day_of_month,
            target_count,
            archived,
            format,
        } => println!(
            "{}",
            // Cadence replacement is atomic: providing `--frequency-type`
            // (with detail) replaces the whole cadence, mirroring the MCP
            // write contract.
            run_habit_update(
                &habit_id,
                name.as_deref(),
                icon.as_deref(),
                color.as_deref(),
                cue.as_deref(),
                frequency_type.as_deref(),
                &weekdays,
                per_period_target,
                day_of_month,
                target_count,
                archived,
                format,
            )?
        ),
        HabitsCommand::Delete { habit_id, format } => {
            println!("{}", run_habit_delete(&habit_id, format)?);
        }
        HabitsCommand::Uncomplete {
            habit_id,
            date,
            format,
        } => println!(
            "{}",
            run_habit_uncomplete(&habit_id, date.as_deref(), format)?
        ),
        HabitsCommand::Stats {
            habit_id,
            days,
            format,
        } => println!("{}", run_habit_stats(&habit_id, days, format)?),
        HabitsCommand::ReminderList { format } => {
            println!("{}", run_habit_reminder_policies(format)?);
        }
        HabitsCommand::ReminderUpsert {
            policy_id,
            habit_id,
            reminder_time,
            enabled,
            format,
        } => println!(
            "{}",
            run_habit_reminder_upsert(
                policy_id.as_deref(),
                &habit_id,
                &reminder_time,
                enabled,
                format,
            )?
        ),
        HabitsCommand::ReminderDelete { policy_id, format } => {
            println!("{}", run_habit_reminder_delete(&policy_id, format)?);
        }
    }
    Ok(())
}
