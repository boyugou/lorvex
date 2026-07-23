//! CLI-side idempotency lookup + record helpers shared by the
//! task-write verbs. The shape mirrors the MCP server's idempotency
//! integration: callers compute a canonical request representation,
//! call [`lookup_cli_idempotency`] before doing any work, and call
//! [`record_cli_idempotency`] with the rendered response after the
//! mutation transaction commits.

use rusqlite::Connection;

use crate::error::CliError;

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
