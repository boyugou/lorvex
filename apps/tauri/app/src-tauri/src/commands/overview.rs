use crate::db::get_read_conn;
use crate::error::AppResult;
use lorvex_workflow::overview::{
    load_overview_snapshot, OverviewCurrentFocusSummary, OverviewLimits, OverviewList,
    OverviewStats,
};

use super::{tasks_from_task_rows, CurrentFocusSummary, ListWithCount, Overview, Stats, TaskList};

#[tauri::command]
pub fn get_overview() -> Result<Overview, String> {
    let conn = get_read_conn()?;
    compute_overview(&conn).map_err(String::from)
}

/// compute the overview from a pre-acquired connection.
/// Exposed so `get_today_bootstrap` can share a single deferred-read
/// snapshot across every first-paint read instead of opening a fresh
/// connection per panel.
pub(crate) fn compute_overview(conn: &rusqlite::Connection) -> AppResult<Overview> {
    let snapshot = load_overview_snapshot(conn, OverviewLimits::app())?;
    let top_by_priority = tasks_from_task_rows(conn, snapshot.top_by_priority)?;
    let recently_completed = tasks_from_task_rows(conn, snapshot.recently_completed)?;

    Ok(Overview {
        stats: stats_from_snapshot(snapshot.stats),
        lists: snapshot.lists.into_iter().map(list_from_snapshot).collect(),
        current_focus: snapshot.current_focus.map(current_focus_from_snapshot),
        top_by_priority,
        recently_completed,
    })
}

fn stats_from_snapshot(stats: OverviewStats) -> Stats {
    Stats {
        open_count: stats.open_count,
        overdue_count: stats.overdue_count,
        today_pool_count: stats.today_pool_count,
        attention_count: stats.attention_count,
        upcoming_week_count: stats.upcoming_week_count,
        completed_today: stats.completed_today,
        completed_this_week: stats.completed_this_week,
        completed_last_week: stats.completed_last_week,
        someday_count: stats.someday_count,
        completion_streak: stats.completion_streak,
        streak_active_today: stats.streak_active_today,
    }
}

fn list_from_snapshot(list: OverviewList) -> ListWithCount {
    ListWithCount {
        list: TaskList {
            id: list.id,
            name: list.name,
            color: list.color,
            icon: list.icon,
            description: list.description,
            ai_notes: list.ai_notes,
            created_at: list.created_at,
            updated_at: list.updated_at,
        },
        open_count: list.open_count,
    }
}

fn current_focus_from_snapshot(summary: OverviewCurrentFocusSummary) -> CurrentFocusSummary {
    CurrentFocusSummary {
        task_count: summary.task_count,
        briefing: summary.briefing,
        timezone: summary.timezone,
    }
}
