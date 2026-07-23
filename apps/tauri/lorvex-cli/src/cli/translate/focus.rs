use super::super::args::{
    FocusCmd, FocusDateArgs, FocusMutationArgs, FocusRemoveArgs, FocusScheduleCmd,
    FocusScheduleSaveArgs,
};
use super::super::command::{Command, FocusCommand, OutputFormat};

pub(in crate::cli) fn translate_focus(cmd: FocusCmd) -> Command {
    Command::Focus(match cmd {
        FocusCmd::Show(FocusDateArgs { date }) => FocusCommand::Show {
            date,
            format: OutputFormat::default(),
        },
        FocusCmd::Set(FocusMutationArgs {
            date,
            task_ids,
            briefing,
        }) => FocusCommand::Set {
            date,
            task_ids,
            briefing,
            format: OutputFormat::default(),
        },
        FocusCmd::Add(FocusMutationArgs {
            date,
            task_ids,
            briefing,
        }) => FocusCommand::Add {
            date,
            task_ids,
            briefing,
            format: OutputFormat::default(),
        },
        FocusCmd::Remove(FocusRemoveArgs { task_id, date }) => FocusCommand::Remove {
            date,
            task_id,
            format: OutputFormat::default(),
        },
        FocusCmd::Clear(FocusDateArgs { date }) => FocusCommand::Clear {
            date,
            format: OutputFormat::default(),
        },
        FocusCmd::Schedule(FocusScheduleCmd::Get(FocusDateArgs { date })) => {
            FocusCommand::ScheduleGet {
                date,
                format: OutputFormat::default(),
            }
        }
        FocusCmd::Schedule(FocusScheduleCmd::Propose(FocusDateArgs { date })) => {
            FocusCommand::SchedulePropose {
                date,
                format: OutputFormat::default(),
            }
        }
        FocusCmd::Schedule(FocusScheduleCmd::Save(FocusScheduleSaveArgs {
            date,
            blocks_json,
            rationale,
        })) => FocusCommand::ScheduleSave {
            date,
            blocks_json,
            rationale,
            format: OutputFormat::default(),
        },
    })
}
