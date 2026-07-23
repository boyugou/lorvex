//! Sync conflict log — records merge outcomes for debugging and Settings UI.
//!
//! The `sync_conflict_log` table is local-only (never synced). One INSERT per
//! conflict. Conflicts are rare in single-user multi-device scenarios, but
//! invaluable for debugging sync issues when they occur.
//!
//! See spec Section 23: Sync Conflict Log.

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;

/// A sync conflict resolution record.
///
/// `resolution_type` uses `Cow<'static, str>` because every production
/// caller passes one of the `naming::RESOLUTION_*` `&'static str`
/// constants. A `String` field would force an allocation per envelope
/// (`naming::RESOLUTION_X.to_string()`) even on the `WHERE NOT EXISTS`
/// dedupe path that ultimately writes nothing. The `Cow` lets static
/// callers pass `Cow::Borrowed(naming::RESOLUTION_X)` and keeps the
/// option open for tests / row-read paths to construct owned `String`s
/// via `Cow::Owned`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ConflictLogEntry {
    /// Row ID (autoincrement). 0 or omitted on input (assigned by DB).
    pub id: i64,
    /// Canonical entity type name.
    ///
    /// `Cow<'static, str>` (mirrors `resolution_type`) so envelope-driven
    /// callers can pass `Cow::Borrowed(envelope.entity_type.as_str())`
    /// allocation-free, while a small set of synthetic-source rows
    /// (`sync_pending_inbox` horizon-check) can pass
    /// `Cow::Borrowed("sync_pending_inbox")` without inventing an
    /// `EntityKind` variant for diagnostic-only sentinels.
    pub entity_type: Cow<'static, str>,
    /// Entity identity.
    pub entity_id: String,
    /// HLC version of the winning entity.
    pub winner_version: String,
    /// HLC version of the losing entity.
    pub loser_version: String,
    /// Device that produced the losing entity.
    pub loser_device_id: String,
    /// Optional: the discarded snapshot (canonicalized JSON).
    pub loser_payload: Option<String>,
    /// RFC 3339 timestamp when the conflict was resolved.
    pub resolved_at: String,
    /// The resolution strategy used: "lww", "tag_merge", "recurrence_dedup",
    /// "fk_stalled", "fk_unresolved", or "reseed_required". See
    /// `lorvex_domain::naming::RESOLUTION_*` for the constants.
    pub resolution_type: Cow<'static, str>,
}

