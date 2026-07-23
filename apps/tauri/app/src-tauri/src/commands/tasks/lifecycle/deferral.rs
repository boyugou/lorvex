use lorvex_domain::naming::{STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_workflow::task_deferral;
use rusqlite::Connection;

use super::super::*;
use crate::error::AppResult;

fn stale_task_version_error(task_id: &str) -> AppError {
    AppError::Store(Box::new(lorvex_store::StoreError::StaleVersion {
        entity: "task",
        id: task_id.to_string(),
    }))
}

fn enqueue_shifted_task_reminders(conn: &Connection, reminder_ids: &[String]) -> AppResult<()> {
    for reminder_id in reminder_ids {
        crate::commands::enqueue_task_reminder_upsert(conn, reminder_id)?;
    }
    Ok(())
}

/// Core deferral logic shared between `#[tauri::command]` wrappers and the
/// notification action handler.
///
/// Validates the task status, applies the deferral patch, logs the change,
/// enqueues for sync, and emits the data-changed event.
///
/// Must be called inside an IMMEDIATE transaction.
pub(crate) fn defer_task_internal(
    conn: &Connection,
    id: &str,
    planned_date: &str,
    structured_reason: Option<&str>,
) -> Result<Task, AppError> {
    let before_task = fetch_task_by_id(conn, id)?;

    if before_task.status == STATUS_COMPLETED || before_task.status == STATUS_CANCELLED {
        return Err(AppError::Validation(format!(
            "Cannot defer a task with status '{}'",
            before_task.status
        )));
    }

    // Validate structured defer reason if provided.
    if let Some(r) = structured_reason {
        if !lorvex_domain::naming::is_valid_defer_reason(r) {
            return Err(AppError::Validation(format!(
                "Invalid defer reason '{}'. Valid values: {}",
                r,
                lorvex_domain::naming::ALL_DEFER_REASONS.join(", ")
            )));
        }
    }

    let now = sync_timestamp_now();
    let version = crate::hlc::generate_version_result()?;
    let patch = task_deferral::TaskDeferralPatch {
        planned_date: Some(planned_date),
        ai_notes: None,
        last_defer_reason: structured_reason,
    };
    let id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
    let result = task_deferral::defer_task(conn, &id_typed, &patch, &version, &now, || {
        crate::hlc::generate_version_result()
    })?;
    if !result.updated {
        return Err(stale_task_version_error(id));
    }

    enqueue_shifted_task_reminders(conn, &result.shifted_reminder_ids)?;

    finalize_task_mutation(conn, id)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn defer_task(id: String, structured_reason: Option<String>) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so a malformed id can't reach the deferral writer.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    defer_task_inner(id, structured_reason).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn defer_task_inner(id: String, structured_reason: Option<String>) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = defer_task_with_conn(&conn, &id, structured_reason.as_deref())?;

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

/// Transactional body of `defer_task` against a caller-supplied
/// connection.
pub(crate) fn defer_task_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    structured_reason: Option<&str>,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let tomorrow = lorvex_workflow::timezone::date_plus_days_ymd_for_conn(conn, 1)?;
        defer_task_internal(conn, id, &tomorrow, structured_reason)
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn defer_task_until(
    id: String,
    until_date: String,
    structured_reason: Option<String>,
) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so a malformed value never reaches the writer body.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    // lift the date-shape check ABOVE `get_conn()` so a
    // malformed `until_date` doesn't first acquire a writer-pool slot
    // (and a SQLite immediate transaction) only to be rejected by
    // `normalize_date_input_for_conn`. The shape-only validator
    // doesn't need a connection — only the timezone-aware
    // normalization downstream does. Fail-fast keeps the writer pool
    // free when the input is obviously bad.
    lorvex_domain::validation::validate_date_format(&until_date)
        .map_err(|err| AppError::Validation(err.to_string()))
        .map_err(String::from)?;
    defer_task_until_inner(id, until_date, structured_reason).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn defer_task_until_inner(
    id: String,
    until_date: String,
    structured_reason: Option<String>,
) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = defer_task_until_with_conn(&conn, &id, &until_date, structured_reason.as_deref())?;

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

/// Transactional body of `defer_task_until` against a caller-supplied
/// connection.
pub(crate) fn defer_task_until_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    until_date: &str,
    structured_reason: Option<&str>,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let normalized_until_date = normalize_date_input_for_conn(conn, until_date)?;

        if lorvex_domain::validation::validate_date_format(&normalized_until_date).is_err() {
            return Err(AppError::Validation(
                "until_date must be a valid YYYY-MM-DD date".to_string(),
            ));
        }

        defer_task_internal(conn, id, &normalized_until_date, structured_reason)
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn reset_task_deferral(id: String) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    reset_task_deferral_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn reset_task_deferral_inner(id: String) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = reset_task_deferral_with_conn(&conn, &id)?;

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

/// Transactional body of `reset_task_deferral` against a caller-supplied
/// connection.
pub(crate) fn reset_task_deferral_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let before_task = fetch_task_by_id(conn, id)?;
        if before_task.status == STATUS_COMPLETED || before_task.status == STATUS_CANCELLED {
            return Err(AppError::Validation(format!(
                "Cannot reset deferral on a task with status '{}'",
                before_task.status
            )));
        }

        let now = sync_timestamp_now();
        let version = crate::hlc::generate_version_result()?;
        let id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
        if !task_deferral::reset_task_deferral(conn, &id_typed, &version, &now)? {
            return Err(stale_task_version_error(id));
        }

        finalize_task_mutation(conn, id)
    })
}

