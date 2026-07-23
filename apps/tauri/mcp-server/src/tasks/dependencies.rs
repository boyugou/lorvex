use crate::error::McpError;
use lorvex_domain::naming::{
    EDGE_TASK_DEPENDENCY, ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TASK, OP_DELETE,
    OP_UPSERT,
};
use lorvex_domain::TaskId;

use crate::runtime::change_tracking::{enqueue_relation_sync, log_change, LogChangeParams};
use crate::system::handler_support::fetch_tasks_json_batch;
use rusqlite::Connection;
use serde_json::Value;

// ── Edge table operations ───────────────────────────────────────────

/// Find all open/someday tasks that depend on `task_id`
/// (i.e., task_id appears as depends_on_task_id in the edge table).
///
/// the `WHERE t.status IN ('open', 'someday')` filter
/// is INTENTIONAL. The only consumers are blocker / unblock-on-complete
/// notifications and the dependency-cycle preview surfaces, both of
/// which only care about tasks the user can still act on. Completed,
/// cancelled, or archived dependents are silently skipped because
/// notifying about a "task X unblocked completed-task Y" is noise —
/// the user already finished Y, and the finishing event broke the
/// dependency by definition. The dependency edge ROW itself stays in
/// `task_dependencies` (and is correctly cascaded on parent delete),
/// so historical audit reads via `find_task_dependencies` still see
/// the full graph.
pub(crate) fn find_tasks_depending_on(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<String>, McpError> {
    // The active-status list comes from the canonical
    // `lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST` so a
    // future status addition flows here automatically. Static
    // interpolation keeps the SQL string `&'static str`-friendly for
    // `prepare_cached`.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let mut stmt = conn.prepare_cached(SQL.get_or_init(|| {
        format!(
            "SELECT td.task_id FROM task_dependencies td
                 JOIN tasks t ON t.id = td.task_id
                 WHERE td.depends_on_task_id = ?1
                   AND t.status IN ({active_list})
                   AND t.archived_at IS NULL",
            active_list = lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST,
        )
    }))?;
    let ids: Vec<String> = stmt
        .query_map([task_id.as_str()], |row| row.get(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ids)
}

// ── Removal (task deletion/cancellation cleanup) ─────────────────────

/// Result of `remove_task_from_all_deps`. Carries the affected ids
/// alongside their pre-mutation row snapshots so the downstream
/// `sync_dep_affected_tasks` audit log can populate `before_json`.
/// peers unable to tell what the cascade deletion actually changed.
pub(crate) struct DepAffectedSnapshot {
    pub(crate) ids: Vec<String>,
    pub(crate) before_by_id: std::collections::HashMap<String, serde_json::Value>,
}

impl DepAffectedSnapshot {
    /// Construct a snapshot for callers that already mutated state
    /// upstream (e.g. transition side-effects from
    /// `batch::*::side_effects`). Pre-mutation row state
    /// isn't recoverable here, so `before_json` will be `None` for
    /// each id —Cascade
    /// flows that go through `remove_task_from_all_deps` get a
    /// correctly populated snapshot via that function's return.
    pub(crate) fn from_ids_only(ids: Vec<String>) -> Self {
        Self {
            ids,
            before_by_id: std::collections::HashMap::new(),
        }
    }
}

