use crate::db::get_conn;
use crate::event_bus;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct ResetPreferencesResult {
    pub deleted: usize,
}

#[tauri::command]
pub fn reset_preferences() -> Result<ResetPreferencesResult, String> {
    let conn = get_conn()?;
    let result = reset_preferences_with_conn(&conn)
        .map_err(|e| format!("Failed to clear preferences: {e}"))?;

    if result.deleted > 0 {
        event_bus::emit_data_changed(event_bus::Entity::Preference);
    }

    Ok(result)
}

/// testable entry point for `reset_preferences` —
/// drives the same writer transaction body against a caller-supplied
/// connection so unit tests can assert the per-key DELETE envelope
/// payload carries the full pre-delete snapshot (`value` + `version`
/// + `updated_at`), not the legacy `{key}`-only shape.
pub(super) fn reset_preferences_with_conn(
    conn: &rusqlite::Connection,
) -> Result<ResetPreferencesResult, crate::error::AppError> {
    use crate::commands::with_immediate_transaction;
    use crate::error::AppError;

    let deleted = with_immediate_transaction(conn, |conn| {
        // Capture each preference's pre-delete snapshot (`key`,
        // `value`, `version`, `updated_at`) BEFORE the bulk DELETE so
        // the per-row tombstone envelope carries a coherent
        // (version, updated_at) tuple for peer LWW. The previous
        // shape shipped `{key}` only — peers running the typed apply
        // path saw a degenerate no-version compare branch on every
        // reset and could quietly resurrect a value the user had
        // just wiped.
        let keys: Vec<String> = conn
            .prepare("SELECT key FROM preferences")?
            .query_map([], |row| row.get(0))?
            .collect::<Result<Vec<_>, _>>()?;
        let mut snapshots: Vec<(String, serde_json::Value)> = Vec::with_capacity(keys.len());
        for key in &keys {
            let snapshot = crate::commands::load_preference_pre_delete_snapshot(conn, key)?;
            snapshots.push((key.clone(), snapshot));
        }

        let deleted = conn.execute("DELETE FROM preferences", [])?;

        // Route every per-preference tombstone through the typed
        // `DeleteEnvelope` pipeline so the payload carries the full
        // pre-delete snapshot (gated by
        // `enqueue_preference_delete::is_local_only_preference`,
        // which short-circuits device-local keys before they hit
        // the wire).
        for (key, snapshot) in snapshots {
            // The tuple's `key` is the authoritative `preferences.key`
            // value just read from the row. Re-deriving it from
            // `snapshot.get("key")` was redundant and — under a future
            // upstream snapshot-builder regression that omitted the
            // field — would have shipped a `entity_id = ""` tombstone
            // into the outbox.
            crate::commands::enqueue_preference_delete(
                conn,
                crate::commands::DeleteEnvelope::new(key, snapshot),
            )?;
        }

        Ok::<usize, AppError>(deleted)
    })?;

    Ok(ResetPreferencesResult { deleted })
}
