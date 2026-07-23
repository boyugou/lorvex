use super::enqueue_imports::*;
use super::*;

fn load_task_reminder_sync_payload(
    conn: &rusqlite::Connection,
    reminder_id: &str,
) -> AppResult<serde_json::Value> {
    // Delegate to `lorvex-store::sync_payload_builders` so seed and
    // runtime emit byte-identical envelopes.
    let typed = lorvex_domain::ReminderId::from_trusted(reminder_id.to_string());
    lorvex_store::payload_loaders::load_task_reminder_sync_payload(conn, &typed)
        .map_err(AppError::from)?
        .ok_or_else(|| {
            AppError::NotFound(format!(
                "task reminder '{reminder_id}' not found for sync snapshot"
            ))
        })
}

fn load_task_checklist_item_sync_payload(
    conn: &rusqlite::Connection,
    item_id: &str,
) -> AppResult<serde_json::Value> {
    let typed = lorvex_domain::ChecklistItemId::from_trusted(item_id.to_string());
    lorvex_store::payload_loaders::load_task_checklist_item_sync_payload(conn, &typed)
        .map_err(AppError::from)?
        .ok_or_else(|| {
            AppError::NotFound(format!(
                "task checklist item '{item_id}' not found for sync snapshot"
            ))
        })
}

pub(crate) fn enqueue_task_reminder_upsert(
    conn: &rusqlite::Connection,
    reminder_id: &str,
) -> AppResult<()> {
    let payload = load_task_reminder_sync_payload(conn, reminder_id)?;
    enqueue_to_outbox_typed(conn, ENTITY_TASK_REMINDER, reminder_id, OP_UPSERT, &payload)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// enqueue a `task_reminder` tombstone with the
/// pre-delete snapshot baked into the envelope at the type level.
/// The caller passes a [`DeleteEnvelope`] populated from a snapshot
/// loaded *before* the row was DELETEd; there is no constructor that
/// builds an `{id}`-only envelope, so a peer that GC'd its own copy
/// can always reconstruct the deleted state.
pub(crate) fn enqueue_task_reminder_delete<T: serde::Serialize>(
    conn: &rusqlite::Connection,
    envelope: DeleteEnvelope<T>,
) -> AppResult<()> {
    let payload = envelope.to_payload()?;
    enqueue_to_outbox_typed(
        conn,
        ENTITY_TASK_REMINDER,
        &envelope.id,
        OP_DELETE,
        &payload,
    )
}

/// Load the pre-delete snapshot for a `task_reminders` row. Public to
/// the crate so call sites that DELETE the row first can grab the
/// snapshot before issuing the delete and feed it into a typed
/// `DeleteEnvelope`. Returns `NotFound` if the row is already gone.
pub(crate) fn load_task_reminder_pre_delete_snapshot(
    conn: &rusqlite::Connection,
    reminder_id: &str,
) -> AppResult<serde_json::Value> {
    load_task_reminder_sync_payload(conn, reminder_id)
}

pub(crate) fn enqueue_task_checklist_item_upsert(
    conn: &rusqlite::Connection,
    item_id: &str,
) -> AppResult<()> {
    let payload = load_task_checklist_item_sync_payload(conn, item_id)?;
    enqueue_to_outbox_typed(
        conn,
        ENTITY_TASK_CHECKLIST_ITEM,
        item_id,
        OP_UPSERT,
        &payload,
    )
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// typed `DeleteEnvelope`-driven enqueue for task
/// checklist items. The caller loads the pre-delete snapshot via
/// [`load_task_checklist_item_pre_delete_snapshot`] before issuing
/// the DELETE; the envelope ships the full row so peers can
/// reconstruct the deleted item's `before_json` audit row.
pub(crate) fn enqueue_task_checklist_item_delete<T: serde::Serialize>(
    conn: &rusqlite::Connection,
    envelope: DeleteEnvelope<T>,
) -> AppResult<()> {
    let payload = envelope.to_payload()?;
    enqueue_to_outbox_typed(
        conn,
        ENTITY_TASK_CHECKLIST_ITEM,
        &envelope.id,
        OP_DELETE,
        &payload,
    )
}

pub(crate) fn load_task_checklist_item_pre_delete_snapshot(
    conn: &rusqlite::Connection,
    item_id: &str,
) -> AppResult<serde_json::Value> {
    load_task_checklist_item_sync_payload(conn, item_id)
}

/// Batch-load pre-delete snapshots for many `task_reminders` rows in
/// one indexed scan. Closes the per-id `SELECT … WHERE id = ?` N+1
/// pattern in cascade-delete paths. Returns a `HashMap<id, payload>`;
/// ids absent from the table are absent from the map. Delegates to
/// `lorvex_store::payload_loaders` where the SELECT projection
/// and row mapper live, so this Tauri-side wrapper stays in lock-step
/// with the per-id loader and the batch path is unit-tested in
/// `sync_payload_builders/tests.rs`.
pub(crate) fn load_task_reminder_pre_delete_snapshots(
    conn: &rusqlite::Connection,
    reminder_ids: &[String],
) -> AppResult<std::collections::HashMap<String, serde_json::Value>> {
    lorvex_store::payload_loaders::load_task_reminder_pre_delete_snapshots(conn, reminder_ids)
        .map_err(AppError::from)
}

/// Batch sibling of [`load_task_checklist_item_pre_delete_snapshot`].
/// See [`load_task_reminder_pre_delete_snapshots`] for the rationale.
pub(crate) fn load_task_checklist_item_pre_delete_snapshots(
    conn: &rusqlite::Connection,
    item_ids: &[String],
) -> AppResult<std::collections::HashMap<String, serde_json::Value>> {
    lorvex_store::payload_loaders::load_task_checklist_item_pre_delete_snapshots(conn, item_ids)
        .map_err(AppError::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_task_reminder_sync_payload_returns_full_snapshot_shape() {
        let conn = crate::test_support::test_conn();
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
            .title("Task 1")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-28T08:00:00Z")
            .insert(&conn);
        conn.execute(
            "INSERT INTO task_reminders
               (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at,
                original_local_time, original_tz)
             VALUES
               ('rem-1', 'task-1', '2026-03-29T09:00:00Z', NULL, '2026-03-28T10:00:00Z',
                '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-28T08:05:00Z', '09:00', 'Asia/Tokyo')",
            [],
        )
        .expect("insert task reminder");

        let payload =
            load_task_reminder_sync_payload(&conn, "rem-1").expect("load reminder sync payload");

        assert_eq!(payload["id"], "rem-1");
        assert_eq!(payload["task_id"], "task-1");
        assert_eq!(payload["reminder_at"], "2026-03-29T09:00:00Z");
        assert_eq!(payload["cancelled_at"], "2026-03-28T10:00:00Z");
        assert_eq!(payload["created_at"], "2026-03-28T08:05:00Z");
        assert_eq!(payload["original_local_time"], "09:00");
        assert_eq!(payload["original_tz"], "Asia/Tokyo");
        assert!(
            payload.get("updated_at").is_none(),
            "task reminder sync payload should not invent an updated_at field"
        );
    }
}
