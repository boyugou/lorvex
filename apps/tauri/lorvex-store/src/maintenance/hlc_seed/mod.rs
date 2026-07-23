//! HLC seed recovery: bump in-memory HLC state past the highest HLC
//! observed locally at process startup so the monotonicity invariant
//! survives app restarts with wall-clock drift.
//!
//! `HlcState::new(suffix)` initialises `(last_physical_ms: 0, counter:
//! 0)` on every process launch. If the wall clock drifts backward
//! between runs (NTP correction, DST transition on systems that
//! mishandle it, VM pause/resume), the next `generate()` would produce
//! an HLC strictly less than the last one the device emitted before
//! shutdown — breaking the global LWW invariant.
//!
//! To avoid that, the state is seeded from the highest HLC the device
//! has ever written locally. That value is preserved in every synced
//! entity's `version` column (set by
//! `lorvex_sync::version_stamp::stamp_entity_version` at enqueue time)
//! plus the `sync_outbox`, `sync_tombstones`, and `sync_conflict_log`
//! audit trails. We union all of them, take the max, and `update_on_
//! receive` past it.

use lorvex_domain::hlc::{Hlc, HlcSurface};
use lorvex_domain::hlc_state::HlcState;
use lorvex_runtime::device_id_to_hlc_suffix;
use rusqlite::Connection;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

/// Every table on which the local device persists an HLC `version`
/// value. Every synced aggregate root, every independent child, every
/// edge, plus the sync audit tables. Keep alphabetized for diffs.
const HLC_BEARING_TABLES: &[(&str, &str)] = &[
    ("calendar_events", "version"),
    ("calendar_subscriptions", "version"),
    ("current_focus", "version"),
    ("daily_reviews", "version"),
    ("focus_schedule", "version"),
    ("habit_completions", "version"),
    ("habit_reminder_policies", "version"),
    ("habits", "version"),
    ("lists", "version"),
    ("memories", "version"),
    ("memory_revisions", "version"),
    ("preferences", "version"),
    ("sync_conflict_log", "winner_version"),
    ("sync_outbox", "version"),
    ("sync_tombstones", "version"),
    ("tags", "version"),
    ("task_calendar_event_links", "version"),
    ("task_checklist_items", "version"),
    ("task_dependencies", "version"),
    ("task_reminders", "version"),
    ("task_tags", "version"),
    ("tasks", "version"),
];

/// Scan every HLC-bearing table locally and return the highest HLC
/// ever emitted by *this* device — across every surface suffix
/// (`app`, `mcp`, `cli`) that the device_id can produce — as long as
/// it is a structurally-valid HLC string.
///
/// a single device_id produces three distinct suffixes,
/// one per [`HlcSurface`]. A new Tauri-app process must seed past
/// HLCs written by the MCP server and the CLI on the same
/// device; otherwise a wall-clock regression (NTP correction, VM
/// resume) could let the app emit an HLC ordered before an MCP HLC
/// still present in the local DB. Aggregating across all three
/// suffixes preserves the per-device monotonicity invariant the LWW
/// pipeline depends on.
///
/// Returning `None` means the device has no prior local history
/// (fresh install) under any surface — `HlcState::new` is already
/// safe to start from 0.
pub fn max_local_hlc_for_device(
    conn: &Connection,
    device_id: &str,
) -> Result<Option<Hlc>, rusqlite::Error> {
    let suffixes: Vec<String> = HlcSurface::all()
        .iter()
        .map(|s| device_id_to_hlc_suffix(device_id, *s))
        .collect();
    Ok(max_local_hlc_for_suffixes(conn, &suffixes))
}

/// Internal primitive used by both `max_local_hlc_for_device` and
/// the `seed_hlc_state_from_local_history` path, which needs to
/// aggregate over a pre-computed suffix list.
fn max_local_hlc_for_suffixes(conn: &Connection, suffixes: &[String]) -> Option<Hlc> {
    if suffixes.is_empty() {
        return None;
    }
    let queries = max_hlc_queries();
    let mut best: Option<Hlc> = None;
    for suffix in suffixes {
        let suffix_like_pattern = format!("%_{suffix}");
        for sql in queries {
            // The `version LIKE '%_{suffix}'` filter keeps the query
            // from scanning remote-origin rows — only HLCs this
            // device emitted under this surface. HLCs are ASCII so
            // the pattern can't misbehave on composed Unicode.
            let candidate: Option<String> = conn
                .query_row(sql, [&suffix_like_pattern], |row| row.get(0))
                .unwrap_or(None);
            if let Some(raw) = candidate {
                if let Ok(hlc) = Hlc::parse(&raw) {
                    if best.as_ref().is_none_or(|current| hlc > *current) {
                        best = Some(hlc);
                    }
                }
            }
        }
    }
    best
}

/// Process-wide cache of the per-table `SELECT MAX(...) WHERE ... LIKE ?1`
/// SQL strings rendered from [`HLC_BEARING_TABLES`]. The `(table, column)`
/// set is fixed at compile time and the pattern parameter is bound at
/// query time, so the SQL itself only needs to be formatted once per
/// process. Without the cache, every `seed_hlc_state_from_local_history`
/// call (each test, each app/MCP/CLI startup) re-rendered all 25 SQL
/// strings × every surface suffix.
fn max_hlc_queries() -> &'static [String] {
    static CACHE: OnceLock<Vec<String>> = OnceLock::new();
    CACHE.get_or_init(|| {
        HLC_BEARING_TABLES
            .iter()
            .map(|(table, column)| {
                // Defense-in-depth: the `(table, column)` set is closed
                // and authored in this file, but `format!`-interpolating
                // either into SQL still warrants an explicit guard so a
                // future row added to `HLC_BEARING_TABLES` with a typo
                // (e.g. a quote, space, or comment delimiter) panics
                // here instead of silently producing malformed SQL. The
                // assert runs once per process at cache init time.
                lorvex_domain::assert_safe_sql_identifier(table);
                lorvex_domain::assert_safe_sql_identifier(column);
                format!("SELECT MAX({column}) FROM {table} WHERE {column} LIKE ?1")
            })
            .collect()
    })
}

/// Seed a freshly-constructed `HlcState` by bumping it past the
/// highest HLC this device has persisted — across every
/// surface. Returns the high-water HLC that was folded in, if any.
///
/// Must be called inside `init_hlc` (app, mcp-server, cli) before the
/// first `generate()` — otherwise a post-restart write can silently
/// regress below a pre-restart HLC written by **any** surface on the
/// same device.
pub fn seed_hlc_state_from_local_history(
    conn: &Connection,
    device_id: &str,
    state: &mut HlcState,
) -> Result<Option<Hlc>, rusqlite::Error> {
    let Some(observed) = max_local_hlc_for_device(conn, device_id)? else {
        return Ok(None);
    };

    let wall_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64);
    state.update_on_receive(&observed, wall_ms);
    Ok(Some(observed))
}

#[cfg(test)]
mod tests;
