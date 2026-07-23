//! Local SQL primitives the shadow modules need.
//!
//! `lorvex-store`'s richer helpers (`with_savepoint` with busy retry +
//! panic safety; `append_error_log_best_effort` with per-process
//! silent-failure counters) live one layer up in the dep graph and
//! cannot reach back into this crate without forming a cycle. The
//! helpers here provide the minimum semantic surface the shadow CRUD
//! and merge paths rely on:
//!
//! * [`with_savepoint`] — uniquely-named SAVEPOINT wrapper that
//!   commits on `Ok` and rolls back on `Err`. Used by
//!   `merge_shadow_into_redirect`. The call is always made from
//!   inside an outer transaction held by `lorvex-store` / `lorvex-sync`
//!   apply, so a BUSY return from the inner `SAVEPOINT` statement is
//!   already serialized away by the write mutex — no busy-retry
//!   wrapper is required at this layer.
//! * [`append_error_log_best_effort`] — minimal redact-then-insert
//!   diagnostic write. Routes the message and details through
//!   `lorvex_domain::diagnostics::redact_diagnostic_text` so the
//!   "every `error_logs` row is redacted" invariant promised in
//!   `lorvex_domain::diagnostics` holds across the shadow paths the
//!   same way it does across the rest of the storage layer.

use crate::PayloadError;
use rusqlite::{params, Connection};
use std::sync::atomic::{AtomicU64, Ordering};

/// Process-global counter that names uniquely-scoped savepoints.
/// `Relaxed` is sufficient — the only invariant is "no two concurrent
/// fetch_adds return the same value," which every ordering provides.
static SAVEPOINT_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Execute `f` inside a uniquely-named `SAVEPOINT`. Releases on `Ok`,
/// rolls back on `Err`. The savepoint name is built from a sanitized
/// prefix and the process-global counter so concurrent invocations
/// cannot alias.
pub(crate) fn with_savepoint<T>(
    conn: &Connection,
    prefix: &str,
    f: impl FnOnce(&Connection) -> Result<T, PayloadError>,
) -> Result<T, PayloadError> {
    let safe_prefix: String = prefix
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if safe_prefix.is_empty() {
        return Err(PayloadError::Invariant(format!(
            "savepoint prefix '{prefix}' contains no valid identifier characters"
        )));
    }
    let id = SAVEPOINT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let name = format!("lvx_sp_{safe_prefix}_{id}");
    conn.execute_batch(&format!("SAVEPOINT \"{name}\""))?;
    match f(conn) {
        Ok(value) => {
            conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""))?;
            Ok(value)
        }
        Err(err) => {
            // Best-effort rollback; if the cleanup itself fails, the
            // original error still wins (the savepoint will unwind
            // when the outer transaction rolls back).
            let _ = conn.execute_batch(&format!("ROLLBACK TO SAVEPOINT \"{name}\""));
            let _ = conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""));
            Err(err)
        }
    }
}

const MAX_MESSAGE_BYTES: usize = 2048;
const MAX_DETAIL_BYTES: usize = 8192;

/// Best-effort diagnostic write to `error_logs`. Mirrors the redact-
/// then-truncate contract enforced by `lorvex_store::error::log`:
/// every column value is run through the domain-level redactor before
/// it lands in SQLite, and the result is truncated to the column
/// budget on UTF-8 char boundaries. Failures are swallowed so a
/// broken diagnostic ring cannot eclipse the primary failure the
/// caller is logging.
pub(crate) fn append_error_log_best_effort(
    conn: &Connection,
    source: &str,
    message: &str,
    details: Option<&str>,
    level: Option<&str>,
) {
    let _ = append_error_log(conn, source, message, details, level);
}

fn append_error_log(
    conn: &Connection,
    source: &str,
    message: &str,
    details: Option<&str>,
    level: Option<&str>,
) -> Result<(), rusqlite::Error> {
    let src_trimmed = source.trim();
    if src_trimmed.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "error_logs.source must not be empty".to_string(),
        ));
    }
    let pre_truncated_src = truncate_utf8_to_max_bytes(src_trimmed, MAX_MESSAGE_BYTES);
    let redacted_src = lorvex_domain::diagnostics::redact_diagnostic_text(&pre_truncated_src);
    let src = truncate_utf8_to_max_bytes(&redacted_src, MAX_MESSAGE_BYTES);
    if src.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "error_logs.source empty after redaction".to_string(),
        ));
    }

    let msg_trimmed = message.trim();
    if msg_trimmed.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "error_logs.message must not be empty".to_string(),
        ));
    }
    let pre_truncated_msg = truncate_utf8_to_max_bytes(msg_trimmed, MAX_MESSAGE_BYTES);
    let redacted_msg = lorvex_domain::diagnostics::redact_diagnostic_text(&pre_truncated_msg);
    let final_msg = truncate_utf8_to_max_bytes(&redacted_msg, MAX_MESSAGE_BYTES);
    if final_msg.trim().is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "error_logs.message empty after redaction".to_string(),
        ));
    }

    let final_details = details.and_then(|raw| {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            None
        } else {
            let pre_truncated = truncate_utf8_to_max_bytes(trimmed, MAX_DETAIL_BYTES);
            let redacted = lorvex_domain::diagnostics::redact_diagnostic_text(&pre_truncated);
            Some(truncate_utf8_to_max_bytes(&redacted, MAX_DETAIL_BYTES))
        }
    });

    let id = lorvex_domain::new_entity_id_string();
    let now = lorvex_domain::sync_timestamp_now();
    let mut stmt = conn.prepare_cached(
        "INSERT INTO error_logs (id, source, level, message, details, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
    )?;
    stmt.execute(params![
        id,
        src,
        normalize_error_level(level),
        final_msg,
        final_details,
        now,
    ])?;
    Ok(())
}

fn normalize_error_level(level: Option<&str>) -> &'static str {
    match level
        .unwrap_or("error")
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "debug" => "debug",
        "info" => "info",
        "warn" | "warning" => "warn",
        _ => "error",
    }
}

fn truncate_utf8_to_max_bytes(value: &str, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_string();
    }
    let mut end = max_bytes;
    while end > 0 && !value.is_char_boundary(end) {
        end -= 1;
    }
    value[..end].to_string()
}
