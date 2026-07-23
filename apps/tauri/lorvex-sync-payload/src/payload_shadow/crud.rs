//! CRUD primitives for `sync_payload_shadow` rows. The merge / redirect
//! logic lives in [`super::merge`]; this module restricts itself to
//! single-row reads, writes, and the version-gated supersede check.

use super::{parse_hlc, validate_raw_payload_size, PayloadShadowRow};
use crate::error::PayloadError;
use lorvex_domain::naming::EntityKind;
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{Map, Value};

/// Parse a SQLite-stored `entity_type` column at the read boundary,
/// surfacing an unknown value as a typed `PayloadError::Invariant` that
/// preserves the offending string for diagnostics.
fn parse_entity_kind_from_row(value: &str) -> Result<EntityKind, PayloadError> {
    EntityKind::try_parse(value).map_err(|err| {
        PayloadError::Invariant(format!(
            "sync_payload_shadow.entity_type contains unknown entity kind {value:?}: {err}"
        ))
    })
}

pub fn upsert_shadow(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    base_version: &str,
    payload_schema_version: u32,
    raw_payload_json: &str,
    source_device_id: &str,
) -> Result<(), PayloadError> {
    // persist only the unknown-keys diff. The full
    // `raw_payload_json` arriving at this writer holds every known
    // schema field plus any forward-compat unknown keys the peer
    // shipped. `merge_payload_with_shadow` (re-emit path) overwrites
    // every known key from the live local payload, so the shadow's
    // copy of those known keys is never read. Stripping them here
    // halves long-term storage growth on long-lived databases and
    // makes the shadow row far easier to reason about during
    // incident response (one place to look for "what is live", one
    // place to look for "what did we preserve forward-compat").
    //
    // A `serde_json::from_str` failure falls back to persisting the
    // raw form unchanged — the apply pipeline already enforced
    // canonical JSON shape upstream, so a non-object payload here
    // would surface in the merge path as a typed error (see
    // `merge_payload_with_shadow`). Persisting verbatim under the
    // pathological case keeps the size cap as the single source of
    // truth on what reaches disk.
    let trimmed_payload = strip_known_keys_for_shadow(entity_type, raw_payload_json);
    let payload_for_db: &str = trimmed_payload.as_deref().unwrap_or(raw_payload_json);
    validate_raw_payload_size(entity_type, entity_id, payload_for_db)?;
    conn.prepare_cached(
        "INSERT INTO sync_payload_shadow (
            entity_type, entity_id, base_version, payload_schema_version,
            raw_payload_json, source_device_id, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
         ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            base_version = excluded.base_version,
            payload_schema_version = excluded.payload_schema_version,
            raw_payload_json = excluded.raw_payload_json,
            source_device_id = excluded.source_device_id,
            updated_at = excluded.updated_at
         WHERE excluded.base_version > sync_payload_shadow.base_version",
    )?
    .execute(params![
        entity_type,
        entity_id,
        base_version,
        payload_schema_version,
        payload_for_db,
        source_device_id,
    ])?;
    Ok(())
}

/// parse `raw_payload_json` as a JSON object and remove
/// every key the local schema owns (`owned_keys_for_entity`),
/// returning the trimmed re-serialized form. Returns `None` for any
/// input that doesn't parse as a JSON object, signalling that the
/// caller should persist the raw form verbatim — the apply pipeline
/// already enforces canonical shape upstream, so a non-object here
/// is a contract violation that surfaces in `merge_payload_with_shadow`
/// as a typed error.
fn strip_known_keys_for_shadow(entity_type: &str, raw_payload_json: &str) -> Option<String> {
    let mut object: Map<String, Value> = match serde_json::from_str(raw_payload_json) {
        Ok(Value::Object(map)) => map,
        _ => return None,
    };
    let owned = super::owned_keys::owned_keys_for_entity(entity_type);
    if owned.is_empty() {
        // No known keys for this entity type → the shadow IS the full
        // payload. Re-serializing would be a no-op in shape but might
        // canonicalize spacing; persist the raw form verbatim instead
        // so the upstream canonicalization stays the source of truth.
        return None;
    }
    let mut trimmed_any = false;
    for key in owned {
        if object.remove(*key).is_some() {
            trimmed_any = true;
        }
    }
    if !trimmed_any {
        // Nothing to strip — the payload was already lean. Persist
        // verbatim to preserve canonical spacing.
        return None;
    }
    serde_json::to_string(&Value::Object(object)).ok()
}

