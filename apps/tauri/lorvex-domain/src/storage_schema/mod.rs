//! Pure helpers for canonical SQLite schema semantics shared by store and sync.

/// Maximum allowed byte size for a sync envelope payload — both the
/// canonicalized JSON over the wire and the field-level
/// `raw_payload_json` row that lands in `sync_payload_shadow` /
/// `sync_pending_inbox`.
///
/// the same 256 KiB constant was declared
/// independently in three places (`lorvex_sync_payload::payload_shadow::
/// MAX_RAW_PAYLOAD_JSON_BYTES`, `lorvex_sync::canonicalize::
/// MAX_CANONICAL_PAYLOAD_BYTES`; the canonicalize one carried its own
/// copy and could drift). Canonicalizing the value here in `lorvex-domain` —
/// the lowest layer in the dependency graph — lets every consumer
/// re-export from a single source of truth.
///
/// 256 KiB is well above legitimate task bodies + checklists + tags
/// plus metadata (the MCP layer caps individual fields well below
/// this) while staying far below DoS territory; the cap is the
/// last-line defense against a peer pushing a single 100 MB string,
/// a million flat keys, or a wide array through the sync apply
/// pipeline (#2860).
pub const MAX_PAYLOAD_BYTES: usize = 256 * 1024;

/// Returns true when a SQLite INTEGER column is semantically a JSON boolean
/// on external payload surfaces such as sync envelopes and export archives.
pub const SQLITE_BOOL_COLUMNS: &[(&str, &str)] = &[
    ("habits", "archived"),
    ("calendar_events", "all_day"),
    ("calendar_subscriptions", "enabled"),
    ("habit_reminder_policies", "enabled"),
];

pub fn is_sqlite_bool_column(table: &str, column: &str) -> bool {
    SQLITE_BOOL_COLUMNS
        .iter()
        .any(|(known_table, known_column)| *known_table == table && *known_column == column)
}

#[cfg(test)]
mod tests;
