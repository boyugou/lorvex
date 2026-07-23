//! Indexed bulk-merge path for export pipelines.
//!
//! [`ShadowIndex`] pre-loads `(entity_type, entity_id)` membership for
//! both `sync_payload_shadow` and the cross-type-redirect subset of
//! `sync_tombstones` in a single pass. Per-row callers route through
//! [`merge_payload_with_shadow_indexed`] which short-circuits the two
//! point-SELECTs that
//! [`super::single::merge_payload_with_shadow`] would otherwise issue
//! against rows that the index already proves have neither a shadow
//! nor a cross-type redirect.

use super::helpers::{
    cross_type_redirect_tombstone_present, merge_payload_with_shadow_after_lookup,
};
use crate::error::PayloadError;
use rusqlite::Connection;
use serde_json::Value;
use std::collections::{HashMap, HashSet};

/// Pre-built `(entity_type, entity_id)` membership cache used by export
/// pipelines that loop `merge_payload_with_shadow` over many rows.
///
/// `merge_payload_with_shadow` issues two point-SELECTs per call —
/// `sync_payload_shadow` and `sync_tombstones` — even when the
/// overwhelming majority of entities have neither a shadow row nor a
/// cross-type redirect tombstone. On a 50 k-task export that's
/// 100 k+ index probes for nothing. The index pulls both tables
/// once and lets the per-row caller short-circuit when the key is
/// guaranteed-absent.
///
/// Build once per export with [`Self::build`], then route each row
/// through [`merge_payload_with_shadow_indexed`] instead of the
/// unindexed wrapper.
pub struct ShadowIndex {
    // Nested map keyed by `entity_type` → `entity_id` set. The previous
    // `HashSet<(String, String)>` shape forced every probe to allocate
    // two `String`s to construct the composite lookup key — for a
    // 50 k-task export that is 100 k throwaway heap allocations on the
    // very path the index exists to make cheap. Splitting the key lets
    // both lookups go through `Borrow<str>` without allocating.
    has_shadow: HashMap<String, HashSet<String>>,
    // Same-shape parallel index for cross-type redirect tombstones. A
    // `merge_payload_with_shadow` call against a `(type, id)` that has
    // a shadow but no cross-type redirect tombstone can skip the
    // per-row tombstone SELECT entirely, so the export pass avoids
    // an extra point-SELECT per row.
    cross_type_redirects: HashMap<String, HashSet<String>>,
}

impl ShadowIndex {
    pub fn build(conn: &Connection) -> Result<Self, PayloadError> {
        Ok(Self {
            has_shadow: collect_entity_index(
                conn,
                "SELECT entity_type, entity_id FROM sync_payload_shadow",
            )?,
            cross_type_redirects: collect_entity_index(
                conn,
                "SELECT entity_type, entity_id FROM sync_tombstones \
                 WHERE redirect_entity_type IS NOT NULL \
                   AND redirect_entity_type != entity_type",
            )?,
        })
    }

    fn contains(&self, entity_type: &str, entity_id: &str) -> bool {
        self.has_shadow
            .get(entity_type)
            .is_some_and(|ids| ids.contains(entity_id))
    }

    fn has_cross_type_redirect(&self, entity_type: &str, entity_id: &str) -> bool {
        self.cross_type_redirects
            .get(entity_type)
            .is_some_and(|ids| ids.contains(entity_id))
    }
}

/// Run a `SELECT entity_type, entity_id FROM ...` query and bucket the
/// results into `entity_type → set<entity_id>`. Shared between the
/// shadow-presence and cross-type-redirect indexes that
/// [`ShadowIndex::build`] populates from two distinct source tables.
fn collect_entity_index(
    conn: &Connection,
    sql: &str,
) -> Result<HashMap<String, HashSet<String>>, PayloadError> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut index: HashMap<String, HashSet<String>> = HashMap::new();
    for row in rows {
        let (entity_type, entity_id) = row?;
        index.entry(entity_type).or_default().insert(entity_id);
    }
    Ok(index)
}

/// `merge_payload_with_shadow` driven by a pre-built [`ShadowIndex`].
///
/// When the index proves the row has no shadow, returns
/// `known_payload.clone()` immediately without touching the DB. When the
/// index says "shadow present but no cross-type redirect," skip the
/// per-row `sync_tombstones` SELECT entirely — the index already proved
/// it absent. Only when both shadow AND a
/// redirect are indexed does the helper run the per-row recheck (the
/// redirect predicate may be tighter than the index's coarse filter).
pub fn merge_payload_with_shadow_indexed(
    conn: &Connection,
    index: &ShadowIndex,
    entity_type: &str,
    entity_id: &str,
    known_payload: &Value,
) -> Result<Value, PayloadError> {
    if !index.contains(entity_type, entity_id) {
        return Ok(known_payload.clone());
    }
    let Some(shadow) = super::super::crud::get_shadow(conn, entity_type, entity_id)? else {
        return Ok(known_payload.clone());
    };
    let cross_type_tombstone_present = if index.has_cross_type_redirect(entity_type, entity_id) {
        // Index reports a redirect — re-read for the concrete
        // tombstone shape so the merge sees the same predicate the
        // unindexed path would (cheap on the rare-case path).
        cross_type_redirect_tombstone_present(conn, entity_type, entity_id)?
    } else {
        // Index proves no same-key cross-type redirect exists; skip
        // the SELECT round-trip on the bulk-shadow happy path.
        false
    };
    merge_payload_with_shadow_after_lookup(
        conn,
        entity_type,
        entity_id,
        known_payload,
        &shadow,
        cross_type_tombstone_present,
    )
}
