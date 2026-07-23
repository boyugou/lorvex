use super::{
    compare_sync_versions_with_outbox_id, Deserialize, IncomingSyncRecord, Serialize,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
};
use crate::error::{AppError, AppResult};
use lorvex_domain::hlc::Hlc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FilesystemBridgePullCursor {
    pub(crate) updated_at: String,
    pub(crate) device_id: String,
    pub(crate) event_id: String,
}

pub(crate) fn load_filesystem_bridge_pull_cursor(
    conn: &rusqlite::Connection,
) -> AppResult<Option<FilesystemBridgePullCursor>> {
    let current = lorvex_runtime::sync_checkpoint_get(
        conn,
        SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
    )
    .map_err(AppError::from)?;
    if let Some(raw) = current {
        let cursor = serde_json::from_str::<FilesystemBridgePullCursor>(&raw).map_err(|e| {
            AppError::Serialization(format!(
                "Failed to decode filesystem bridge pull cursor: {e}"
            ))
        })?;
        if cursor.updated_at.trim().is_empty()
            || cursor.device_id.trim().is_empty()
            || cursor.event_id.trim().is_empty()
        {
            return Err(AppError::Validation(
                "Filesystem bridge pull cursor fields cannot be empty".to_string(),
            ));
        }
        if Hlc::parse(&cursor.updated_at).is_err() {
            return Err(AppError::Validation(
                "Filesystem bridge pull cursor must use an HLC version".to_string(),
            ));
        }
        return Ok(Some(cursor));
    }

    Ok(None)
}

pub(crate) fn store_filesystem_bridge_pull_cursor(
    conn: &rusqlite::Connection,
    cursor: &FilesystemBridgePullCursor,
) -> AppResult<()> {
    if cursor.updated_at.trim().is_empty()
        || cursor.device_id.trim().is_empty()
        || cursor.event_id.trim().is_empty()
    {
        return Err(AppError::Validation(
            "Filesystem bridge pull cursor fields cannot be empty".to_string(),
        ));
    }
    if Hlc::parse(&cursor.updated_at).is_err() {
        return Err(AppError::Validation(
            "Filesystem bridge pull cursor must use an HLC version".to_string(),
        ));
    }

    if let Some(existing) = load_filesystem_bridge_pull_cursor(conn)? {
        let is_newer_than_existing = compare_sync_versions_with_outbox_id(
            &cursor.updated_at,
            &cursor.event_id,
            &existing.updated_at,
            &existing.event_id,
        )
        .is_gt();
        if !is_newer_than_existing {
            return Ok(());
        }
    }

    let serialized = serde_json::to_string(cursor).map_err(|e| {
        AppError::Serialization(format!("Failed to serialize filesystem bridge cursor: {e}"))
    })?;
    lorvex_runtime::sync_checkpoint_set(
        conn,
        SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
        &serialized,
    )
    .map_err(AppError::from)?;
    Ok(())
}

pub(crate) fn newest_filesystem_bridge_pull_cursor(
    records: &[IncomingSyncRecord],
) -> Option<FilesystemBridgePullCursor> {
    records
        .iter()
        .filter(|r| {
            // `r.envelope.version` is typed `Hlc` at the
            // wire boundary; serde upholds the parse precondition.
            !r.id.trim().is_empty() && !r.envelope.device_id.trim().is_empty()
        })
        .max_by(|left, right| {
            compare_sync_versions_with_outbox_id(
                &left.envelope.version.to_string(),
                &left.id,
                &right.envelope.version.to_string(),
                &right.id,
            )
        })
        .map(|r| FilesystemBridgePullCursor {
            updated_at: r.envelope.version.to_string(),
            device_id: r.envelope.device_id.clone(),
            event_id: r.id.clone(),
        })
}