/// Record a sync conflict resolution.
///
/// The `id` field of the entry is ignored; the database assigns an autoincrement
/// row ID. `loser_payload`, if present, is passed through [`scrub_loser_payload`]
/// before insertion so user-authored text (titles, notes, location) never
/// lands in the DB verbatim. The diagnostic value of the log is in the
/// keys / structure / HLC versions, not in the user content.
///
/// # Natural-key dedupe contract — IMPORTANT for new callers
///
/// The INSERT is guarded by a `WHERE NOT EXISTS` on the natural-key tuple
/// `(entity_type, entity_id, loser_version, loser_device_id, resolution_type, loser_payload)`.
/// `loser_payload` is part of the key; the comparison is `IS NOT DISTINCT FROM`
/// so two NULL payloads collapse (preserving idempotency for resolution
/// types — `tag_merge`, `fk_stalled`, `fk_unresolved`, `reseed_required` —
/// that don't carry one).
///
/// **Per-tx multi-row contract:** if a single envelope-apply tx emits
/// `>= 2` conflict rows, callers MUST set a payload that varies between
/// the rows. Two rows that share `(entity_type, entity_id, loser_version,
/// loser_device_id, resolution_type)` AND share (or both lack) a
/// `loser_payload` will collapse into a single DB row, silently hiding
/// every conflict after the first.
///
/// **Concrete precedent (#2878):** calendar-event apply ran into this
/// when an inbound batch contained N attendees that all collided on
/// the same canonical email. The deterministic-resolution code emits
/// one `lww` row per dropped attendee — same envelope, same authoring
/// peer, so `(entity, loser_version, device, resolution_type)` is
/// uniform across the batch. Without the payload-aware dedupe, only
/// the first dropped attendee surfaced in Settings → Sync → Conflicts;
/// the rest disappeared and the operator had no diagnostic for the
/// missing data. The fix added `loser_payload` to the dedupe key (commit
/// 96735ebc5) and made each row carry its own per-attendee payload.
///
/// **Future callers — checklist when emitting multi-row conflicts in one tx:**
///   * each row's `loser_payload` must be `Some(_)` and must differ from
///     every sibling's payload after [`scrub_loser_payload`] runs (the
///     scrubber is structure-preserving, so payloads with distinct
///     non-PII fields — ids, hlc versions, timestamps — stay distinct);
///   * if a domain genuinely needs to log identical losers (e.g. a
///     "this conflict happened N times" surface), aggregate at the
///     caller and store the count in a new column rather than relying
///     on multiple identical rows;
///   * resolution types that fundamentally produce one row per envelope
///     (`tag_merge`, `recurrence_dedup`, `fk_*`, `reseed_required`) are
///     unaffected — they may continue passing `loser_payload: None`.
///
/// Replays of the same envelope still dedupe correctly because the
/// scrubbed payload is byte-stable across replays of the same input
/// (canonical JSON in, deterministic PII scrubber, canonical JSON out).
///
/// The dedupe relies on byte-equality of `loser_payload`, so every
/// caller MUST pass the loser payload as already-canonicalized JSON
/// (`serde_json::to_string` on a value that flowed through
/// `lorvex_store::canonical::canonicalize_value`, or any equivalent
/// stable-key serializer). A caller that passes a raw
/// `serde_json::Value::to_string()` whose key order tracks insertion
/// order can produce two byte-different strings for the same logical
/// payload across replays, causing the dedupe predicate to insert
/// duplicate rows. The PII scrubber at line 88 below is structure-
/// preserving but does NOT re-canonicalize key order, so the contract
/// is "canonical JSON in" — keep it that way.
pub fn log_conflict(conn: &Connection, entry: &ConflictLogEntry) -> Result<(), rusqlite::Error> {
    let scrubbed_payload = entry.loser_payload.as_deref().map(scrub_loser_payload);
    // Natural-key dedupe — see the function-level doc-comment for the
    // full contract (entity_type, entity_id, loser_version,
    // loser_device_id, resolution_type, loser_payload). `IS NOT DISTINCT
    // FROM` lets two NULL payloads compare equal so resolution types
    // that don't carry one (tag_merge / fk_stalled / etc.) keep their
    // single-row-per-envelope idempotency; multi-row callers (#2878)
    // MUST set a per-row payload that differs across siblings.
    conn.prepare_cached(
        "INSERT INTO sync_conflict_log
            (entity_type, entity_id, winner_version, loser_version,
             loser_device_id, loser_payload, resolved_at, resolution_type)
         SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8
         WHERE NOT EXISTS (
             SELECT 1 FROM sync_conflict_log
             WHERE entity_type = ?1
               AND entity_id = ?2
               AND loser_version = ?4
               AND loser_device_id = ?5
               AND resolution_type = ?8
               AND loser_payload IS NOT DISTINCT FROM ?6
         )",
    )?
    .execute(params![
        entry.entity_type.as_ref(),
        entry.entity_id,
        entry.winner_version,
        entry.loser_version,
        entry.loser_device_id,
        scrubbed_payload,
        entry.resolved_at,
        entry.resolution_type.as_ref(),
    ])?;
    Ok(())
}

