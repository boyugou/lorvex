use rusqlite::params;

use super::enqueue_imports::*;
use super::*;

// ---------------------------------------------------------------------------
// Batch / orchestration helpers
//
// These reduce the repeated for-loop + json! + enqueue_to_outbox boilerplate
// that appears wherever lifecycle side effects are synced.
// ---------------------------------------------------------------------------

/// Enqueue sync deletes for removed dependency edges.
///
/// The payload + entity_id encoding flow through the shared
/// `lorvex_sync::outbox_enqueue` builders so this surface, the MCP
/// `enqueue_deleted_task_dependency_syncs`, and the CLI
/// `enqueue_deleted_dependency_edges` all emit a byte-identical
/// envelope shape. Dropping `created_at` or `version` from the
/// payload would prevent peers that missed the upsert envelope from
/// reconstructing the edge row for restore-from-trash flows.
pub(crate) fn enqueue_deleted_dep_edges(
    conn: &rusqlite::Connection,
    edges: &[DeletedDependencyEdge],
) -> AppResult<()> {
    for edge in edges {
        let entity_id = lorvex_sync::outbox_enqueue::encode_dependency_edge_entity_id(edge);
        let payload = lorvex_sync::outbox_enqueue::build_dependency_edge_delete_payload(edge);
        enqueue_to_outbox_typed(conn, EDGE_TASK_DEPENDENCY, &entity_id, OP_DELETE, &payload)?;
    }
    Ok(())
}

