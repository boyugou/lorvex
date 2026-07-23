use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};
use lorvex_store::TASK_ORDER_BY;
use rusqlite::params;

use crate::commands::{
    clamp_limit, fetch_task_by_id, tasks_from_query, tasks_from_task_rows, Task, MAX_UPCOMING_DAYS,
    TASK_COLS,
};

#[tauri::command]
pub fn get_someday_tasks() -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_someday_tasks_with_conn(&conn).map_err(String::from)
}

fn get_someday_tasks_with_conn(conn: &rusqlite::Connection) -> AppResult<Vec<Task>> {
    // `id ASC` is the deterministic tiebreaker required by CLAUDE.md
    // core rule #4 — without it, two someday tasks created in the
    // same millisecond would shuffle between OFFSET pages on every
    // refetch (the original `ORDER BY created_at DESC` alone produced
    // visible row-flicker in the Someday list).
    tasks_from_query(
        conn,
        &format!(
            "SELECT {TASK_COLS} FROM tasks \
             WHERE status = 'someday' AND tasks.archived_at IS NULL \
             ORDER BY created_at DESC, id ASC"
        ),
        [],
    )
}

/// Returns every non-archived task carrying a recurrence rule.
///
/// Powers the Recurring Tasks index (#2511): a power-user dashboard
/// that answers "which tasks recur?" in a single view. The filter is
/// `recurrence IS NOT NULL AND archived_at IS NULL` — an archived rule
/// would only add noise to an audit of what still fires. Ordering
/// mirrors `TASK_ORDER_BY` so the Recurring view feels consistent
/// with Upcoming / All Tasks.
#[tauri::command]
pub fn get_recurring_tasks() -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_recurring_tasks_with_conn(&conn).map_err(String::from)
}

fn get_recurring_tasks_with_conn(conn: &rusqlite::Connection) -> AppResult<Vec<Task>> {
    tasks_from_query(
        conn,
        &format!(
            "SELECT {TASK_COLS} FROM tasks \
             WHERE recurrence IS NOT NULL \
               AND archived_at IS NULL \
             ORDER BY {TASK_ORDER_BY}"
        ),
        [],
    )
}

fn get_task_with_conn(conn: &rusqlite::Connection, id: &str) -> AppResult<Option<Task>> {
    match fetch_task_by_id(conn, id) {
        Ok(task) => Ok(Some(task)),
        Err(AppError::NotFound(_)) => Ok(None),
        Err(error) => Err(error),
    }
}

#[cfg(test)]
fn get_task_ipc_with_conn(conn: &rusqlite::Connection, id: &str) -> AppResult<Option<Task>> {
    let id = crate::commands::shared::validate_uuid_id(id, "id").map_err(AppError::Validation)?;
    get_task_with_conn(conn, &id)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_task(id: String) -> Result<Option<Task>, String> {
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    let conn = get_read_conn()?;
    get_task_with_conn(&conn, &id).map_err(String::from)
}

fn search_tasks_with_conn(
    conn: &rusqlite::Connection,
    query: String,
    include_cancelled: Option<bool>,
    limit: Option<i64>,
) -> AppResult<Vec<Task>> {
    let limit = clamp_limit(limit, 200, 1, 500);

    let mut status_filter = vec![
        lorvex_domain::naming::STATUS_OPEN.to_string(),
        lorvex_domain::naming::STATUS_SOMEDAY.to_string(),
        lorvex_domain::naming::STATUS_COMPLETED.to_string(),
    ];
    if include_cancelled.unwrap_or(false) {
        status_filter.push(lorvex_domain::naming::STATUS_CANCELLED.to_string());
    }

    let pred = lorvex_domain::query::SearchPredicate {
        query,
        status_filter: Some(status_filter),
        list_filter: None,
        tag_filter: None,
    };
    let page = lorvex_domain::query::Pagination {
        limit: limit as u32,
        offset: 0,
    };

    let result =
        lorvex_store::repositories::task::read::search_tasks_with_fallback(conn, &pred, page)
            .map_err(AppError::from)?;

    // read::search_tasks_* already applies the
    // archived_at IS NULL filter at SQL level. The previous in-memory
    // retain was a redundant second pass.
    tasks_from_task_rows(conn, result.rows)
}

#[tauri::command]
pub fn search_tasks(
    query: String,
    include_cancelled: Option<bool>,
    limit: Option<i64>,
) -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    search_tasks_with_conn(&conn, query, include_cancelled, limit).map_err(String::from)
}

