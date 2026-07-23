use super::detect::path_is_executable_binary;
use super::model::{
    priority_for_kind_str, McpHostAuthorityKind, McpHostAuthorityRecord, McpHostWriteOutcome,
    MCP_HOST_APP, MCP_HOST_CLI,
};
use rusqlite::OptionalExtension;
use std::path::Path;

/// Claim the active MCP host choice in the shared `mcp_host_authority`
/// table using the normal host-priority rules.
///
/// The CAS predicate is
/// `excluded.priority > stored.priority OR
///  (excluded.priority == stored.priority AND excluded.updated_at > stored.updated_at)`,
/// so a same-ms boot race between two same-priority surfaces is
/// resolved by `updated_at` rather than by lex-compare on the host
/// string (which would silently re-shuffle when a new kind is added).
/// A stale write — lower `priority`, or older `updated_at` at equal
/// priority — cannot overwrite a fresher decision.
///
/// Returns the typed [`McpHostWriteOutcome`].
pub fn claim_mcp_host_authority(
    conn: &rusqlite::Connection,
    host: McpHostAuthorityKind,
) -> crate::RuntimeResult<McpHostWriteOutcome> {
    let host_path = authority_host_path(host);
    let host_str = host.as_str();
    let updated_at = crate::local_state::current_timestamp_ms();
    let priority = i64::from(priority_for_kind_str(host_str));

    let affected = conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at) \
         VALUES (1, ?1, ?2, ?3, ?4) \
         ON CONFLICT(id) DO UPDATE SET \
             host = excluded.host, \
             priority = excluded.priority, \
             host_path = excluded.host_path, \
             updated_at = excluded.updated_at \
         WHERE excluded.priority > mcp_host_authority.priority \
            OR (excluded.priority = mcp_host_authority.priority \
                AND excluded.updated_at > mcp_host_authority.updated_at)",
        rusqlite::params![host_str, priority, host_path.as_deref(), updated_at],
    )?;

    if affected > 0 {
        return Ok(McpHostWriteOutcome::Stored);
    }

    // CAS rejected. Read the row AFTER the failed UPSERT to classify
    // the outcome from the current row state. Reading post-CAS rather
    // than pre-CAS is required to close the TOCTOU window: with a
    // pre-UPSERT SELECT, same-priority contention with a third host
    // kind could give a false-positive `AlreadyCorrect` (the snapshot
    // would show our own desired host, but a different host could
    // write between our SELECT and UPSERT and now hold the row at our
    // priority). Reading post-CAS collapses the window — the row we
    // observe is the one our UPSERT lost to. Under SQLite's
    // serializable transaction model (every caller wraps writes in
    // BEGIN IMMEDIATE via the connection pool), this is fully
    // correct; the lone
    // pre-UPSERT SELECT was a redundant roundtrip.
    classify_post_cas_outcome(conn, host_str)
}

/// Classify the outcome of a CAS-rejected upsert by re-reading the
/// authority row. If the stored host matches the value we tried to
/// write, the row is already in the desired state
/// ([`McpHostWriteOutcome::AlreadyCorrect`]); otherwise some peer won
/// the race ([`McpHostWriteOutcome::LostRace`]). Shared by
/// [`claim_mcp_host_authority`] and [`classify_failed_app_reclaim`] so
/// the post-CAS classification rule lives in one place.
fn classify_post_cas_outcome(
    conn: &rusqlite::Connection,
    desired_host: &str,
) -> crate::RuntimeResult<McpHostWriteOutcome> {
    let stored_host = read_mcp_host_authority_record(conn)?.map(|record| record.host);
    Ok(match stored_host {
        Some(found) if found == desired_host => McpHostWriteOutcome::AlreadyCorrect,
        _ => McpHostWriteOutcome::LostRace,
    })
}

/// Let the App reclaim MCP host authority when the standalone CLI binary is
/// absent.
///
/// The normal claim path intentionally gives `cli` a higher priority than
/// `app`, so a stale `cli` row would otherwise block the packaged macOS app /
/// app-only channel forever after the user uninstalls the CLI. This explicit
/// reclaim path is the only lower-priority overwrite: callers must pass the
/// current CLI detection result, and the function refuses to write when a CLI
/// binary is still detected.
pub fn reclaim_app_mcp_host_authority_when_cli_missing(
    conn: &rusqlite::Connection,
    cli_detected: bool,
) -> crate::RuntimeResult<Option<McpHostWriteOutcome>> {
    if cli_detected {
        return Ok(None);
    }

    match read_mcp_host_authority_record(conn)? {
        None => store_app_mcp_host_authority_if_absent(conn).map(Some),
        Some(record) if record.host == MCP_HOST_APP => {
            Ok(Some(McpHostWriteOutcome::AlreadyCorrect))
        }
        Some(record) if recorded_cli_path_is_missing(&record) => {
            reclaim_app_mcp_host_authority_from_cli_record(conn, &record).map(Some)
        }
        Some(_) => Ok(None),
    }
}

