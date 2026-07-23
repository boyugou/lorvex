use super::super::super::*;
use super::TRASH_RETENTION_DAYS;

// ── empty_trash ─────────────────────────────────────────────────────

/// Result payload for `empty_trash`. Counts are returned so the UI can
/// say "deleted 12 items" instead of just a generic "done".
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct EmptyTrashResult {
    pub deleted: usize,
    /// IDs that were hard-deleted (included for the frontend so it can
    /// invalidate per-entity caches if it ever starts tracking them).
    pub deleted_ids: Vec<String>,
    /// Entries still in the Trash that were younger than the retention
    /// window. The UI shows "N older than 30 days were removed; M remain"
    /// in the toast.
    pub remaining: i64,
}

/// Manual "Empty trash" action. Hard-deletes every archived task older
/// than the retention window (30 days). Entries inside the window are
/// left alone — the user can click "Delete forever" on individual rows
/// to purge them sooner.
#[tauri::command]
pub fn empty_trash() -> Result<EmptyTrashResult, String> {
    empty_trash_inner(TRASH_RETENTION_DAYS).map_err(String::from)
}

fn empty_trash_inner(retention_days: i64) -> Result<EmptyTrashResult, AppError> {
    let conn = get_conn()?;
    let result = empty_trash_with_conn(&conn, retention_days)?;
    if !result.deleted_ids.is_empty() {
        event_bus::emit_data_changed(event_bus::Entity::Task);
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
                result.deleted_ids.clone(),
            )],
        );
    }
    Ok(result)
}

pub(crate) fn empty_trash_with_conn(
    conn: &rusqlite::Connection,
    retention_days: i64,
) -> Result<EmptyTrashResult, AppError> {
    let report = lorvex_sync::startup_trash_purge::purge_expired_archived_tasks(
        conn,
        retention_days,
        |_| {
            crate::hlc::generate_version_result().map_err(|err| {
                lorvex_sync::error::SyncError::Envelope(format!(
                    "app HLC generation failed during trash purge: {err}"
                ))
            })
        },
    )?;
    Ok(EmptyTrashResult {
        deleted: report.deleted,
        deleted_ids: report.deleted_ids,
        remaining: report.remaining,
    })
}