fn get_upcoming_tasks_with_conn(
    conn: &rusqlite::Connection,
    days: Option<i64>,
) -> AppResult<Vec<Task>> {
    let days = clamp_limit(days, 7, 1, MAX_UPCOMING_DAYS);
    let today_str = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
    let today = chrono::NaiveDate::parse_from_str(&today_str, "%Y-%m-%d")
        .map_err(|e| AppError::Validation(format!("Invalid today date: {e}")))?;

    let pred = lorvex_domain::query::UpcomingPredicate {
        from_date: today,
        days: days as u32,
    };
    let page = lorvex_domain::query::Pagination {
        limit: 1000,
        offset: 0,
    };

    let rows = lorvex_store::repositories::task::read::get_upcoming_tasks(conn, &pred, page)
        .map_err(AppError::from)?;

    // repo-level filter already applied.
    tasks_from_task_rows(conn, rows)
}

#[tauri::command]
pub fn get_upcoming_tasks(days: Option<i64>) -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_upcoming_tasks_with_conn(&conn, days).map_err(String::from)
}

fn get_all_tasks_with_conn(
    conn: &rusqlite::Connection,
    include_completed: Option<bool>,
    include_cancelled: Option<bool>,
) -> AppResult<Vec<Task>> {
    let include_completed = include_completed.unwrap_or(false);
    let include_cancelled = include_cancelled.unwrap_or(false);
    let sql = build_get_all_tasks_sql(include_completed, include_cancelled);
    tasks_from_query(conn, &sql, [])
}

#[tauri::command]
pub fn get_all_tasks(
    include_completed: Option<bool>,
    include_cancelled: Option<bool>,
) -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_all_tasks_with_conn(&conn, include_completed, include_cancelled).map_err(String::from)
}

/// Hard cap for get_all_tasks to prevent unbounded result sets.
///
/// bound to `TASK_LIST_RESULT_LIMIT` (defined in
/// `commands::shared::limits`) so a single edit covers every
/// task-list-IPC payload cap.
const GET_ALL_TASKS_LIMIT: u32 = crate::commands::shared::TASK_LIST_RESULT_LIMIT;

pub(crate) fn build_get_all_tasks_sql(include_completed: bool, include_cancelled: bool) -> String {
    let mut statuses = vec!["'open'", "'someday'"];
    if include_completed {
        statuses.push("'completed'");
    }
    if include_cancelled {
        statuses.push("'cancelled'");
    }
    let status_list = statuses.join(", ");

    let order_by_with_status = format!(
        "CASE status WHEN 'open' THEN 0 WHEN 'someday' THEN 1 \
                     WHEN 'completed' THEN 2 WHEN 'cancelled' THEN 3 ELSE 4 END, \
         {TASK_ORDER_BY}"
    );
    let order_by: &str = if include_completed || include_cancelled {
        &order_by_with_status
    } else {
        TASK_ORDER_BY
    };

    format!(
        "SELECT {TASK_COLS} FROM tasks \
         WHERE status IN ({status_list}) AND tasks.archived_at IS NULL \
         ORDER BY {order_by} \
         LIMIT {GET_ALL_TASKS_LIMIT}"
    )
}

/// Returns the "today pool" — open tasks whose planned_date or due_date puts
/// them on or before today.  Used by TodayView instead of fetching all tasks
/// and filtering client-side.
#[tauri::command]
pub fn get_today_pool_tasks() -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_today_pool_tasks_with_conn(&conn).map_err(String::from)
}

fn get_today_pool_tasks_with_conn(conn: &rusqlite::Connection) -> AppResult<Vec<Task>> {
    let today_str = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
    let today = chrono::NaiveDate::parse_from_str(&today_str, "%Y-%m-%d")
        .map_err(|e| AppError::Validation(format!("Invalid today date: {e}")))?;
    let rows = lorvex_store::repositories::task::read::get_today_tasks(
        conn,
        &lorvex_domain::query::TodayPredicate { date: today },
        lorvex_domain::query::Pagination {
            limit: 1000,
            offset: 0,
        },
    )
    .map_err(AppError::from)?;
    // repo-level filter already applied.
    tasks_from_task_rows(conn, rows)
}

#[tauri::command]
pub fn get_overdue_tasks() -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_overdue_tasks_with_conn(&conn).map_err(String::from)
}

