//! Review journal and weekly review argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{
    parse_cli_date_arg, parse_list_id, parse_positive_u32, parse_review_scale, parse_task_id,
};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum ReviewCmd {
    /// Show one daily review. Defaults to today.
    Get(ReviewGetArgs),
    /// List recent daily reviews.
    History(ReviewHistoryArgs),
    /// Show a seven-day weekly review snapshot.
    Weekly(ReviewWeeklyArgs),
    /// Show the assistant-facing weekly review brief (mirrors MCP
    /// `get_weekly_review_brief`). Each section includes
    /// `total_matching` + `truncated` so the assistant can decide
    /// whether to drill in.
    Brief(ReviewBriefArgs),
    /// Create or replace the review for a date.
    Add(ReviewAddArgs),
    /// Amend selected fields or replace selected link sets.
    Amend(ReviewAmendArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReviewGetArgs {
    /// Review date in YYYY-MM-DD format. Defaults to today.
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReviewHistoryArgs {
    /// Earliest review date to include.
    #[arg(long = "since", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) since: Option<String>,
    /// Maximum number of review rows to return.
    #[arg(short = 'l', long = "limit", default_value_t = 14, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReviewWeeklyArgs {
    /// Maximum completed tasks to include.
    #[arg(long = "completed-limit", default_value_t = 5, value_parser = parse_positive_u32)]
    pub(in crate::cli) completed_limit: u32,
    /// Maximum stalled lists to include.
    #[arg(long = "stalled-limit", default_value_t = 3, value_parser = parse_positive_u32)]
    pub(in crate::cli) stalled_lists_limit: u32,
    /// Maximum frequently deferred tasks to include.
    #[arg(long = "deferred-limit", default_value_t = 5, value_parser = parse_positive_u32)]
    pub(in crate::cli) deferred_limit: u32,
    /// Maximum someday items to include.
    #[arg(long = "someday-limit", default_value_t = 5, value_parser = parse_positive_u32)]
    pub(in crate::cli) someday_limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReviewBriefArgs {
    /// Maximum completed tasks to include (mirrors MCP
    /// `WEEKLY_BRIEF_COMPLETED_DEFAULT`).
    #[arg(long = "completed-limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) completed_limit: u32,
    /// Maximum stalled lists to include (mirrors MCP
    /// `WEEKLY_BRIEF_STALLED_DEFAULT`).
    #[arg(long = "stalled-limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) stalled_lists_limit: u32,
    /// Maximum frequently-deferred tasks to include (mirrors MCP
    /// `WEEKLY_BRIEF_DEFERRED_DEFAULT`).
    #[arg(long = "deferred-limit", default_value_t = 10, value_parser = parse_positive_u32)]
    pub(in crate::cli) deferred_limit: u32,
    /// Maximum someday items to include (mirrors MCP
    /// `WEEKLY_BRIEF_SOMEDAY_DEFAULT`).
    #[arg(long = "someday-limit", default_value_t = 20, value_parser = parse_positive_u32)]
    pub(in crate::cli) someday_limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReviewAddArgs {
    /// Review date in YYYY-MM-DD format. Defaults to today.
    #[arg(long = "date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: Option<String>,
    /// Required daily summary.
    #[arg(long = "summary")]
    pub(in crate::cli) summary: String,
    #[arg(long = "mood", value_parser = parse_review_scale)]
    pub(in crate::cli) mood: Option<u8>,
    #[arg(long = "energy", value_parser = parse_review_scale)]
    pub(in crate::cli) energy_level: Option<u8>,
    #[arg(long = "win")]
    pub(in crate::cli) wins: Option<String>,
    #[arg(long = "blocker")]
    pub(in crate::cli) blockers: Option<String>,
    #[arg(long = "learning")]
    pub(in crate::cli) learnings: Option<String>,
    #[arg(long = "ai-synthesis")]
    pub(in crate::cli) ai_synthesis: Option<String>,
    #[arg(long = "linked-task", value_parser = parse_task_id)]
    pub(in crate::cli) linked_task_ids: Vec<String>,
    #[arg(long = "linked-list", value_parser = parse_list_id)]
    pub(in crate::cli) linked_list_ids: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReviewAmendArgs {
    #[arg(value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: String,
    #[arg(long = "summary")]
    pub(in crate::cli) summary: Option<String>,
    #[arg(long = "mood", value_parser = parse_review_scale)]
    pub(in crate::cli) mood: Option<u8>,
    #[arg(long = "energy", value_parser = parse_review_scale)]
    pub(in crate::cli) energy_level: Option<u8>,
    #[arg(long = "win")]
    pub(in crate::cli) wins: Option<String>,
    #[arg(long = "blocker")]
    pub(in crate::cli) blockers: Option<String>,
    #[arg(long = "learning")]
    pub(in crate::cli) learnings: Option<String>,
    #[arg(long = "ai-synthesis")]
    pub(in crate::cli) ai_synthesis: Option<String>,
    #[arg(
        long = "linked-task-set",
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) linked_task_ids: Option<Vec<String>>,
    #[arg(
        long = "linked-list-set",
        num_args = 1..,
        value_parser = parse_list_id
    )]
    pub(in crate::cli) linked_list_ids: Option<Vec<String>>,
}
