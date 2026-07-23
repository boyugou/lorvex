use crate::startup_maintenance::open_db_at_path;
use chrono::{Duration, Utc};
use lorvex_runtime::resolve_db_path;
use lorvex_store::repositories::list_repo;
use lorvex_store::repositories::task::read;
use rusqlite::types::Value as SqlValue;

use crate::cli::OutputFormat;
use crate::commands::shared::today_ymd_for_conn;
use crate::models::{ListHealthLimits, ListHealthRow, ListHealthSnapshot, ListHealthSummary};
use crate::render::{
    render_list_collection, render_list_detail, render_list_health_snapshot, task_row_to_summary,
};

pub(crate) fn run_lists(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let lists = list_repo::get_all_lists_with_counts(&conn)?;
    render_list_collection(&db_path, &lists, format)
}

const LIST_HEALTH_LIMIT_DEFAULT: u32 = 50;
const LIST_HEALTH_LIMIT_CAP: u32 = 200;
const LIST_HEALTH_NAME_MAX_CHARS: usize = 80;

pub(crate) fn run_list_health(
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let snapshot = get_list_health_snapshot_with_conn(&conn, limit)?;
    render_list_health_snapshot(&db_path, &snapshot, format)
}

pub(super) fn get_list_health_snapshot_with_conn(
    conn: &rusqlite::Connection,
    limit: u32,
) -> Result<ListHealthSnapshot, crate::error::CliError> {
    let limit = match limit {
        0 => LIST_HEALTH_LIMIT_DEFAULT,
        value => value.min(LIST_HEALTH_LIMIT_CAP),
    };
    let today = today_ymd_for_conn(conn)?;
    let sql = r"
        SELECT
          l.id,
          l.name,
          l.color,
          l.icon,
          COALESCE(SUM(CASE WHEN t.status = 'open' THEN 1 ELSE 0 END), 0) AS open_count,
          COALESCE(SUM(CASE WHEN t.status = 'open' AND t.due_date < ? THEN 1 ELSE 0 END), 0) AS overdue_open_count,
          COALESCE(SUM(CASE WHEN t.status = 'open' AND t.due_date = ? THEN 1 ELSE 0 END), 0) AS due_today_open_count,
          COUNT(*) OVER() AS total_lists
        FROM lists l
        LEFT JOIN tasks t ON t.list_id = l.id AND t.archived_at IS NULL
        GROUP BY l.id
        ORDER BY l.created_at ASC
        LIMIT ?
        ";

    let mut stmt = conn.prepare(sql)?;
    let mut rows = stmt.query(rusqlite::params![
        SqlValue::Text(today.clone()),
        SqlValue::Text(today.clone()),
        SqlValue::Integer(i64::from(limit)),
    ])?;

    let mut lists = Vec::new();
    let mut total_lists = 0;
    while let Some(row) = rows.next()? {
        if lists.is_empty() {
            total_lists = row.get::<_, i64>("total_lists")?;
        }
        lists.push(ListHealthRow {
            id: row.get("id")?,
            name: compact_and_truncate_list_name(&row.get::<_, String>("name")?),
            color: row.get("color")?,
            icon: row.get("icon")?,
            open_count: row.get("open_count")?,
            overdue_open_count: row.get("overdue_open_count")?,
            due_today_open_count: row.get("due_today_open_count")?,
        });
    }

    Ok(ListHealthSnapshot {
        date: today,
        summary: ListHealthSummary {
            total_lists,
            returned_lists: lists.len(),
            limit,
            truncated: total_lists > lists.len() as i64,
        },
        lists,
        limits: ListHealthLimits {
            lists: limit,
            name_max_chars: LIST_HEALTH_NAME_MAX_CHARS,
        },
    })
}

fn compact_and_truncate_list_name(raw: &str) -> String {
    let compacted = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut chars = compacted.chars();
    let truncated = chars
        .by_ref()
        .take(LIST_HEALTH_NAME_MAX_CHARS)
        .collect::<String>();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        truncated
    }
}

pub(crate) fn run_list_show(
    list_id: &str,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let list_id_typed = lorvex_domain::ListId::from_trusted(list_id.to_string());
    let list = list_repo::get_list(&conn, &list_id_typed)?
        .ok_or_else(|| crate::error::CliError::NotFound(format!("list '{list_id}' not found")))?;
    let end = Utc::now();
    let start = end - Duration::days(7);
    // the repository now trims to `limit` and reports
    // `total_matching` directly, so the CLI no longer needs the
    // post-fetch `.take()` it apply. Push the limit into the
    // SQL via the typed parameter rather than fetch-everything-then-
    // truncate.
    let result = read::get_list_tasks_with_recent_completed(
        &conn,
        &list_id_typed,
        &start.to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
        &end.to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
        limit,
    )?;
    let tasks = result
        .rows
        .into_iter()
        .map(task_row_to_summary)
        .collect::<Vec<_>>();
    render_list_detail(&db_path, &list, &tasks, format)
}
