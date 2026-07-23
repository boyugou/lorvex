use super::super::*;

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn reopen_task(id: String) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so a malformed id can't reach the lifecycle writer.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    reopen_task_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn reopen_task_inner(id: String) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = reopen_task_with_conn(&conn, &id)?;
    crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);

    // Post-commit Spotlight dispatch.
    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
            vec![task.id.clone()],
        )],
    );
    Ok(task)
}

/// Testable entry point — runs the reopen transaction against a
/// caller-supplied connection, without the Spotlight/event-bus side
/// effects that require a live Tauri runtime.
pub(crate) fn reopen_task_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let before_task = fetch_task_by_id(conn, id)?;
        if before_task.status == lorvex_domain::naming::STATUS_OPEN {
            return Err(AppError::Validation(format!("Task '{id}' is already open")));
        }
        let now = sync_timestamp_now();
        // #3606: convert once at the lifecycle-effect boundary.
        let task_id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
        let transition = crate::hlc::with_hlc_session(|session| {
            super::effects::run_reopen(conn, &task_id_typed, &before_task.status, &now, session)
        })?;

        enqueue_lifecycle_sync_plan(
            conn,
            lorvex_workflow::lifecycle::LifecycleSyncPlan::from_reopen(&transition),
        )?;

        finalize_task_mutation(conn, id)
    })
}

#[cfg(test)]
mod tests;
