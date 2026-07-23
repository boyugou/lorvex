use super::super::args::{
    ReviewAddArgs, ReviewAmendArgs, ReviewBriefArgs, ReviewCmd, ReviewGetArgs, ReviewHistoryArgs,
    ReviewWeeklyArgs,
};
use super::super::command::{Command, OutputFormat, ReviewCommand};

pub(in crate::cli) fn translate_review(cmd: ReviewCmd) -> Command {
    Command::Review(match cmd {
        ReviewCmd::Get(ReviewGetArgs { date }) => ReviewCommand::Get {
            date,
            format: OutputFormat::default(),
        },
        ReviewCmd::History(ReviewHistoryArgs { since, limit }) => ReviewCommand::History {
            since,
            limit,
            format: OutputFormat::default(),
        },
        ReviewCmd::Weekly(ReviewWeeklyArgs {
            completed_limit,
            stalled_lists_limit,
            deferred_limit,
            someday_limit,
        }) => ReviewCommand::Weekly {
            completed_limit,
            stalled_lists_limit,
            deferred_limit,
            someday_limit,
            format: OutputFormat::default(),
        },
        ReviewCmd::Brief(ReviewBriefArgs {
            completed_limit,
            stalled_lists_limit,
            deferred_limit,
            someday_limit,
        }) => ReviewCommand::Brief {
            completed_limit,
            stalled_lists_limit,
            deferred_limit,
            someday_limit,
            format: OutputFormat::default(),
        },
        ReviewCmd::Add(ReviewAddArgs {
            date,
            summary,
            mood,
            energy_level,
            wins,
            blockers,
            learnings,
            ai_synthesis,
            linked_task_ids,
            linked_list_ids,
        }) => ReviewCommand::Add {
            date,
            summary,
            mood,
            energy_level,
            wins,
            blockers,
            learnings,
            ai_synthesis,
            linked_task_ids,
            linked_list_ids,
            format: OutputFormat::default(),
        },
        ReviewCmd::Amend(ReviewAmendArgs {
            date,
            summary,
            mood,
            energy_level,
            wins,
            blockers,
            learnings,
            ai_synthesis,
            linked_task_ids,
            linked_list_ids,
        }) => ReviewCommand::Amend {
            date,
            summary,
            mood,
            energy_level,
            wins,
            blockers,
            learnings,
            ai_synthesis,
            linked_task_ids,
            linked_list_ids,
            format: OutputFormat::default(),
        },
    })
}
