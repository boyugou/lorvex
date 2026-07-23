//! Write-side tombstone primitives — create/remove tombstones and update
//! per-device sync cursors. Cursor updates live here because they are the
//! write-domain inputs the watermark GC reads back ([`super::gc`]).

use lorvex_sync_payload::payload_shadow::{merge_shadow_into_redirect, remove_shadow};
use rusqlite::{params, Connection, OptionalExtension};

/// Record or update a device's sync cursor.
///
/// `last_sync_at` is wall-clock for device-lifecycle (active/inactive).
/// `last_applied_version` is HLC for the version-domain watermark.
/// Call this whenever a device completes a sync cycle.
pub fn upsert_device_cursor(
    conn: &Connection,
    device_id: &str,
    last_sync_at: &str,
) -> Result<(), rusqlite::Error> {
    upsert_device_cursor_with_version(conn, device_id, last_sync_at, None)
}

/// Record or update a device's sync cursor with an HLC version.
///
/// the `?3 > sync_device_cursors.last_applied_version`
/// clause relies on HLC TEXT strings being fixed-width lex-orderable.
/// The invariant `lorvex_domain::hlc::Hlc` enforces (13-digit
/// physical-ms zero-padded, `_`, 4-digit logical-counter zero-padded,
/// `_`, device-suffix) guarantees lexicographic order matches semantic
/// order; truncating, padding, or hand-editing an HLC could break
/// this comparison silently. The version-stamping helpers
/// (`version_stamp.rs`, `outbox_enqueue.rs::stamp_version`) are the
/// only paths that produce an HLC for storage, and both route through
/// the canonical [`Hlc::Display`] impl, so the invariant holds
/// end-to-end. See also `apply/mod.rs` audit `#2946-M5` which uses
/// typed `Hlc::parse` for in-process comparisons; SQL paths cross a
/// SQLite boundary that has no HLC awareness, so we lean on the
/// fixed-width invariant here rather than round-tripping through Rust.
pub fn upsert_device_cursor_with_version(
    conn: &Connection,
    device_id: &str,
    last_sync_at: &str,
    last_applied_version: Option<&str>,
) -> Result<(), rusqlite::Error> {
    debug_assert!(
        last_applied_version.is_none_or(|v| lorvex_domain::hlc::Hlc::parse(v).is_ok()),
        "last_applied_version must be a canonical-format HLC string parseable by Hlc::parse \
         (the lex compare in the upsert below relies on this — got {last_applied_version:?})"
    );
    conn.execute(
        "INSERT INTO sync_device_cursors (device_id, last_sync_at, last_applied_version)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(device_id) DO UPDATE SET
             last_sync_at = CASE WHEN ?2 > sync_device_cursors.last_sync_at THEN ?2 ELSE sync_device_cursors.last_sync_at END,
             last_applied_version = CASE WHEN ?3 IS NOT NULL AND (?3 > sync_device_cursors.last_applied_version OR sync_device_cursors.last_applied_version IS NULL) THEN ?3 ELSE sync_device_cursors.last_applied_version END",
        params![device_id, last_sync_at, last_applied_version],
    )?;
    Ok(())
}

