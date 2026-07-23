use crate::contract::{
    default_weekly_completed_limit, default_weekly_deferred_limit, default_weekly_someday_limit,
    default_weekly_stalled_limit,
};
use lorvex_mcp_derive::ContractValidate;
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetDailyReviewArgs {
    #[schemars(description = "Date in YYYY-MM-DD format (defaults to today)")]
    pub(crate) date: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct AddDailyReviewArgs {
    #[schemars(description = "Date in YYYY-MM-DD format (defaults to today)")]
    pub(crate) date: Option<String>,
    #[schemars(description = "2-4 sentence prose summary of the day")]
    pub(crate) summary: String,
    #[schemars(description = "Mood 1-5")]
    pub(crate) mood: Option<u8>,
    #[schemars(description = "Energy 1-5")]
    pub(crate) energy_level: Option<u8>,
    #[schemars(description = "Task IDs discussed or completed today")]
    pub(crate) linked_task_ids: Option<Vec<String>>,
    #[schemars(description = "List IDs relevant to today's work")]
    pub(crate) linked_list_ids: Option<Vec<String>>,
    #[schemars(description = "What went well today")]
    pub(crate) wins: Option<String>,
    #[schemars(description = "What got in the way or caused friction")]
    pub(crate) blockers: Option<String>,
    #[schemars(description = "Explicit insights or takeaways from the day")]
    pub(crate) learnings: Option<String>,
    #[schemars(
        description = "AI's cross-day observations (e.g. patterns across multiple reviews)"
    )]
    pub(crate) ai_synthesis: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema, ContractValidate)]
pub(crate) struct AmendDailyReviewArgs {
    #[schemars(description = "Date of the review to amend (YYYY-MM-DD)")]
    pub(crate) date: String,
    #[schemars(description = "Updated prose summary of the day")]
    pub(crate) summary: Option<String>,
    #[schemars(description = "Mood 1-5")]
    pub(crate) mood: Option<u8>,
    #[schemars(description = "Energy 1-5")]
    pub(crate) energy_level: Option<u8>,
    #[schemars(description = "What went well today")]
    pub(crate) wins: Option<String>,
    #[schemars(description = "What got in the way or caused friction")]
    pub(crate) blockers: Option<String>,
    #[schemars(description = "Explicit insights or takeaways from the day")]
    pub(crate) learnings: Option<String>,
    #[schemars(
        description = "AI's cross-day observations (e.g. patterns across multiple reviews)"
    )]
    pub(crate) ai_synthesis: Option<String>,
    #[schemars(description = "Task IDs discussed or completed today")]
    #[validate(exists_in = "tasks_active")]
    pub(crate) linked_task_ids: Option<Vec<String>>,
    #[schemars(description = "List IDs relevant to today's work")]
    #[validate(exists_in = "lists")]
    pub(crate) linked_list_ids: Option<Vec<String>>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetReviewHistoryArgs {
    #[schemars(description = "Max entries to return (default 14, max 90)")]
    pub(crate) limit: Option<u32>,
    // pagination offset.
    #[schemars(description = "Zero-based offset for stable pagination. Default 0.")]
    pub(crate) offset: Option<u32>,
    #[schemars(description = "Only return reviews on or after this date (YYYY-MM-DD)")]
    pub(crate) since: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetWeeklyReviewBriefArgs {
    #[serde(default = "default_weekly_completed_limit")]
    #[schemars(description = "Maximum completed-this-week tasks (default 50, max 500)")]
    pub(crate) completed_limit: u32,
    #[serde(default = "default_weekly_stalled_limit")]
    #[schemars(description = "Maximum stalled lists (default 50, max 500)")]
    pub(crate) stalled_lists_limit: u32,
    #[serde(default = "default_weekly_deferred_limit")]
    #[schemars(description = "Maximum frequently deferred tasks (default 10, max 500)")]
    pub(crate) deferred_limit: u32,
    #[serde(default = "default_weekly_someday_limit")]
    #[schemars(description = "Maximum someday items (default 20, max 500)")]
    pub(crate) someday_limit: u32,
}
