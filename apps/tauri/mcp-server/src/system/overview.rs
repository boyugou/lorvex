use crate::error::McpError;
use crate::system::diagnostics::{clamp_rows_text_field, truncate_compact_text};
use crate::system::handler_support::enrich_and_fence_tasks_for_response;
use lorvex_store::repositories::task::read::TaskRow;
use lorvex_workflow::overview::{
    load_overview_snapshot, OverviewCurrentFocusSummary, OverviewLimits, OverviewStats,
};
use rusqlite::Connection;
use serde_json::{json, Value};

const OVERVIEW_COMPACT_TITLE_MAX_CHARS: usize = 120;
const OVERVIEW_COMPACT_BRIEFING_MAX_CHARS: usize = 320;

pub(crate) fn get_overview(conn: &Connection) -> Result<String, McpError> {
    let snapshot = load_overview_snapshot(conn, OverviewLimits::mcp_full())?;
    let stats = stats_to_json(snapshot.stats);
    let mut lists: Vec<Value> = snapshot
        .lists
        .into_iter()
        .map(serde_json::to_value)
        .collect::<Result<_, _>>()?;
    for list in &mut lists {
        if let Some(obj) = list.as_object_mut() {
            crate::system::text_hygiene::fence_object_field(obj, "name");
            crate::system::text_hygiene::fence_object_field(obj, "description");
            crate::system::text_hygiene::fence_object_field(obj, "ai_notes");
        }
    }

    let top_by_priority = task_rows_to_mcp_json(conn, snapshot.top_by_priority)?;
    let recently_completed = task_rows_to_mcp_json(conn, snapshot.recently_completed)?;
    let current_focus = summarize_current_focus(snapshot.current_focus.as_ref());

    let payload = json!({
        "stats": stats,
        "lists": lists,
        "lists_truncated": snapshot.lists_truncated,
        "lists_total": snapshot.lists_total,
        "top_by_priority": top_by_priority,
        "recently_completed": recently_completed,
        "current_focus": current_focus,
        "habits": {
            "count": snapshot.habits.count,
            "completed_today": snapshot.habits.completed_today,
        },
    });

    Ok(serde_json::to_string(&payload)?)
}

pub(crate) fn get_overview_compact(conn: &Connection) -> Result<String, McpError> {
    let snapshot = load_overview_snapshot(conn, OverviewLimits::mcp_compact())?;
    let mut top_tasks: Vec<Value> = snapshot
        .top_by_priority
        .iter()
        .map(compact_task_to_json)
        .collect();
    clamp_rows_text_field(&mut top_tasks, "title", OVERVIEW_COMPACT_TITLE_MAX_CHARS);
    crate::system::text_hygiene::fence_tasks_user_fields(&mut top_tasks);

    let payload = json!({
        "date": snapshot.date,
        "stats": compact_stats_to_json(snapshot.stats),
        "current_focus": summarize_current_focus(snapshot.current_focus.as_ref()),
        "top_tasks": top_tasks,
        "limits": {
            "top_tasks": 5,
            "title_max_chars": OVERVIEW_COMPACT_TITLE_MAX_CHARS,
            "briefing_max_chars": OVERVIEW_COMPACT_BRIEFING_MAX_CHARS
        }
    });

    Ok(serde_json::to_string(&payload)?)
}

fn stats_to_json(stats: OverviewStats) -> Value {
    json!({
        "open_count": stats.open_count,
        "overdue_count": stats.overdue_count,
        "today_pool_count": stats.today_pool_count,
        "attention_count": stats.attention_count,
        "upcoming_week_count": stats.upcoming_week_count,
        "completed_today": stats.completed_today,
        "completed_this_week": stats.completed_this_week,
        "completed_last_week": stats.completed_last_week,
        "someday_count": stats.someday_count,
        "completion_streak": stats.completion_streak,
        "streak_active_today": stats.streak_active_today,
    })
}

fn compact_stats_to_json(stats: OverviewStats) -> Value {
    json!({
        "open_count": stats.open_count,
        "overdue_count": stats.overdue_count,
        "today_pool_count": stats.today_pool_count,
        "attention_count": stats.attention_count,
        "upcoming_week_count": stats.upcoming_week_count,
    })
}

fn task_rows_to_mcp_json(conn: &Connection, rows: Vec<TaskRow>) -> Result<Vec<Value>, McpError> {
    let mut tasks: Vec<Value> = rows
        .into_iter()
        .map(serde_json::to_value)
        .collect::<Result<_, _>>()?;
    enrich_and_fence_tasks_for_response(conn, &mut tasks)?;
    Ok(tasks)
}

fn compact_task_to_json(task: &TaskRow) -> Value {
    let core = task.core();
    let scheduling = task.scheduling();
    json!({
        "id": core.id(),
        "title": core.title(),
        "status": core.status(),
        "list_id": core.list_id(),
        "priority": core.priority(),
        "due_date": scheduling.due_date().map(|date| date.to_string()),
        "due_time": scheduling.due_time().map(|time| time.to_string()),
    })
}

fn summarize_current_focus(summary: Option<&OverviewCurrentFocusSummary>) -> Value {
    match summary {
        Some(summary) => {
            let briefing = summary.briefing.as_deref().map_or(Value::Null, |raw| {
                let truncated = truncate_compact_text(raw, OVERVIEW_COMPACT_BRIEFING_MAX_CHARS);
                Value::String(crate::system::text_hygiene::mcp_untrusted_text(&truncated))
            });

            json!({
                "exists": true,
                "task_count": summary.task_count,
                "briefing": briefing,
            })
        }
        None => Value::Null,
    }
}
