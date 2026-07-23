use crate::error::McpError;
use crate::json_row::query_all_as_json;
use lorvex_domain::naming;
use rusqlite::{params_from_iter, types::Value as SqlValue, Connection};
use serde_json::{json, Value};

pub(super) fn build_task_intake_advice(
    conn: &Connection,
    task: &Value,
) -> Result<Vec<Value>, McpError> {
    let Some(task_id) = task.get("id").and_then(Value::as_str) else {
        return Ok(Vec::new());
    };
    let title = task
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("task")
        .to_string();
    let status = task
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or(naming::STATUS_OPEN);
    let mut advice = Vec::new();

    if status == naming::STATUS_OPEN
        && task
            .get("estimated_minutes")
            .and_then(Value::as_i64)
            .unwrap_or(0)
            <= 0
    {
        advice.push(json!({
            "code": "missing_estimate",
            "severity": "medium",
            "message": "Add an estimate if you have a confident rough time cost.",
        }));
    }

    if status == naming::STATUS_OPEN && task.get("planned_date").and_then(Value::as_str).is_none() {
        advice.push(json!({
            "code": "missing_planned_date",
            "severity": "medium",
            "message": "Set a planned_date when you know which day you intend to work on this.",
        }));
    }

    let duplicate_values = vec![
        SqlValue::Text(title.to_lowercase()),
        SqlValue::Text(task_id.to_string()),
        SqlValue::Text(naming::STATUS_OPEN.to_string()),
        SqlValue::Text(naming::STATUS_SOMEDAY.to_string()),
        SqlValue::Integer(3),
    ];
    let duplicates = query_all_as_json(
        conn,
        "SELECT id, title, status, list_id
         FROM tasks
         WHERE LOWER(title) = ?1
           AND id != ?2
           AND archived_at IS NULL
           AND status IN (?3, ?4)
         ORDER BY created_at DESC, id ASC
         LIMIT ?5",
        params_from_iter(duplicate_values),
    )?;
    if !duplicates.is_empty() {
        advice.push(json!({
            "code": "likely_duplicate_title",
            "severity": "low",
            "message": "A task with the same title is already active.",
            "related_tasks": duplicates,
        }));
    }

    Ok(advice)
}
