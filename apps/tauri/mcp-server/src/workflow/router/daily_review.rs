//! Daily review tools.
//!
//! Owns the per-day reflection surface: write/amend a single day's review,
//! read one day, and read recent history.

use crate::contract::{
    AddDailyReviewArgs, AmendDailyReviewArgs, GetDailyReviewArgs, GetReviewHistoryArgs,
};
use crate::reviews::daily;

crate::server::tool_macros::mcp_tools! {
    router = workflow_daily_review_tool_router;

    write add_daily_review(AddDailyReviewArgs) -> daily::add_daily_review;
        "Write a structured daily review entry after an end-of-day conversation. Use when wrapping up the day to capture mood, energy, accomplishments, blockers, and habit check-ins. Only one review per day — use amend_daily_review to update. Returns the full daily review object with linked task and list IDs.";

    write amend_daily_review(AmendDailyReviewArgs) -> daily::amend_daily_review;
        "Update specific fields of an existing daily review. Use when the user wants to revise their review after the initial write, or to add habit completions later. Returns the full updated daily review object with linked task and list IDs.";

    read get_daily_review(GetDailyReviewArgs) -> daily::get_daily_review;
        "Retrieve a specific day's review entry. Defaults to today. Use to recall past reviews during weekly review, when the user asks about a specific day, or to check if today's review already exists before creating one. Returns the daily review object, or a not-found message if none exists.";

    read get_review_history(GetReviewHistoryArgs) -> daily::get_review_history;
        "Retrieve recent daily reviews. Use during weekly review to see daily patterns and trends, or when the user asks about their recent rhythm, energy, or accomplishments over multiple days. Returns a paginated envelope with reviews ordered by date descending.";
}
