//! Apply handlers for day-scoped aggregates with embedded collection
//! materialization.
//!
//! These entities use `date` as their natural primary key. Each has one or more
//! child tables (materialization tables) whose rows are rebuilt atomically on
//! every upsert.

use rusqlite::Connection;

use super::{version_cmp, ApplyError, LwwTieBreak};

/// Parse a time field that may be an integer (minutes from midnight) or "HH:MM" string.
fn parse_required_time_field(
    val: Option<&serde_json::Value>,
    field: &str,
) -> Result<i64, ApplyError> {
    match val {
        // `unwrap_or(0)` silently
        // collapsed an out-of-i64-range integer (e.g. JSON
        // 9999999999999999) to 0. The downstream range check at
        // `apply_focus_schedule_upsert` accepted 0 (in 0..=1440),
        // so the malicious payload landed at start=0 instead of
        // erroring. Reject the parse outright with a typed error.
        Some(v) if v.is_i64() => v.as_i64().ok_or_else(|| {
            ApplyError::InvalidPayload(format!(
                "invalid day-scoped payload: {field} integer is not representable as i64"
            ))
        }),
        Some(v) if v.is_string() => {
            let raw = v.as_str().ok_or_else(|| {
                ApplyError::InvalidPayload(format!(
                    "invalid day-scoped payload: {field} must be an integer or HH:MM string"
                ))
            })?;
            lorvex_domain::parse_hhmm_to_minutes(raw).ok_or_else(|| {
                ApplyError::InvalidPayload(format!(
                    "invalid day-scoped payload: {field} has invalid time {raw}"
                ))
            })
        }
        Some(_) => Err(ApplyError::InvalidPayload(format!(
            "invalid day-scoped payload: {field} must be an integer or HH:MM string"
        ))),
        None => Err(ApplyError::InvalidPayload(format!(
            "invalid day-scoped payload: missing required field {field}"
        ))),
    }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

// JSON-extraction primitives now live in `apply::json_helpers`
//.
use super::json_helpers::{optional_str, required_str};

/// Returns `true` if `s` looks like a standard UUID (36 chars, dashes at
/// positions 8/13/18/23, hex digits everywhere else). defensively
/// reject provider-specific event keys that are not canonical UUIDs.
///
/// Audit F10: the previous implementation only checked dash positions
/// and total length, accepting strings like
/// `"GGGGGGGG-GGGG-GGGG-GGGG-GGGGGGGGGGGG"`. A hostile peer could smuggle
/// non-UUID provider keys through the gate. We now require every
/// non-dash position to be `[0-9a-fA-F]`.
fn is_canonical_uuid(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 36 {
        return false;
    }
    if b[8] != b'-' || b[13] != b'-' || b[18] != b'-' || b[23] != b'-' {
        return false;
    }
    for (i, &c) in b.iter().enumerate() {
        if matches!(i, 8 | 13 | 18 | 23) {
            continue;
        }
        if !c.is_ascii_hexdigit() {
            return false;
        }
    }
    true
}

use super::json_helpers::optional_i64;

fn string_array_field(val: &serde_json::Value, key: &str) -> Result<Vec<String>, ApplyError> {
    match val.get(key) {
        // Missing or null is treated as empty for forward-compatibility:
        // older payloads may not have these fields.
        None | Some(serde_json::Value::Null) => Ok(Vec::new()),
        Some(serde_json::Value::Array(arr)) => arr
            .iter()
            .map(|entry| {
                entry.as_str().map(String::from).ok_or_else(|| {
                    ApplyError::InvalidPayload(format!(
                        "invalid day-scoped payload: {key} must contain only strings"
                    ))
                })
            })
            .collect(),
        Some(_) => Err(ApplyError::InvalidPayload(format!(
            "invalid day-scoped payload: {key} must be an array of strings"
        ))),
    }
}

fn required_array_field<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<&'a [serde_json::Value], ApplyError> {
    match val.get(key) {
        Some(serde_json::Value::Array(arr)) => Ok(arr),
        _ => Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} must be an array"
        ))),
    }
}

// ---------------------------------------------------------------------------
// current_focus (PK = date)
// ---------------------------------------------------------------------------

pub(crate) fn apply_current_focus_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    let val: serde_json::Value = serde_json::from_str(payload)?;
    let date = entity_id; // natural key

    let briefing = optional_str(&val, "briefing", "current_focus")?;
    let timezone = optional_str(&val, "timezone", "current_focus")?;
    let created_at = required_str(&val, "created_at", "current_focus")?;
    let updated_at = required_str(&val, "updated_at", "current_focus")?;

    // Upsert parent row via shared op (sync-mode: overwrites timezone + created_at).
    let cmp = version_cmp(allow_equal_versions);
    let wrote = lorvex_store::current_focus_items::sync_upsert_current_focus(
        conn, date, briefing, timezone, version, created_at, updated_at, cmp,
    )?;

    // Only rebuild materialization if the parent row was actually written.
    if wrote {
        let task_ids = string_array_field(&val, "task_ids")?;
        lorvex_store::current_focus_items::materialize_focus_items(conn, date, &task_ids)?;
    }

    Ok(())
}

