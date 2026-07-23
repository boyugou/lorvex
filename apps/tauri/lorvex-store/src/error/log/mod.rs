//! Canonical writer for the `error_logs` diagnostic table.
//!
//! Every layer that writes a diagnostic row (lorvex-sync, mcp-server,
//! the Tauri app, the CLI) routes through this helper so the
//! redaction invariant promised in `lorvex_domain::diagnostics` —
//! "every write to error_logs is redacted" — holds uniformly.
//!
//! The helper:
//! - Generates a UUIDv7 id per call.
//! - Trims and rejects empty `source` / `message`.
//! - Runs both `message` and `details` through
//!   [`lorvex_domain::diagnostics::redact_diagnostic_text`] so secrets
//!   (API keys, OAuth tokens, file paths, email addresses, etc.) never
//!   land in the DB.
//! - Truncates after redaction (redaction can only shrink) to fit
//!   inside the column budget — 2 KiB for `message`, 8 KiB for
//!   `details`. Truncation respects UTF-8 char boundaries.
//! - Normalizes the `level` column to one of {debug, info, warn, error}
//!   with `error` as the default.
//!
//! Failures to insert are returned as `rusqlite::Error` to the caller.
//! Callers that need best-effort semantics (e.g., the apply pipeline's
//! device-collision warning) can swallow the error themselves.

use rusqlite::{params, Connection};
use std::sync::atomic::{AtomicU64, Ordering};

const MAX_MESSAGE_BYTES: usize = 2048;
const MAX_DETAIL_BYTES: usize = 8192;

/// Process-lifetime counter of best-effort diagnostic-write failures.
///
/// `append_error_log_best_effort` swallows every `INSERT` failure
/// because a broken diagnostic write must not eclipse the primary
/// failure that triggered it (apply pipeline, sync write loop, etc.).
/// Without an out-of-band counter the swallow is invisible:
/// diagnosing a "diagnostic ring full / corrupt" regression would
/// require attaching to a running process and probing SQLite
/// directly.
///
/// Surface the count via [`silent_diagnostic_failure_count`] so a
/// Settings → Diagnostics panel can render "diagnostic write
/// failures: N (since process start)" once. The counter is
/// monotonically increasing; the user-facing surface is responsible
/// for "since last view" framing.
static SILENT_DIAGNOSTIC_FAILURES: AtomicU64 = AtomicU64::new(0);

/// Read the cumulative count of best-effort diagnostic-write failures
/// observed by this process. Returns `0` when the diagnostic surface
/// has been healthy. See [`SILENT_DIAGNOSTIC_FAILURES`] for the
/// surfaceing contract.
pub fn silent_diagnostic_failure_count() -> u64 {
    SILENT_DIAGNOSTIC_FAILURES.load(Ordering::Relaxed)
}

/// Append one row to `error_logs`. See module docs for the redaction
/// + truncation contract.
pub fn append_error_log(
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
    // Audit: `source` was written verbatim under the
    // assumption that callers always pass a static identifier
    // (`mcp.foo`, `sync.filesystem_bridge.bar`). Run it through the same
    // redactor as `message`/`details` so a dynamic source label that
    // happens to contain an email or path still has the secret
    // scrubbed before it reaches the DB. Cap at MAX_MESSAGE_BYTES
    // (2 KiB) — sources should be short tokens; this is generous.
    //
    // #2861: same truncate-after-redact-and-truncate pattern as
    // `message` / `details` so any future redactor expansion is
    // bounded by the column budget on both sides of the redact call.
    let pre_truncated_src = truncate_utf8_to_max_bytes(src_trimmed, MAX_MESSAGE_BYTES);
    let redacted_src = lorvex_domain::diagnostics::redact_diagnostic_text(&pre_truncated_src);
    let src_owned = truncate_utf8_to_max_bytes(&redacted_src, MAX_MESSAGE_BYTES);
    if src_owned.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "error_logs.source empty after redaction".to_string(),
        ));
    }
    let src: &str = &src_owned;

    let msg_trimmed = message.trim();
    if msg_trimmed.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "error_logs.message must not be empty".to_string(),
        ));
    }

    // defensive truncate-after-redact pattern. The
    // module doc claims "redaction can only shrink" but doesn't
    // assert it at the boundary — and a future redactor change that
    // expands a placeholder (e.g. `sk_X` → `[REDACTED-API-KEY]`)
    // would leave the post-redact string longer than the input,
    // potentially overflowing the column or splitting inside the
    // placeholder on the next truncation. Truncating BEFORE redaction
    // bounds memory and SQL byte budget; redacting AFTER catches any
    // secret near the boundary; truncating AGAIN guarantees the
    // final byte budget regardless of whether redaction expanded
    // anything. The cost is one extra char-boundary walk, negligible
    // vs the redactor's regex pass.
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
    // route the diagnostic INSERT through
    // `prepare_cached` so the 17 call sites (one per failure surface
    // in the apply pipeline + the Tauri/MCP error-channel wrappers)
    // amortize the prepare/plan cost across a single connection's
    // lifetime instead of re-preparing the same statement on every
    // call.
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

/// Best-effort wrapper around [`append_error_log`].
///
/// replaces `let _ = append_error_log(...)` sites that
/// silently swallowed every diagnostic write failure. Production
/// semantics stay best-effort (a broken diagnostic INSERT must never
/// eclipse the primary failure that triggered it), but `debug_assert!`
/// surfaces the regression class loudly in tests / debug builds.
pub fn append_error_log_best_effort(
    conn: &Connection,
    source: &str,
    message: &str,
    details: Option<&str>,
    level: Option<&str>,
) {
    if let Err(err) = append_error_log(conn, source, message, details, level) {
        // bump the process-wide counter on every
        // swallow so the "diagnostic ring is broken" regression class
        // becomes observable via [`silent_diagnostic_failure_count`].
        SILENT_DIAGNOSTIC_FAILURES.fetch_add(1, Ordering::Relaxed);
        debug_assert!(
            false,
            "diagnostic append_error_log failed (source={source}): {err}"
        );
        let _ = err;
    }
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

#[cfg(test)]
mod tests;
