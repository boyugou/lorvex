use super::enqueue_imports::*;
use super::*;

pub(crate) fn enqueue_task_upsert(conn: &rusqlite::Connection, task: &Task) -> AppResult<()> {
    let raw = serde_json::to_value(task).map_err(AppError::from)?;
    // Derived / child fields are synced independently. Delegate the
    // strip-policy to the shared helper in `lorvex-sync` so a future
    // surface (CLI, MCP) that ships a serialized Task uses the same
    // policy (audit B4): a missed strip silently bloats the sync
    // envelope and the remote per-row budget.
    let payload = lorvex_sync::task_payload::strip_derived_task_fields(raw);
    enqueue_to_outbox_typed(conn, ENTITY_TASK, &task.id, OP_UPSERT, &payload)
}

pub(crate) fn enqueue_task_delete_with_version(
    conn: &rusqlite::Connection,
    task_id: &str,
    before: Option<&Task>,
    version: &str,
) -> AppResult<()> {
    let payload = before
        .map(serde_json::to_value)
        .transpose()
        .map_err(AppError::from)?
        .unwrap_or_else(|| serde_json::json!({ "id": task_id }));
    let Some(device_id) = crate::hlc::try_device_id() else {
        return Err(AppError::Internal(
            "task delete outbox write failed: HLC not initialized".to_string(),
        ));
    };
    enqueue_payload_delete(
        conn,
        ENTITY_TASK,
        task_id,
        &payload,
        OutboxWriteContext { version, device_id },
    )
    .map_err(AppError::from)
}

pub(crate) fn enqueue_list_upsert(conn: &rusqlite::Connection, list: &TaskList) -> AppResult<()> {
    // `TaskList` is the IPC/UI shape and intentionally omits sync-owned
    // columns such as `version`, `archived_at`, and `position`. Always rebuild
    // the envelope payload from the canonical DB snapshot so Tauri app writes
    // carry the same wire shape as MCP/CLI and first-time seed.
    let payload =
        lorvex_sync::outbox_enqueue::read_entity_payload_snapshot(conn, ENTITY_LIST, &list.id)
            .map_err(AppError::from)?;
    enqueue_to_outbox_typed(conn, ENTITY_LIST, &list.id, OP_UPSERT, &payload)
}

pub(crate) fn enqueue_list_delete_with_version(
    conn: &rusqlite::Connection,
    list_id: &str,
    before_payload: &serde_json::Value,
    version: &str,
) -> AppResult<()> {
    let Some(device_id) = crate::hlc::try_device_id() else {
        return Err(AppError::Internal(
            "list delete outbox write failed: HLC not initialized".to_string(),
        ));
    };
    enqueue_payload_delete(
        conn,
        ENTITY_LIST,
        list_id,
        before_payload,
        OutboxWriteContext { version, device_id },
    )
    .map_err(AppError::from)
}

fn load_tag_sync_payload(
    conn: &rusqlite::Connection,
    tag_id: &str,
) -> AppResult<serde_json::Value> {
    // Delegate to the shared `lorvex-store::sync_payload_builders`
    // helper so the seed-side full-table scan and this point-lookup
    // emit byte-identical envelopes. Adding a column to `tags` lands
    // in one place.
    let typed = lorvex_domain::TagId::from_trusted(tag_id.to_string());
    lorvex_store::payload_loaders::load_tag_sync_payload(conn, &typed)
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("tag '{tag_id}' not found for sync snapshot")))
}

pub(crate) fn enqueue_tag_upsert(conn: &rusqlite::Connection, tag_id: &str) -> AppResult<()> {
    let payload = load_tag_sync_payload(conn, tag_id)?;
    enqueue_to_outbox_typed(conn, ENTITY_TAG, tag_id, OP_UPSERT, &payload)
}