/// Remove a task from all dependency references.
/// With CASCADE on the edge table, deleting a task automatically removes
/// its edges. This function handles the case where a task is cancelled
/// (not deleted) — we need to remove edges where other tasks depend on it.
///
/// Returns the IDs of tasks whose dependency sets changed and a
/// `before_json` snapshot for each (captured BEFORE the edge delete).
pub(crate) fn remove_task_from_all_deps(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<DepAffectedSnapshot, McpError> {
    // SELECT `version` + `created_at` along with the dependent
    // task_id so the per-edge tombstone payload below matches the
    // canonical spb shape.
    let mut stmt = conn.prepare_cached(
        "SELECT task_id, version, created_at \
         FROM task_dependencies WHERE depends_on_task_id = ?1",
    )?;
    let affected_rows: Vec<(String, String, String)> = stmt
        .query_map([task_id.as_str()], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    drop(stmt);
    let affected: Vec<String> = affected_rows.iter().map(|(id, _, _)| id.clone()).collect();

    // #3019-H2: snapshot the affected task rows BEFORE the edge delete
    // so the audit row carries a full pre-mutation `before_json` per
    // task. The dependency-set change isn't visible on the row itself,
    // but the snapshot still pins the rest of the task state at the
    // moment of cascade so peers can diff.
    let before_snapshots = fetch_tasks_json_batch(conn, &affected, "dep cleanup before_json")?;
    let mut before_by_id: std::collections::HashMap<String, serde_json::Value> =
        std::collections::HashMap::with_capacity(before_snapshots.len());
    for snapshot in before_snapshots {
        if let Some(id) = snapshot.get("id").and_then(Value::as_str) {
            before_by_id.insert(id.to_string(), snapshot);
        }
    }

    // Also collect edges where this task depends on others —
    // capturing `version` + `created_at` for the canonical tombstone
    // shape.
    let mut own_deps_stmt = conn.prepare_cached(
        "SELECT depends_on_task_id, version, created_at \
         FROM task_dependencies WHERE task_id = ?1",
    )?;
    let own_deps: Vec<(String, String, String)> = own_deps_stmt
        .query_map([task_id.as_str()], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    drop(own_deps_stmt);

    // Remove all edges where this task is a dependency target
    conn.prepare_cached("DELETE FROM task_dependencies WHERE depends_on_task_id = ?1")?
        .execute([task_id.as_str()])?;

    // Remove outgoing edges too. Relying solely on the later
    // task-row CASCADE would let the local helper emit a DELETE
    // envelope for a row it has not actually removed yet.
    if !own_deps.is_empty() {
        conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")?
            .execute([task_id.as_str()])?;
    }

    // per-edge tombstone snapshots routed through the spb primitive
    // so peers receive the canonical 4-field shape
    // (`task_id, depends_on_task_id, version, created_at`) instead of
    // no-version LWW compare branch.
    for (dep_task_id, version, created_at) in &affected_rows {
        let entity_id = format!("{}:{}", dep_task_id, task_id.as_str());
        let typed_dep_task_id = lorvex_domain::TaskId::from_trusted(dep_task_id.clone());
        let snapshot = lorvex_store::payload_loaders::task_dependency_payload(
            &typed_dep_task_id,
            task_id,
            version,
            created_at,
        );
        crate::runtime::change_tracking::enqueue_relation_sync_with_snapshot(
            conn,
            EDGE_TASK_DEPENDENCY,
            &entity_id,
            OP_DELETE,
            Some(snapshot),
        )?;
    }
    for (dep_id, version, created_at) in &own_deps {
        let entity_id = format!("{}:{}", task_id.as_str(), dep_id);
        let typed_dep_id = lorvex_domain::TaskId::from_trusted(dep_id.clone());
        let snapshot = lorvex_store::payload_loaders::task_dependency_payload(
            task_id,
            &typed_dep_id,
            version,
            created_at,
        );
        crate::runtime::change_tracking::enqueue_relation_sync_with_snapshot(
            conn,
            EDGE_TASK_DEPENDENCY,
            &entity_id,
            OP_DELETE,
            Some(snapshot),
        )?;
    }

    Ok(DepAffectedSnapshot {
        ids: affected,
        before_by_id,
    })
}

// ── Plan orphan cleanup ──────────────────────────────────────────────

/// Remove a deleted task from current_focus_items and focus_schedule_blocks
/// to prevent orphaned soft-ref rows (neither table has FK CASCADE from tasks).
pub(crate) fn cleanup_plan_refs_after_removal(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<(), McpError> {
    let affected_focus_dates: Vec<String> = {
        let mut stmt = conn
            .prepare_cached("SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?1")?;
        let dates = stmt
            .query_map(rusqlite::params![task_id.as_str()], |row| {
                row.get::<_, String>(0)
            })?
            .collect::<Result<Vec<_>, _>>()?;
        dates
    };
    let affected_schedule_dates: Vec<String> = {
        let mut stmt = conn.prepare_cached(
            "SELECT DISTINCT schedule_date FROM focus_schedule_blocks WHERE task_id = ?1",
        )?;
        let dates = stmt
            .query_map(rusqlite::params![task_id.as_str()], |row| {
                row.get::<_, String>(0)
            })?
            .collect::<Result<Vec<_>, _>>()?;
        dates
    };

    conn.prepare_cached("DELETE FROM current_focus_items WHERE task_id = ?1")?
        .execute(rusqlite::params![task_id.as_str()])?;
    conn.prepare_cached("DELETE FROM focus_schedule_blocks WHERE task_id = ?1")?
        .execute(rusqlite::params![task_id.as_str()])?;

    for date in &affected_focus_dates {
        enqueue_relation_sync(conn, ENTITY_CURRENT_FOCUS, date, OP_UPSERT)?;
    }
    for date in &affected_schedule_dates {
        enqueue_relation_sync(conn, ENTITY_FOCUS_SCHEDULE, date, OP_UPSERT)?;
    }
    Ok(())
}

// ── Sync helper ──────────────────────────────────────────────────────

/// Log sync events for tasks whose dependency sets were modified.
///
/// `dep_affected.before_by_id` carries the pre-mutation row snapshots
/// captured inside `remove_task_from_all_deps` BEFORE the edge delete
/// (#3019-H2). Each audit row therefore pairs a `before_json` (state
/// at the moment the cascade ran) with an `after_json` (post-cleanup
/// state read here) so peers can diff the two surfaces.
pub(crate) fn sync_dep_affected_tasks(
    conn: &Connection,
    dep_affected: &DepAffectedSnapshot,
    removed_task_title: &str,
    mcp_tool: &'static str,
) -> Result<(), McpError> {
    if dep_affected.ids.is_empty() {
        return Ok(());
    }
    let dep_updated = fetch_tasks_json_batch(conn, &dep_affected.ids, "dep cleanup sync")?;
    for dep_task in &dep_updated {
        let dep_id = match dep_task.get("id").and_then(Value::as_str) {
            Some(did) => did.to_string(),
            None => continue,
        };
        let dep_title = dep_task
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("task");
        let before_json = dep_affected.before_by_id.get(&dep_id).cloned();
        log_change(
            conn,
            LogChangeParams::new(
                "update",
                ENTITY_TASK,
                mcp_tool,
                format!("Removed '{removed_task_title}' from '{dep_title}' dependencies"),
            )
            .with_entity_id(dep_id)
            .with_before_opt(before_json)
            .with_after(dep_task.clone()),
            None,
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn find_tasks_depending_on_excludes_archived_active_status_dependents() {
        let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
        use lorvex_store::test_support::fixtures::TaskBuilder;
        TaskBuilder::new("blocker").title("Blocker").insert(&conn);
        TaskBuilder::new("live-open")
            .title("Live open")
            .status(lorvex_domain::naming::STATUS_OPEN)
            .insert(&conn);
        TaskBuilder::new("live-someday")
            .title("Live someday")
            .status(lorvex_domain::naming::STATUS_SOMEDAY)
            .insert(&conn);
        TaskBuilder::new("archived-open")
            .title("Archived open")
            .status(lorvex_domain::naming::STATUS_OPEN)
            .archived_at(Some("2026-05-01T00:00:00.000000Z"))
            .insert(&conn);
        TaskBuilder::new("archived-someday")
            .title("Archived someday")
            .status(lorvex_domain::naming::STATUS_SOMEDAY)
            .archived_at(Some("2026-05-01T00:00:00.000000Z"))
            .insert(&conn);
        conn.execute(
            "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
             VALUES
             ('live-open', 'blocker', '0000000000000_0000_dep000000000001', '2026-05-01T00:00:00Z'),
             ('live-someday', 'blocker', '0000000000000_0000_dep000000000002', '2026-05-01T00:00:00Z'),
             ('archived-open', 'blocker', '0000000000000_0000_dep000000000003', '2026-05-01T00:00:00Z'),
             ('archived-someday', 'blocker', '0000000000000_0000_dep000000000004', '2026-05-01T00:00:00Z')",
            [],
        )
        .expect("seed dependency edges");

        let dependents =
            find_tasks_depending_on(&conn, &TaskId::from_trusted("blocker".to_string()))
                .expect("find dependents");

        assert_eq!(dependents, vec!["live-open", "live-someday"]);
    }
}
