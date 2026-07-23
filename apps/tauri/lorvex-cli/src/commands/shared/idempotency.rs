//! Shared CLI idempotency cache helpers.
//!
//! Every CLI write surface that mirrors an MCP tool with an
//! `idempotency_key` parameter (`task.create`, `task.update`, ...)
//! consults the same `mcp_idempotency` cache the MCP server uses. On
//! a hit the cached response is returned without re-running the
//! mutation; on a miss the mutation runs and the canonicalized request
//! repr is recorded against the supplied key so a retry short-circuits.
//!
//! The cache lookup is keyed on `(tool_name, idempotency_key)` and
//! validates the request's canonical-JSON checksum so the same key
//! cannot be reused with a different payload — that surfaces as a
//! `Validation` error naming both the prior tool and the new payload
//! drift.

use rusqlite::Connection;

use crate::error::CliError;

/// Validate the supplied idempotency key shape and look it up in the
/// shared cache. Returns `Ok(Some(payload))` on a cache hit (the
/// caller should short-circuit and return the cached response),
/// `Ok(None)` on a miss or when no key was supplied (the caller
/// should run the mutation and then call [`record_cli_idempotency`]
/// with the resulting response).
pub(crate) fn lookup_cli_idempotency(
    conn: &Connection,
    tool_name: &str,
    key: Option<&str>,
    request_repr: &str,
) -> Result<Option<String>, CliError> {
    lorvex_domain::validation::validate_optional_string_length(
        key,
        "idempotency_key",
        lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
    )
    .map_err(|error| CliError::Validation(error.to_string()))?;
    let Some(key) = key else {
        return Ok(None);
    };
    let checksum = lorvex_store::mcp_idempotency::compute_request_checksum(request_repr);
    match lorvex_store::mcp_idempotency::lookup_checked(conn, tool_name, key, &checksum)? {
        lorvex_store::mcp_idempotency::LookupOutcome::Miss => Ok(None),
        lorvex_store::mcp_idempotency::LookupOutcome::Hit(payload) => Ok(Some(payload)),
        lorvex_store::mcp_idempotency::LookupOutcome::ChecksumMismatch {
            stored_tool,
            stored_checksum: _,
            supplied_checksum: _,
        } => Err(CliError::Validation(format!(
            "idempotency_key '{key}' was previously used by tool '{stored_tool}' with a different request payload. Use a fresh idempotency_key for this request."
        ))),
    }
}

/// Persist the mutation's response against the supplied idempotency
/// key so a retry returns the cached response on the next call.
/// No-op when `key` is `None`.
pub(crate) fn record_cli_idempotency(
    conn: &Connection,
    tool_name: &str,
    key: Option<&str>,
    request_repr: &str,
    response: &str,
) -> Result<(), CliError> {
    let Some(key) = key else {
        return Ok(());
    };
    let checksum = lorvex_store::mcp_idempotency::compute_request_checksum(request_repr);
    lorvex_store::mcp_idempotency::record(conn, key, tool_name, &checksum, response)?;
    Ok(())
}