pub fn get_shadow(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<PayloadShadowRow>, PayloadError> {
    conn.prepare_cached(
        "SELECT entity_type, entity_id, base_version, payload_schema_version,
                raw_payload_json, source_device_id, updated_at
             FROM sync_payload_shadow
             WHERE entity_type = ?1 AND entity_id = ?2",
    )?
    .query_row(params![entity_type, entity_id], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, u32>(3)?,
            row.get::<_, String>(4)?,
            row.get::<_, String>(5)?,
            row.get::<_, String>(6)?,
        ))
    })
    .optional()?
    .map(
        |(
            et,
            entity_id,
            base_version,
            payload_schema_version,
            raw_payload_json,
            source_device_id,
            updated_at,
        )| {
            Ok::<_, PayloadError>(PayloadShadowRow {
                entity_type: parse_entity_kind_from_row(&et)?,
                entity_id,
                base_version,
                payload_schema_version,
                raw_payload_json,
                source_device_id,
                updated_at,
            })
        },
    )
    .transpose()
}

pub fn list_shadows(conn: &Connection) -> Result<Vec<PayloadShadowRow>, PayloadError> {
    let mut stmt = conn.prepare_cached(
        "SELECT entity_type, entity_id, base_version, payload_schema_version,
                raw_payload_json, source_device_id, updated_at
         FROM sync_payload_shadow
         ORDER BY entity_type, entity_id",
    )?;
    let mut result = Vec::new();
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let entity_type_raw: String = row.get(0)?;
        result.push(PayloadShadowRow {
            entity_type: parse_entity_kind_from_row(&entity_type_raw)?,
            entity_id: row.get(1)?,
            base_version: row.get(2)?,
            payload_schema_version: row.get(3)?,
            raw_payload_json: row.get(4)?,
            source_device_id: row.get(5)?,
            updated_at: row.get(6)?,
        });
    }
    Ok(result)
}

pub fn restore_shadow(conn: &Connection, row: &PayloadShadowRow) -> Result<(), PayloadError> {
    // the predicate is `>=` rather than `>` so the
    // redirect-merge path (`merge_shadow_into_redirect`) can rewrite
    // the winning shadow row with merged content even when the
    // merged row's `base_version` ties the existing winner's. The
    // strictly-greater form silently dropped any keys that lived
    // only on the loser when winner-version == loser-version,
    // because the subsequent `remove_shadow(loser)` ran
    // unconditionally — that's exactly the silent data loss the
    // shadow layer is meant to prevent.
    //
    // Equal-version overwrites are also harmless for the import path
    // (idempotent re-import lands the same bytes) and for any future
    // race where two writers compute the same merged row at once.
    //
    // cap the raw_payload_json size so a malicious
    // or corrupted import archive cannot ship a 50 MB shadow row
    // through the restore path. The same cap is enforced on
    // `upsert_shadow`; this is the parallel defense-in-depth at
    // the import boundary.
    validate_raw_payload_size(
        row.entity_type.as_str(),
        &row.entity_id,
        &row.raw_payload_json,
    )?;
    conn.prepare_cached(
        "INSERT INTO sync_payload_shadow (
            entity_type, entity_id, base_version, payload_schema_version,
            raw_payload_json, source_device_id, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            base_version = excluded.base_version,
            payload_schema_version = excluded.payload_schema_version,
            raw_payload_json = excluded.raw_payload_json,
            source_device_id = excluded.source_device_id,
            updated_at = excluded.updated_at
         WHERE excluded.base_version >= sync_payload_shadow.base_version",
    )?
    .execute(params![
        row.entity_type.as_str(),
        row.entity_id,
        row.base_version,
        row.payload_schema_version,
        row.raw_payload_json,
        row.source_device_id,
        row.updated_at,
    ])?;
    Ok(())
}

pub fn remove_shadow(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<(), PayloadError> {
    conn.prepare_cached(
        "DELETE FROM sync_payload_shadow WHERE entity_type = ?1 AND entity_id = ?2",
    )?
    .execute(params![entity_type, entity_id])?;
    Ok(())
}

pub fn remove_shadow_if_superseded(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> Result<(), PayloadError> {
    let Some(existing) = get_shadow(conn, entity_type, entity_id)? else {
        return Ok(());
    };
    // Audit (payload_shadow F4): a corrupted persisted `base_version`
    // (legacy data, manual DB edit, future schema bug) fail
    // the entire apply path here — one bad shadow row blocked every
    // subsequent envelope for that entity. We can't compare a
    // malformed version against the candidate, so we also can't
    // claim the shadow is preserving anything useful: log and delete
    // it so the candidate envelope can proceed.
    let shadow_version = match parse_hlc(&existing.base_version, "payload shadow base_version") {
        Ok(v) => v,
        Err(e) => {
            crate::support::append_error_log_best_effort(
                conn,
                "store.payload_shadow.corrupted_base_version",
                "corrupted base_version on persisted payload shadow",
                Some(&format!(
                    "entity_type={entity_type} entity_id={entity_id} base_version={} \
                     source_device_id={} error={e}",
                    existing.base_version, existing.source_device_id
                )),
                Some("warn"),
            );
            return remove_shadow(conn, entity_type, entity_id);
        }
    };
    let candidate = parse_hlc(version, "payload shadow candidate version")?;
    if candidate >= shadow_version {
        remove_shadow(conn, entity_type, entity_id)?;
    }
    Ok(())
}
