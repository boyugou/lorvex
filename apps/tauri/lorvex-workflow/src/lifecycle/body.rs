use lorvex_domain::TaskId;
use rusqlite::{params, Connection, OptionalExtension};

use lorvex_store::StoreError;

/// Atomically append text to a task's body, separated by a blank line.
///
/// Returns the new body value. The caller is responsible for wrapping this in a
/// transaction and for outbox enqueue / audit logging.
///
/// Enforces the full-body length cap at the store layer so both
/// MCP and Tauri callers are protected. A check that only inspects
/// the NEW text would let an assistant call append 200× with 50K
/// chunks and silently grow the body to 10 MB.
///
/// Stamps a fresh `version` alongside `updated_at`. Leaving
/// `version` unchanged would make cross-device LWW reconciliation
/// treat the body-mutated row as older than any peer that did
/// update its version — peer writes silently dropped
/// the appended text.
///
/// the UPDATE is gated by `?2 > version` so a stale
/// caller stamp cannot clobber a freshly-applied peer envelope.
/// Mirrors `recurrence::add_task_recurrence_exception_inner`:
/// zero rows changed surfaces as `StoreError::StaleVersion` so the
/// boundary layer can re-stamp HLC and retry instead of treating
/// the silent no-op as success. The TOCTOU between the `SELECT body`
/// read and the gated UPDATE is acceptable because callers wrap this
/// in an immediate transaction; if the row is mutated mid-transaction
/// by a peer apply, the gate rejects the (now-stale) stamp.
pub fn append_to_task_body(
    conn: &Connection,
    task_id: &TaskId,
    text: &str,
    version: &str,
    now: &str,
) -> Result<String, StoreError> {
    let current_body: Option<String> = conn
        .query_row(
            "SELECT body FROM tasks WHERE id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .optional()?
        .flatten();

    let new_body = match current_body {
        Some(existing) if !existing.is_empty() => format!("{existing}\n\n{text}"),
        _ => text.to_string(),
    };

    // Enforce the combined-body cap before writing so peers never see
    // an over-length body via sync either.
    lorvex_domain::validation::validate_body(&new_body)
        .map_err(|err| StoreError::Validation(err.to_string()))?;

    let rows = conn.execute(
        "UPDATE tasks SET body = ?1, version = ?2, updated_at = ?3 \
         WHERE id = ?4 AND ?2 > version",
        params![new_body, version, now, task_id],
    )?;
    if rows == 0 {
        return Err(StoreError::StaleVersion {
            entity: "task",
            id: task_id.as_str().to_string(),
        });
    }

    Ok(new_body)
}