fn store_app_mcp_host_authority_if_absent(
    conn: &rusqlite::Connection,
) -> crate::RuntimeResult<McpHostWriteOutcome> {
    let updated_at = crate::local_state::current_timestamp_ms();
    let priority = i64::from(priority_for_kind_str(MCP_HOST_APP));
    let affected = conn.execute(
        "INSERT INTO mcp_host_authority (id, host, priority, host_path, updated_at) \
         VALUES (1, ?1, ?2, NULL, ?3) \
         ON CONFLICT(id) DO NOTHING",
        rusqlite::params![MCP_HOST_APP, priority, updated_at],
    )?;
    if affected > 0 {
        return Ok(McpHostWriteOutcome::Stored);
    }
    classify_failed_app_reclaim(conn)
}

pub(super) fn reclaim_app_mcp_host_authority_from_cli_record(
    conn: &rusqlite::Connection,
    record: &McpHostAuthorityRecord,
) -> crate::RuntimeResult<McpHostWriteOutcome> {
    let Some(recorded_path) = record.host_path.as_deref() else {
        return Ok(McpHostWriteOutcome::LostRace);
    };
    let updated_at = crate::local_state::current_timestamp_ms();
    let priority = i64::from(priority_for_kind_str(MCP_HOST_APP));
    let affected = conn.execute(
        "UPDATE mcp_host_authority \
         SET host = ?1, priority = ?2, host_path = NULL, updated_at = ?3 \
         WHERE id = 1 \
           AND host = ?4 \
           AND host_path = ?5 \
           AND updated_at = ?6",
        rusqlite::params![
            MCP_HOST_APP,
            priority,
            updated_at,
            MCP_HOST_CLI,
            recorded_path,
            record.updated_at
        ],
    )?;
    if affected > 0 {
        return Ok(McpHostWriteOutcome::Stored);
    }
    classify_failed_app_reclaim(conn)
}

fn classify_failed_app_reclaim(
    conn: &rusqlite::Connection,
) -> crate::RuntimeResult<McpHostWriteOutcome> {
    classify_post_cas_outcome(conn, MCP_HOST_APP)
}

fn authority_host_path(host: McpHostAuthorityKind) -> Option<String> {
    match host {
        McpHostAuthorityKind::Cli => std::env::current_exe()
            .ok()
            .map(|path| path.to_string_lossy().into_owned()),
        McpHostAuthorityKind::App => None,
    }
}

fn recorded_cli_path_is_missing(record: &McpHostAuthorityRecord) -> bool {
    record.host == MCP_HOST_CLI
        && record
            .host_path
            .as_deref()
            .is_some_and(|path| !path_is_executable_binary(Path::new(path)))
}

pub(super) fn read_mcp_host_authority_record(
    conn: &rusqlite::Connection,
) -> crate::RuntimeResult<Option<McpHostAuthorityRecord>> {
    let record = conn
        .query_row(
            "SELECT host, host_path, updated_at FROM mcp_host_authority WHERE id = 1",
            [],
            |row| {
                Ok(McpHostAuthorityRecord {
                    host: row.get(0)?,
                    host_path: row.get(1)?,
                    updated_at: row.get(2)?,
                })
            },
        )
        .optional()?;
    Ok(record)
}

/// Read the current MCP host authority from the shared
/// `mcp_host_authority` table. Returns None if no authority has been
/// set (first run).
///
/// Routes through [`read_mcp_host_authority_record`] so the SELECT
/// projection (`host, host_path, updated_at`) lives in one place.
/// Pre-fix this function ran a parallel
/// `SELECT host FROM mcp_host_authority WHERE id = 1` that would
/// drift if a column was renamed or the row's PK shape changed —
/// the unused `host_path` / `updated_at` columns add no real cost
/// because SQLite already streamed the whole row through the index
/// pin.
pub fn get_mcp_host_authority(conn: &rusqlite::Connection) -> crate::RuntimeResult<Option<String>> {
    Ok(read_mcp_host_authority_record(conn)?.map(|record| record.host))
}
