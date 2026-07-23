/// Translates internal errors (SQLite, serde, IO) into user-facing messages.
/// Known SQLite/Rust internals are mapped to friendly messages; unrecognized
/// errors are sanitized + truncated before being returned so the AI client
/// has enough signal to retry / adapt, without leaking table / column names
/// or a stack trace. The unmapped branch must NOT discard the raw error —
/// the assistant needs distinct signal for "database busy, retry me" vs
/// "payload validation failed, give up", or the AI-as-write-interface
/// contract collapses into a single generic error string.
pub(crate) fn to_error_message(error: impl std::fmt::Display) -> String {
    format!("Error: {}", to_error_detail(error))
}

/// Produces the same sanitized human-readable body as [`to_error_message`]
/// but without the `Error: ` prefix, so it can be embedded inside the
/// structured JSON error payload (#2182) emitted on the MCP tool boundary.
///
/// All redaction / truncation guarantees (secret scrubbing, 200-char cap
/// on unmapped detail, SQLite-error mapping to friendly language) are
/// preserved — this is the single source of truth for both the legacy
/// prose path and the structured-payload path.
pub(crate) fn to_error_detail(error: impl std::fmt::Display) -> String {
    let raw = error.to_string();
    if let Some(friendly) = lorvex_store::error_sanitize::sanitize_sqlite_error(&raw) {
        tracing::warn!(
            diagnostic_detail = %lorvex_domain::diagnostics::redact_diagnostic_text(&raw),
            mapped_message = %friendly,
            "MCP internal error mapped to safe user-facing message"
        );
        return friendly;
    }
    let detail = sanitize_unmapped_detail(&raw);
    tracing::warn!(
        diagnostic_detail = %detail,
        "MCP internal error surfaced with sanitized detail"
    );
    // matches the lowercase-after-`Error: ` convention
    // tightened in pass 11. The McpError envelope prepends `Error: `
    // before this string lands on the wire, so the visible message
    // reads "Error: an internal error occurred. Details: …".
    format!("an internal error occurred. Details: {detail} (please report if persistent).",)
}

/// Strip SQL/Rust internals from an otherwise-unknown error string so the
/// result is safe to return over MCP. Keeps a short, actionable hint
/// (first line only, truncated, sensitive tokens redacted) — nothing that
/// could leak a user's data or a table/column name.
fn sanitize_unmapped_detail(raw: &str) -> String {
    // First line only: Rust error chains often put the high-level class
    // on the first line and internals on subsequent lines.
    let first = raw.lines().next().unwrap_or(raw).trim();
    let redacted = lorvex_domain::diagnostics::redact_diagnostic_text(first);
    // Hard cap at 200 chars so the generic prefix stays the dominant signal.
    if redacted.chars().count() <= 200 {
        redacted
    } else {
        let truncated: String = redacted.chars().take(200).collect();
        format!("{truncated}…")
    }
}

// Helper messages omit the `Error: ` prefix. The `McpError::NotFound`
// / `McpError::UserMessage` envelopes route the result through
// `encode_payload`, which wraps the message in a structured
// `{kind: "not_found", message: "<prose>", entity_id: "<id>", ...}`
// payload — the `kind` field is the canonical machine-readable
// classifier, and an inline `Error: ` prefix would duplicate it on
// the wire. Sibling sites that do NOT route through these helpers
// (`format!("Task '{id}' not found")` in
// `server_lists/mutations/update.rs`,
// `server_task_lifecycle/writes/reopen.rs`, etc.) follow the same
// no-prefix convention so the helper-vs-inline shape stays
// consistent.
pub(crate) fn not_found_error(entity: &str, id: &str) -> String {
    format!("{entity} \'{id}\' not found")
}

pub(crate) fn load_failed_error(entity: &str, id: &str) -> String {
    format!("failed to load {entity} \'{id}\'")
}

#[cfg(test)]
mod tests;
