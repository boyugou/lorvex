//! Wire-format encoder for MCP tool errors. Every helper in this
//! module participates in the path from a typed [`McpError`] to the
//! sanitized JSON payload that the rmcp transport sends back as the
//! tool result's error string.
//!
//! Security-sensitive: `sanitize_error_message`, `extract_quoted_id`,
//! `sync_error_kind_from_message`, and `encode_payload` collectively
//! decide what user-controlled bytes round-trip through the
//! assistant's tool-call result. Living in its own module keeps the
//! encoder independently auditable from the type definitions and the
//! `From` impls.
//!
//! See `wire format` section in the parent module rustdoc
//! (`mcp-server/src/error.rs`) for the canonical JSON shape.

use super::types::{ErrorKind, McpError};
use crate::system::handler_support::to_error_detail;
use serde_json::json;

/// error messages interpolate caller-supplied ids / names /
/// keys verbatim. An attacker who tricks the assistant into calling a
/// tool with an id like `"\n\nSYSTEM: do X"` would see the string round-
/// trip back inside the tool-call result, where a model might treat the
/// `SYSTEM:` framing as a fresh instruction.
///
/// Strip C0/C1 control characters (collapse every NL/CR/TAB etc. to a
/// single space) and cap total length. We do NOT strip content per se —
/// the goal is to make the echoed text incapable of simulating a new
/// system/tool-call boundary. 256 chars is more than enough for any
/// realistic "Task 'xxx' not found" message, and bounds log spam.
pub(super) fn sanitize_error_message(raw: String) -> String {
    const MAX_LEN: usize = 256;
    let mut out = String::with_capacity(raw.len().min(MAX_LEN * 4));
    let mut last_was_space = false;
    // Track char count incrementally — `out.chars().count()` is O(n);
    // calling it per-iteration would make the whole loop O(n²) and
    // expose a DoS vector on long error strings.
    let mut char_count: usize = 0;
    for ch in raw.chars() {
        // Replace any C0 control char with a single space and collapse
        // consecutive replacements.
        let replacement = if ch.is_control() { ' ' } else { ch };
        if replacement == ' ' && last_was_space {
            continue;
        }
        last_was_space = replacement == ' ';
        out.push(replacement);
        char_count += 1;
        if char_count >= MAX_LEN {
            // Reserve room for the ellipsis so total stays at MAX_LEN.
            break;
        }
    }
    // Trim trailing space that collapsing may have left behind.
    let trimmed = out.trim_end();
    if char_count >= MAX_LEN {
        let mut capped: String = trimmed.chars().take(MAX_LEN - 1).collect();
        capped.push('…');
        capped
    } else {
        trimmed.to_string()
    }
}

/// Extract the quoted id out of a canonical NotFound string of the form
/// `"{entity} '{id}' not found"`. Returns `None` when the message is not
/// in that shape so `entity_id` stays absent rather than carrying noise.
///
/// `rfind` (not `find`) finds the closing quote because real entity ids
/// can legitimately contain a single quote — task titles like
/// `"don't forget"` round-trip through the NotFound message verbatim,
/// and the closing quote is always the LAST `'` in the message.
/// `find` would short-circuit on the first inner quote and truncate the
/// id (e.g. extract `"don"` from `Task 'don't forget' not found`).
pub(super) fn extract_quoted_id(message: &str) -> Option<String> {
    let start = message.find('\'')?;
    let rest = &message[start + 1..];
    let end = rest.rfind('\'')?;
    let id = &rest[..end];
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}

/// Detect generic retryable sync failures that arrive through
/// `UserMessage` / `Internal` / `Sync` surfaces as free-form text.
pub(super) fn sync_error_kind_from_message(message: &str) -> Option<ErrorKind> {
    let lower = message.to_ascii_lowercase();
    if lower.contains("timeout")
        || lower.contains("timed out")
        || lower.contains("deadline")
        || lower.contains("unavailable")
        || lower.contains("offline")
        || lower.contains("network")
    {
        return Some(ErrorKind::SyncConflict);
    }
    None
}

