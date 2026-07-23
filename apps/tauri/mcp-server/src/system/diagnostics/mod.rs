use crate::contract::LogLevelFilter;
use lorvex_domain::naming::OP_DELETE;
use serde_json::{json, Value};

pub(crate) fn normalize_log_level(level: Option<&str>, fallback: LogLevelFilter) -> LogLevelFilter {
    match level.unwrap_or_default() {
        "debug" => LogLevelFilter::Debug,
        "info" => LogLevelFilter::Info,
        "warn" => LogLevelFilter::Warn,
        "error" => LogLevelFilter::Error,
        _ => fallback,
    }
}

pub(crate) const fn log_level_to_str(level: LogLevelFilter) -> &'static str {
    match level {
        LogLevelFilter::Debug => "debug",
        LogLevelFilter::Info => "info",
        LogLevelFilter::Warn => "warn",
        LogLevelFilter::Error => "error",
    }
}

pub(crate) fn level_for_changelog_operation(operation: &str) -> LogLevelFilter {
    if matches!(
        operation,
        "feedback" | OP_DELETE | "cancel" | "permanent_delete"
    ) {
        return LogLevelFilter::Warn;
    }
    LogLevelFilter::Info
}

pub(crate) fn truncate_diagnostic_text(value: &str, max_length: usize) -> String {
    // strip ASCII/C1 control characters (except TAB/CR/LF)
    // before the whitespace collapse so a remote peer's ANSI escape
    // sequence planted in a task title / ai_notes / error message
    // can't survive into a terminal-based MCP client (Claude Code,
    // SSH consoles, CI logs). `split_whitespace` only treats Unicode
    // White_Space as a separator; ESC (0x1B), CSI introducer bytes,
    // and the C1 control range pass through unchanged otherwise.
    let stripped: String = value.chars().filter(|c| !is_unsafe_control(*c)).collect();
    let normalized = stripped.split_whitespace().collect::<Vec<_>>().join(" ");
    if max_length == 0 {
        return String::new();
    }

    let mut chars = normalized.chars();
    let mut prefix = String::new();
    for _ in 0..max_length {
        let Some(ch) = chars.next() else {
            return normalized;
        };
        prefix.push(ch);
    }

    if chars.next().is_some() {
        format!("{prefix}...")
    } else {
        normalized
    }
}

/// Alias for `truncate_diagnostic_text` — same logic, kept for call-site clarity.
pub(crate) fn truncate_compact_text(value: &str, max_chars: usize) -> String {
    truncate_diagnostic_text(value, max_chars)
}

/// In-place clamp: every row's `field` (if present and a string) is
/// rewritten through [`truncate_compact_text`] using `max_chars`. Rows
/// that are not objects, or that are missing the field, or whose field
/// is non-string, are skipped.
///
/// This be open-coded three times across `system::overview`,
/// `lists::health`, and `reviews::weekly::snapshot` — every row-shaped
/// JSON envelope that ships user-controlled prose to the AI client
/// runs through the same clamp+fence pattern, so the body lives next
/// to `truncate_compact_text` (its only operation) for one source of
/// truth.
pub(crate) fn clamp_rows_text_field(rows: &mut [Value], field: &str, max_chars: usize) {
    for row in rows {
        let Some(object) = row.as_object_mut() else {
            continue;
        };
        let Some(raw) = object
            .get(field)
            .and_then(Value::as_str)
            .map(str::to_string)
        else {
            continue;
        };
        object.insert(
            field.to_string(),
            Value::String(truncate_compact_text(&raw, max_chars)),
        );
    }
}

/// Whitelist: strip every char that's in a control category EXCEPT
/// TAB/LF/CR (which `split_whitespace` will collapse anyway). Covers
/// C0 (0x00..0x1F), DEL (0x7F), and the C1 range (0x80..0x9F).
fn is_unsafe_control(c: char) -> bool {
    if matches!(c, '\t' | '\n' | '\r') {
        return false;
    }
    c.is_control()
}

/// Thin wrapper around `lorvex_domain::diagnostics::redact_diagnostic_text`
/// so both this MCP diagnostics surface and `app/src-tauri`'s
/// `error_logs::normalize_optional_error_details` share one implementation.
/// Kept as a pub(crate) function (not a `use` re-export) because the
/// MCP module-extraction contract test enumerates symbol-level function
/// signatures expected in this file; removing the declaration would
/// break that contract.
pub(crate) fn redact_diagnostic_text(value: &str) -> String {
    lorvex_domain::diagnostics::redact_diagnostic_text(value)
}

pub(crate) fn sanitize_diagnostic_text(
    value: Option<&str>,
    max_length: usize,
    redact: bool,
) -> Option<String> {
    let raw = value?;
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let processed = if redact {
        redact_diagnostic_text(trimmed)
    } else {
        trimmed.to_string()
    };
    let truncated = truncate_diagnostic_text(&processed, max_length);
    if truncated.is_empty() {
        None
    } else {
        Some(truncated)
    }
}

pub(crate) fn increment_source_count(source_counts: &mut Value, key: &str) {
    if let Some(obj) = source_counts.as_object_mut() {
        if let Some(entry) = obj.get_mut(key) {
            let next = entry.as_i64().unwrap_or(0) + 1;
            *entry = json!(next);
        }
    }
}

#[cfg(test)]
mod tests;
