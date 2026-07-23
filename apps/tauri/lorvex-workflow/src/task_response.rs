use chrono::NaiveDate;
use lorvex_domain::TaskId;
use lorvex_store::payload_loaders::load_task_reminders_for_task;
use lorvex_store::repositories::task::read;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::task_enrichment::{self, ChecklistItemData};

fn task_date(task: &Value, field: &str) -> Option<NaiveDate> {
    task.get(field)
        .and_then(Value::as_str)
        .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok())
}

fn checklist_item_json(item: ChecklistItemData) -> Value {
    json!({
        "id": item.id,
        "task_id": item.task_id,
        "position": item.position,
        "text": item.text,
        "completed_at": item.completed_at,
        "version": item.version,
        "created_at": item.created_at,
        "updated_at": item.updated_at,
    })
}

pub(crate) fn enrich_task_json(conn: &Connection, task: &mut Value) -> Result<(), StoreError> {
    let Some(task_id) = task.get("id").and_then(Value::as_str).map(str::to_string) else {
        return Err(StoreError::Invariant(
            "task response JSON missing id".to_string(),
        ));
    };
    let today = crate::timezone::today_ymd_for_conn(conn)?;
    let planned = task_date(task, "planned_date");
    let due = task_date(task, "due_date");
    let enrichment =
        task_enrichment::compute_enrichments(conn, &[(task_id.as_str(), planned, due)], &today)?
            .remove(&task_id)
            .unwrap_or_default();

    task["tags"] = enrichment
        .tags
        .map_or_else(|| json!([]), |tags| json!(tags));
    task["depends_on"] = enrichment
        .depends_on
        .map_or_else(|| json!([]), |depends_on| json!(depends_on));
    task["checklist_items"] = enrichment.checklist_items.map_or_else(
        || json!([]),
        |items| Value::Array(items.into_iter().map(checklist_item_json).collect()),
    );
    task["lateness_state"] = enrichment.lateness.map_or(Value::Null, |lateness| {
        serde_json::to_value(lateness).unwrap_or(Value::Null)
    });

    let typed_task_id = TaskId::from_trusted(task_id);
    let mut reminders = load_task_reminders_for_task(conn, &typed_task_id)?;
    reminders.sort_by(|(_, left), (_, right)| {
        left.get("reminder_at")
            .and_then(Value::as_str)
            .cmp(&right.get("reminder_at").and_then(Value::as_str))
    });
    task["reminders"] = Value::Array(reminders.into_iter().map(|(_, payload)| payload).collect());
    Ok(())
}

pub fn load_enriched_task_json(conn: &Connection, task_id: &TaskId) -> Result<Value, StoreError> {
    let row = read::get_task(conn, task_id)?.ok_or_else(|| StoreError::NotFound {
        entity: lorvex_domain::naming::ENTITY_TASK,
        id: task_id.to_string(),
    })?;
    let mut task = serde_json::to_value(row)?;
    enrich_task_json(conn, &mut task)?;
    Ok(task)
}

pub(crate) fn load_enriched_tasks_json(
    conn: &Connection,
    task_ids: &[String],
) -> Result<Vec<Value>, StoreError> {
    let mut tasks = Vec::with_capacity(task_ids.len());
    for task_id in task_ids {
        tasks.push(load_enriched_task_json(
            conn,
            &TaskId::from_trusted(task_id.clone()),
        )?);
    }
    Ok(tasks)
}

pub fn task_title(task: &Value) -> &str {
    task.get("title").and_then(Value::as_str).unwrap_or("task")
}