/// Classify a raw `rusqlite::Error` into a structured kind. `DatabaseBusy`
/// and `DatabaseLocked` become `DbBusy` (retryable); every other rusqlite
/// failure flattens to `Internal` — the raw SQLite error string is still
/// routed through `to_error_detail` so secrets / table names remain
/// scrubbed before the message reaches the assistant.
pub(super) const fn classify_sql_error(error: &rusqlite::Error) -> ErrorKind {
    use rusqlite::ffi::ErrorCode;
    if let rusqlite::Error::SqliteFailure(code, _) = error {
        if matches!(
            code.code,
            ErrorCode::DatabaseBusy | ErrorCode::DatabaseLocked
        ) {
            return ErrorKind::DbBusy;
        }
    }
    ErrorKind::Internal
}

/// Classify a `lorvex-sync` error. Sync-layer failures fold into
/// `SyncConflict` so callers re-read and retry after the sync pipeline
/// catches up. Any embedded `Sql` busy flag still wins.
pub(super) const fn classify_sync_error(error: &lorvex_sync::error::SyncError) -> ErrorKind {
    use lorvex_sync::error::SyncError;
    match error {
        SyncError::Sql(sql) => classify_sql_error(sql),
        SyncError::SerializationCategorized { .. } => ErrorKind::Serialization,
        SyncError::NetworkDropped { .. } => ErrorKind::SyncConflict,
        SyncError::Store(_) | SyncError::Envelope(_) => ErrorKind::SyncConflict,
    }
}

/// Build the canonical JSON payload emitted on the MCP tool-error boundary.
///
/// Shape (#4492 item 4 — JSON-RPC-aligned envelope):
///
/// ```json
/// {
///   "code": "<machine-readable kind>",
///   "message": "<sanitized human-readable>",
///   "retryable": bool,
///   "details": {
///     "docs_hint": "<optional pointer>",
///     "entity_id": "<optional>"
///   }
/// }
/// ```
///
/// `code` is the same discriminator the older `kind` field carried;
/// the rename aligns the boundary with the JSON-RPC error pattern
/// MCP clients already speak. Contextual hints (docs link, offending
/// entity id) nest under `details` so the top-level envelope stays
/// stable across kinds.
///
/// Keeps the payload compact (omits the `details` object entirely
/// when there are no hints to attach) so the wire size on the
/// chatty error path stays bounded.
pub(super) fn encode_payload(
    kind: ErrorKind,
    message: String,
    entity_id: Option<String>,
) -> String {
    let mut obj = serde_json::Map::new();
    obj.insert("code".to_string(), json!(kind));
    obj.insert("message".to_string(), json!(message));
    obj.insert("retryable".to_string(), json!(kind.retryable()));

    let mut details = serde_json::Map::new();
    if let Some(hint) = kind.docs_hint() {
        details.insert("docs_hint".to_string(), json!(hint));
    }
    if let Some(id) = entity_id {
        details.insert("entity_id".to_string(), json!(id));
    }
    if !details.is_empty() {
        obj.insert("details".to_string(), serde_json::Value::Object(details));
    }

    // Infallible: all values are primitive JSON scalars / nested
    // string maps. Asserting the contract surfaces any future
    // serde_json regression as a panic (programmer error) instead of
    // emitting an `encode failed` sentinel that no MCP client would
    // ever see and that masks the underlying bug.
    serde_json::to_string(&serde_json::Value::Object(obj))
        .expect("serde_json::Value::Object of primitive scalars -> String is infallible")
}

