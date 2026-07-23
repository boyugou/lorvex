//! `lorvex review …` dispatcher (daily/weekly review surfaces).

use crate::cli::ReviewCommand;
use crate::commands::mutate::reviews::effects::{DailyReviewAddFields, DailyReviewAmendFields};
use crate::commands::mutate::{run_review_add, run_review_amend};
use crate::commands::query::{
    run_review_brief, run_review_get, run_review_history, run_review_weekly,
};
use crate::error::CliError;

pub(super) fn dispatch_review(command: ReviewCommand) -> Result<(), CliError> {
    match command {
        ReviewCommand::Get { date, format } => {
            println!("{}", run_review_get(date.as_deref(), format)?);
        }
        ReviewCommand::History {
            since,
            limit,
            format,
        } => println!("{}", run_review_history(since.as_deref(), limit, format)?),
        ReviewCommand::Weekly {
            completed_limit,
            stalled_lists_limit,
            deferred_limit,
            someday_limit,
            format,
        } => println!(
            "{}",
            run_review_weekly(
                completed_limit,
                stalled_lists_limit,
                deferred_limit,
                someday_limit,
                format,
            )?
        ),
        ReviewCommand::Brief {
            completed_limit,
            stalled_lists_limit,
            deferred_limit,
            someday_limit,
            format,
        } => println!(
            "{}",
            run_review_brief(
                completed_limit,
                stalled_lists_limit,
                deferred_limit,
                someday_limit,
                format,
            )?
        ),
        ReviewCommand::Add {
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
            format,
        } => println!(
            "{}",
            run_review_add(
                DailyReviewAddFields {
                    date: date.as_deref(),
                    summary: &summary,
                    mood,
                    energy_level,
                    wins: wins.as_deref(),
                    blockers: blockers.as_deref(),
                    learnings: learnings.as_deref(),
                    ai_synthesis: ai_synthesis.as_deref(),
                    linked_task_ids: &linked_task_ids,
                    linked_list_ids: &linked_list_ids,
                },
                format,
            )?
        ),
        ReviewCommand::Amend {
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
            format,
        } => println!(
            "{}",
            run_review_amend(
                DailyReviewAmendFields {
                    date: &date,
                    summary: summary.as_deref(),
                    mood,
                    energy_level,
                    wins: wins.as_deref(),
                    blockers: blockers.as_deref(),
                    learnings: learnings.as_deref(),
                    ai_synthesis: ai_synthesis.as_deref(),
                    linked_task_ids: linked_task_ids.as_deref(),
                    linked_list_ids: linked_list_ids.as_deref(),
                },
                format,
            )?
        ),
    }
    Ok(())
}
