//! Per-attendee forward-compat shadow for `calendar_event.attendees[]`.
//!
//! `calendar_event_attendees` persists only the known
//! per-attendee fields (`email`, `name`, `status`). A newer peer may
//! emit additional keys per attendee (e.g. `role`, `rsvp_deadline`).
//! Without a shadow, the next outbound enqueue rebuilds the
//! `attendees` array purely from the known-columns table and silently
//! drops anything the current schema doesn't understand — so a newer
//! peer → older peer → newer peer round-trip loses the unknown field.
//!
//! This module mirrors the aggregate-level [`crate::payload_shadow`]
//! scoped to a single nested array. On
//! apply, `apply_calendar_event_upsert` collects each attendee's
//! surplus keys into [`replace_attendee_shadows`] (one call per
//! event_id, all attendees in one rowset). On re-echo, both the
//! MCP enrichment path and the app's outbox seeder call
//! [`load_attendees_with_extras`] to get attendee JSON objects that
//! carry their preserved extras alongside the canonical fields.

use std::collections::HashMap;

use crate::error::PayloadError;
use rusqlite::{params, types::ToSql, Connection};
use serde_json::{Map, Value};

/// Keys that the primary `calendar_event_attendees` table already
/// owns. Any other key on an inbound attendee object is surplus and
/// belongs in the shadow's `extra_fields_json`.
pub const KNOWN_ATTENDEE_KEYS: &[&str] = &["email", "name", "status"];

/// Replace the full shadow rowset for a single calendar event.
///
/// Callers pass one `(attendee_id, extras)` pair per attendee that
/// carries unknown fields; attendees with no surplus keys should be
/// omitted (their row is removed by this call). `attendee_id` is the
/// synthesized device-local identity (see
/// `lorvex_domain::attendee_identity`) — the same key the primary
/// `calendar_event_attendees` table uses — so the shadow join in
/// [`load_attendees_with_extras`] lines up.
///
/// This function deletes every shadow row for `event_id` and
/// re-inserts the supplied pairs, so it must be called in the same
/// transaction as the `calendar_event_attendees` rebuild. When an
/// attendee is removed from the envelope, its shadow row is also
/// removed — that is the purge-on-absence semantics the issue
/// requires.
pub fn replace_attendee_shadows(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
    rows: &[(String, Map<String, Value>)],
) -> Result<(), PayloadError> {
    conn.prepare_cached("DELETE FROM calendar_event_attendee_shadow WHERE event_id = ?1")?
        .execute(params![event_id])?;
    if rows.is_empty() {
        return Ok(());
    }
    let updated_at = lorvex_domain::sync_timestamp_now();
    let mut stmt = conn.prepare_cached(
        "INSERT INTO calendar_event_attendee_shadow (event_id, attendee_id, extra_fields_json, updated_at)
         VALUES (?1, ?2, ?3, ?4)",
    )?;
    for (attendee_id, extras) in rows {
        if extras.is_empty() {
            continue;
        }
        // serialize the borrowed `Map<String, Value>`
        // directly — `Map` implements `Serialize` and produces the
        // same JSON object literal as `Value::Object(...)` would.
        // per attendee just to feed the `Object` constructor; on a
        // recurring meeting with many attendees that was one full
        // tree clone per row.
        let json = serde_json::to_string(extras)?;
        stmt.execute(params![event_id, attendee_id, json, updated_at])?;
    }
    Ok(())
}

/// Build the merged `attendees` array for an outbound envelope.
///
/// Reads `calendar_event_attendees` in a stable order (by
/// `attendee_id` ASC — the device-local synthesized identity, so an
/// anonymous attendee's slot does not shift when a keyed peer sorts
/// around it), then overlays any `extra_fields_json` on top. Known
/// keys take precedence — the shadow is strictly a forward-compat
/// escape hatch for keys the current schema doesn't own, not an
/// override channel for known columns. `attendee_id` itself is never
/// emitted on the wire; the merged object carries only `email` /
/// `name` / `status` plus surplus keys.
///
/// Returns an empty vector when the event has no attendees; callers
/// decide whether to emit the `attendees` key as `null`, absent, or
/// an empty array based on their wire format.
pub fn load_attendees_with_extras(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
) -> Result<Vec<Value>, PayloadError> {
    let mut stmt = conn.prepare_cached(
        "SELECT a.email, a.name, a.status, s.extra_fields_json
         FROM calendar_event_attendees a
         LEFT JOIN calendar_event_attendee_shadow s
            ON s.event_id = a.event_id AND s.attendee_id = a.attendee_id
         WHERE a.event_id = ?1
         ORDER BY a.attendee_id",
    )?;
    let mut out: Vec<Value> = Vec::new();
    let mut rows = stmt.query(params![event_id])?;
    while let Some(row) = rows.next()? {
        out.push(merged_attendee_object(row, /* email_idx */ 0)?);
    }
    Ok(out)
}

