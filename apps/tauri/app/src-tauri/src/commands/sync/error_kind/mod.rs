//! classify sync command failures into a small, stable set of
//! actionable categories so the UI can render "Retry" / "Open System
//! Settings" / "Open docs" instead of dumping a raw `rusqlite` /
//! `rusqlite` / filesystem message at the user.
//!
//! Design: at the `#[tauri::command]` boundary, the `String` error is
//! replaced with a JSON envelope `{"kind":"...","message":"...",
//! "retryable":bool,"path":string|null}`. The frontend parses this and
//! falls back to the raw message if parsing fails. Shape is
//! backward-compatible: every other consumer that just reads the string
//! as a human-readable message still gets something legible (the envelope
//! starts with an English phrase — but the frontend typically unwraps it
//! first). The full raw message is preserved in `message` for
//! copy-to-clipboard and diagnostics.

use serde::Serialize;

/// Stable user-actionable categories for sync failures.
/// These map 1:1 to a translation key on the frontend; do not rename
/// without updating `parseSyncErrorKind` + the locale files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum SyncErrorKind {
    Offline,
    Permissions,
    Timeout,
    Unknown,
}

impl SyncErrorKind {
    /// The toast on the frontend decides whether to offer a Retry
    /// button based on this flag.
    const fn is_retryable(self) -> bool {
        true
    }
}

/// Wire envelope returned to the frontend as a JSON-encoded String
/// (so the `Result<T, String>` Tauri command signature is preserved).
#[derive(Debug, Serialize)]
pub(crate) struct SyncErrorEnvelope<'a> {
    pub kind: SyncErrorKind,
    pub message: &'a str,
    pub retryable: bool,
    pub path: Option<&'a str>,
}

/// Classify a raw error message into a stable kind.
///
/// We lean on substring matching of lowercased message text because the
/// `AppError` enum is a shallow wrapper around stringified errors from
/// multiple crates (rusqlite, reqwest, std::io). That
/// same flat shape is what made issue #2271 happen in the first place;
/// classifying here keeps the fix surface bounded without restructuring
/// the whole error pipeline.
pub(crate) fn classify_sync_error(raw: &str) -> SyncErrorKind {
    let lower = raw.to_ascii_lowercase();

    // Network offline / DNS / connection refused indicators.
    if lower.contains("no network")
        || lower.contains("network is unreachable")
        || lower.contains("network unreachable")
        || lower.contains("offline")
        || lower.contains("dns error")
        || lower.contains("failed to lookup address")
        || lower.contains("failed to resolve host")
        || lower.contains("connection refused")
        || lower.contains("err_internet_disconnected")
        || lower.contains("nsurlerrordomain error -1009") // kCFURLErrorNotConnectedToInternet
        || lower.contains("nsurlerrordomain error -1003")
    // kCFURLErrorCannotFindHost
    {
        return SyncErrorKind::Offline;
    }

    // Filesystem permission errors on the filesystem-bridge root.
    if lower.contains("permission denied")
        || lower.contains("eacces")
        || lower.contains("eperm")
        || lower.contains("access is denied")
        || lower.contains("operation not permitted")
        || lower.contains("read-only file system")
    {
        return SyncErrorKind::Permissions;
    }

    // Network timeouts (reqwest / URLSession timeout).
    if lower.contains("timed out")
        || lower.contains("timeout")
        || lower.contains("request timed out")
        || lower.contains("nsurlerrordomain error -1001") // kCFURLErrorTimedOut
        || lower.contains("operation timed out")
    {
        return SyncErrorKind::Timeout;
    }

    SyncErrorKind::Unknown
}

/// Extract a filesystem path from a permissions-related error message.
/// Best-effort: scans for the first absolute path token. Populates
/// the `{path}` interpolation in the i18n message.
pub(crate) fn extract_path_hint(raw: &str) -> Option<String> {
    // Look for macOS/Linux absolute paths starting with `/` and
    // Windows drive letters. Scan token-by-token so paths embedded in
    // multi-word messages ("failed to write /Users/a/b: EACCES") are
    // captured cleanly.
    for token in raw.split_whitespace() {
        let cleaned = token.trim_matches(|c: char| matches!(c, '"' | '\'' | ':' | ',' | '.' | ';'));
        if cleaned.starts_with('/') && cleaned.len() > 1 {
            return Some(cleaned.to_string());
        }
        if cleaned.len() >= 3 {
            let bytes = cleaned.as_bytes();
            if bytes[0].is_ascii_alphabetic() && bytes[1] == b':' && bytes[2] == b'\\' {
                return Some(cleaned.to_string());
            }
        }
    }
    None
}

/// Serialize an error into the wire envelope. Falls back to the raw
/// string when serialization fails (it shouldn't, but we never want to
/// swallow the original diagnostic).
#[cfg(test)]
fn encode_sync_error(raw: String) -> String {
    let kind = classify_sync_error(&raw);
    let path = if matches!(kind, SyncErrorKind::Permissions) {
        extract_path_hint(&raw)
    } else {
        None
    };
    let envelope = SyncErrorEnvelope {
        kind,
        message: &raw,
        retryable: kind.is_retryable(),
        path: path.as_deref(),
    };
    serde_json::to_string(&envelope).unwrap_or(raw)
}

/// Classify an `AppError` directly so we can see the raw inner error
/// text of Sql/Store/Sync variants (which the user-facing `From<AppError>
/// for String` conversion sanitizes to a generic string). The returned
/// envelope uses the sanitized message for the `message` field but
/// classifies off the richer raw text — so a rusqlite `EACCES` wrapped
/// in `AppError::Sql` still becomes `kind: "permissions"` on the wire.
pub(crate) fn encode_app_error(error: crate::error::AppError) -> String {
    // Raw (unsanitized) error text for classification purposes only.
    let raw_for_classify = error.to_string();
    let kind = classify_sync_error(&raw_for_classify);
    // User-facing message preserves the existing sanitization policy
    // (no rusqlite schema details leak into the toast) — callers that
    // want the raw text can still pull it from `error_logs` via the
    // upstream `logAssistantSettingsError` call.
    let sanitized: String = error.into();
    let path = if matches!(kind, SyncErrorKind::Permissions) {
        extract_path_hint(&raw_for_classify).or_else(|| extract_path_hint(&sanitized))
    } else {
        None
    };
    let envelope = SyncErrorEnvelope {
        kind,
        message: &sanitized,
        retryable: kind.is_retryable(),
        path: path.as_deref(),
    };
    serde_json::to_string(&envelope).unwrap_or(sanitized)
}

#[cfg(test)]
mod tests;
