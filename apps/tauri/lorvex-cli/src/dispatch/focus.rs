//! `lorvex focus …` dispatcher.

use crate::cli::FocusCommand;
use crate::commands::mutate::{
    run_focus_add, run_focus_clear, run_focus_remove, run_focus_schedule_save, run_focus_set,
};
use crate::commands::query::{run_focus_schedule_get, run_focus_schedule_propose, run_focus_show};
use crate::error::CliError;

pub(super) fn dispatch_focus(command: FocusCommand) -> Result<(), CliError> {
    match command {
        FocusCommand::Show { date, format } => {
            println!("{}", run_focus_show(date.as_deref(), format)?);
        }
        FocusCommand::Set {
            date,
            task_ids,
            briefing,
            format,
        } => println!(
            "{}",
            run_focus_set(date.as_deref(), &task_ids, briefing.as_deref(), format)?
        ),
        FocusCommand::Add {
            date,
            task_ids,
            briefing,
            format,
        } => println!(
            "{}",
            run_focus_add(date.as_deref(), &task_ids, briefing.as_deref(), format)?
        ),
        FocusCommand::Remove {
            date,
            task_id,
            format,
        } => println!("{}", run_focus_remove(date.as_deref(), &task_id, format)?),
        FocusCommand::Clear { date, format } => {
            println!("{}", run_focus_clear(date.as_deref(), format)?);
        }
        FocusCommand::ScheduleGet { date, format } => {
            println!("{}", run_focus_schedule_get(date.as_deref(), format)?);
        }
        FocusCommand::SchedulePropose { date, format } => {
            println!("{}", run_focus_schedule_propose(date.as_deref(), format)?);
        }
        FocusCommand::ScheduleSave {
            date,
            blocks_json,
            rationale,
            format,
        } => println!(
            "{}",
            run_focus_schedule_save(date.as_deref(), &blocks_json, rationale.as_deref(), format)?
        ),
    }
    Ok(())
}