/// Snapshot of a task's deferral fields captured by the frontend
/// before a `defer_task` mutation so the "Undo" toast can restore
/// the exact pre-defer state. Distinct from `reset_task_deferral`,
/// which zeros the whole history — zeroing is wrong for undo
/// because a task with N prior defers must remain at count N after
/// undoing the (N+1)-th defer (A2).
#[derive(Debug, serde::Deserialize)]
pub struct DeferralSnapshot {
    pub planned_date: Option<String>,
    pub defer_count: i64,
    pub last_deferred_at: Option<String>,
    pub last_defer_reason: Option<String>,
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn restore_task_deferral(id: String, snapshot: DeferralSnapshot) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    restore_task_deferral_inner(id, snapshot).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn restore_task_deferral_inner(id: String, snapshot: DeferralSnapshot) -> Result<Task, AppError> {
    let conn = get_conn()?;
    let task = restore_task_deferral_with_conn(&conn, &id, &snapshot)?;

    crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);

    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
            vec![task.id.clone()],
        )],
    );
    Ok(task)
}

/// Transactional body of `restore_task_deferral` against a
/// caller-supplied connection.
pub(crate) fn restore_task_deferral_with_conn(
    conn: &rusqlite::Connection,
    id: &str,
    snapshot: &DeferralSnapshot,
) -> Result<Task, AppError> {
    with_immediate_transaction(conn, |conn| {
        let before_task = fetch_task_by_id(conn, id)?;
        if before_task.status == STATUS_COMPLETED || before_task.status == STATUS_CANCELLED {
            return Err(AppError::Validation(format!(
                "Cannot restore deferral on a task with status '{}'",
                before_task.status
            )));
        }

        let now = sync_timestamp_now();
        let version = crate::hlc::generate_version_result()?;
        let store_snapshot = task_deferral::TaskDeferralSnapshot {
            planned_date: snapshot.planned_date.as_deref(),
            defer_count: snapshot.defer_count,
            last_deferred_at: snapshot.last_deferred_at.as_deref(),
            last_defer_reason: snapshot.last_defer_reason.as_deref(),
        };
        let id_typed = lorvex_domain::TaskId::from_trusted(id.to_string());
        if !task_deferral::restore_task_deferral(conn, &id_typed, &store_snapshot, &version, &now)?
        {
            return Err(stale_task_version_error(id));
        }

        finalize_task_mutation(conn, id)
    })
}

#[cfg(test)]
mod tests;
