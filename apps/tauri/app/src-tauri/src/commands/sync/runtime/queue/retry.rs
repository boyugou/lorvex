use super::*;
use crate::error::{AppError, AppResult};
use rusqlite::OptionalExtension;

/// when the user switches sync transports (
/// filesystem bridge, etc.), reset \`retry_count\` on every unsynced
/// outbox row. The retry counts accumulated against the previous
/// transport are meaningless to the new one, and without this reset
/// a user whose sync provider was unreachable could toggle to
/// filesystem-bridge only to find that rows already at
/// \`retry_count >= MAX_RETRIES\` stay permanently quarantined and
/// never push.
///
/// Structurally-poisoned rows (bumped to \`MAX_RETRIES\` by the outbox
/// decode-quarantine path, not by transport failures) are left alone
/// — they're malformed regardless of which transport handles them.
#[tauri::command]
pub fn reset_outbox_retry_counts_for_transport_switch() -> Result<i64, String> {
    reset_outbox_retry_counts_for_transport_switch_inner().map_err(String::from)
}

fn reset_outbox_retry_counts_for_transport_switch_inner() -> AppResult<i64> {
    let conn = get_conn()?;
    // #3033-M8: capture the pre-reset retry-count distribution so
    // the audit row records the before-state. We snapshot the
    // sum + max + non-zero count instead of every row id because
    // the reset is intentionally bulk and the row-level history
    // adds nothing actionable for the audit trail.
    let (before_sum, before_max, before_nonzero) = read_outbox_retry_distribution(&conn)?;

    let changed = lorvex_sync::outbox::reset_retry_counts_for_transport_switch(&conn)
        .map_err(AppError::from)?;

    append_sync_admin_diagnostic_row(
        &conn,
        "reset_outbox_retry_counts_for_transport_switch",
        format!(
            "Reset outbox retry counts on transport switch ({changed} row(s)). \
             before: sum={before_sum}, max={before_max}, nonzero={before_nonzero}",
        ),
        serde_json::json!({
            "changed": changed,
            "before": {
                "sum": before_sum,
                "max": before_max,
                "nonzero_rows": before_nonzero,
            },
            "after": {
                // The reset zeroes structurally-OK rows; structurally-
                // poisoned rows (retry_count == MAX_RETRIES via the
                // decode-quarantine path) are left alone, so we don't
                // claim "after: all zero" — the audit row says how
                // many we touched.
                "rows_reset": changed,
            },
        }),
    )?;

    i64::try_from(changed)
        .map_err(|_| AppError::Internal(format!("changed row count overflowed i64: {changed}")))
}

