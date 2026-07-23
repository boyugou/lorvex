use super::thresholds::{load_insight_thresholds, InsightThresholds};
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::runtime::cancellation::check_cancelled;
use crate::system::time_support::trailing_day_window_bounds_for_conn;
use lorvex_domain::naming::{STATUS_COMPLETED, STATUS_OPEN};
use lorvex_workflow::timezone::{active_timezone_name, today_ymd_for_conn};
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::Value;
use tokio_util::sync::CancellationToken;

/// Convert an RFC 3339 UTC timestamp to a local YMD in the given IANA
/// timezone (or system-local when the name is empty/unparseable). Delegates
/// to `lorvex_domain::time::today_ymd_for_timezone_name` which owns the
/// canonical timezone→day conversion logic. Returns the raw UTC prefix
/// of the input if parsing fails — the resulting diagnostic may be
/// slightly off, but one malformed row must not abort the whole
/// pattern-analysis run.
fn completed_at_local_ymd(completed_at: &str, tz_name: Option<&str>) -> String {
    if let Ok(parsed) = chrono::DateTime::parse_from_rfc3339(completed_at) {
        return lorvex_domain::time::today_ymd_for_timezone_name(
            parsed.with_timezone(&chrono::Utc),
            tz_name,
        );
    }
    completed_at.chars().take(10).collect()
}

pub(in crate::system::guidance::task_pattern_analysis) struct LearningMetrics {
    pub(in crate::system::guidance::task_pattern_analysis) today: String,
    pub(in crate::system::guidance::task_pattern_analysis) created_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) completed_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) attention_distribution: Vec<Value>,
    pub(in crate::system::guidance::task_pattern_analysis) deferred_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) deferred_tasks: Vec<Value>,
    pub(in crate::system::guidance::task_pattern_analysis) due_date_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) due_date_miss_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) due_date_miss_tasks: Vec<Value>,
    pub(in crate::system::guidance::task_pattern_analysis) stalled_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) stalled_lists: Vec<Value>,
    pub(in crate::system::guidance::task_pattern_analysis) overdue_total: i64,
    pub(in crate::system::guidance::task_pattern_analysis) overdue_tasks: Vec<Value>,
    pub(in crate::system::guidance::task_pattern_analysis) thresholds: InsightThresholds,
}

