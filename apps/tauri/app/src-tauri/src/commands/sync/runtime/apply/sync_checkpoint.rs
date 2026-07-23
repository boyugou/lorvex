use super::super::*;
use crate::error::{AppError, AppResult};

pub(crate) fn upsert_sync_checkpoint_timestamp_if_newer(
    conn: &rusqlite::Connection,
    key: &str,
    candidate_ts: &str,
) -> AppResult<()> {
    let existing = lorvex_runtime::sync_checkpoint_get(conn, key).map_err(AppError::from)?;

    let should_update = match existing.as_deref() {
        Some(current_ts) => match (
            parse_rfc3339_utc(current_ts),
            parse_rfc3339_utc(candidate_ts),
        ) {
            (Some(current), Some(candidate)) => candidate >= current,
            (None, Some(_)) => true,
            (Some(_), None) => false,
            (None, None) => candidate_ts >= current_ts,
        },
        None => true,
    };

    if should_update {
        lorvex_runtime::sync_checkpoint_set(conn, key, candidate_ts).map_err(AppError::from)?;
    }

    Ok(())
}
