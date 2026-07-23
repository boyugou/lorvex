use super::*;

/// Edges loaded by `tag_id` (the rename / merge path). The lookup is
/// keyed by tag so each row needs its `task_id` to drive per-task
/// resync, and the new `display_name` is already known by the caller
/// — no join into `tags` is required, which keeps the rename merge
/// path cheap.
#[derive(Debug, Clone)]
pub(super) struct TaskTagEdgeWithTaskRow {
    pub(super) task_id: String,
    pub(super) tag_id: String,
    pub(super) created_at: String,
    pub(super) version: String,
}

pub(super) fn load_task_tag_edges_by_tag_id(
    conn: &Connection,
    tag_id: &lorvex_domain::TagId,
) -> Result<Vec<TaskTagEdgeWithTaskRow>, crate::error::CliError> {
    let mut stmt = conn.prepare_cached(
        "SELECT task_id, tag_id, created_at, version
         FROM task_tags
         WHERE tag_id = ?1
         ORDER BY task_id ASC",
    )?;
    let rows = stmt
        .query_map([tag_id.as_str()], |row| {
            Ok(TaskTagEdgeWithTaskRow {
                task_id: row.get(0)?,
                tag_id: row.get(1)?,
                created_at: row.get(2)?,
                version: row.get(3)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}