/// Create or update a tombstone with version monotonicity.
///
/// A newer tombstone always overwrites an older one. An older tombstone
/// is silently ignored. This guarantee is enforced by the primitive
/// itself — callers do not need to check versions first.
///
/// same-version tombstones (`excluded.version =
/// sync_tombstones.version`) are NOT overwritten — the existing row
/// wins. In practice the same `version` is the same HLC, which means
/// the same wall-clock-microsecond + counter + 8-char device-suffix
/// triple; producing two genuinely-distinct tombstones at the same
/// HLC requires a device-suffix collision, which is itself
/// surfaced as an `error_logs` entry by the apply pipeline (#2192).
/// In the absence of a real collision, "same version, conflicting
/// redirect_entity_id" cannot occur — so the documented policy is
/// "first writer wins on tie" and the cluster recovers when the
/// device-suffix collision is repaired. Switching to `>=` with a
/// device-suffix tiebreak would narrow the window further but at
/// the cost of a non-trivial second-key sort that shadow-promotion
/// (`payload_shadow::merge_shadow_into_redirect`) would also have
/// to honor; we accept the residual risk and keep monotonicity
/// strict on the primitive's contract.
pub fn create_tombstone(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
    deleted_at: &str,
    redirect_entity_id: Option<&str>,
    redirect_entity_type: Option<&str>,
) -> Result<(), lorvex_store::StoreError> {
    // reject a self-redirect at the write boundary. A
    // tombstone whose `redirect_entity_*` points at its own
    // `(entity_type, entity_id)` tuple is nonsensical — the redirect
    // chase loop in `apply/mod.rs` (`follow_redirect_chain`) treats
    // such a row as a one-hop cycle and aborts with `RedirectCycle`,
    // which is correct at read time but only fires once the bad row
    // has already been written and observed by the apply pipeline.
    // Validating at the primitive entry point keeps the bad shape
    // out of `sync_tombstones` entirely so neither `apply_envelope`
    // nor `payload_shadow::merge_shadow_into_redirect` can be tripped
    // by it. Cross-type "self" redirects (same id, different
    // entity_type — e.g. a `task` → `habit` merge that happens to
    // reuse an id by accident) are still permitted because the
    // tuple identity differs; the redirect chase honours
    // `entity_type` as part of the key.
    if let Some(redirect_id) = redirect_entity_id {
        let redirect_type = redirect_entity_type.unwrap_or(entity_type);
        if redirect_id == entity_id && redirect_type == entity_type {
            return Err(lorvex_store::StoreError::Validation(format!(
                "self-redirect tombstone rejected: ({entity_type}, {entity_id}) cannot \
                 redirect to itself"
            )));
        }
    }
    // cascade-delete loops in `helpers::tombstone_*`
    // call this primitive once per child row, so the
    // per-call `conn.execute` was re-preparing + re-planning the same
    // ON-CONFLICT INSERT for every tombstoned edge. Routing through
    // `prepare_cached` collapses N prepares into one for the entire
    // cascade of a single parent delete.
    //
    // Adopt the parse-then-typed-compare discipline shared with
    // `outbox::coalesce::enqueue_coalesced` and
    // `version_stamp::stamp_entity_version`.
    // monotonicity guard was a SQL byte-compare via
    // `excluded.version > sync_tombstones.version` — correct for
    // canonical HLCs but invertible when one side is a stale-shape
    // literal (`'v1'`, `'seed'`, hand-edited DB), since ASCII letters
    // sort ABOVE digits. A tainted existing tombstone could falsely
    // win the monotonicity check and silently swallow a legitimately-
    // newer Delete envelope from a peer.
    //
    // The fix: read the existing row's version first, parse both
    // sides, prefer typed `Hlc::cmp` whenever both parse, and fall
    // back to byte-compare only when both fail to parse (so the
    // tombstone write still terminates on a legacy DB rather than
    // panicking). Partial-tainted cases log + treat the canonical
    // side as the unambiguous winner — same shape as outbox.
    //
    // Existing tests still inject bad-shape version strings to
    // exercise downstream graceful-error paths in `apply_envelope`;
    // those continue to work because the byte-fallback honors the
    // historical lex-compare for both-tainted pairs.
    let existing_version: Option<String> = {
        let mut stmt = conn.prepare_cached(
            "SELECT version FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2 \
             LIMIT 1",
        )?;
        stmt.query_row(params![entity_type, entity_id], |row| row.get(0))
            .optional()?
    };

    let should_write = existing_version.as_deref().is_none_or(|existing| {
        let existing_parse = lorvex_domain::hlc::Hlc::parse(existing);
        let incoming_parse = lorvex_domain::hlc::Hlc::parse(version);
        match (&existing_parse, &incoming_parse) {
            (Ok(existing_hlc), Ok(incoming_hlc)) => incoming_hlc > existing_hlc,
            (Err(_), Err(_)) => {
                // Both tainted: best-effort byte compare so the
                // tombstone write terminates on a legacy DB.
                let dedup_signature =
                    format!("tombstone_create|{entity_type}|{entity_id}|both_tainted");
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.tombstone.create_unparseable_version",
                    &format!(
                        "tombstone monotonicity byte-compare fallback for \
                             entity_type={entity_type}, entity_id={entity_id}, \
                             incoming={version:?} (parsed=false), \
                             existing={existing:?} (parsed=false)"
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
                version > existing
            }
            (Ok(_), Err(_)) => {
                // Canonical incoming vs tainted existing: treat
                // the tainted predecessor as monotonicity-loser
                // and let the canonical incoming overwrite. The
                // re-write clears the taint in the same call.
                let dedup_signature = format!(
                    "tombstone_create|{entity_type}|{entity_id}|incoming_ok=true|existing_ok=false"
                );
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.tombstone.create_unparseable_version",
                    &format!(
                        "tombstone monotonicity partial-tainted fallback for \
                             entity_type={entity_type}, entity_id={entity_id}, \
                             incoming={version:?} (parsed=true), \
                             existing={existing:?} (parsed=false); \
                             treating tainted existing as monotonicity-loser"
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
                true
            }
            (Err(_), Ok(_)) => {
                // Tainted incoming vs canonical existing: keep
                // the canonical predecessor.
                let dedup_signature = format!(
                    "tombstone_create|{entity_type}|{entity_id}|incoming_ok=false|existing_ok=true"
                );
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.tombstone.create_unparseable_version",
                    &format!(
                        "tombstone monotonicity partial-tainted fallback for \
                             entity_type={entity_type}, entity_id={entity_id}, \
                             incoming={version:?} (parsed=false), \
                             existing={existing:?} (parsed=true); \
                             keeping canonical existing"
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
                false
            }
        }
    });

    let updated = if should_write {
        if existing_version.is_some() {
            let mut stmt = conn.prepare_cached(
                "UPDATE sync_tombstones SET
                    version = ?3,
                    deleted_at = ?4,
                    redirect_entity_id = ?5,
                    redirect_entity_type = ?6
                 WHERE entity_type = ?1 AND entity_id = ?2",
            )?;
            stmt.execute(params![
                entity_type,
                entity_id,
                version,
                deleted_at,
                redirect_entity_id,
                redirect_entity_type,
            ])?
        } else {
            let mut stmt = conn.prepare_cached(
                "INSERT INTO sync_tombstones
                    (entity_type, entity_id, version, deleted_at,
                     redirect_entity_id, redirect_entity_type)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            stmt.execute(params![
                entity_type,
                entity_id,
                version,
                deleted_at,
                redirect_entity_id,
                redirect_entity_type,
            ])?
        }
    } else {
        0
    };

    if updated > 0 {
        if let Some(redirect_id) = redirect_entity_id {
            let redirect_type = redirect_entity_type.unwrap_or(entity_type);
            merge_shadow_into_redirect(conn, entity_type, entity_id, redirect_type, redirect_id)?;
        } else {
            remove_shadow(conn, entity_type, entity_id)?;
        }
    }
    Ok(())
}

/// Remove a specific tombstone by (entity_type, entity_id).
///
/// Used when a concurrent-update-wins-over-concurrent-delete scenario is
/// resolved: an upsert with a strictly newer version than the tombstone wins,
/// so the tombstone is removed.
pub fn remove_tombstone(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<bool, rusqlite::Error> {
    let deleted = conn.execute(
        "DELETE FROM sync_tombstones WHERE entity_type = ?1 AND entity_id = ?2",
        params![entity_type, entity_id],
    )?;
    Ok(deleted > 0)
}
