use super::enqueue::{
    enqueue_affected_dependent_upserts, enqueue_cascaded_child_deletes, enqueue_delete,
    optional_entity_snapshot,
};
use super::references::cleanup_plan_refs_after_removal;
use super::snapshots::collect_cascaded_task_snapshots;
use super::*;
use lorvex_domain::ids::TaskId;

pub(super) fn purge_one_archived_task<F>(
    conn: &Connection,
    task_id: &TaskId,
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<bool>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let Some(task_snapshot) = optional_entity_snapshot(conn, ENTITY_TASK, task_id.as_str())? else {
        return Ok(false);
    };
    let archived_at = task_snapshot.get("archived_at").and_then(Value::as_str);
    if archived_at.is_none() {
        return Err(SyncError::Envelope(format!(
            "startup trash purge selected live task {task_id}; refusing hard-delete"
        )));
    }

    let child_snapshots = collect_cascaded_task_snapshots(conn, task_id)?;
    enqueue_cascaded_child_deletes(conn, &child_snapshots, device_id, mint_version)?;

    let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let (affected_dependent_ids, deleted_dep_edges) =
        lorvex_workflow::lifecycle::detach_task_dependency_edges(conn, &task_id_typed)?;
    for edge in &deleted_dep_edges {
        let entity_id = encode_dependency_edge_entity_id(edge);
        let payload = build_dependency_edge_delete_payload(edge);
        enqueue_delete(
            conn,
            EDGE_TASK_DEPENDENCY,
            &entity_id,
            &payload,
            device_id,
            mint_version,
        )?;
    }
    enqueue_affected_dependent_upserts(conn, &affected_dependent_ids, device_id, mint_version)?;

    cleanup_plan_refs_after_removal(conn, task_id, device_id, mint_version)?;
    let affected = conn.execute("DELETE FROM tasks WHERE id = ?1", params![task_id])?;
    if affected == 0 {
        return Ok(false);
    }
    enqueue_delete(
        conn,
        ENTITY_TASK,
        task_id.as_str(),
        &task_snapshot,
        device_id,
        mint_version,
    )?;
    Ok(true)
}
