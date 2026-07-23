//! Cross-type / same-type redirect consolidation for payload shadows.
//!
//! [`merge_shadow_into_redirect`] folds a loser shadow row into the
//! redirect target. For cross-type redirects the loser is dropped (with
//! diagnostics) because forward-compat unknown keys cannot safely cross
//! schemas. For same-type redirects it runs a SAVEPOINT-protected
//! read-merge-write driven by [`merge_shadow_rows`] (an HLC-ordered LWW
//! combiner) with an explicit CAS re-check on the winner's
//! `base_version` to defeat concurrent writers.

use super::super::{parse_hlc, PayloadShadowRow};
use super::helpers::parse_json_object;
use crate::error::PayloadError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::Value;

pub fn merge_shadow_into_redirect(
    conn: &Connection,
    from_entity_type: &str,
    from_entity_id: &str,
    to_entity_type: &str,
    to_entity_id: &str,
) -> Result<(), PayloadError> {
    let Some(loser) = super::super::crud::get_shadow(conn, from_entity_type, from_entity_id)?
    else {
        return Ok(());
    };
    // Cross-type redirects are allowed but cannot safely preserve raw payload
    // ownership semantics across two different schemas. Drop the loser shadow
    // in that case rather than misapplying fields onto the winner type.
    //
    // silently dropping the shadow loses any
    // forward-compat unknown_field bytes the loser preserved for a
    // peer running a newer schema. Surface the drop to error_logs so
    // a recurring cross-type redirect (which is itself a rare event)
    // is visible in Settings → Diagnostics; the loser's raw_payload
    // is included in the details so an operator can inspect what was
    // dropped. Best-effort logging — the redirect itself must
    // succeed even if the diagnostic write fails.
    if from_entity_type != to_entity_type {
        crate::support::append_error_log_best_effort(
            conn,
            "store.payload_shadow.cross_type_redirect_drop",
            &format!(
                "redirect {from_entity_type}:{from_entity_id} -> \
                 {to_entity_type}:{to_entity_id} crosses entity types; \
                 loser shadow dropped (forward-compat unknown fields lost)"
            ),
            Some(&loser.raw_payload_json),
            Some("warn"),
        );
        // the warn-level error_log entry above is
        // useful for debugging but does not surface in the
        // dedicated Settings → Sync → Conflicts panel — that
        // surface reads ONLY from `sync_conflict_log`. Without a
        // conflict-log row, an operator triaging "we lost some
        // forward-compat data on a cross-schema redirect" had no
        // canonical view; the row was buried in the error feed
        // alongside permission failures and disk-IO blips. Promote
        // the drop into the conflict surface with the new
        // `RESOLUTION_CROSS_TYPE_REDIRECT_DROP` resolution_type so
        // it sits next to every other LWW / merge / tombstone
        // outcome in the same view.
        //
        // Mirror `lorvex_sync::conflict_log::log_conflict`'s
        // natural-key dedupe contract: same entity identity,
        // loser_version, device, resolution_type, AND payload
        // collapse to one row. The loser's `source_device_id` is
        // the device that authored the dropped shadow; if it's
        // empty (legacy import-archive rows), persist as-is — the
        // schema requires the column non-null but does not
        // forbid the empty string. The winner_version reads from
        // the redirect target's existing shadow when present, and
        // falls back to the loser's own base_version when the
        // target has no shadow yet (the redirect target may be a
        // brand-new entity created by the merge). Falling back to
        // the loser version is honest — the actual winning HLC is
        // whatever merge tombstone caused this redirect, but that
        // tombstone is several call frames above and not available
        // here without threading.
        let winner_version = super::super::crud::get_shadow(conn, to_entity_type, to_entity_id)?
            .map_or_else(|| loser.base_version.clone(), |w| w.base_version);
        let resolved_at = lorvex_domain::sync_timestamp_now();
        // Best-effort: never block the redirect on a diagnostic
        // write. The conflict_log INSERT can fail under disk-full
        // or schema drift but the merge MUST proceed so the
        // redirect chain stays consistent. The error_log entry
        // above already captured the raw_payload bytes for forensic
        // recovery.
        //
        // The INSERT Result must NOT be discarded via `let _`. A
        // schema-drift INSERT failure swallowed by `let _` would be
        // completely invisible — the cross-type redirect would drop
        // a shadow with forward-compat unknown bytes AND the
        // conflict-log surface meant to record it would silently
        // lose the row. Surface the secondary failure to error_logs
        // (best-effort) and `debug_assert!` so test runs catch a
        // regression that breaks the conflict-log INSERT path.
        let insert_result = conn
            .prepare_cached(
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
            )
            .and_then(|mut stmt| {
                stmt.execute(rusqlite::params![
                    from_entity_type,
                    from_entity_id,
                    winner_version,
                    loser.base_version,
                    loser.source_device_id,
                    loser.raw_payload_json,
                    resolved_at,
                    lorvex_domain::naming::RESOLUTION_CROSS_TYPE_REDIRECT_DROP,
                ])
            });
        if let Err(insert_err) = insert_result {
            crate::support::append_error_log_best_effort(
                conn,
                "store.payload_shadow.conflict_log_insert_failed",
                &format!(
                    "sync_conflict_log INSERT failed for cross-type redirect drop \
                     {from_entity_type}:{from_entity_id} -> \
                     {to_entity_type}:{to_entity_id}: {insert_err}"
                ),
                Some(&loser.raw_payload_json),
                Some("error"),
            );
            debug_assert!(
                false,
                "sync_conflict_log INSERT failed during cross-type redirect drop: {insert_err}",
            );
        }
        super::super::crud::remove_shadow(conn, from_entity_type, from_entity_id)?;
        return Ok(());
    }

    // read-merge-write under an explicit SAVEPOINT
    // with a CAS re-check.
    //
    // The shape of this routine is "read winner → merge with loser
    // → write merged back → drop loser." In production every apply
    // pipeline path that reaches us runs inside the outer
    // `BEGIN IMMEDIATE` (`apply_envelope` enforces it via
    // `assert_in_transaction`) so SQLite's single-writer lock
    // serializes all writers and the read-snapshot-write window
    // cannot in fact be interrupted by a concurrent winner update.
    // But the contract of this primitive does not advertise that
    // requirement — `create_tombstone` calls us from the sync
    // layer, but a future caller (import path, manual repair tool,
    // a maintenance routine that opens a fresh connection) could
    // run it outside an outer transaction. Without a CAS, a
    // concurrent writer that bumped the winner's base_version
    // between our `get_shadow` and `restore_shadow` would have its
    // newer row clobbered by our stale merge — exactly the silent
    // data-loss shape `restore_shadow`'s `>= base_version`
    // predicate exists to prevent for the FORWARD path, but here
    // the merged row carries `winner.base_version` which equals
    // the value already in the table — `>=` admits the overwrite
    // even though the table state has actually advanced.
    //
    // Wrap the read-merge-write in a SAVEPOINT and verify the
    // winner's base_version is unchanged at write time. Routes
    // through `transaction::with_savepoint` so a panic inside the
    // closure (e.g. allocator OOM mid-`merge_shadow_rows` on a
    // 250 KiB payload) tears the savepoint down BEFORE the unwind
    // resumes — the next writer otherwise inherits a dangling
    // `merge_shadow_redirect` frame and fails with "no such savepoint"
    // once the outer Mutex recovers from poison. The helper also
    // assigns a unique name via `SAVEPOINT_COUNTER` so concurrent
    // invocations don't collide. On the rare CAS-fail case we
    // surface a typed `Validation` error and the helper auto-
    // rollbacks; the caller can decide whether to retry or escalate.
    crate::support::with_savepoint(conn, "merge_shadow_redirect", |conn| {
        let winner = super::super::crud::get_shadow(conn, to_entity_type, to_entity_id)?;
        let winner_base_version_before = winner.as_ref().map(|w| w.base_version.clone());
        let merged = if let Some(ref w) = winner {
            merge_shadow_rows(w, &loser)?
        } else {
            // Parse `to_entity_type` at the boundary; the redirect
            // target type is derived from a tombstone column whose
            // value originated as a typed `EntityKind` upstream.
            // An unknown value here would also be rejected by the
            // SQLite read in `crud::get_shadow`, but parsing here
            // keeps the typed carrier honest at construction time.
            let to_kind =
                lorvex_domain::naming::EntityKind::try_parse(to_entity_type).map_err(|err| {
                    PayloadError::Invariant(format!(
                    "merge_shadow_into_redirect: redirect target entity_type {to_entity_type:?} \
                     is not a known EntityKind: {err}"
                ))
                })?;
            PayloadShadowRow {
                entity_type: to_kind,
                entity_id: to_entity_id.to_string(),
                // Inherit the loser's `source_device_id` since we're
                // hoisting its content into the redirect target slot.
                ..loser.clone()
            }
        };

        // CAS: re-read the winner's base_version under the savepoint
        // and verify it matches what we observed before the merge.
        // SQLite's `INSERT … ON CONFLICT DO UPDATE` does not expose a
        // "WHERE current_value = ?" predicate that distinguishes
        // "no winner row" from "winner row with this base_version,"
        // so the explicit re-read is the cleanest portable shape.
        let winner_base_version_after: Option<String> = conn
            .query_row(
                "SELECT base_version FROM sync_payload_shadow
                 WHERE entity_type = ?1 AND entity_id = ?2",
                rusqlite::params![to_entity_type, to_entity_id],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        if winner_base_version_before != winner_base_version_after {
            // A concurrent writer slipped a winner update in between
            // our snapshot and the CAS check. The helper auto-rolls
            // back so the merged-but-not-yet-written state is discarded
            // and the loser shadow stays intact (a future apply pass
            // can re-attempt the merge against the new winner).
            return Err(PayloadError::Validation(format!(
                "merge_shadow_into_redirect: concurrent winner update on \
                 {to_entity_type}:{to_entity_id} (base_version changed from \
                 {winner_base_version_before:?} to {winner_base_version_after:?}); \
                 merge aborted, loser shadow preserved for retry"
            )));
        }

        super::super::crud::restore_shadow(conn, &merged)?;
        super::super::crud::remove_shadow(conn, from_entity_type, from_entity_id)?;
        Ok(())
    })
}

/// HLC-ordered LWW combiner for two shadow rows targeting the same
/// redirect terminus. The newer-versioned row wins as the `base`; the
/// older row's keys are unioned in only where the base does not already
/// supply them, so forward-compat unknown bytes from the loser side are
/// preserved without overwriting anything the winner authored.
fn merge_shadow_rows(
    winner: &PayloadShadowRow,
    loser: &PayloadShadowRow,
) -> Result<PayloadShadowRow, PayloadError> {
    let winner_version = parse_hlc(&winner.base_version, "winner payload shadow base_version")?;
    let loser_version = parse_hlc(&loser.base_version, "loser payload shadow base_version")?;
    let (base, overlay) = if loser_version > winner_version {
        (loser, winner)
    } else {
        (winner, loser)
    };

    let mut merged_json = parse_json_object(
        &base.raw_payload_json,
        "base payload shadow raw_payload_json",
    )?;
    let overlay_obj = parse_json_object(
        &overlay.raw_payload_json,
        "overlay payload shadow raw_payload_json",
    )?;
    for (key, value) in overlay_obj {
        merged_json.entry(key).or_insert(value);
    }

    Ok(PayloadShadowRow {
        entity_type: winner.entity_type,
        entity_id: winner.entity_id.clone(),
        base_version: base.base_version.clone(),
        payload_schema_version: base
            .payload_schema_version
            .max(overlay.payload_schema_version),
        raw_payload_json: serde_json::to_string(&Value::Object(merged_json))?,
        // Inherit the `base` shadow's `source_device_id` since we
        // keep its `base_version` — the (version, device) pair must
        // stay consistent so promote_payload_shadows can replay
        // with correct attribution (#2875).
        source_device_id: base.source_device_id.clone(),
        // Use `sync_timestamp_now()` (millisecond `Z` form, see
        // `lorvex-domain/src/time/sync_timestamp.rs`) instead of
        // `Utc::now().to_rfc3339()` (nanosecond `+00:00` form). Payload
        // shadow rows are upserted during sync apply and may be compared
        // via lex ORDER BY updated_at in diagnostic paths — mixed formats
        // would flip the ordering. Same lex drift class as R5/R11.
        updated_at: lorvex_domain::sync_timestamp_now(),
    })
}
