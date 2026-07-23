use crate::error::StoreError;
use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskChecklistItemRow {
    pub id: String,
    pub task_id: String,
    pub position: i64,
    pub text: String,
    pub completed_at: Option<String>,
    pub version: String,
    pub created_at: String,
    pub updated_at: String,
}

fn checklist_item_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskChecklistItemRow> {
    Ok(TaskChecklistItemRow {
        id: row.get(0)?,
        task_id: row.get(1)?,
        position: row.get(2)?,
        text: row.get(3)?,
        completed_at: row.get(4)?,
        version: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

pub fn list_task_checklist_items(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<TaskChecklistItemRow>, StoreError> {
    // use `prepare_cached` so callers that loop over
    // many task ids (`super::promote`, cold-open
    // markdown promotion) reuse a single compiled statement instead of
    // re-preparing on every iteration. The statement-cache key is the
    // SQL string itself, so identical text is shared across call sites.
    let mut stmt = conn.prepare_cached(
        "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
         FROM task_checklist_items
         WHERE task_id = ?1
         ORDER BY position ASC, created_at ASC, id ASC",
    )?;
    let rows = stmt.query_map(params![task_id], checklist_item_from_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

pub fn list_task_checklist_items_for_tasks(
    conn: &Connection,
    task_ids: &[TaskId],
) -> Result<Vec<TaskChecklistItemRow>, StoreError> {
    if task_ids.is_empty() {
        return Ok(Vec::new());
    }

    let placeholders = lorvex_domain::sql_in_placeholders(task_ids.len(), 0);
    let sql = format!(
        "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
         FROM task_checklist_items
         WHERE task_id IN ({placeholders})
         ORDER BY task_id ASC, position ASC, created_at ASC, id ASC"
    );
    // route the per-N IN-list SELECT through `prepare_cached`
    // so apply-time batches with stable N reuse the parsed plan.
    // The cache-key permutation is bounded by the per-task checklist
    // item count distribution, which is small (typically < 10).
    let mut stmt = conn.prepare_cached(&sql)?;
    let params: Vec<&dyn rusqlite::types::ToSql> = task_ids
        .iter()
        .map(|id| id as &dyn rusqlite::types::ToSql)
        .collect();
    let rows = stmt.query_map(params.as_slice(), checklist_item_from_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}