/// Enqueue a `task_dependency` edge upsert from a composite
/// `task_id:depends_on_task_id` entity id. The row is loaded fresh from
/// the join table so peer LWW has a coherent `(version, created_at)` pair.
pub(crate) fn enqueue_dependency_edge_upsert(
    conn: &rusqlite::Connection,
    composite: &str,
) -> AppResult<()> {
    let (task_id, depends_on_task_id) = lorvex_domain::TaskDependencyEdgeId::try_parse(composite)
        .map_err(|err| AppError::Internal(err.to_string()))?;
    let (version, created_at): (String, String) = conn
        .query_row(
            "SELECT version, created_at \
             FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id = ?2",
            params![task_id.as_str(), depends_on_task_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|err| match err {
            rusqlite::Error::QueryReturnedNoRows => AppError::NotFound(format!(
                "task_dependency edge '{composite}' not found for sync snapshot"
            )),
            other => AppError::from(other),
        })?;
    let payload = lorvex_store::payload_loaders::task_dependency_payload(
        &task_id,
        &depends_on_task_id,
        &version,
        &created_at,
    );
    enqueue_to_outbox_typed(conn, EDGE_TASK_DEPENDENCY, composite, OP_UPSERT, &payload)
}

/// Enqueue task upserts for tasks whose dependency sets changed.
///
/// Issues one batched `fetch_ordered_tasks_by_ids` per affected
/// dependent set: a single SELECT IN plus constant-time tag / dep /
/// checklist enrichment, regardless of dependent count. A per-row
/// `fetch_task_by_id` loop would cost ~150 round-trips inside the
/// writer transaction for a 50-dependent chain (1 SELECT + 2
/// enrichment queries per task).
pub(crate) fn enqueue_affected_dependents(
    conn: &rusqlite::Connection,
    dependent_ids: &[String],
) -> AppResult<()> {
    if dependent_ids.is_empty() {
        return Ok(());
    }
    let dep_tasks = crate::commands::fetch_ordered_tasks_by_ids(
        conn,
        dependent_ids,
        "enqueue_affected_dependents",
    )?;
    for dep_task in &dep_tasks {
        enqueue_task_upsert(conn, dep_task)?;
    }
    Ok(())
}

/// Enqueue sync for tag edges copied to a spawned recurrence successor.
pub(crate) fn enqueue_copied_tag_edges(
    conn: &rusqlite::Connection,
    tag_edges: &[CopiedTagEdge],
) -> AppResult<()> {
    for te in tag_edges {
        let entity_id = format!("{}:{}", te.task_id, te.tag_id);
        let payload = serde_json::json!({
            "task_id": te.task_id,
            "tag_id": te.tag_id,
            "version": te.version,
            "created_at": te.created_at,
        });
        enqueue_to_outbox_typed(conn, EDGE_TASK_TAG, &entity_id, OP_UPSERT, &payload)?;
    }
    Ok(())
}

/// Enqueue task upserts for cancelled successor tasks.
pub(crate) fn enqueue_cancelled_successors(
    conn: &rusqlite::Connection,
    successor_ids: &[String],
) -> AppResult<()> {
    for sid in successor_ids {
        let task = crate::commands::fetch_task_by_id(conn, sid)?;
        enqueue_task_upsert(conn, &task)?;
    }
    Ok(())
}

fn enqueue_status_sync_plan(
    conn: &rusqlite::Connection,
    plan: StatusSideEffectSyncPlan<'_>,
) -> AppResult<()> {
    for rid in plan.cancelled_reminder_ids {
        enqueue_task_reminder_upsert(conn, rid)?;
    }
    enqueue_deleted_dep_edges(conn, plan.deleted_dependency_edges)?;
    enqueue_affected_dependents(conn, plan.affected_dependent_ids)?;
    Ok(())
}

/// Enqueue all related-entity sync envelopes from a workflow-owned lifecycle plan.
pub(crate) fn enqueue_lifecycle_sync_plan(
    conn: &rusqlite::Connection,
    plan: LifecycleSyncPlan<'_>,
) -> AppResult<()> {
    enqueue_status_sync_plan(conn, plan.status)?;

    for rid in plan.reopened_reminder_ids {
        enqueue_task_reminder_upsert(conn, rid)?;
    }

    if let Some(successor_id) = plan.spawned_successor_id {
        let task = crate::commands::fetch_task_by_id(conn, successor_id)?;
        enqueue_task_upsert(conn, &task)?;
    }
    enqueue_copied_tag_edges(conn, plan.spawned_successor_tag_edges)?;
    for item_id in plan.spawned_successor_checklist_item_ids {
        enqueue_task_checklist_item_upsert(conn, item_id)?;
    }
    for reminder_id in plan.spawned_successor_reminder_ids {
        enqueue_task_reminder_upsert(conn, reminder_id)?;
    }

    enqueue_cancelled_successors(conn, plan.cancelled_successor_ids)?;
    enqueue_status_sync_plan(conn, plan.successor_cancel)?;

    for date in plan.rewired_focus_schedule_dates {
        enqueue_focus_schedule_upsert_for_date(conn, date)?;
    }
    for date in plan.rewired_current_focus_dates {
        enqueue_current_focus_upsert_for_date(conn, date)?;
    }

    Ok(())
}

/// Enqueue all related-entity sync envelopes from a generic lifecycle transition.
#[allow(dead_code)] // retained for the sync enqueue module extraction contract and non-plan transition callers
pub(crate) fn enqueue_lifecycle_transition(
    conn: &rusqlite::Connection,
    transition: &LifecycleTransitionResult,
) -> AppResult<()> {
    enqueue_lifecycle_sync_plan(conn, LifecycleSyncPlan::from_transition(transition))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enqueue_lifecycle_sync_plan_surfaces_missing_reminder_errors() {
        let conn = crate::test_support::test_conn();
        let reminder_ids = [String::from("missing-reminder")];
        let plan = LifecycleSyncPlan {
            status: StatusSideEffectSyncPlan {
                cancelled_reminder_ids: &reminder_ids,
                affected_dependent_ids: &[],
                deleted_dependency_edges: &[],
            },
            ..LifecycleSyncPlan::empty()
        };

        let error = enqueue_lifecycle_sync_plan(&conn, plan)
            .expect_err("missing reminder should fail the enqueue helper");

        assert!(
            error.to_string().contains("missing-reminder"),
            "unexpected error: {error}"
        );
    }
}
