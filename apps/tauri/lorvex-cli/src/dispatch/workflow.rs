//! `lorvex workflow …` dispatcher — agent-facing orientation, log access,
//! analysis, reorganization, and habit-completion telemetry.

use crate::cli::WorkflowCommand;
use crate::commands::workflow as wf;
use crate::error::CliError;

pub(super) fn dispatch_workflow(command: WorkflowCommand) -> Result<(), CliError> {
    match command {
        WorkflowCommand::Overview { compact, format } => {
            println!("{}", wf::run_overview(compact, format)?);
        }
        WorkflowCommand::SessionContext { format } => {
            println!("{}", wf::run_session_context(format)?);
        }
        WorkflowCommand::Guide { topic, format } => println!("{}", wf::run_guide(topic, format)?),
        WorkflowCommand::RecentLogs {
            limit,
            since,
            levels,
            sources,
            include_details,
            redact,
            format,
        } => println!(
            "{}",
            wf::run_recent_logs(
                limit,
                since.as_deref(),
                &levels,
                &sources,
                include_details,
                redact,
                format,
            )?
        ),
        WorkflowCommand::Analyze {
            window_days,
            top_n,
            format,
        } => println!("{}", wf::run_analyze(window_days, top_n, format)?),
        WorkflowCommand::Reorganize {
            list_id,
            strategy,
            task_ids,
            dry_run,
            format,
        } => println!(
            "{}",
            wf::run_reorganize_list(&list_id, strategy, &task_ids, dry_run, format)?
        ),
        WorkflowCommand::HabitCompletions {
            habit_id,
            days,
            format,
        } => println!("{}", wf::run_habit_completions(&habit_id, days, format)?),
    }
    Ok(())
}
