use super::{
    blocks::{normalize_schedule_block_entries, validate_schedule_block_ids},
    read::get_focus_schedule_with_conn,
    sync::enqueue_focus_schedule_sync,
    *,
};

#[tauri::command]
pub fn update_focus_schedule_blocks(
    mut blocks: Vec<ScheduleBlock>,
) -> Result<FocusScheduleWithTasks, String> {
    // cap the input batch at the IPC boundary so a
    // runaway frontend bug or hostile caller can't drive the writer
    // transaction with an unbounded `Vec` before per-row validators
    // ever see it. The legitimate UI shape is a single focus day's
    // blocks (dozens at most); 1 000 covers any realistic batch
    // while still bounding the worst case.
    //
    // Note re #3025 M5: an empty `blocks` Vec is intentionally NOT
    // rejected here — `materialize_schedule_blocks` treats "no
    // blocks" as the canonical clear-day operation that bumps the
    // header and ships a sync envelope. Rejecting empty would break
    // the legitimate "user removed every block" flow.
    if blocks.len() > crate::commands::shared::MAX_IPC_BATCH_ITEMS {
        return Err(format!(
            "blocks count {} exceeds maximum {}",
            blocks.len(),
            crate::commands::shared::MAX_IPC_BATCH_ITEMS
        ));
    }
    validate_schedule_block_ids(&mut blocks)?;
    let conn = get_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let now = sync_timestamp_now();

    let schedule = update_focus_schedule_blocks_with_conn(&conn, &today, blocks, &now)
        .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Planning);
    Ok(schedule)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(super) fn update_focus_schedule_blocks_with_conn(
    conn: &rusqlite::Connection,
    today: &str,
    blocks: Vec<ScheduleBlock>,
    now: &str,
) -> AppResult<FocusScheduleWithTasks> {
    with_immediate_transaction(conn, |conn| {
        let exists =
            <rusqlite::Result<_> as crate::commands::OptionalExt<_>>::optional(conn.query_row(
                "SELECT 1 FROM focus_schedule WHERE date = ?1",
                params![today],
                |_| Ok(true),
            ))
            .map_err(AppError::from)?
            .unwrap_or(false);

        if !exists {
            return Err(AppError::NotFound(
                "Focus schedule not found for today".to_string(),
            ));
        }

        let entries = normalize_schedule_block_entries(&blocks)?;
        let mut seen = std::collections::HashSet::new();
        let task_ids: Vec<String> = entries
            .iter()
            .filter(|entry| entry.block_type == "task")
            .filter_map(|entry| entry.task_id.clone())
            .filter(|id| seen.insert(id.clone()))
            .collect();
        lorvex_store::validate_task_ids_live(conn, &task_ids, "focus schedule blocks[].task_id")
            .map_err(AppError::from)?;

        lorvex_store::focus_schedule_blocks::touch_focus_schedule_header(conn, today, now)
            .map_err(AppError::from)?;

        lorvex_store::focus_schedule_blocks::materialize_schedule_blocks(conn, today, &entries)
            .map_err(AppError::from)?;
        // only the focus_schedule aggregate is enqueued
        // below — `current_focus_items` rebuilt from this writer used
        // to silently leave the parent `current_focus` row stale. Peer
        // envelopes that re-arrived later were rejected by the local
        // LWW gate (`?1 > version`) because the parent's `version`
        // column had not advanced. Bake the parent header bump into
        // the same call so the row's `(version, updated_at)` stay in
        // lockstep with the rebuilt children. When no current_focus
        // row exists yet, the UPDATE inside the helper is a no-op
        // (an empty task_ids list is a no-op delete; a non-empty list
        // would FK-fail because current_focus_items requires a parent
        // row).
        let version = crate::hlc::generate_version_result()?;
        lorvex_store::current_focus_items::materialize_focus_items_with_header_bump(
            conn, today, &task_ids, &version, now,
        )
        .map_err(AppError::from)?;

        enqueue_focus_schedule_sync(conn, today)?;
        enqueue_current_focus_upsert_for_date(conn, today)?;

        get_focus_schedule_with_conn(conn, today)?.ok_or_else(|| {
            AppError::Internal("Focus schedule disappeared after update".to_string())
        })
    })
}
