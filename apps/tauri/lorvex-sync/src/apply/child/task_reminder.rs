use lorvex_domain::canonicalize_rfc3339_instant;
use lorvex_domain::ids::{ReminderId, TaskId};

use super::helpers::{optional_str, required_str};
use super::*;

fn reminder_instant_key(value: &str) -> String {
    canonicalize_rfc3339_instant(value).unwrap_or_else(|| value.to_string())
}

pub(crate) fn apply_task_reminder_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the PK and the task-id FK into typed
    // newtypes at handler entry. SQL bind sites use the rusqlite ToSql
    // impl on the newtype (zero-copy); dispatcher-validated upstream so
    // `from_trusted` skips a redundant parse.
    let id = ReminderId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let task_id_str = required_str(&val, "task_id", "task_reminder")?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let reminder_at_raw = required_str(&val, "reminder_at", "task_reminder")?;
    let reminder_at = canonicalize_rfc3339_instant(reminder_at_raw).ok_or_else(|| {
        ApplyError::InvalidPayload(format!(
            "task_reminder payload.reminder_at must be a valid RFC 3339 datetime, got '{reminder_at_raw}'"
        ))
    })?;
    let dismissed_at = optional_str(&val, "dismissed_at", "task_reminder")?;
    let cancelled_at = optional_str(&val, "cancelled_at", "task_reminder")?;
    let created_at = required_str(&val, "created_at", "task_reminder")?;
    // local wall-clock anchor columns. Optional so that
    // envelopes originating from legacy builds (or MCP paths that
    // can't resolve PREF_TIMEZONE) still apply cleanly as NULLs.
    let original_local_time = optional_str(&val, "original_local_time", "task_reminder")?;
    let original_tz = optional_str(&val, "original_tz", "task_reminder")?;

    // Capture the previous reminder_at (if the row exists) so we can detect
    // whether the UPSERT actually changed the scheduled time. When a remote
    // edit changes the time, the device-local delivery_state row for the
    // prior firing must be cleared so the reminder can re-fire. Without this,
    // a reminder that had already `delivered` would remain suppressed by the
    // query filter even though the user rescheduled it.
    let previous_reminder_at: Option<String> = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = ?1",
            params![&id],
            |row| row.get(0),
        )
        .optional()?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "task_reminders",
        columns: &[
            "id",
            "task_id",
            "reminder_at",
            "dismissed_at",
            "cancelled_at",
            "created_at",
            "original_local_time",
            "original_tz",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":id": &id,
        ":task_id": &task_id,
        ":reminder_at": reminder_at,
        ":dismissed_at": dismissed_at,
        ":cancelled_at": cancelled_at,
        ":created_at": created_at,
        ":original_local_time": original_local_time,
        ":original_tz": original_tz,
        ":version": version,
    })?;

    // After the UPSERT, re-read the row and compare the stored reminder_at
    // with the previous value. (LWW may have rejected the update if our local
    // version is newer, in which case nothing to reset.)
    let stored_reminder_at: Option<String> = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = ?1",
            params![&id],
            |row| row.get(0),
        )
        .optional()?;

    let time_changed = match (
        previous_reminder_at.as_deref(),
        stored_reminder_at.as_deref(),
    ) {
        // Row existed before, and the stored value is now different from the
        // previous value → the UPSERT won LWW and updated reminder_at.
        (Some(prev), Some(curr)) => reminder_instant_key(prev) != reminder_instant_key(curr),
        // Row did not exist before → this was a fresh insert; no stale
        // delivery_state to clear.
        _ => false,
    };

    if time_changed {
        conn.prepare_cached("DELETE FROM task_reminder_delivery_state WHERE reminder_id = ?1")?
            .execute(params![&id])?;
    }

    Ok(())
}

pub(crate) fn apply_task_reminder_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the PK to a typed `ReminderId` at
    // handler entry. SQL bind threads it via the rusqlite ToSql impl.
    let id = ReminderId::from_trusted(entity_id.to_string());
    // route through `lww_gated_delete` so the in-row
    // LWW guard parses the typed HLC instead of byte-comparing the
    // string directly — same discipline as every other apply-time
    // delete. The upstream `apply_envelope` already gates child
    // deletes by HLC via the tombstone bookkeeping, but the handler
    // is also reachable from `apply_entity_with_version_mode(_, true)`
    // (shadow promotion) and any future replay path; routing through
    // the helper makes the gate safe regardless of upstream coverage.
    crate::apply::lww_gated_delete(conn, "task_reminders", &["id"], &[id.as_str()], version)?;
    Ok(())
}
