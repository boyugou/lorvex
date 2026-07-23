use super::super::super::*;

/// Map the workflow op's `StoreError` variants onto the Tauri
/// surface's typed envelopes so callers see `AppError::Validation` /
/// `AppError::NotFound` / `AppError::Internal` instead of the
/// `AppError::Store(...)` wrapper that `#[from]` produces. Other
/// `StoreError` variants fall through to the canonical
/// `From<StoreError> for AppError` mapping.
fn map_archive_store_error(verb: &'static str, err: lorvex_store::StoreError) -> AppError {
    match err {
        lorvex_store::StoreError::Validation(msg) => AppError::Validation(msg),
        lorvex_store::StoreError::NotFound { id, .. } => {
            AppError::NotFound(format!("task '{id}' not found"))
        }
        lorvex_store::StoreError::StaleVersion { id, .. } => {
            AppError::Internal(format!("Task '{id}' could not be {verb}d"))
        }
        other => AppError::from(other),
    }
}

// ── archive_task ────────────────────────────────────────────────────

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn archive_task(id: String) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so the soft-delete writer never sees a malformed id.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    archive_task_inner(id).map_err(String::from)
}

fn archive_task_inner(id: String) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = archive_task_with_conn(&conn, &id)?;
    event_bus::emit_data_changed(event_bus::Entity::Task);

    // Post-commit: drop from Spotlight so archived tasks don't appear in
    // system-wide search. A later restore will re-index.
    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
            vec![id],
        )],
    );
    Ok(task)
}

pub(crate) fn archive_task_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        let version = crate::hlc::generate_version_result()?;
        let task_id = lorvex_domain::TaskId::from_trusted(id.to_string());
        lorvex_workflow::task_archive::archive_task_op(conn, &task_id, &version, &now)
            .map_err(|err| map_archive_store_error("archive", err))?;

        // drop the task from any live focus
        // / schedule references so the widget and Today view don't
        // keep rendering a Trashed row, AND re-enqueue parent-aggregate
        // upsert envelopes for each affected day so peers see the
        // rewired plan. The shared helper in `lifecycle::removal`
        // collects the affected dates BEFORE the DELETEs wipe them,
        // performs the DELETE, and enqueues `current_focus` /
        // `focus_schedule` upserts for each date. Hoisting this pattern
        // out of the soft-delete path makes the same envelopes flow
        // from every hard-delete site (#2998-H3 hole in
        // `purge_expired_archived_tasks` and `cleanup_plan_refs_after_removal`).
        super::super::removal::cleanup_plan_refs_after_removal(conn, id)?;

        finalize_task_mutation(conn, id)
    })
}

// ── restore_task_from_trash ─────────────────────────────────────────

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn restore_task_from_trash(id: String) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    restore_task_from_trash_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn restore_task_from_trash_inner(id: String) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = restore_task_from_trash_with_conn(&conn, &id)?;
    event_bus::emit_data_changed(event_bus::Entity::Task);

    // Post-commit: re-index in Spotlight.
    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
            vec![task.id.clone()],
        )],
    );
    Ok(task)
}

pub(crate) fn restore_task_from_trash_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        let version = crate::hlc::generate_version_result()?;
        let task_id = lorvex_domain::TaskId::from_trusted(id.to_string());
        lorvex_workflow::task_archive::restore_task_op(conn, &task_id, &version, &now)
            .map_err(|err| map_archive_store_error("restore", err))?;

        finalize_task_mutation(conn, id)
    })
}
