//! Read-side task queries: list, search, show, plus the date-window
//! helpers (today / overdue / upcoming / deferred) and the cross-list
//! `move` mutation. All return values funnel into `Command::Tasks`.

use super::super::args::{
    DeferredArgs, LimitArgs, MoveArgs, SearchArgs, ShowArgs, TasksArgs, UpcomingArgs,
};
use super::super::clap_patch::mutually_exclusive_bool;
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_tasks(args: TasksArgs) -> Command {
    let TasksArgs {
        list_id,
        status,
        priority,
        due_from,
        due_to,
        planned_from,
        planned_to,
        completed_from,
        completed_to,
        created_from,
        created_to,
        has_due_date,
        no_due_date,
        has_planned_date,
        no_planned_date,
        tags,
        text,
        blocked_only,
        blocking_others,
        sort_by,
        sort_direction,
        limit,
    } = args;
    Command::Tasks(TasksCommand::List {
        list_id,
        status,
        priority,
        due_from,
        due_to,
        planned_from,
        planned_to,
        completed_from,
        completed_to,
        created_from,
        created_to,
        has_due_date: mutually_exclusive_bool(has_due_date, no_due_date),
        has_planned_date: mutually_exclusive_bool(has_planned_date, no_planned_date),
        tags,
        text,
        blocked_only,
        blocking_others,
        sort_by,
        sort_direction,
        limit,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_search(args: SearchArgs) -> Command {
    let SearchArgs { query, limit } = args;
    Command::Tasks(TasksCommand::Search {
        query: query.join(" "),
        limit,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_show(args: ShowArgs) -> Command {
    let ShowArgs { task_id } = args;
    Command::Tasks(TasksCommand::Show {
        task_id,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_today(args: &LimitArgs) -> Command {
    Command::Tasks(TasksCommand::Today {
        limit: args.limit,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_overdue(args: &LimitArgs) -> Command {
    Command::Tasks(TasksCommand::Overdue {
        limit: args.limit,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_upcoming(args: &UpcomingArgs) -> Command {
    Command::Tasks(TasksCommand::Upcoming {
        days: args.days,
        limit: args.limit,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_deferred(args: DeferredArgs) -> Command {
    let DeferredArgs { list_id, limit } = args;
    Command::Tasks(TasksCommand::Deferred {
        list_id,
        limit,
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_move(args: MoveArgs) -> Command {
    let MoveArgs { list_id, task_ids } = args;
    Command::Tasks(TasksCommand::Move {
        list_id,
        task_ids,
        format: OutputFormat::default(),
    })
}
