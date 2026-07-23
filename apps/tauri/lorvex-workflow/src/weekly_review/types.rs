//! Wire types returned by the three weekly-review entry points.
//!
//! Each `WeeklyReview*` struct mirrors exactly one consumer-facing
//! shape (full read model, MCP snapshot, conversational brief). The
//! shared `WeeklyReview*Limits` structs carry per-section caps that
//! the validator module checks before any SQL runs.

use serde::Serialize;

/// Trailing-day window for every weekly-review entry point.
pub const WEEKLY_REVIEW_DAYS: i64 = 7;
/// Upper bound on per-section row caps. Validators reject any cap
/// outside `1..=WEEKLY_REVIEW_LIMIT_CAP`.
pub const WEEKLY_REVIEW_LIMIT_CAP: u32 = 500;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct WeeklyReviewReadModel {
    pub window: WeeklyReviewWindow,
    pub counts: WeeklyReviewCounts,
    pub estimate_summary: WeeklyReviewEstimateSummary,
    pub completed_this_week: Vec<WeeklyReviewTaskItem>,
    pub stalled_lists: Vec<WeeklyReviewStalledList>,
    pub frequently_deferred: Vec<WeeklyReviewTaskItem>,
    pub overdue_tasks: Vec<WeeklyReviewTaskItem>,
    pub someday_items: Vec<WeeklyReviewTaskItem>,
    pub limits: WeeklyReviewLimits,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct WeeklyReviewSnapshot {
    pub window: WeeklyReviewWindow,
    pub counts: WeeklyReviewCounts,
    pub estimate_summary: WeeklyReviewEstimateSummary,
    pub top_completed: Vec<WeeklyReviewTaskItem>,
    pub stalled_lists: Vec<WeeklyReviewStalledList>,
    pub frequently_deferred: Vec<WeeklyReviewTaskItem>,
    pub someday_items: Vec<WeeklyReviewTaskItem>,
    pub limits: WeeklyReviewSnapshotLimits,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct WeeklyReviewBrief {
    pub window: WeeklyReviewWindow,
    pub completed_this_week: Vec<WeeklyReviewTaskItem>,
    pub stalled_lists: Vec<WeeklyReviewStalledList>,
    pub frequently_deferred: Vec<WeeklyReviewTaskItem>,
    pub overdue_count: i64,
    pub someday_items: Vec<WeeklyReviewTaskItem>,
    pub created_this_week: i64,
    pub estimate_summary: WeeklyReviewEstimateSummary,
    pub section_meta: WeeklyReviewBriefSectionMeta,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewWindow {
    pub from: String,
    pub to: String,
    pub start_utc: String,
    pub end_utc: String,
    pub days: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewCounts {
    pub completed_this_week: i64,
    pub created_this_week: i64,
    pub overdue_open: i64,
    pub deferred_open: i64,
    pub someday: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct WeeklyReviewEstimateSummary {
    pub completed_total: i64,
    pub completed_with_estimate_count: i64,
    pub estimate_coverage_ratio: Option<f64>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewTaskItem {
    pub id: String,
    pub title: String,
    pub list_id: String,
    pub status: String,
    pub completed_at: Option<String>,
    pub due_date: Option<lorvex_domain::Date>,
    pub defer_count: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewStalledList {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub open_task_count: i64,
    pub last_activity: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewLimits {
    pub completed_this_week: u32,
    pub stalled_lists: u32,
    pub frequently_deferred: u32,
    pub overdue_tasks: u32,
    pub someday_items: u32,
}

impl WeeklyReviewLimits {
    pub const fn app_defaults() -> Self {
        Self {
            completed_this_week: WEEKLY_REVIEW_LIMIT_CAP,
            stalled_lists: WEEKLY_REVIEW_LIMIT_CAP,
            frequently_deferred: 10,
            overdue_tasks: 10,
            someday_items: 20,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewSnapshotLimits {
    pub top_completed: u32,
    pub stalled_lists: u32,
    pub frequently_deferred: u32,
    pub someday_items: u32,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewBriefLimits {
    pub completed_this_week: u32,
    pub stalled_lists: u32,
    pub frequently_deferred: u32,
    pub someday_items: u32,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewBriefSectionMeta {
    pub completed_this_week: WeeklyReviewBriefSectionEntry,
    pub stalled_lists: WeeklyReviewBriefSectionEntry,
    pub frequently_deferred: WeeklyReviewBriefSectionEntry,
    pub someday_items: WeeklyReviewBriefSectionEntry,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WeeklyReviewBriefSectionEntry {
    pub limit: u32,
    pub total_matching: i64,
    pub returned: usize,
    pub truncated: bool,
}
