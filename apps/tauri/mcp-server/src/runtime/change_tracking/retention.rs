//! Retention-preference validation + the `ai_changelog` row → outbox
//! enqueue helper. Used by both `log_change` and the preview-only audit
//! row writer; kept together because they share the changelog-row
//! lifecycle concern.

use lorvex_domain::naming::{ENTITY_AI_CHANGELOG, OP_UPSERT};
use lorvex_domain::parse_positive_i64_preference;
use lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY;
use rusqlite::Connection;
use serde_json::{json, Value};

use super::get_or_create_sync_device_id;
use super::outbox::write_to_outbox;
use crate::error::McpError;

/// Read the user's ai_changelog retention window from preferences.
///
/// Returns:
/// - `Ok(None)` when the preference is unset (semantically "forever" —
///   keep all entries, never clean up).
/// - `Ok(Some(days))` for any positive integer day count.
/// - `Err(Validation)` if the stored value is a non-integer or
///   non-positive.
pub(super) fn read_changelog_retention_days(conn: &Connection) -> Result<Option<i64>, McpError> {
    let raw = conn.query_row(
        "SELECT value FROM preferences WHERE key = ?1",
        [PREF_AI_CHANGELOG_RETENTION_POLICY],
        |row| row.get::<_, String>(0),
    );

    match raw {
        Ok(value) => parse_positive_i64_preference(&value, PREF_AI_CHANGELOG_RETENTION_POLICY)
            .map(Some)
            .map_err(McpError::from),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(error) => Err(error.into()),
    }
}

/// Enqueue the ai_changelog entry to `sync_outbox`.
///
/// Retention-preference validation is the caller's responsibility
/// (`log_change` and `write_preview_audit_entry` both run it once
/// at the top of the write).
pub(super) fn enqueue_changelog_to_outbox(
    conn: &Connection,
    changelog_id: &str,
) -> Result<(), McpError> {
    let device_id = get_or_create_sync_device_id(conn)?;

    // Read the freshly-inserted row to build the sync payload. Every
    // schema column on `ai_changelog` must round-trip through the
    // envelope — the apply-side INSERT projects the same column list,
    // and a peer that receives a truncated payload would silently fall
    // back to schema defaults (`is_preview = 0`, `undo_token = NULL`).
    #[allow(clippy::type_complexity)]
    let (
        id,
        timestamp,
        operation,
        entity_type,
        entity_id,
        entity_ids_raw,
        summary,
        initiated_by,
        mcp_tool,
        source_device_id,
        before_json_raw,
        after_json_raw,
        undo_token_raw,
        is_preview_raw,
    ): (
        String,
        String,
        String,
        String,
        Option<String>,
        Option<String>,
        String,
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        i64,
    ) = conn
        .query_row(
            // Project through `columns::AI_CHANGELOG.select_clause` so
            // the `entity_ids` tuple position carries the wire-form
            // JSON array rebuilt from the `ai_changelog_entities`
            // join table.
            &format!(
                "SELECT {select_clause} FROM ai_changelog WHERE id = ?1",
                select_clause = lorvex_store::repositories::columns::AI_CHANGELOG.select_clause,
            ),
            [changelog_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, String>(6)?,
                    row.get::<_, String>(7)?,
                    row.get::<_, Option<String>>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, Option<String>>(10)?,
                    row.get::<_, Option<String>>(11)?,
                    row.get::<_, Option<String>>(12)?,
                    row.get::<_, i64>(13)?,
                ))
            },
        )
        .map_err(|error| {
            McpError::Internal(format!(
                "failed to load ai_changelog snapshot for {changelog_id}: {error}"
            ))
        })?;
    let entity_ids = entity_ids_raw
        .map(|raw| serde_json::from_str::<Value>(&raw))
        .transpose()?;
    let payload = json!({
        "id": id,
        "timestamp": timestamp,
        "operation": operation,
        "entity_type": entity_type,
        "entity_id": entity_id,
        "entity_ids": entity_ids,
        "summary": summary,
        "initiated_by": initiated_by,
        "mcp_tool": mcp_tool,
        "source_device_id": source_device_id,
        "before_json": before_json_raw,
        "after_json": after_json_raw,
        "undo_token": undo_token_raw,
        "is_preview": is_preview_raw != 0,
    });
    write_to_outbox(
        conn,
        ENTITY_AI_CHANGELOG,
        changelog_id,
        OP_UPSERT,
        &payload,
        &device_id,
    )?;
    Ok(())
}