pub(crate) fn apply_current_focus_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Child rows cascade-deleted via FK.
    //
    // cascading without per-edge tombstones is
    // INTENTIONAL for the day-scoped materialization tables
    // (`current_focus_items`, `focus_schedule_blocks`,
    // `daily_review_task_links`, `daily_review_list_links`) —
    // unlike `apply_task_delete`, these child rows are NOT
    // independently synced. They have no `version` column, no
    // outbox enqueue site, and no entry in `dispatch::ENTITY_HANDLERS`,
    // so their state is wholly derived from the parent
    // upsert payload and rebuilt atomically on every apply. There is
    // therefore no peer that could resurrect a stale edge into
    // divergence.
    //
    // The drift guard below in this module's `tests` block enforces
    // that contract: if a future contributor adds any of these
    // materialization tables to `naming::ALL_SYNCABLE_TYPES` or to
    // the dispatch table, they MUST also lift the parent delete onto
    // the cascading-tombstone helper (see
    // `apply::aggregate::helpers::tombstone_child_rows`) before
    // shipping, or peers running an older build will permanently
    // diverge on edge state (/ #2946-H3).
    //
    // defense-in-depth LWW guard mirroring
    // `apply_task_delete`. The day-scoped delete helpers are reachable
    // from `apply_entity_with_version_mode(_, true)` (shadow promotion)
    // and any future replay path; the in-row predicate makes the
    // helper safe regardless of upstream gating. Routes through
    // `lww_gated_delete` so every aggregate/edge/child/day-scoped
    // delete shares one typed-comparator implementation
    // (`compare_versions_with_fallback` rather than raw SQL byte
    // compare).
    crate::apply::lww_gated_delete(conn, "current_focus", &["date"], &[entity_id], version)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// focus_schedule (PK = date)
// ---------------------------------------------------------------------------

pub(crate) fn apply_focus_schedule_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    let val: serde_json::Value = serde_json::from_str(payload)?;
    let date = entity_id;

    let rationale = optional_str(&val, "rationale", "focus_schedule")?;
    let timezone = optional_str(&val, "timezone", "focus_schedule")?;
    let created_at = required_str(&val, "created_at", "focus_schedule")?;
    let updated_at = required_str(&val, "updated_at", "focus_schedule")?;

    // Upsert parent row via shared op (sync-mode: overwrites timezone + created_at).
    // thread the typed `SyncVersionCmp` enum to the
    // store helper so the LWW comparator can never be SQL-injected.
    let cmp = if allow_equal_versions.allow_equal() {
        lorvex_store::focus_schedule_blocks::SyncVersionCmp::GreaterOrEqual
    } else {
        lorvex_store::focus_schedule_blocks::SyncVersionCmp::Greater
    };
    let wrote = lorvex_store::focus_schedule_blocks::sync_upsert_focus_schedule(
        conn, date, rationale, timezone, version, created_at, updated_at, cmp,
    )?;

    // Only rebuild materialization if the parent row was actually written.
    if !wrote {
        return Ok(());
    }

    // Rebuild materialization: focus_schedule_blocks via shared op.
    let blocks = required_array_field(&val, "blocks", "focus_schedule")?;
    let entries: Vec<lorvex_store::focus_schedule_blocks::ScheduleBlockEntry> = blocks
        .iter()
        .map(|block| {
            let block_type = match block.get("block_type") {
                None | Some(serde_json::Value::Null) => Ok("buffer".to_string()),
                Some(value) => value.as_str().map(str::to_string).ok_or_else(|| {
                    ApplyError::InvalidPayload(
                        "invalid day-scoped payload: blocks[*].block_type must be a string".to_string(),
                    )
                }),
            }?;
            // Accept both integer minutes and "HH:MM" string
            let start_minutes =
                parse_required_time_field(block.get("start_time"), "blocks[*].start_time")?;
            let end_minutes =
                parse_required_time_field(block.get("end_time"), "blocks[*].end_time")?;
            // validate the time range is well-formed
            // before storing. The integer branch of
            // `parse_required_time_field` accepts arbitrary i64
            // (e.g. -30, 99999); the schema CHECK does not enforce
            // 0..=1440 or `start <= end`, so a peer with a malformed
            // payload would otherwise materialise an inverted /
            // out-of-range block that breaks the focus-mode UI.
            if !(0..=1440).contains(&start_minutes) || !(0..=1440).contains(&end_minutes) {
                return Err(ApplyError::InvalidPayload(format!(
                    "invalid day-scoped payload: blocks[*] time minutes must be \
                     in 0..=1440 (got start={start_minutes}, end={end_minutes})"
                )));
            }
            if end_minutes < start_minutes {
                return Err(ApplyError::InvalidPayload(format!(
                    "invalid day-scoped payload: blocks[*] end_time \
                     ({end_minutes}m) precedes start_time ({start_minutes}m)"
                )));
            }
            let task_id = match block.get("task_id") {
                None | Some(serde_json::Value::Null) => None,
                Some(value) => Some(
                    value
                        .as_str()
                        .filter(|s| !s.is_empty())
                        .map(String::from)
                        .ok_or_else(|| {
                            ApplyError::InvalidPayload(
                                "invalid day-scoped payload: blocks[*].task_id must be a string or null".to_string(),
                            )
                        })?,
                ),
            };
            // Defensive strip: only allow canonical calendar_event UUIDs through.
            // Provider-specific event keys (EventKit identifiers, VEVENT UIDs, etc.)
            // must never leak into synced focus_schedule payloads.
            let event_id = match block.get("event_id") {
                None | Some(serde_json::Value::Null) => None,
                Some(value) => Some(
                    value
                        .as_str()
                        .filter(|id| is_canonical_uuid(id))
                        .map(String::from)
                        .ok_or_else(|| {
                            ApplyError::InvalidPayload(
                                "invalid day-scoped payload: blocks[*].event_id must be a canonical UUID string or null".to_string(),
                            )
                        })?,
                ),
            };
            let title = match block.get("title") {
                None | Some(serde_json::Value::Null) => None,
                Some(value) => Some(value.as_str().map(String::from).ok_or_else(|| {
                    ApplyError::InvalidPayload(
                        "invalid day-scoped payload: blocks[*].title must be a string or null".to_string(),
                    )
                })?),
            };
            Ok(lorvex_store::focus_schedule_blocks::ScheduleBlockEntry {
                block_type,
                start_minutes,
                end_minutes,
                task_id,
                event_id,
                title,
            })
        })
        .collect::<Result<Vec<_>, ApplyError>>()?;
    lorvex_store::focus_schedule_blocks::materialize_schedule_blocks(conn, date, &entries)?;

    Ok(())
}

