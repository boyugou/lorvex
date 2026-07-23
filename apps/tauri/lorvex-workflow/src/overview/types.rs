//! Wire types and limit presets for the overview read model.

use lorvex_store::repositories::task::read;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OverviewLimits {
    /// `None` means include every list. `Some(n)` caps the list rows while
    /// still reporting `lists_total` and `lists_truncated`.
    pub lists: Option<usize>,
    pub top_tasks: usize,
    pub recently_completed: usize,
}

impl OverviewLimits {
    pub const fn app() -> Self {
        Self {
            lists: None,
            top_tasks: 10,
            recently_completed: 5,
        }
    }

    pub const fn mcp_full() -> Self {
        Self {
            lists: Some(200),
            top_tasks: 10,
            recently_completed: 5,
        }
    }

    pub const fn mcp_compact() -> Self {
        Self {
            lists: Some(0),
            top_tasks: 5,
            recently_completed: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct OverviewSnapshot {
    pub date: String,
    pub stats: OverviewStats,
    pub lists: Vec<OverviewList>,
    pub lists_total: i64,
    pub lists_truncated: bool,
    pub top_by_priority: Vec<read::TaskRow>,
    pub recently_completed: Vec<read::TaskRow>,
    pub current_focus: Option<OverviewCurrentFocusSummary>,
    pub habits: OverviewHabitSummary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OverviewStats {
    pub open_count: i64,
    pub overdue_count: i64,
    pub today_pool_count: i64,
    pub attention_count: i64,
    pub upcoming_week_count: i64,
    pub completed_today: i64,
    pub completed_this_week: i64,
    pub completed_last_week: i64,
    pub someday_count: i64,
    pub completion_streak: i64,
    pub streak_active_today: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct OverviewList {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub ai_notes: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
    pub open_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OverviewCurrentFocusSummary {
    pub task_count: usize,
    pub briefing: Option<String>,
    pub timezone: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OverviewHabitSummary {
    pub count: i64,
    pub completed_today: i64,
}