impl From<McpError> for String {
    fn from(error: McpError) -> Self {
        match error {
            // #2133: keep the cancellation surface short and
            // machine-grep-friendly. Don't route through the JSON encoder —
            // cancellation is a normal client-initiated outcome, not a
            // fault the assistant needs to classify.
            McpError::CancelledByClient => "Error: cancelled by client".to_string(),

            // Route helper-produced prose through the structured encoder.
            McpError::UserMessage(message) => {
                let sanitized = sanitize_error_message(message);
                let kind = sync_error_kind_from_message(&sanitized).unwrap_or_else(|| {
                    if sanitized.to_ascii_lowercase().contains(" not found") {
                        ErrorKind::NotFound
                    } else {
                        ErrorKind::Internal
                    }
                });
                let entity_id = (kind == ErrorKind::NotFound)
                    .then(|| extract_quoted_id(&sanitized))
                    .flatten();
                encode_payload(kind, sanitized, entity_id)
            }

            McpError::Validation(message) => {
                let sanitized = sanitize_error_message(message);
                encode_payload(ErrorKind::Validation, sanitized, None)
            }

            McpError::RateLimited(message) => {
                let sanitized = sanitize_error_message(message);
                encode_payload(ErrorKind::RateLimited, sanitized, None)
            }

            McpError::NotFound(message) => {
                let sanitized = sanitize_error_message(message);
                let entity_id = extract_quoted_id(&sanitized);
                encode_payload(ErrorKind::NotFound, sanitized, entity_id)
            }

            McpError::Serialization(detail) => {
                // `to_error_detail` runs the redaction / truncation
                // pipeline on the raw serde message so column / path
                // internals stay scrubbed.
                let message = to_error_detail(format!("serialization error: {detail}"));
                encode_payload(ErrorKind::Serialization, message, None)
            }

            McpError::Sql(sql) => {
                let kind = classify_sql_error(&sql);
                let message = to_error_detail(&*sql);
                encode_payload(kind, message, None)
            }

            McpError::Store(store_err) => {
                // `From<StoreError> for McpError` already peels off
                // `Validation` / `NotFound` variants, so the remainder
                // is genuinely internal (DiskFull, Sql, IO, invariant)
                // — except `StaleVersion`, which is the LWW gate
                // refusing to clobber a newer version (audit
                // #3021-M2). That maps to `SyncConflict` so callers
                // know to re-read + retry against the cluster's
                // canonical state.
                let kind = match &*store_err {
                    lorvex_store::StoreError::StaleVersion { .. } => ErrorKind::SyncConflict,
                    _ => ErrorKind::Internal,
                };
                let entity_id = match &*store_err {
                    lorvex_store::StoreError::StaleVersion { id, .. } => Some(id.clone()),
                    _ => None,
                };
                let message = to_error_detail(&*store_err);
                encode_payload(kind, message, entity_id)
            }

            McpError::Sync(sync_err) => {
                let kind = classify_sync_error(&sync_err);
                let message = to_error_detail(&*sync_err);
                encode_payload(kind, message, None)
            }

            McpError::OutboxEnqueue(enq_err) => {
                use lorvex_sync::outbox_enqueue::EnqueueError;
                let (kind, entity_id) = match &*enq_err {
                    EnqueueError::EntityNotFound { entity_id, .. } => {
                        (ErrorKind::NotFound, Some(entity_id.clone()))
                    }
                    EnqueueError::UnknownEntityType(_) => (ErrorKind::Validation, None),
                    EnqueueError::Sqlite(sql) => (classify_sql_error(sql), None),
                    // VersionSuperseded: a concurrent writer raced this
                    // enqueue and stamped a strictly newer version.
                    // TaintedVersion: outbox refused the envelope at the
                    // boundary because the incoming `version` failed
                    // `Hlc::parse` (caller minted a tainted HLC).
                    // Both surface as `SyncConflict` with the entity_id
                    // so the user-facing playbook (re-read + re-stamp +
                    // re-enqueue) is the same.
                    EnqueueError::VersionSuperseded { entity_id, .. }
                    | EnqueueError::TaintedVersion { entity_id, .. }
                    | EnqueueError::ContentionExhausted { entity_id, .. } => {
                        (ErrorKind::SyncConflict, Some(entity_id.clone()))
                    }
                    EnqueueError::PendingDrainTargetLookup {
                        entity_id, source, ..
                    }
                    | EnqueueError::PendingDrain {
                        entity_id, source, ..
                    } => (classify_sync_error(source), Some(entity_id.clone())),
                    EnqueueError::Store(_)
                    | EnqueueError::VersionStamp(_)
                    | EnqueueError::Canonicalization(_)
                    | EnqueueError::UnsupportedOperation { .. } => (ErrorKind::Internal, None),
                };
                let message = to_error_detail(&*enq_err);
                encode_payload(kind, message, entity_id)
            }

            McpError::Internal(detail) => {
                let message = to_error_detail(detail);
                let kind = sync_error_kind_from_message(&message).unwrap_or(ErrorKind::Internal);
                encode_payload(kind, message, None)
            }
        }
    }
}