pub(in crate::system::guidance::task_pattern_analysis) fn collect_task_pattern_metrics(
    conn: &Connection,
    window_days: u32,
    top_n: u32,
    ct: &CancellationToken,
) -> Result<LearningMetrics, McpError> {
    let today = today_ymd_for_conn(conn)?;
    let thresholds = load_insight_thresholds(conn)?;
    let learning_window = trailing_day_window_bounds_for_conn(conn, i64::from(window_days))?;
    let stalled_window = trailing_day_window_bounds_for_conn(conn, thresholds.stalled_window_days)?;

    // #2133: check at every major SQL boundary. Each of these
    // SELECTs can run tens of milliseconds on a realistically-sized
    // task table; on a cold cache they can be hundreds. Returning
    // early here lets the MCP client's Stop button actually stop
    // the rest of the aggregate, instead of waiting for the full
    // pipeline to complete.
    check_cancelled(ct)?;
    let created_total: i64 = conn.query_row(
        "
        SELECT COUNT(*)
        FROM tasks
        -- bare compare uses idx on created_at; wrapping
        -- in datetime() forces a full table scan.
        WHERE created_at >= ?
          AND created_at < ?
        ",
        [
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
        ],
        |row| row.get(0),
    )?;
    let completed_total: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(*) \
             FROM tasks \
             WHERE status = '{STATUS_COMPLETED}' \
               AND archived_at IS NULL \
               AND completed_at IS NOT NULL \
               AND completed_at >= ? \
               AND completed_at < ?"
        ),
        [
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
        ],
        |row| row.get(0),
    )?;
    check_cancelled(ct)?;
    let attention_distribution = query_all_as_json(
        conn,
        &format!(
            // `updated_at` is always ISO-8601; wrapping in datetime() is
            // a no-op semantically but defeats `idx_tasks_updated_at`.
            // Compare the raw strings instead.
            "SELECT \
               t.list_id AS list_id, \
               l.name AS list_name, \
               COUNT(*) AS touched_count, \
               SUM(CASE WHEN t.status = '{STATUS_COMPLETED}' \
                          AND t.completed_at IS NOT NULL \
                          AND t.completed_at >= ? \
                          AND t.completed_at < ? \
                         THEN 1 ELSE 0 END) AS completed_count, \
               SUM(CASE WHEN t.status = '{STATUS_OPEN}' THEN 1 ELSE 0 END) AS open_count \
             FROM tasks t \
             JOIN lists l ON l.id = t.list_id \
             WHERE t.updated_at >= ? \
               AND t.updated_at < ? \
               AND t.archived_at IS NULL \
             GROUP BY t.list_id, l.name \
             ORDER BY touched_count DESC, completed_count DESC, list_name ASC, t.list_id ASC \
             LIMIT ?"
        ),
        [
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
            SqlValue::Integer(i64::from(top_n)),
        ],
    )?;

    check_cancelled(ct)?;
    let deferred_total: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(*) \
             FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND archived_at IS NULL \
               AND defer_count >= ? \
               AND updated_at >= ? \
               AND updated_at < ?"
        ),
        [
            SqlValue::Integer(thresholds.defer_count_min),
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
        ],
        |row| row.get(0),
    )?;
    // #3319: pattern-analysis snapshot diverges from the canonical
    // `TASK_ORDER_BY` because this is a learning-metrics view, not a
    // task list. The user-facing question is "what is the assistant
    // deferring most?" so `defer_count DESC` is the primary axis;
    // canonical priority/due_date drop to secondary. `updated_at DESC`
    // surfaces tasks the user touched most recently so the assistant
    // can reason about live offenders before stale ones. `id ASC` is
    // the OFFSET-pagination tiebreaker.
    let deferred_tasks = query_all_as_json(
        conn,
        &format!(
            "SELECT id, title, defer_count, due_date, updated_at \
             FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND archived_at IS NULL \
               AND defer_count >= ? \
               AND updated_at >= ? \
               AND updated_at < ? \
             ORDER BY defer_count DESC, priority_effective ASC, due_date ASC NULLS LAST, updated_at DESC, id ASC \
             LIMIT ?"
        ),
        [
            SqlValue::Integer(thresholds.defer_count_min),
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
            SqlValue::Integer(i64::from(top_n)),
        ],
    )?;
    check_cancelled(ct)?;
    let due_date_total: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(*) \
             FROM tasks \
             WHERE status = '{STATUS_COMPLETED}' \
               AND archived_at IS NULL \
               AND due_date IS NOT NULL \
               AND completed_at IS NOT NULL \
               AND completed_at >= ? \
               AND completed_at < ?"
        ),
        [
            SqlValue::Text(learning_window.start_utc.clone()),
            SqlValue::Text(learning_window.end_utc.clone()),
        ],
        |row| row.get(0),
    )?;
    // — which returns the UTC calendar day for a Z-suffixed timestamp —
    // against `due_date`, which is stored as a local YMD string. Users
    // west of UTC got spurious "miss" flags (completed on-time after
    // 5pm local → bumped to next UTC day); users east of UTC had real
    // misses disappear. Do the compare in Rust against the user's
    // configured timezone instead.
    // active_timezone_name returns `Option<String>` — None
    // means "use system local".
    let active_tz: Option<String> = active_timezone_name(conn)?;
    let candidate_tasks = query_all_as_json(
        conn,
        &format!(
            "SELECT id, title, due_date, completed_at \
             FROM tasks \
             WHERE status = '{STATUS_COMPLETED}' \
               AND archived_at IS NULL \
               AND due_date IS NOT NULL \
               AND completed_at IS NOT NULL \
               AND completed_at >= ? \
               AND completed_at < ? \
             ORDER BY due_date ASC, completed_at DESC, id ASC"
        ),
        [
            SqlValue::Text(learning_window.start_utc),
            SqlValue::Text(learning_window.end_utc),
        ],
    )?;
    let mut missed_tasks: Vec<Value> = Vec::new();
    for task in &candidate_tasks {
        let Some(completed_at) = task.get("completed_at").and_then(Value::as_str) else {
            continue;
        };
        let Some(due_date) = task.get("due_date").and_then(Value::as_str) else {
            continue;
        };
        let local_ymd = completed_at_local_ymd(completed_at, active_tz.as_deref());
        if local_ymd.as_str() > due_date {
            missed_tasks.push(task.clone());
        }
    }
    let due_date_miss_total: i64 = missed_tasks.len() as i64;
    let due_date_miss_tasks: Vec<Value> = missed_tasks.into_iter().take(top_n as usize).collect();

    check_cancelled(ct)?;
    let stalled_total: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(*) FROM ( \
               SELECT l.id \
               FROM lists l \
               JOIN tasks t \
                 ON t.list_id = l.id \
                AND t.status = '{STATUS_OPEN}' \
                AND t.archived_at IS NULL \
               GROUP BY l.id \
               HAVING MAX(t.updated_at) < ? \
             )"
        ),
        [stalled_window.start_utc.clone()],
        |row| row.get(0),
    )?;
    let stalled_lists = query_all_as_json(
        conn,
        &format!(
            "SELECT l.id, l.name, COUNT(t.id) AS open_task_count, MAX(t.updated_at) AS last_activity \
             FROM lists l \
             JOIN tasks t \
               ON t.list_id = l.id \
              AND t.status = '{STATUS_OPEN}' \
              AND t.archived_at IS NULL \
             GROUP BY l.id \
             HAVING last_activity < ? \
             ORDER BY open_task_count DESC, last_activity ASC, l.id ASC \
             LIMIT ?"
        ),
        [
            SqlValue::Text(stalled_window.start_utc),
            SqlValue::Integer(i64::from(top_n)),
        ],
    )?;

    check_cancelled(ct)?;
    let overdue_total: i64 = conn.query_row(
        &format!(
            "SELECT COUNT(*) \
             FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND archived_at IS NULL \
               AND due_date IS NOT NULL \
               AND due_date < ?"
        ),
        [today.clone()],
        |row| row.get(0),
    )?;
    // #3319: overdue snapshot for pattern analysis diverges from the
    // canonical `TASK_ORDER_BY`. We lead with `due_date ASC` so the
    // longest-overdue tasks (the most actionable signal for the
    // assistant) surface first regardless of priority. Within an
    // equal-overdue date, priority then `created_at DESC` (newer
    // tasks first — the older ones are presumably already known) and
    // `id ASC` for OFFSET stability.
    let overdue_tasks = query_all_as_json(
        conn,
        &format!(
            "SELECT id, title, due_date \
             FROM tasks \
             WHERE status = '{STATUS_OPEN}' \
               AND archived_at IS NULL \
               AND due_date IS NOT NULL \
               AND due_date < ? \
             ORDER BY due_date ASC, priority_effective ASC, created_at DESC, id ASC \
             LIMIT ?"
        ),
        [
            SqlValue::Text(today.clone()),
            SqlValue::Integer(i64::from(top_n)),
        ],
    )?;

    Ok(LearningMetrics {
        today,
        created_total,
        completed_total,
        attention_distribution,
        deferred_total,
        deferred_tasks,
        due_date_total,
        due_date_miss_total,
        due_date_miss_tasks,
        stalled_total,
        stalled_lists,
        overdue_total,
        overdue_tasks,
        thresholds,
    })
}
