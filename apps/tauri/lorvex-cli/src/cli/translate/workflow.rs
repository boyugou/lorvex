//! Workflow / read-aggregation mirrors. All arms below funnel into
//! `Command::Workflow` and mirror the corresponding MCP read tools
//! (overview, session-context, guide, recent-logs, analyze,
//! reorganize, habit-completions).

use super::super::args::{
    AnalyzeArgs, GuideArgs, HabitCompletionsArgs, OverviewArgs, RecentLogsArgs, ReorganizeArgs,
    SessionContextArgs,
};
use super::super::command::{Command, OutputFormat, WorkflowCommand};

pub(in crate::cli) fn translate_overview(args: &OverviewArgs) -> Command {
    Command::Workflow(WorkflowCommand::Overview {
        compact: args.compact,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_session_context(_args: &SessionContextArgs) -> Command {
    Command::Workflow(WorkflowCommand::SessionContext {
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_guide(args: &GuideArgs) -> Command {
    Command::Workflow(WorkflowCommand::Guide {
        topic: args
            .topic
            .map(super::super::args::workflow::GuideTopicArg::as_serde_value),
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_recent_logs(args: RecentLogsArgs) -> Command {
    let RecentLogsArgs {
        limit,
        since,
        levels,
        sources,
        include_details,
        no_redact,
    } = args;
    Command::Workflow(WorkflowCommand::RecentLogs {
        limit,
        since,
        levels,
        sources,
        include_details,
        redact: !no_redact,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_analyze(args: &AnalyzeArgs) -> Command {
    Command::Workflow(WorkflowCommand::Analyze {
        window_days: args.window_days,
        top_n: args.top_n,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_reorganize(args: ReorganizeArgs) -> Command {
    let ReorganizeArgs {
        list_id,
        strategy,
        task_ids,
        dry_run,
    } = args;
    Command::Workflow(WorkflowCommand::Reorganize {
        list_id,
        strategy: strategy.as_serde_value(),
        task_ids,
        dry_run,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_habit_completions(args: HabitCompletionsArgs) -> Command {
    let HabitCompletionsArgs { habit_id, days } = args;
    Command::Workflow(WorkflowCommand::HabitCompletions {
        habit_id,
        days,
        format: OutputFormat::default(),
    })
}
