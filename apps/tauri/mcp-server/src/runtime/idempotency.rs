//! Per-tool idempotency cache helpers.
//!
//! Idempotent retry semantics MUST gate on the request payload, not
//! just the caller-supplied `key`. A pure stringy-key lookup is a
//! cache-poisoning hazard: a list could be deleted between two
//! retries that share an idempotency token, and the second retry
//! would return the cached "success" payload referring to a row the
//! assistant had since destroyed.
//!
//! This helper closes the gap with a payload-checksum gate. Callers
//! pass:
//!
//! 1. The MCP `tool_name` whose response may be replayed.
//! 2. The idempotency `key` (caller-supplied stringy token).
//! 3. A canonical `request_repr` of the *current* request — the
//!    serialized `args` shape works fine because it carries every
//!    field that distinguishes one call from another.
//!
//! [`cache_lookup`] hashes the repr and consults the store. On a
//! same-tool match it returns the cached response. On a stored-row
//! checksum mismatch it returns a Validation `McpError` that names the
//! prior tool — the assistant can decide whether to retry under a
//! fresh key.
//!
//! [`cache_record`] writes the current repr's checksum alongside the
//! response payload so future lookups can detect collisions.

use crate::error::McpError;
use lorvex_store::mcp_idempotency::{self, compute_request_checksum, LookupOutcome};
use rusqlite::Connection;
use serde::Serialize;
use serde_json::Value;

/// Build the canonical request representation for an idempotency
/// cache key.
///
///  M11:
/// which renders the struct's fields in declaration order. A future
/// derive reorder (a refactor that splits `args` into a wrapped enum,
/// or adds a field) would silently invalidate every existing cache
/// entry — every retried request would Validation-fail with
/// `ChecksumMismatch` until the cache eventually GC'd. Route through
/// `lorvex_domain::canonical_json::canonicalize_json` so the
/// representation is sorted-key compact JSON; reordering the struct
/// derives no longer flips the checksum.
///
/// #3051 M12: every batch/preview tool whose args carry a `dry_run`
/// flag included it in the cache key. Re-calling the same
/// `idempotency_key` with `dry_run:true` then `dry_run:false` then
/// surfaced `ChecksumMismatch` instead of running the real call. The
/// caller is supposed to be able to "preview, then commit" under the
/// same idempotency token. Strip `dry_run` from the canonicalized
/// representation so preview-then-commit lands in the same cache
/// slot. (The `is_preview` envelope field is logged separately
/// downstream so the audit trail still distinguishes the two.)
pub(crate) fn canonical_request_repr<T: Serialize>(args: &T) -> Result<String, McpError> {
    let mut value = serde_json::to_value(args)?;
    if let Value::Object(ref mut map) = value {
        // M12: dry_run is a routing flag, not a request-shape
        // discriminator. Drop it before checksumming so a preview
        // and the real call share a cache slot.
        map.remove("dry_run");
    }
    lorvex_domain::canonical_json::canonicalize_json(&value).map_err(|e| {
        McpError::Validation(format!("idempotency request canonicalization failed: {e}"))
    })
}

/// Look up a cached idempotent response, gated on a payload checksum.
///
/// Returns `Ok(Some(payload))` on a true cache hit (tool/key match +
/// checksum match), `Ok(None)` on a miss, or a Validation `McpError`
/// when the stored checksum disagrees with the supplied `request_repr`
/// — that outcome means the same key has been reused for a
/// semantically different same-tool request and the cached response
/// would lie to the caller.
fn cache_lookup(
    conn: &Connection,
    tool_name: &str,
    key: &str,
    request_repr: &str,
) -> Result<Option<String>, McpError> {
    let checksum = compute_request_checksum(request_repr);
    match mcp_idempotency::lookup_checked(conn, tool_name, key, &checksum)? {
        LookupOutcome::Miss => Ok(None),
        LookupOutcome::Hit(payload) => Ok(Some(payload)),
        LookupOutcome::ChecksumMismatch {
            stored_tool,
            stored_checksum: _,
            supplied_checksum: _,
        } => Err(McpError::Validation(format!(
            "idempotency_key '{key}' was previously used by tool '{stored_tool}' \
             with a different request payload. The cache cannot replay the prior \
             response without lying. Use a fresh idempotency_key for this request."
        ))),
    }
}

/// Validate the idempotency key length and consult the cache when a
/// key was supplied. Returns the cached payload on a hit, `None` on a
/// miss or when no key was supplied. Bundles the
/// `validate_optional_string_length` length guard with the
/// `if let Some(key) … cache_lookup …` pattern so every write tool
/// can call one helper instead of repeating both steps verbatim.
pub(crate) fn lookup_cached(
    conn: &Connection,
    tool_name: &str,
    idempotency_key: Option<&str>,
    request_repr: &str,
) -> Result<Option<String>, McpError> {
    crate::tasks::validation::validate_optional_string_length(
        idempotency_key,
        "idempotency_key",
        lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
    )?;
    let Some(key) = idempotency_key else {
        return Ok(None);
    };
    cache_lookup(conn, tool_name, key, request_repr)
}

/// Record an idempotent response when an `idempotency_key` was
/// supplied, otherwise do nothing. Companion to [`lookup_cached`] —
/// every callsite that consults the cache via that helper records its
/// response through this one so the "key was/was not supplied"
/// branching lives in one place.
pub(crate) fn record_if_keyed(
    conn: &Connection,
    idempotency_key: Option<&str>,
    tool_name: &str,
    request_repr: &str,
    response: &str,
) -> Result<(), McpError> {
    let Some(key) = idempotency_key else {
        return Ok(());
    };
    cache_record(conn, key, tool_name, request_repr, response)
}

/// Record a fresh idempotent response, hashing the request repr so a
/// subsequent retry under the same key with a different payload is
/// detectable.
pub(crate) fn cache_record(
    conn: &Connection,
    key: &str,
    tool_name: &str,
    request_repr: &str,
    response: &str,
) -> Result<(), McpError> {
    let checksum = compute_request_checksum(request_repr);
    mcp_idempotency::record(conn, key, tool_name, &checksum, response)?;
    Ok(())
}

/// route a write tool through the
/// payload-checksum-gated idempotency cache. Used by the workflow
/// router for tools whose handler signature does not natively accept
/// the `idempotency_key` (e.g. `create_habit`'s
/// per-field-positional handler shape).
///
/// The closure is invoked only on a cache miss; on a hit the cached
/// response is returned without ever running the closure.
///
/// # Length guard
///
/// `idempotency_key` is gated against
/// `MAX_SHORT_TEXT_LENGTH` so a malicious or buggy client cannot
/// stuff multi-MB strings into the cache key column.
pub(crate) fn run_with_cache<F, T>(
    conn: &Connection,
    tool_name: &str,
    request_repr: &str,
    idempotency_key: Option<&str>,
    handler: F,
) -> Result<String, McpError>
where
    F: FnOnce(&Connection) -> Result<String, T>,
    T: Into<McpError>,
{
    if let Some(cached) = lookup_cached(conn, tool_name, idempotency_key, request_repr)? {
        return Ok(cached);
    }
    let response = handler(conn).map_err(Into::into)?;
    record_if_keyed(conn, idempotency_key, tool_name, request_repr, &response)?;
    Ok(response)
}
