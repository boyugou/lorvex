pub(super) use super::super::*;
pub(super) use crate::commands::diagnostics::{
    append_error_log_internal, read_diagnostics_device_ids, read_retention_days,
    read_sync_conflict_log, read_unseen_error_log_count, run_data_retention_cleanup_with_conn,
};
pub(super) use chrono::{Duration, SecondsFormat, Utc};
pub(super) use lorvex_domain::preference_keys::DEV_ERROR_LOGS_LAST_VIEWED_AT;
pub(super) use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
pub(super) use rusqlite::Connection;

pub(super) fn insert_conflict_row(
    conn: &Connection,
    entity_id: &str,
    resolved_at: &str,
    resolution_type: &str,
) {
    conn.execute(
        "INSERT INTO sync_conflict_log
            (entity_type, entity_id, winner_version, loser_version,
             loser_device_id, loser_payload, resolved_at, resolution_type)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![
            "task",
            entity_id,
            "1711234567891_0000_aaaaaaaaaaaaaaaa",
            "1711234567890_0000_bbbbbbbbbbbbbbbb",
            "device-remote",
            None::<String>,
            resolved_at,
            resolution_type,
        ],
    )
    .expect("insert sync_conflict_log row");
}
