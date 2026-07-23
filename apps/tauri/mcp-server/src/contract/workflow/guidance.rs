use schemars::JsonSchema;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum GuideTopic {
    Overview,
    GettingStarted,
    TaskManagement,
    CurrentFocus,
    Lists,
    FocusMode,
    WeeklyReview,
    Preferences,
    DataAndExport,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetGuideArgs {
    #[schemars(
        description = "Guide topic: overview, getting_started, task_management, current_focus, lists, focus_mode, weekly_review, preferences, data_and_export. If omitted, auto-detects from app state."
    )]
    pub(crate) topic: Option<GuideTopic>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct AnalyzeTaskPatternsArgs {
    #[schemars(description = "Analysis window in days (default 14)")]
    pub(crate) window_days: Option<u32>,
    #[schemars(description = "Max deferred/overdue items to surface (default 5)")]
    pub(crate) top_n: Option<u32>,
}
