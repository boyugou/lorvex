use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

use lorvex_store::StoreError;

use super::types::DeletedDependencyEdge;

/// Remove a task from all dependency edges (both incoming and outgoing).
/// Returns (affected_task_ids, deleted_edges) where affected_task_ids are
/// tasks that depended on this one (now unblocked), and deleted_edges are
/// the exact edge identities for sync deletion.
pub(crate) fn remove_task_dependency_edges(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<(Vec<String>, Vec<DeletedDependencyEdge>), StoreError> {
    let mut deleted_edges = Vec::new();

    // Capture the row's `created_at` + `version` alongside the id
    // pair so the caller can ship the cascade tombstone via
    // `enqueue_payload_delete` with the full pre-delete payload
    // shape. Selecting only the id columns would force the caller to
    // enqueue an empty `{}` tombstone.

    // Find tasks that depend on this one (incoming edges).
    let mut affected: Vec<String> = Vec::new();
    {
        let mut stmt = conn.prepare_cached(
            "SELECT task_id, created_at, version FROM task_dependencies WHERE depends_on_task_id = ?1",
        )?;
        let rows = stmt
            .query_map(params![task_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        for (dep_task_id, created_at, version) in rows {
            affected.push(dep_task_id.clone());
            deleted_edges.push(DeletedDependencyEdge {
                task_id: dep_task_id,
                depends_on_task_id: task_id.as_str().to_string(),
                created_at,
                version,
            });
        }
    }

    // Find outgoing edges (this task's own dependencies).
    {
        let mut stmt = conn.prepare_cached(
            "SELECT depends_on_task_id, created_at, version FROM task_dependencies WHERE task_id = ?1",
        )?;
        let rows = stmt
            .query_map(params![task_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        for (dep_id, created_at, version) in rows {
            deleted_edges.push(DeletedDependencyEdge {
                task_id: task_id.as_str().to_string(),
                depends_on_task_id: dep_id,
                created_at,
                version,
            });
        }
    }

    // Remove incoming + outgoing edges. Issued as TWO separate
    // DELETEs (one per direction) rather than a single
    // `WHERE task_id = ?1 OR depends_on_task_id = ?1` because SQLite
    // cannot combine the PK `(task_id, depends_on_task_id)` index with
    // the secondary `idx_task_deps_depends_on(depends_on_task_id)`
    // for an `OR` predicate — the planner falls back to a full table
    // scan or an `OR-by-rowid` union with two index probes plus a
    // temp B-tree of rowids. Splitting into two prepared DELETEs lets
    // each one use its own index directly. The pair runs inside the
    // same transaction the caller already holds (every `cleanup_*`
    // call site is wrapped in a savepoint), so a process crash
    // between the two statements still rolls back atomically and
    // preserves the "after Ok, every edge touching task_id is gone"
    // invariant the loader above relies on.
    conn.execute(
        "DELETE FROM task_dependencies WHERE task_id = ?1",
        params![task_id],
    )?;
    conn.execute(
        "DELETE FROM task_dependencies WHERE depends_on_task_id = ?1",
        params![task_id],
    )?;

    Ok((affected, deleted_edges))
}