/// Keys in a canonicalized entity payload that carry free-form,
/// user-authored text. These are the fields that can reveal task
/// contents, relationships, and locations in a copy-paste-to-bug-report
/// screenshot of Settings → Sync → Conflicts. Keep structure and
/// non-text metadata (dates, flags, ids, HLC versions) intact so the
/// conflict log stays useful for debugging.
const PII_BEARING_JSON_KEYS: &[&str] = &[
    "title",
    "notes",
    "ai_notes",
    "description",
    "body",
    "location",
    "attendees_json",
    "attendees",
    "content",
    "summary",
];

/// Replace the value of every PII-bearing JSON key with a placeholder
/// while preserving the rest of the payload. If the payload doesn't
/// parse as JSON, fall back to a generic `<non-json payload
/// suppressed>` marker — we never store the raw string because
/// verbatim payloads leak free-form user content into the conflict
/// log.
pub fn scrub_loser_payload(raw: &str) -> String {
    let Ok(mut value) = serde_json::from_str::<serde_json::Value>(raw) else {
        return "<non-json payload suppressed>".to_string();
    };
    scrub_json_value_in_place(&mut value);
    // `serde_json::to_string` on a `serde_json::Value` is infallible by
    // construction: the value was just parsed from JSON, and the
    // scrubber only replaces existing values. The previous
    // `unwrap_or_else` returned a `<scrub serialization failed>`
    // sentinel that no caller ever observed and that masked any future
    // serde_json bug behind a string-equality check. Per CLAUDE.md
    // ("don't add error handling for scenarios that can't happen"),
    // assert the contract instead — a panic here would be a serde_json
    // regression, not a runtime fault.
    serde_json::to_string(&value).expect("serde_json::Value -> String is infallible")
}

fn scrub_json_value_in_place(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::Object(map) => {
            for (k, v) in map.iter_mut() {
                if PII_BEARING_JSON_KEYS.contains(&k.as_str()) {
                    *v = serde_json::Value::String("[REDACTED_PII]".to_string());
                } else {
                    scrub_json_value_in_place(v);
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items.iter_mut() {
                scrub_json_value_in_place(item);
            }
        }
        _ => {}
    }
}

/// Delete conflict log entries older than `retention_days`.
///
/// Returns the number of deleted entries.
pub fn gc_conflicts(conn: &Connection, retention_days: u32) -> Result<u64, rusqlite::Error> {
    let deleted = conn
        .prepare_cached(
            "DELETE FROM sync_conflict_log
             WHERE resolved_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        )?
        .execute(params![format!("-{retention_days} days")])?;
    Ok(deleted as u64)
}

/// Get the total number of conflict log entries.
#[cfg(test)]
fn count_conflicts(conn: &Connection) -> Result<u64, rusqlite::Error> {
    let count: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM sync_conflict_log")?
        .query_row([], |row| row.get(0))?;
    Ok(count as u64)
}

/// Get conflicts filtered by resolution type.
pub fn get_conflicts_by_type(
    conn: &Connection,
    resolution_type: &str,
    limit: u32,
) -> Result<Vec<ConflictLogEntry>, rusqlite::Error> {
    let mut stmt = conn.prepare_cached(
        "SELECT id, entity_type, entity_id, winner_version, loser_version,
                loser_device_id, loser_payload, resolved_at, resolution_type
         FROM sync_conflict_log
         WHERE resolution_type = ?1
         ORDER BY id DESC
         LIMIT ?2",
    )?;

    let rows = stmt.query_map(params![resolution_type, limit], |row| {
        let res: String = row.get(8)?;
        let et: String = row.get(1)?;
        Ok(ConflictLogEntry {
            id: row.get(0)?,
            entity_type: Cow::Owned(et),
            entity_id: row.get(2)?,
            winner_version: row.get(3)?,
            loser_version: row.get(4)?,
            loser_device_id: row.get(5)?,
            loser_payload: row.get(6)?,
            resolved_at: row.get(7)?,
            resolution_type: Cow::Owned(res),
        })
    })?;

    rows.collect()
}

#[cfg(test)]
mod tests;
