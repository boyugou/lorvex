use super::snapshots::CascadedTaskSnapshots;
use super::*;

pub(super) fn enqueue_cascaded_child_deletes<F>(
    conn: &Connection,
    snapshots: &CascadedTaskSnapshots,
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<()>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    for (entity_id, payload) in &snapshots.tag_edges {
        enqueue_delete(
            conn,
            EDGE_TASK_TAG,
            entity_id,
            payload,
            device_id,
            mint_version,
        )?;
    }
    for (entity_id, payload) in &snapshots.checklist_items {
        enqueue_delete(
            conn,
            ENTITY_TASK_CHECKLIST_ITEM,
            entity_id,
            payload,
            device_id,
            mint_version,
        )?;
    }
    for (entity_id, payload) in &snapshots.reminders {
        enqueue_delete(
            conn,
            ENTITY_TASK_REMINDER,
            entity_id,
            payload,
            device_id,
            mint_version,
        )?;
    }
    for (entity_id, payload) in &snapshots.calendar_links {
        enqueue_delete(
            conn,
            EDGE_TASK_CALENDAR_EVENT_LINK,
            entity_id,
            payload,
            device_id,
            mint_version,
        )?;
    }
    Ok(())
}

pub(super) fn enqueue_affected_dependent_upserts<F>(
    conn: &Connection,
    affected_dependent_ids: &[String],
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<()>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    for task_id in affected_dependent_ids {
        if let Some(payload) = optional_entity_snapshot(conn, ENTITY_TASK, task_id)? {
            enqueue_upsert(
                conn,
                ENTITY_TASK,
                task_id,
                &payload,
                device_id,
                mint_version,
            )?;
        }
    }
    Ok(())
}

pub(super) fn optional_entity_snapshot(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> StartupTrashPurgeResult<Option<Value>> {
    match read_entity_payload_snapshot(conn, entity_type, entity_id) {
        Ok(payload) => Ok(Some(payload)),
        Err(crate::outbox_enqueue::EnqueueError::EntityNotFound { .. }) => Ok(None),
        Err(err) => Err(SyncError::Envelope(err.to_string())),
    }
}

pub(super) fn enqueue_delete<F>(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    payload: &Value,
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<()>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let version = mint_version(conn)?;
    enqueue_payload_delete(
        conn,
        entity_type,
        entity_id,
        payload,
        OutboxWriteContext {
            version: &version,
            device_id,
        },
    )
    .map_err(|err| SyncError::Envelope(err.to_string()))
}

pub(super) fn enqueue_upsert<F>(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    payload: &Value,
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<()>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let version = mint_version(conn)?;
    enqueue_payload_upsert(
        conn,
        entity_type,
        entity_id,
        payload,
        OutboxWriteContext {
            version: &version,
            device_id,
        },
    )
    .map_err(|err| SyncError::Envelope(err.to_string()))
}
