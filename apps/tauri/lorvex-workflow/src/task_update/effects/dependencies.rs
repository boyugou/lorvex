//! Dependency edge replace for a single-row task update.
//!
//! [`replace_dependency_edges`] snapshots the row's current dependency
//! edge set, deletes them, and re-inserts the new list — accumulating
//! the deleted-edge tombstone payloads and the upsert ids into
//! [`TaskUpdateSyncEffects`]. The cross-row dependency-cycle revalidator
//! lives in the orchestrator [`super::super::mutation`] so it can see
//! the final post-update graph after every row's edges have landed.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::{TaskDependencyEdgeId, TaskId};
use lorvex_store::StoreError;
use rusqlite::Connection;

use super::super::mutation::TaskUpdateSyncEffects;
use crate::lifecycle::DeletedDependencyEdge;

pub(in crate::task_update) fn replace_dependency_edges(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &TaskId,
    new_depends_on: &[String],
    effects: &mut TaskUpdateSyncEffects,
) -> Result<(), StoreError> {
    let old_deps = conn
        .prepare_cached(
            "SELECT depends_on_task_id, version, created_at \
             FROM task_dependencies WHERE task_id = ?1",
        )?
        .query_map([task_id.as_str()], |row| {
            Ok(DeletedDependencyEdge {
                task_id: task_id.as_str().to_string(),
                depends_on_task_id: row.get(0)?,
                version: row.get(1)?,
                created_at: row.get(2)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")?
        .execute([task_id.as_str()])?;
    effects.deleted_dependency_edges.extend(old_deps);

    if new_depends_on.is_empty() {
        return Ok(());
    }
    let version = hlc.next_version_string();
    let now = lorvex_domain::sync_timestamp_now();
    let deps = new_depends_on
        .iter()
        .map(|dep| TaskId::from_trusted_str(dep))
        .collect::<Vec<_>>();
    lorvex_store::repositories::task::dependencies::insert_dependency_edges_batch(
        conn, task_id, &deps, &version, &now,
    )?;
    effects
        .dependency_edge_upsert_ids
        .extend(new_depends_on.iter().map(|dep| {
            TaskDependencyEdgeId::new(task_id, &TaskId::from_trusted_str(dep)).into_string()
        }));
    Ok(())
}

pub(in crate::task_update) fn find_task_dependencies(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<String>, StoreError> {
    let mut stmt =
        conn.prepare_cached("SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?1")?;
    let deps = stmt
        .query_map([task_id.as_str()], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(deps)
}

/// Trim, drop blanks, and deduplicate (preserving first-seen order).
/// Used by both the replace (`depends_on`) and incremental
/// (`depends_on_add` / `depends_on_remove`) paths in preparation so
/// the workflow's canonical dependency list is always normalized
/// regardless of which surface produced it.
pub(in crate::task_update) fn normalize_dependency_ids(ids: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::with_capacity(ids.len());
    ids.into_iter()
        .map(|id| id.trim().to_string())
        .filter(|id| !id.is_empty() && seen.insert(id.clone()))
        .collect()
}

/// Resolver mirroring [`super::tags::apply_tag_patch`]: merges the
/// add/remove patches into the row's current dependency edge set.
/// Removes run before adds so a single patch can replace a specific
/// edge in place (remove + add the same id).
pub(in crate::task_update) fn apply_dependency_patch(
    current: &[String],
    depends_on_add: Option<Vec<String>>,
    depends_on_remove: Option<Vec<String>>,
) -> Vec<String> {
    let mut deps = normalize_dependency_ids(current.to_vec());
    let remove_set: std::collections::HashSet<String> =
        normalize_dependency_ids(depends_on_remove.unwrap_or_default())
            .into_iter()
            .collect();
    if !remove_set.is_empty() {
        deps.retain(|id| !remove_set.contains(id));
    }
    if let Some(to_add) = depends_on_add {
        deps.extend(to_add);
    }
    normalize_dependency_ids(deps)
}
