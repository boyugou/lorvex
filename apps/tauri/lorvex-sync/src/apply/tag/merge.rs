use super::*;

// ---------------------------------------------------------------------------
// Tag merge logic
// ---------------------------------------------------------------------------

/// If two tags share the same `lookup_key`, merge them: min ID wins, re-point
/// task_tags, delete + tombstone the loser.
pub(super) fn merge_duplicate_tags(
    conn: &Connection,
    _just_upserted_id: &str,
    lookup_key: &str,
    version: &str,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    // Pull `id` AND `version` in a single SELECT instead of one
    // row-id list + N per-row version lookups. The combined query
    // is one round-trip regardless of merge fan-out; walking `tags`
    // twice (once for ids, then N single-row queries inside the
    // version-max loop) would cost 3 round-trips for a typical
    // 2-tag merge and N+1 for an N-way merge.
    let mut stmt =
        conn.prepare_cached("SELECT id, version FROM tags WHERE lookup_key = ?1 ORDER BY id ASC")?;
    let tag_rows: Vec<(String, String)> = stmt
        .query_map([lookup_key], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    if tag_rows.len() <= 1 {
        return Ok(()); // No duplicate.
    }

    // unzip the (id, version) pairs once instead
    // of cloning ids out into a parallel Vec. The two halves are used
    // independently below — `tag_ids` for the winner/loser walk,
    // `tag_versions` for the max-HLC computation — so building them
    // in a single pass avoids allocating a throwaway clone of every
    // id string.
    let (tag_ids, tag_versions): (Vec<String>, Vec<String>) = tag_rows.into_iter().unzip();
    // Winner = min ID (first in sorted order).
    let winner_id = &tag_ids[0];

    // Compute a merge version that's guaranteed greater than all participants.
    // Every participant version must be parseable; otherwise the local tag
    // state is corrupted and we must fail rather than fabricate a merge HLC.
    let mut max_hlc = Hlc::parse(version)?;
    for tag_version in &tag_versions {
        let tag_hlc = Hlc::parse(tag_version)?;
        if tag_hlc > max_hlc {
            max_hlc = tag_hlc;
        }
    }

    // use the LOCAL device's suffix on the merge
    // tombstone, not whichever input tag happened to have the highest
    // HLC. The suffix is documented as "originating device"; writing
    // a tombstone here IS a local authoring event even though the
    // timestamp/counter are chosen to sort past every participant.
    // the merge inherited a remote peer's suffix, which
    // broke device-id filters in remote device-cursor recording /
    // conflict_log / HLC clock observation, and could cause the
    // local HLC state to observe "its own" tombstone as a remote one.
    let local_device_suffix =
        read_local_device_hlc_suffix(conn).unwrap_or_else(|| max_hlc.device_suffix().to_string());
    let merge_hlc = mint_merge_hlc_after(&max_hlc, &local_device_suffix, "tag merge")?;
    let merge_version = merge_hlc.to_string();

    // feed the freshly-minted merge HLC back into the
    // process-wide HlcState so subsequent local emissions strictly
    // dominate it. The merge mints this HLC via direct `Hlc::new(...)`
    // — never through `hlc_state.generate()` — so without this hook
    // the in-process clock has no record of having emitted it, and a
    // subsequent local edit could produce an HLC that lex-orders
    // BELOW the just-stamped task_tags rows. Mirror of the recurrence
    // merge fix; see `apply::aggregate::recurrence` for the full
    // rationale.
    //
    // dev-only invariant: production callers (Tauri
    // startup, MCP startup) MUST have installed the observer at boot.
    // Forgotten wire-up would silently mint an HLC the caller's
    // HlcState never learns about. Fail loudly in dev/test so the
    // regression surfaces here. See the parallel debug_assert in
    // `apply::aggregate::recurrence` for the full rationale.
    #[cfg(all(debug_assertions, not(test)))]
    debug_assert!(
        crate::hlc::production_observer_is_installed(),
        "tag merge minted a local HLC but no production observer is wired in — \
         call `lorvex_sync::hlc::set_local_event_observer` from your app/MCP startup so \
         subsequent local emissions strictly dominate merge_version"
    );
    crate::hlc::observe_local_event(&merge_hlc);

    // Wrap the multi-step merge in a savepoint so a partial failure
    // does not leave task_tags re-pointed but the loser tag still present.
    //
    // Routes through `lorvex_store::transaction::with_savepoint_mapped`
    // so a panic inside the merge (e.g. a poisoned tag row, an
    // unwrap on a stale-shape `version` literal) rolls the
    // savepoint back BEFORE the unwind resumes. A hand-rolled
    // `SAVEPOINT … ; RELEASE` block would leave the savepoint
    // dangling on the connection on panic, and the next write
    // would fail with "no such savepoint" even after the outer
    // mutex recovered from poison.
    lorvex_store::transaction::with_savepoint_mapped(
        conn,
        "merge_tags",
        ApplyError::InvalidPayload,
        |conn| {
            // lift the 3 per-loser SQLs into
            // `prepare_cached` handles bound ONCE before the loop.
            // Mirrors the H1 refactor in `apply::aggregate::recurrence`
            // and the pattern documented at `tombstone::create_tombstone`.
            let mut stmt_repoint_task_tags = conn.prepare_cached(
            "INSERT INTO task_tags (task_id, tag_id, created_at, version)
             SELECT task_id, :winner_id, :now, :merge_version FROM task_tags WHERE tag_id = :loser_id
             ON CONFLICT(task_id, tag_id) DO UPDATE SET
                 version = :merge_version,
                 created_at = excluded.created_at",
        )?;
            let mut stmt_delete_task_tags =
                conn.prepare_cached("DELETE FROM task_tags WHERE tag_id = ?1")?;
            let mut stmt_delete_loser_tag =
                conn.prepare_cached("DELETE FROM tags WHERE id = ?1")?;

            // Pre-load winner + every loser's distinguishing fields in
            // a single `WHERE id IN (...)` round-trip.
            // site issued one `prepare_cached` query per loser inside the
            // merge loop (the helper still wrapped winner+loser in one
            // round trip, but every loser repeated the prepare). At
            // typical fan-out this is fine, but the recurrence-merge
            // sibling already coalesces the equivalent reads cluster-wide,
            // and the symmetry is worth the small refactor.
            let losers: &[String] = &tag_ids[1..];
            let mut tag_fields = read_tag_merge_fields(conn, winner_id, losers)?;
            let winner_fields = tag_fields.remove(winner_id).ok_or_else(|| {
                ApplyError::Store(lorvex_store::StoreError::Invariant(format!(
                    "tag merge winner row missing for id={winner_id}"
                )))
            })?;

            for loser_id in losers {
                // capture the loser tag's distinguishing
                // fields BEFORE the delete and log a `tag_merge` conflict
                // entry whenever they differ from the winner. Mirror of
                // the recurrence-merge fix (#2828) — the previous code
                // silently dropped the loser's `display_name` / `color`
                // with no diagnostic trail.
                let loser_fields = tag_fields.remove(loser_id).ok_or_else(|| {
                    ApplyError::Store(lorvex_store::StoreError::Invariant(format!(
                        "tag merge fields read missed loser row: winner_id={winner_id} loser_id={loser_id}"
                    )))
                })?;
                let divergent = compute_tag_divergence(&winner_fields, loser_fields);
                if let Some((loser_payload, loser_version)) = divergent {
                    // share the once-per-envelope `apply_ts`.
                    let resolved_at = apply_ts.to_string();
                    // Audit (silent-failure-hunter):
                    // `Hlc::parse(...).map(...).unwrap_or_default()`
                    // turned a corrupt HLC into `""` indistinguishable
                    // from a genuinely empty device suffix. Surface
                    // the corruption to error_logs so diagnostics
                    // can flag it while still completing the merge —
                    // the user still gets the conflict entry; only
                    // the provenance attribution is degraded.
                    let loser_device_id = match lorvex_domain::hlc::Hlc::parse(&loser_version) {
                        Ok(h) => h.device_suffix().to_string(),
                        Err(parse_err) => {
                            crate::error_log::log_sync_error(
                                conn,
                                "sync.apply.tag_merge_corrupt_loser_hlc",
                                &format!(
                                    "loser HLC '{loser_version}' on tag merge for winner {winner_id} (loser {loser_id}) \
                                     is not a valid HLC: {parse_err}"
                                ),
                                None,
                            );
                            String::new()
                        }
                    };
                    crate::conflict_log::log_conflict(
                        conn,
                        &crate::conflict_log::ConflictLogEntry {
                            id: 0,
                            entity_type: std::borrow::Cow::Borrowed(
                                lorvex_domain::naming::EntityKind::Tag.as_str(),
                            ),
                            entity_id: winner_id.clone(),
                            winner_version: merge_version.clone(),
                            loser_version,
                            loser_device_id,
                            loser_payload: Some(loser_payload),
                            resolved_at,
                            resolution_type: std::borrow::Cow::Borrowed(
                                naming::RESOLUTION_TAG_MERGE,
                            ),
                        },
                    )?;
                }

                // stamp re-pointed task_tags rows with
                // `merge_version` so subsequent local edits emit
                // envelopes whose version dominates every participant's
                // pre-merge HLC. Without this, peers would reject the
                // first post-merge edge envelope as LWW-stale because
                // the row carried the loser's pre-merge version. Mirror
                // of the recurrence-merge fix in `recurrence.rs`.
                //
                // share the once-per-envelope `apply_ts`
                // so the re-pointed rows + tombstone share the same
                // moment as every other apply-time write.
                let now = apply_ts;
                stmt_repoint_task_tags.execute(named_params! {
                    ":winner_id": winner_id,
                    ":merge_version": &merge_version,
                    ":now": now,
                    ":loser_id": loser_id,
                })?;
                stmt_delete_task_tags.execute([loser_id.as_str()])?;

                // Delete the loser tag row.
                stmt_delete_loser_tag.execute([loser_id.as_str()])?;

                // Tombstone the loser with merge version > all inputs.
                // Reuse `now` captured before the task_tags re-point.
                create_tombstone(
                    conn,
                    naming::ENTITY_TAG,
                    loser_id,
                    &merge_version,
                    now,
                    Some(winner_id.as_str()),
                    Some(naming::ENTITY_TAG),
                )?;
            }

            // stamp the winner tag row's `version`
            // column at `merge_version` so the cluster invariant — root
            // version >= every child / edge version on the same aggregate
            // — is restored. The loop above re-stamped every `task_tags`
            // row at `merge_version` but left `tags.version` at whatever
            // the triggering envelope wrote (strictly less than
            // `merge_version`). A peer reading the snapshot would see a
            // winner tag whose own version lex-orders BELOW its edge
            // rows, breaking the aggregate-root invariant and opening a
            // subtle LWW-loss path on the next local edit to the winner.
            //
            // The LWW guard mirrors `version_stamp` discipline:
            // if a concurrent peer envelope already landed
            // an even-newer version on the winner row (rare but possible
            // inside the same apply batch), the merge must NOT regress it.
            //
            // route through
            // `stamp_merge_winner_version` so the LWW guard uses parse-
            // then-typed-compare instead of a raw SQL byte-compare. See
            // the parallel call in `apply::aggregate::recurrence` for
            // the rationale (stale-shape literals like `'seed'` sort
            // ABOVE canonical HLCs under byte-compare).
            crate::apply::stamp_merge_winner_version(
                conn,
                "tags",
                "id",
                winner_id,
                &merge_version,
            )?;
            Ok(())
        },
    )
}

/// `(display_name, color, version)` for a single tag row, as needed by
/// the merge-conflict divergence check. Stored in
/// [`read_tag_merge_fields`]'s returned map.
type TagMergeFields = (String, Option<String>, String);

/// Single `WHERE id IN (winner, losers...)` read of the merge-relevant
/// columns for the winner tag plus every loser tag in one round-trip,
/// returned as a `HashMap<id, fields>` so the merge loop can drain
/// rather than re-query per loser. Mirrors the recurrence-merge sibling
/// (`apply::aggregate::recurrence::snapshot::read_many`).
fn read_tag_merge_fields(
    conn: &Connection,
    winner_id: &str,
    loser_ids: &[String],
) -> Result<std::collections::HashMap<String, TagMergeFields>, ApplyError> {
    let total = 1 + loser_ids.len();
    let placeholders = lorvex_domain::sql::sql_in_placeholders(total, 0);
    let sql =
        format!("SELECT id, display_name, color, version FROM tags WHERE id IN ({placeholders})");
    let mut stmt = conn.prepare_cached(&sql)?;

    let mut params: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(total);
    params.push(&winner_id);
    for loser_id in loser_ids {
        params.push(loser_id);
    }

    let mut out = std::collections::HashMap::with_capacity(total);
    let rows = stmt.query_map(rusqlite::params_from_iter(params.iter().copied()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<String>>(2)?,
            row.get::<_, String>(3)?,
        ))
    })?;
    for row in rows {
        let (id, display_name, color, version) = row?;
        out.insert(id, (display_name, color, version));
    }
    Ok(out)
}

/// Compute the `display_name` / `color` divergence between the winner
/// and one loser. Returns `Some((loser_json, loser_version))` so the
/// caller can log a `tag_merge` conflict entry before the SQL delete
/// erases the loser, or `None` when the columns match exactly (the
/// merge is genuinely lossless).
fn compute_tag_divergence(
    winner: &TagMergeFields,
    loser: TagMergeFields,
) -> Option<(String, String)> {
    let (loser_display_name, loser_color, loser_version) = loser;
    let mut divergent = serde_json::Map::new();
    if winner.0 != loser_display_name {
        divergent.insert(
            "display_name".to_string(),
            serde_json::json!(loser_display_name),
        );
    }
    if winner.1 != loser_color {
        divergent.insert("color".to_string(), serde_json::json!(loser_color));
    }
    if divergent.is_empty() {
        return None;
    }
    let payload = serde_json::to_string(&serde_json::Value::Object(divergent))
        .expect("tag-divergence map must serialize");
    Some((payload, loser_version))
}
