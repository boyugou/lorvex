use crate::error::McpError;
use lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED;
use rusqlite::{Connection, OptionalExtension};

/// every memory tool — read or write — runs through
/// this gate before touching the database. Without it, the
/// `memory_lock_enabled` preference (which the user toggles from
/// Settings to keep AI memory private during a sensitive session) was
/// purely cosmetic at the MCP boundary: the frontend gated UI
/// rendering, but a buggy or hostile assistant could still call
/// \`get_ai_memory\`, \`write_memory\`, \`delete_memory\`, etc. without
/// any backend-side check.
///
/// The lock pref is stored as the canonical preference JSON shape
/// (`true` / `false`); we strip surrounding quotes if a stringified
/// boolean ever lands in the row. Missing rows mean "lock disabled"
/// — the user has never enabled the toggle.
pub(super) fn require_memory_unlocked(conn: &Connection) -> Result<(), McpError> {
    let raw: Option<String> = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            [PREF_MEMORY_LOCK_ENABLED],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    let Some(raw) = raw else {
        return Ok(());
    };
    let trimmed = raw.trim();
    let normalized = trimmed
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .unwrap_or(trimmed);
    if normalized.eq_ignore_ascii_case("true") {
        return Err(McpError::Validation(
            "AI memory is locked by the user. Ask them to unlock it from Settings → Privacy → Memory before reading or writing memory."
                .to_string(),
        ));
    }
    Ok(())
}