fn get_overdue_tasks_with_conn(conn: &rusqlite::Connection) -> AppResult<Vec<Task>> {
    let today_str = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
    let today = chrono::NaiveDate::parse_from_str(&today_str, "%Y-%m-%d")
        .map_err(|e| AppError::Validation(format!("Invalid today date: {e}")))?;
    let rows = lorvex_store::repositories::task::read::get_overdue_tasks(
        conn,
        &lorvex_domain::query::OverduePredicate { as_of_date: today },
        lorvex_domain::query::Pagination {
            limit: 1000,
            offset: 0,
        },
    )
    .map_err(AppError::from)?;
    // repo-level filter already applied.
    tasks_from_task_rows(conn, rows)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn get_tasks_by_date_range_with_conn(
    conn: &rusqlite::Connection,
    from: String,
    to: String,
    include_completed: Option<bool>,
) -> AppResult<Vec<Task>> {
    let status_filter = if include_completed.unwrap_or(false) {
        "AND status NOT IN ('cancelled')"
    } else {
        "AND status NOT IN ('cancelled', 'completed')"
    };

    tasks_from_query(
        conn,
        // #3319: date-range view diverges from the canonical
        // `TASK_ORDER_BY` because the calendar/timeline UI groups
        // tasks by action date first (each day rendered as a
        // section), then by priority within the day. `created_at
        // DESC` surfaces the most recently captured task above older
        // equal-priority siblings — the user expectation when
        // skimming a date band. `id ASC` is the deterministic
        // OFFSET-pagination tiebreaker so two tasks sharing
        // `(action_date, priority_effective, created_at)` — easy
        // after an assistant batch capture — sort stably (same
        // flicker hazard `TASK_ORDER_BY` was retro-fitted to defeat
        // in #2343 / #2742).
        &format!(
            "SELECT {TASK_COLS} FROM tasks \
             WHERE COALESCE(planned_date, due_date) >= ?1 \
               AND COALESCE(planned_date, due_date) <= ?2 \
               {status_filter} AND tasks.archived_at IS NULL \
             ORDER BY COALESCE(planned_date, due_date) ASC, priority_effective ASC, created_at DESC, id ASC"
        ),
        params![from, to],
    )
}

#[tauri::command]
pub fn get_tasks_by_date_range(
    from: String,
    to: String,
    include_completed: Option<bool>,
) -> Result<Vec<Task>, String> {
    let conn = get_read_conn()?;
    get_tasks_by_date_range_with_conn(&conn, from, to, include_completed).map_err(String::from)
}

/// Return tasks that depend on the given task ID (i.e. tasks
/// that this task "blocks"). Uses the task_dependencies edge table.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_tasks_blocked_by(task_id: String) -> Result<Vec<Task>, String> {
    let task_id = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let task_id = lorvex_domain::TaskId::from_trusted(task_id);
    let conn = get_read_conn()?;
    get_tasks_blocked_by_with_conn(&conn, &task_id).map_err(String::from)
}

#[cfg(test)]
fn get_tasks_blocked_by_ipc_with_conn(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> AppResult<Vec<Task>> {
    let task_id = crate::commands::shared::validate_uuid_id(task_id, "task_id")
        .map_err(AppError::Validation)?;
    let task_id = lorvex_domain::TaskId::from_trusted(task_id);
    get_tasks_blocked_by_with_conn(conn, &task_id)
}

fn get_tasks_blocked_by_with_conn(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
) -> AppResult<Vec<Task>> {
    tasks_from_query(
        conn,
        // Canonical task sort. `TASK_ORDER_BY` expands to
        // `priority_effective ASC, due_date ASC NULLS LAST, id ASC`
        // — the sort every other "task list" surface uses
        // (CLAUDE.md core rule #4). A `created_at DESC` tiebreaker
        // would surface freshly-created blockers above earlier-due
        // ones when priorities match, defeating the user's
        // expectation that a task due tomorrow shows above a task
        // due next week.
        &format!(
            "SELECT {TASK_COLS} FROM tasks \
             WHERE id IN (SELECT task_id FROM task_dependencies WHERE depends_on_task_id = ?1) \
               AND tasks.archived_at IS NULL \
             ORDER BY {TASK_ORDER_BY}"
        ),
        params![task_id.as_str()],
    )
}

// ---------------------------------------------------------------------------
// Tag listing
// ---------------------------------------------------------------------------

/// Lightweight tag info returned by `get_all_tags`.
#[derive(Debug, Clone, serde::Serialize)]
pub struct TagInfo {
    pub display_name: String,
    pub color: Option<String>,
}

#[tauri::command]
pub fn get_all_tags() -> Result<Vec<TagInfo>, String> {
    let conn = get_read_conn()?;
    get_all_tags_with_conn(&conn).map_err(String::from)
}

fn get_all_tags_with_conn(conn: &rusqlite::Connection) -> AppResult<Vec<TagInfo>> {
    let mut stmt = conn
        .prepare_cached("SELECT display_name, color FROM tags ORDER BY display_name ASC")
        .map_err(AppError::from)?;
    let rows = stmt
        .query_map([], |row| {
            Ok(TagInfo {
                display_name: row.get(0)?,
                color: row.get(1)?,
            })
        })
        .map_err(AppError::from)?;
    let mut tags = Vec::new();
    for row in rows {
        tags.push(row.map_err(AppError::from)?);
    }
    Ok(tags)
}

#[cfg(test)]
mod tests;