/// Batch variant: load merged attendee arrays for a set of event ids in
/// one round trip.
///
///: list-style readers
/// (`enrich_events_with_attendees` in the MCP server, future calendar
/// timeline / list-pages exports) call
/// [`load_attendees_with_extras`] in a per-event loop, paying one
/// `prepare_cached` lookup + one round trip per event in the result
/// set. A 50-event timeline window therefore issued 50 separate
/// `SELECT … WHERE event_id = ?1` statements that each scanned the
/// `(event_id)` index for a single value. Folding the loop into a
/// single `WHERE event_id IN (…)` query collapses the 50 round trips
/// into one and lets SQLite walk the index range once.
///
/// Returns one entry per *requested* event id — events with no
/// attendees map to an empty vector so callers can render a
/// definitive `null` / `[]` regardless of presence. Duplicate input
/// ids are deduped internally; the output map's key set matches the
/// deduped input.
pub fn load_attendees_with_extras_for_events(
    conn: &Connection,
    event_ids: &[&str],
) -> Result<HashMap<String, Vec<Value>>, PayloadError> {
    let mut out: HashMap<String, Vec<Value>> = HashMap::with_capacity(event_ids.len());
    if event_ids.is_empty() {
        return Ok(out);
    }
    // Pre-seed the map with empty vectors so events with zero
    // attendees still appear in the output. Without this, callers
    // that look up by event id would have to disambiguate
    // "no row in map" from "row with empty vector"; explicit empties
    // make the contract that the output mirrors the *input* id set.
    for &id in event_ids {
        out.entry(id.to_string()).or_default();
    }

    let placeholders = std::iter::repeat_n("?", out.len())
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!(
        "SELECT a.event_id, a.email, a.name, a.status, s.extra_fields_json
         FROM calendar_event_attendees a
         LEFT JOIN calendar_event_attendee_shadow s
            ON s.event_id = a.event_id AND s.attendee_id = a.attendee_id
         WHERE a.event_id IN ({placeholders})
         ORDER BY a.event_id, a.attendee_id"
    );
    let mut stmt = conn.prepare_cached(&sql)?;

    let owned_ids: Vec<String> = out.keys().cloned().collect();
    let bind: Vec<&dyn ToSql> = owned_ids.iter().map(|s| s as &dyn ToSql).collect();
    let mut rows = stmt.query(rusqlite::params_from_iter(bind.iter().copied()))?;
    while let Some(row) = rows.next()? {
        let event_id: String = row.get(0)?;
        let attendee = merged_attendee_object(row, /* email_idx */ 1)?;
        out.entry(event_id).or_default().push(attendee);
    }
    Ok(out)
}

/// Build a single merged attendee JSON object from a row whose columns
/// at offset `email_idx` are `(email, name, status, extra_fields_json)`.
///
/// Single source of truth for the merge precedence both the per-event
/// and batch loaders rely on.
fn merged_attendee_object(
    row: &rusqlite::Row<'_>,
    email_idx: usize,
) -> Result<Value, PayloadError> {
    let email: String = row.get(email_idx)?;
    let name: Option<String> = row.get(email_idx + 1)?;
    let status: Option<String> = row.get(email_idx + 2)?;
    let extras_json: Option<String> = row.get(email_idx + 3)?;

    let mut obj: Map<String, Value> = match extras_json {
        Some(raw) => match serde_json::from_str::<Value>(&raw)? {
            Value::Object(m) => m,
            _ => {
                return Err(PayloadError::Serialization(
                    "calendar_event_attendee_shadow.extra_fields_json must be a JSON object"
                        .to_string(),
                ));
            }
        },
        None => Map::new(),
    };

    // Known fields win over shadow contents. The shadow should never
    // hold keys already present in the primary table, but defend
    // against the drift case so a stale shadow from a prior schema
    // generation can't corrupt outbound payloads.
    obj.insert("email".to_string(), Value::String(email));
    obj.insert("name".to_string(), name.map_or(Value::Null, Value::String));
    obj.insert(
        "status".to_string(),
        status.map_or(Value::Null, Value::String),
    );
    Ok(Value::Object(obj))
}

#[cfg(test)]
mod tests;
