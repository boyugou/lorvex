use super::{read::get_focus_schedule_with_conn, *};

#[tauri::command]
pub fn dismiss_focus_schedule() -> Result<Option<FocusScheduleWithTasks>, String> {
    let conn = get_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;

    let post_delete_state =
        dismiss_focus_schedule_with_conn(&conn, &today).map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Planning);
    Ok(post_delete_state)
}

/// dismiss now (a) ships a `DeleteEnvelope` whose
/// payload is the canonical aggregate snapshot (header columns +
/// embedded blocks + the `version` already on the parent row) so peer
/// LWW has a coherent compare basis, and (b) returns the post-delete
/// state (`None` on a cleared row, mirroring the rich-return contract
/// every other write IPC honors). The previous shape shipped
/// `{ "date": today }` — no version, no blocks — and returned a stub
/// `()` that gave the renderer no reload signal.
pub(super) fn dismiss_focus_schedule_with_conn(
    conn: &rusqlite::Connection,
    today: &str,
) -> AppResult<Option<FocusScheduleWithTasks>> {
    with_immediate_transaction(conn, |conn| {
        // Load the canonical aggregate payload BEFORE the DELETE so
        // the envelope ships the same shape an upsert would have
        // shipped — header + blocks + version. The aggregate builder
        // returns `None` only when the parent row doesn't exist; in
        // that case we still issue the DELETE (idempotent no-op) and
        // ship a minimal `{date}` payload so peers see the dismiss
        // intent.
        let snapshot_payload = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
            conn,
            ENTITY_FOCUS_SCHEDULE,
            today,
        )
        .map_err(AppError::from)?;

        // CASCADE delete handles focus_schedule_blocks cleanup
        conn.execute("DELETE FROM focus_schedule WHERE date = ?1", params![today])
            .map_err(AppError::from)?;

        // Enqueue sync delete event using the pre-delete aggregate
        // snapshot for peer LWW. Falls back to `{date}` when the row
        // was already absent (idempotent dismiss) — the minimal wire
        // shape carries enough for peers to LWW-resolve against any
        // surviving row.
        let delete_payload =
            snapshot_payload.unwrap_or_else(|| serde_json::json!({ "date": today }));
        enqueue_to_outbox_typed(
            conn,
            ENTITY_FOCUS_SCHEDULE,
            today,
            OP_DELETE,
            &delete_payload,
        )?;

        // Post-delete: read the canonical aggregate (None after the
        // DELETE) so the renderer can refresh without re-issuing the
        // read query.
        get_focus_schedule_with_conn(conn, today)
    })
}