pub(crate) fn apply_focus_schedule_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Blocks cascade-deleted via FK.
    // defense-in-depth LWW guard. See `apply_current_focus_delete`
    // for context. Routes through `lww_gated_delete` for shared
    // typed-comparator semantics.
    crate::apply::lww_gated_delete(conn, "focus_schedule", &["date"], &[entity_id], version)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// daily_review (PK = date)
// ---------------------------------------------------------------------------

pub(crate) fn apply_daily_review_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    let val: serde_json::Value = serde_json::from_str(payload)?;
    let date = entity_id;

    let summary = required_str(&val, "summary", "daily_review")?;
    let mood = optional_i64(&val, "mood", "daily_review")?;
    let energy_level = optional_i64(&val, "energy_level", "daily_review")?;
    let wins = optional_str(&val, "wins", "daily_review")?;
    let blockers = optional_str(&val, "blockers", "daily_review")?;
    let learnings = optional_str(&val, "learnings", "daily_review")?;
    let ai_synthesis = optional_str(&val, "ai_synthesis", "daily_review")?;
    let timezone = optional_str(&val, "timezone", "daily_review")?;
    let created_at = required_str(&val, "created_at", "daily_review")?;
    let updated_at = required_str(&val, "updated_at", "daily_review")?;

    // Upsert parent row via shared op (sync-mode: overwrites timezone + created_at).
    let cmp = version_cmp(allow_equal_versions);
    let wrote = lorvex_store::daily_review_ops::sync_upsert_daily_review(
        conn,
        date,
        summary,
        mood,
        energy_level,
        wins,
        blockers,
        learnings,
        ai_synthesis,
        timezone,
        version,
        created_at,
        updated_at,
        cmp,
    )?;

    // Only rebuild materializations if the parent row was actually written.
    if wrote {
        let task_ids = string_array_field(&val, "linked_task_ids")?;
        lorvex_store::daily_review_ops::materialize_review_task_links(conn, date, &task_ids)?;

        let list_ids = string_array_field(&val, "linked_list_ids")?;
        lorvex_store::daily_review_ops::materialize_review_list_links(conn, date, &list_ids)?;
    }

    Ok(())
}

pub(crate) fn apply_daily_review_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Link tables cascade-deleted via FK.
    // defense-in-depth LWW guard. See `apply_current_focus_delete`
    // for context. Routes through `lww_gated_delete` for shared
    // typed-comparator semantics.
    crate::apply::lww_gated_delete(conn, "daily_reviews", &["date"], &[entity_id], version)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
