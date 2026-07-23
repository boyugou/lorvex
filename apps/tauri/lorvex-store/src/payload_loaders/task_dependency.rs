use lorvex_domain::TaskId;
use rusqlite::Row;
use serde_json::{json, Value};

pub const TASK_DEPENDENCY_SELECT_COLUMNS: &str = "task_id, depends_on_task_id, version, created_at";

/// Primitive payload builder shared by the row-mapper and the
/// `DeletedDependencyEdge` tombstone path. Centralizing the literal
/// keeps the two surfaces in lock-step — a dropped/renamed field
/// would otherwise drift between the upsert and delete envelopes
///.
pub fn task_dependency_payload(
    task_id: &TaskId,
    depends_on_task_id: &TaskId,
    version: &str,
    created_at: &str,
) -> Value {
    json!({
        "task_id": task_id,
        "depends_on_task_id": depends_on_task_id,
        "version": version,
        "created_at": created_at,
    })
}

pub fn task_dependency_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let task_id: TaskId = row.get(0)?;
    let depends_on_task_id: TaskId = row.get(1)?;
    let version: String = row.get(2)?;
    let created_at: String = row.get(3)?;
    Ok(task_dependency_payload(
        &task_id,
        &depends_on_task_id,
        &version,
        &created_at,
    ))
}