/// #3033-M8: aggregate retry-count snapshot for the audit row.
fn read_outbox_retry_distribution(conn: &rusqlite::Connection) -> AppResult<(i64, i64, i64)> {
    let row = conn
        .query_row(
            "SELECT
               COALESCE(SUM(retry_count), 0),
               COALESCE(MAX(retry_count), 0),
               COALESCE(SUM(CASE WHEN retry_count > 0 THEN 1 ELSE 0 END), 0)
             FROM sync_outbox WHERE synced_at IS NULL",
            [],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .map_err(AppError::from)?;
    Ok(row)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Append a sync-admin diagnostic row to `error_logs`.
///
/// Tauri commands do not author `ai_changelog` rows; that table is
/// reserved for AI/MCP history. Sync administration is still worth
/// auditing, but it belongs in the diagnostics channel that already
/// represents app/system events.
fn append_sync_admin_diagnostic_row(
    conn: &rusqlite::Connection,
    event: &str,
    summary: String,
    after_json: serde_json::Value,
) -> AppResult<()> {
    let after_json_str = serde_json::to_string(&after_json).map_err(AppError::from)?;
    crate::commands::diagnostics::append_error_log_internal(
        conn,
        &format!("sync.admin.{event}"),
        &summary,
        Some(after_json_str),
        Some("info".to_string()),
    )
    .map_err(AppError::Internal)?;
    Ok(())
}

/// reset `retry_count`, `last_retry_at`, and `last_error`
/// on a single unsynced outbox row so the user can manually retry a
/// quarantined entry without the full reset-and-reseed sledgehammer.
/// The call is a no-op (returns `Ok(())`) when the row is missing or
/// already synced — this is an idempotent "retry now" primitive.
#[tauri::command]
pub fn reset_outbox_entry_retry_count(id: String) -> Result<(), String> {
    reset_outbox_entry_retry_count_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn reset_outbox_entry_retry_count_inner(id: String) -> AppResult<()> {
    let conn = get_conn()?;
    // sync_outbox.id is INTEGER; parse the string ID for proper matching.
    let int_id: i64 = id
        .parse()
        .map_err(|_| AppError::Validation(format!("Invalid outbox entry id: {id}")))?;

    // #3033-M8: snapshot the pre-reset retry_count + last_error so
    // the audit row records the before-state. The row may have been
    // already-synced or missing — `reset_row_retry_count` silently
    // accepts both as no-ops, so we read the row first and only emit
    // an audit entry when there's something to report.
    //
    // Distinguish "row not found" (genuine no-op) from "query failed"
    // (propagate so the reset-and-record sequence is atomic): only
    // `Ok(None)` short-circuits to the empty before-state; rusqlite
    // errors (including BUSY) bubble to the caller via `AppError`.
    // A blanket `.ok()` would mask SQLITE_BUSY as `None` and suppress
    // the audit changelog row even when the row genuinely existed
    // and contention was the only failure mode.
    let before: Option<(i64, Option<String>)> = conn
        .query_row(
            "SELECT retry_count, last_error
             FROM sync_outbox
             WHERE id = ?1 AND synced_at IS NULL",
            rusqlite::params![int_id],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, Option<String>>(1)?)),
        )
        .optional()
        .map_err(AppError::from)?;

    lorvex_sync::outbox::reset_row_retry_count(&conn, int_id).map_err(AppError::from)?;

    // Append a sync-admin diagnostic only when the reset actually had
    // a row to act on. No-op resets (row missing / already synced)
    // skip the diagnostic so the log isn't polluted with phantom rows
    // from a renderer bug.
    if let Some((before_retry, before_error)) = before {
        append_sync_admin_diagnostic_row(
            &conn,
            "reset_outbox_entry_retry_count",
            format!(
                "Reset outbox entry retry_count for id={int_id} \
                 (was {before_retry}, now 0)",
            ),
            serde_json::json!({
                "outbox_id": int_id,
                "before": {
                    "retry_count": before_retry,
                    "last_error": before_error,
                },
                "after": {
                    "retry_count": 0,
                    "last_error": serde_json::Value::Null,
                },
            }),
        )?;
    }

    Ok(())
}

/// Test-only helper: shared by sync-status regression tests that need
/// to mark outbox rows synced through the canonical update path
/// without going through a Tauri IPC boundary. Issue #2940-H1 removed
/// the `mark_outbox_entries_synced` Tauri command (no UI caller); the
/// test surface stays.
#[cfg(test)]
pub(crate) fn mark_outbox_entries_synced_internal(
    conn: &rusqlite::Connection,
    ids: &[String],
    synced_ts: &str,
) -> AppResult<i64> {
    if ids.is_empty() {
        return Ok(0);
    }

    let sync_ts = synced_ts.to_string();
    // sync_outbox.id is INTEGER; parse the string IDs to i64 for proper matching.
    let int_ids = parse_outbox_entry_ids(ids)?;

    // Wrap in a savepoint so the UPDATE + checkpoint writes are atomic.
    lorvex_store::with_savepoint(conn, "mark_synced", |conn: &rusqlite::Connection| {
        let placeholders = lorvex_domain::sql_csv_placeholders(int_ids.len());
        let sql = format!(
            "UPDATE sync_outbox
             SET synced_at = ?1, last_error = NULL
             WHERE synced_at IS NULL
               AND id IN ({placeholders})"
        );

        let mut values: Vec<Box<dyn rusqlite::types::ToSql>> =
            vec![Box::new(synced_ts.to_string())];
        values.extend(
            int_ids
                .iter()
                .map(|id| Box::new(*id) as Box<dyn rusqlite::types::ToSql>),
        );
        let param_refs: Vec<&dyn rusqlite::types::ToSql> =
            values.iter().map(std::convert::AsRef::as_ref).collect();
        let changed = conn
            .execute(&sql, param_refs.as_slice())
            .map_err(AppError::from)?;

        if changed > 0 {
            upsert_sync_checkpoint_timestamp_if_newer(
                conn,
                lorvex_runtime::KEY_LAST_SUCCESS_AT,
                &sync_ts,
            )?;

            lorvex_runtime::sync_checkpoint_clear(conn, lorvex_runtime::KEY_LAST_ERROR)
                .map_err(AppError::from)?;
        }

        i64::try_from(changed)
            .map_err(|_| AppError::Internal(format!("changed row count overflowed i64: {changed}")))
    })
}

/// Test-only helper: shared by sync-status regression tests that need
/// to bump retry counters through the canonical path. Issue #2940-H1
/// removed the `mark_outbox_entry_retry` Tauri command; the test
/// surface stays.
#[cfg(test)]
pub(crate) fn mark_outbox_entry_retry_internal(
    conn: &rusqlite::Connection,
    id: &str,
    error: &str,
    now: &str,
) -> AppResult<()> {
    // sync_outbox.id is INTEGER; parse the string ID.
    let int_id: i64 = id
        .parse()
        .map_err(|_| AppError::Validation(format!("Invalid outbox entry id: {id}")))?;

    // Wrap in a savepoint so the retry bump + error record are atomic.
    lorvex_store::with_savepoint(conn, "mark_retry", |conn: &rusqlite::Connection| {
        // Route through `outbox::record_retry` with the error
        // string so the helper can (a) store it in the row's
        // `last_error` column and (b) detect same-error repetition
        // and escalate to MAX_RETRIES on the third identical
        // failure. A bare UPDATE here would lose per-row error
        // history entirely, so a row could burn all 10 retries on
        // the same permanent failure.
        let trimmed_error: String = error.chars().take(1_000).collect();
        lorvex_sync::outbox::record_retry(conn, int_id, now, Some(&trimmed_error))
            .map_err(AppError::from)?;

        let message = format!("[{now}] outbox entry failed: {trimmed_error}");
        lorvex_runtime::sync_checkpoint_set(conn, lorvex_runtime::KEY_LAST_ERROR, &message)
            .map_err(AppError::from)?;

        Ok(())
    })
}

pub(crate) fn gc_synced_events(conn: &rusqlite::Connection) -> AppResult<i64> {
    // Use strftime with ISO 8601 format to match the stored synced_at/created_at
    // format (YYYY-MM-DDTHH:MM:SS.sssZ). Using datetime() would produce
    // space-separated timestamps (YYYY-MM-DD HH:MM:SS), causing incorrect
    // lexicographic comparison against T-separated stored values.
    let deleted_synced = conn
        .execute(
            "DELETE FROM sync_outbox
             WHERE synced_at IS NOT NULL
               AND synced_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
            params![format!("-{SYNC_GC_RETENTION_DAYS} days")],
        )
        .map_err(AppError::from)?;

    let deleted_dead = conn
        .execute(
            "DELETE FROM sync_outbox
             WHERE synced_at IS NULL
               AND retry_count >= ?1
               AND created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-30 days')",
            params![lorvex_sync::outbox::MAX_RETRIES],
        )
        .map_err(AppError::from)?;

    i64::try_from(deleted_synced + deleted_dead).map_err(|_| {
        AppError::Internal(format!(
            "deleted row count overflowed i64: {}",
            deleted_synced + deleted_dead
        ))
    })
}

#[cfg(test)]
fn parse_outbox_entry_ids(ids: &[String]) -> AppResult<Vec<i64>> {
    ids.iter()
        .enumerate()
        .map(|(index, raw)| {
            raw.parse::<i64>().map_err(|_| {
                AppError::Validation(format!("Invalid outbox entry id at index {index}: {raw}"))
            })
        })
        .collect()
}

#[cfg(test)]
mod sync_admin_diagnostic_tests {
    use super::*;

    #[test]
    fn sync_admin_diagnostic_writes_error_log_not_ai_changelog() {
        let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

        append_sync_admin_diagnostic_row(
            &conn,
            "reset_outbox_retry_counts_for_transport_switch",
            "Reset outbox retry counts on transport switch (2 row(s)).".to_string(),
            serde_json::json!({ "changed": 2 }),
        )
        .expect("append diagnostic");

        let (source, level, details): (String, String, String) = conn
            .query_row(
                "SELECT source, level, details
                 FROM error_logs
                 WHERE source = 'sync.admin.reset_outbox_retry_counts_for_transport_switch'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read sync-admin diagnostic");
        assert_eq!(
            source,
            "sync.admin.reset_outbox_retry_counts_for_transport_switch"
        );
        assert_eq!(level, "info");
        assert!(
            details.contains("\"changed\":2"),
            "diagnostic details should preserve structured payload, got {details}"
        );

        let changelog_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
            .expect("count ai_changelog rows");
        assert_eq!(
            changelog_count, 0,
            "Tauri sync-admin diagnostics must not write ai_changelog"
        );
    }
}
