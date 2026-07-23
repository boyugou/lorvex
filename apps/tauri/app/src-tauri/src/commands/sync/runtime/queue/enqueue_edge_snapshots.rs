use super::enqueue_imports::*;
use super::*;

pub(crate) fn enqueue_preference_upsert(
    conn: &rusqlite::Connection,
    key: &str,
    value: &str,
    updated_at: &str,
) -> AppResult<()> {
    // device-local preferences (filesystem paths, per-device
    // sync backend choice) must never cross the sync boundary.
    if lorvex_domain::preference_keys::is_local_only_preference(key) {
        return Ok(());
    }
    // Build the canonical preference upsert payload through the shared
    // builder. The builder's `serde_json::from_str` validates that the
    // stored row is canonical JSON and surfaces the key in the error;
    // identical to the prior `parse_canonical_json_value` shape.
    let payload = lorvex_store::payload_loaders::preference_upsert_payload(key, value, updated_at)
        .map_err(AppError::from)?;
    enqueue_to_outbox_typed(conn, ENTITY_PREFERENCE, key, OP_UPSERT, &payload)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// typed delete for `preferences`. The caller loads the
/// pre-delete snapshot (key + last value + last updated_at) before
/// issuing the DELETE so peers can reconstruct the value the user
/// just discarded — useful for the changelog's `before_json` audit
/// row even though preferences are device-local until sync routes
/// them.
pub(crate) fn enqueue_preference_delete<T: serde::Serialize>(
    conn: &rusqlite::Connection,
    envelope: DeleteEnvelope<T>,
) -> AppResult<()> {
    if lorvex_domain::preference_keys::is_local_only_preference(&envelope.id) {
        return Ok(());
    }
    let payload = envelope.to_payload()?;
    enqueue_to_outbox_typed(conn, ENTITY_PREFERENCE, &envelope.id, OP_DELETE, &payload)
}

/// Pre-delete snapshot loader for the `preferences` table. Returns
/// `NotFound` if the key has no row to snapshot.
///
/// snapshot now also carries `version` so the
/// envelope's LWW guard on the peer apply path has a coherent
/// `(version, updated_at)` tuple — `reset_preferences` previously
/// shipped `{key}` only, which forced peers into the degenerate
/// no-version compare branch when the user wiped local prefs.
pub(crate) fn load_preference_pre_delete_snapshot(
    conn: &rusqlite::Connection,
    key: &str,
) -> AppResult<serde_json::Value> {
    lorvex_store::payload_loaders::load_preference_delete_snapshot(conn, key)
        .map_err(AppError::from)?
        .ok_or_else(|| {
            AppError::NotFound(format!("preference '{key}' not found for sync snapshot"))
        })
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// typed `DeleteEnvelope`-driven enqueue for
/// task_tags. The caller loads the pre-delete snapshot via
/// [`load_task_tag_pre_delete_snapshots`] before issuing the DELETE so
/// the envelope ships `(task_id, tag_id, version, created_at)` for
/// peer LWW. The previous shape carried only
/// `{task_id, tag_id, updated_at}` (no `version`, no `created_at`),
/// which forced peers into the degenerate no-version compare branch
/// on the edge tombstone path.
pub(crate) fn enqueue_task_tag_delete<T: serde::Serialize>(
    conn: &rusqlite::Connection,
    envelope: DeleteEnvelope<T>,
) -> AppResult<()> {
    let payload = envelope.to_payload()?;
    enqueue_to_outbox_typed(conn, EDGE_TASK_TAG, &envelope.id, OP_DELETE, &payload)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// typed `DeleteEnvelope`-driven enqueue for
/// task_calendar_event_links. The caller loads the pre-delete
/// snapshot via [`load_task_calendar_event_link_pre_delete_snapshot`]
/// before issuing the DELETE so the envelope ships
/// `(task_id, calendar_event_id, version, created_at, updated_at)`
/// for peer LWW. The previous shape on multiple cascade paths
/// dropped `version` + `created_at`, breaking peer convergence.
pub(crate) fn enqueue_task_calendar_event_link_delete<T: serde::Serialize>(
    conn: &rusqlite::Connection,
    envelope: DeleteEnvelope<T>,
) -> AppResult<()> {
    let payload = envelope.to_payload()?;
    enqueue_to_outbox_typed(
        conn,
        lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
        &envelope.id,
        OP_DELETE,
        &payload,
    )
}

/// Batch sibling of [`load_task_tag_pre_delete_snapshots`]. The cascade-
/// delete path that builds N tag tombstones for one task previously
/// issued N point-SELECTs; this helper does the same job in one
/// indexed scan keyed by `tag_id` within the fixed `task_id` scope.
/// Returns a `HashMap<tag_id, payload>`; tag_ids absent from the
/// table are absent from the map. Delegates to
/// `lorvex_store::payload_loaders` so the column list,
/// row mapper, and binding shape stay in lock-step with the per-id
/// loaders.
pub(crate) fn load_task_tag_pre_delete_snapshots(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    tag_ids: &[String],
) -> AppResult<std::collections::HashMap<String, serde_json::Value>> {
    lorvex_store::payload_loaders::load_task_tag_pre_delete_snapshots(conn, task_id, tag_ids)
        .map_err(AppError::from)
}

/// Pre-delete snapshot loader for a single `task_tags` edge.
/// Delegates to the batch loader so the point-delete path and
/// cascade-delete path keep the same column list and payload shape.
#[allow(dead_code)] // retained for the sync enqueue module extraction contract and future point-delete callers
pub(crate) fn load_task_tag_pre_delete_snapshot(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    tag_id: &str,
) -> AppResult<serde_json::Value> {
    let tag_ids = [tag_id.to_string()];
    let mut snapshots = load_task_tag_pre_delete_snapshots(conn, task_id, &tag_ids)?;
    snapshots.remove(tag_id).ok_or_else(|| {
        AppError::NotFound(format!(
            "task_tag edge '{task_id}:{tag_id}' not found for sync snapshot"
        ))
    })
}

/// Batch sibling of
/// [`load_task_calendar_event_link_pre_delete_snapshot`]. See
/// [`load_task_tag_pre_delete_snapshots`] for rationale; the key is
/// `calendar_event_id` within the fixed `task_id` scope.
pub(crate) fn load_task_calendar_event_link_pre_delete_snapshots(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    calendar_event_ids: &[String],
) -> AppResult<std::collections::HashMap<String, serde_json::Value>> {
    lorvex_store::payload_loaders::load_task_calendar_event_link_pre_delete_snapshots(
        conn,
        task_id,
        calendar_event_ids,
    )
    .map_err(AppError::from)
}

/// Pre-delete snapshot loader for `task_calendar_event_links`.
/// Returns `NotFound` if the edge has already been removed. The
/// snapshot carries `version` + `created_at` + `updated_at` for the
/// same LWW reasons as [`load_task_tag_pre_delete_snapshots`].
pub(crate) fn load_task_calendar_event_link_pre_delete_snapshot(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    calendar_event_id: &lorvex_domain::EventId,
) -> AppResult<serde_json::Value> {
    lorvex_store::payload_loaders::load_task_calendar_event_link_sync_payload(
        conn,
        task_id,
        calendar_event_id,
    )
    .map_err(AppError::from)?
    .ok_or_else(|| {
        AppError::NotFound(format!(
            "task_calendar_event_link edge '{task_id}:{calendar_event_id}' not found for sync snapshot"
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enqueue_preference_upsert_rejects_malformed_json_value() {
        let conn = crate::test_support::test_conn();

        let error =
            enqueue_preference_upsert(&conn, "theme", "{not-valid-json", "2026-03-29T10:00:00Z")
                .expect_err("malformed preference json should fail");

        // accept either AppError::Serialization (legacy direct path)
        // or AppError::Store(StoreError::Serialization(...)) (current
        // path through the store-layer canonical-JSON validator). Both
        // shapes ultimately surface as `kind: serialization` on the
        // IPC envelope, but the test was written before the store-layer
        // wrap and was failing with the typed-store variant.
        let message = match error {
            AppError::Serialization(message) => message,
            AppError::Store(boxed) => match *boxed {
                lorvex_store::StoreError::Serialization(message) => message,
                other => panic!("expected serialization error, got {other:?}"),
            },
            other => panic!("expected serialization error, got {other:?}"),
        };
        assert!(message.contains("theme"), "unexpected error: {message}");
    }
}
