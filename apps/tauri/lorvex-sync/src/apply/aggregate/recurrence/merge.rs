use rusqlite::{named_params, Connection};

use super::snapshot::{divergent_loser_fields, RecurrenceMergeSnapshot};
use super::ApplyError;
use crate::apply::device_identity::read_local_device_hlc_suffix;

/// `task_versions` is the parallel-slice companion to `task_ids`,
/// carrying each task's `version` column so this function can compute
/// `max_hlc` and look up per-loser versions for conflict logging
/// without issuing a single per-loser `SELECT`. Both slices are
/// produced by `unzip`-ing the same `SELECT id, version FROM tasks`
/// query at the call site, so `task_ids[i]` and `task_versions[i]`
/// always refer to the same row.
pub(super) fn merge_recurrence_inner(
    conn: &Connection,
    task_ids: &[String],
    task_versions: &[String],
    triggering_version: &str,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    let winner_id = &task_ids[0];

    // snapshot ALL participants' merge-relevant columns
    // BEFORE any COALESCE iteration runs. The previous shape compared
    // the freshly-COALESCE'd winner against each loser, so when ≥3
    // duplicates landed the second loser's distinct value was
    // silently dropped — iteration 1 already filled the winner's
    // NULL field with loser-1's value, and iteration 2 saw "winner
    // has the same value as loser-1" and skipped the conflict log.
    //
    // Capturing the original winner snapshot once + tracking which
    // fields prior losers already donated lets us emit a
    // `recurrence_dedup` conflict for every loser whose value
    // would otherwise be silently dropped.
    // perf: fetch every participant's pre-merge snapshot in a single
    // `WHERE id IN (...)` round trip rather than firing one
    // `RecurrenceMergeSnapshot::read` per loser inside the dedup loop
    // below — that was an N+1 against the `tasks` table for every
    // recurrence-key collision.
    let mut snapshots = RecurrenceMergeSnapshot::read_many(conn, task_ids)?;
    let winner_pre_merge = snapshots.remove(winner_id).ok_or_else(|| {
        ApplyError::Store(lorvex_store::StoreError::Invariant(format!(
            "recurrence merge winner {winner_id} missing from batched snapshot read"
        )))
    })?;
    let mut already_filled: std::collections::HashSet<&'static str> =
        std::collections::HashSet::new();

    // Compute a merge version guaranteed greater than all participants,
    // matching the tag merge strategy. Without this, a loser task
    // whose version exceeds the triggering envelope's version would
    // receive a tombstone with a *lower* version, confusing watermark-
    // based GC.
    //
    // Read versions from the caller-collected `task_versions` slice
    // (same SELECT that produced `task_ids`) instead of issuing N
    // single-row reads here.
    //
    // A tainted task version (legacy literal like `"v1"`, `"seed"`,
    // or hand-edited DB) must NOT propagate `InvalidVersion` via
    // `?`. Because the tainted version is persisted local data,
    // aborting on it would re-fire the merge on every subsequent
    // envelope apply for any task sharing the same
    // `recurrence_instance_key`, leaving the duplicate rows
    // alongside the winner indefinitely. Mirror
    // `stamp_merge_winner_version`'s tolerance: skip the tainted
    // version with a deduped error_log entry so the merge converges
    // on whatever canonical versions parsed. If a peer holds an
    // envelope whose tainted bytes happen to byte-compare greater
    // than the new `merge_version`, that's a separate corruption the
    // tombstone+redirect still resolves on next apply.
    let mut max_hlc = lorvex_domain::hlc::Hlc::parse(triggering_version)?;
    for task_version in task_versions {
        match lorvex_domain::hlc::Hlc::parse(task_version) {
            Ok(task_hlc) => {
                if task_hlc > max_hlc {
                    max_hlc = task_hlc;
                }
            }
            Err(parse_err) => {
                let dedup_signature =
                    format!("recurrence_merge_max_hlc|task_version_unparseable|{task_version}");
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.apply.recurrence_merge_unparseable_version",
                    &format!(
                        "recurrence merge: skipping unparseable task_version \
                         {task_version:?} during max-HLC computation \
                         (parse_err={parse_err}); merge proceeds using \
                         canonical participant versions"
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
            }
        }
    }
    // Sync apply F2: stamp the merge tombstone with the LOCAL device's
    // suffix, mirroring tag merge. Without this, a
    // locally-authored merge tombstone inherits whichever participant
    // had the highest HLC — typically a remote peer — which breaks
    // device-id filters in remote device-cursor recording and
    // confuses conflict-log diagnostics. Fall back to the remote
    // suffix only when the local device-id checkpoint is missing.
    let merge_suffix =
        read_local_device_hlc_suffix(conn).unwrap_or_else(|| max_hlc.device_suffix().to_string());
    let merge_hlc =
        crate::apply::merge_hlc::mint_merge_hlc_after(&max_hlc, &merge_suffix, "recurrence merge")?;
    let merge_version = merge_hlc.to_string();

    // feed the freshly-minted merge HLC back into the
    // process-wide HlcState via the registered observer so subsequent
    // local emissions strictly dominate it. The merge mints this HLC
    // via direct `Hlc::new(...)` — never through `hlc_state.generate()`
    // — so without this hook the in-process clock has no record of
    // having emitted it. A subsequent local edit could then produce
    // an HLC that lex-orders BELOW `merge_version`, regressing every
    // child row this merge just stamped. The observer is a no-op
    // until a caller (Tauri startup, MCP startup) installs it; tests
    // use `with_temporary_observer` to capture the event.
    //
    // dev-only invariant: production callers (Tauri
    // startup, MCP startup) MUST have installed the observer at boot
    // via `set_local_event_observer`. A forgotten wire-up would let
    // this site silently mint an HLC that the caller's HlcState
    // never learns about, opening the LWW-loss window the observer
    // exists to close. Fail loudly in dev/test so the regression
    // surfaces here rather than as an inscrutable LWW skip in
    // production. The check is bypassed when a `#[cfg(test)]`
    // observer is installed via `with_temporary_observer` (those
    // tests use the test-observer slot, not the production
    // OnceLock).
    #[cfg(all(debug_assertions, not(test)))]
    debug_assert!(
        crate::hlc::production_observer_is_installed(),
        "recurrence merge minted a local HLC but no production observer is wired in — \
         call `lorvex_sync::hlc::set_local_event_observer` from your app/MCP startup so \
         subsequent local emissions strictly dominate merge_version"
    );
    crate::hlc::observe_local_event(&merge_hlc);

    // Lift every per-loser SQL into a `prepare_cached` handle bound
    // ONCE before the loop. Issuing ~10 `conn.execute(...)` calls
    // per loser would re-prepare and re-plan the same statement on
    // each call; for a 3-way merge that's ~20 redundant prepare /
    // plan cycles. Mirrors the pattern documented at
    // `tombstone::create_tombstone`.
    let mut stmt_attr_merge = conn.prepare_cached(
        "UPDATE tasks SET
            body = COALESCE(body, (SELECT body FROM tasks WHERE id = :loser_id)),
            ai_notes = COALESCE(ai_notes, (SELECT ai_notes FROM tasks WHERE id = :loser_id)),
            estimated_minutes = COALESCE(estimated_minutes, (SELECT estimated_minutes FROM tasks WHERE id = :loser_id)),
            due_time = COALESCE(due_time, (SELECT due_time FROM tasks WHERE id = :loser_id))
         WHERE id = :winner_id",
    )?;
    let mut stmt_repoint_task_tags = conn.prepare_cached(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version)
         SELECT :winner_id, tag_id, :now, :merge_version FROM task_tags WHERE task_id = :loser_id
         ON CONFLICT(task_id, tag_id) DO UPDATE SET
             version = :merge_version,
             created_at = excluded.created_at",
    )?;
    let mut stmt_delete_task_tags =
        conn.prepare_cached("DELETE FROM task_tags WHERE task_id = ?1")?;
    let mut stmt_repoint_task_dependencies = conn.prepare_cached(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, created_at, version)
         SELECT :winner_id, depends_on_task_id, :now, :merge_version FROM task_dependencies WHERE task_id = :loser_id
         ON CONFLICT(task_id, depends_on_task_id) DO UPDATE SET
             version = :merge_version,
             created_at = excluded.created_at",
    )?;
    let mut stmt_delete_task_dependencies_from =
        conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")?;
    let mut stmt_repoint_dependencies_target = conn.prepare_cached(
        "UPDATE OR IGNORE task_dependencies SET depends_on_task_id = :winner_id, version = :merge_version, created_at = :now
         WHERE depends_on_task_id = :loser_id",
    )?;
    let mut stmt_delete_dependencies_target =
        conn.prepare_cached("DELETE FROM task_dependencies WHERE depends_on_task_id = ?1")?;
    let mut stmt_repoint_calendar_links = conn.prepare_cached(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, created_at, updated_at, version)
         SELECT :winner_id, calendar_event_id, :now, :now, :merge_version FROM task_calendar_event_links WHERE task_id = :loser_id
         ON CONFLICT(task_id, calendar_event_id) DO UPDATE SET
             version = :merge_version,
             created_at = excluded.created_at,
             updated_at = excluded.updated_at",
    )?;
    let mut stmt_delete_calendar_links =
        conn.prepare_cached("DELETE FROM task_calendar_event_links WHERE task_id = ?1")?;
    let mut stmt_repoint_reminders = conn.prepare_cached(
        "UPDATE task_reminders SET task_id = :winner_id, version = :merge_version WHERE task_id = :loser_id",
    )?;
    let mut stmt_repoint_checklist_items = conn.prepare_cached(
        "UPDATE task_checklist_items \
         SET task_id = :winner_id, \
             version = :merge_version, \
             updated_at = :now \
         WHERE task_id = :loser_id",
    )?;
    // Re-point focus-plan child tables that hold the loser's
    // task_id as a soft reference (no FK, no per-row version). The
    // recurrence-merge codepath must rewire current_focus_items
    // and focus_schedule_blocks alongside every other child table
    // (task_tags, task_dependencies, task_calendar_event_links,
    // task_reminders, task_checklist_items). The loser's
    // `DELETE FROM tasks` at the end of this loop does NOT cascade
    // into those tables (no FK), so without explicit re-pointing
    // the user's focus-plan intent would survive as orphan rows
    // pointing to a now-deleted task ID.
    //
    // current_focus_items has UNIQUE(date, task_id) so a winner that
    // is already in focus on the same date would conflict with the
    // re-pointed loser row. Use UPDATE OR IGNORE + cleanup DELETE,
    // mirroring the task_dependencies reverse-direction pattern
    // upstream in this same prepare-cached block.
    let mut stmt_repoint_current_focus_items = conn.prepare_cached(
        "UPDATE OR IGNORE current_focus_items SET task_id = :winner_id \
         WHERE task_id = :loser_id",
    )?;
    let mut stmt_delete_current_focus_items_loser =
        conn.prepare_cached("DELETE FROM current_focus_items WHERE task_id = ?1")?;
    // focus_schedule_blocks has no uniqueness on task_id (block_type
    // can be 'task' | 'buffer' | 'event' and multiple task blocks
    // are allowed across the day) so a plain UPDATE suffices.
    let mut stmt_repoint_focus_schedule_blocks = conn.prepare_cached(
        "UPDATE focus_schedule_blocks SET task_id = :winner_id \
         WHERE task_id = :loser_id",
    )?;
    let mut stmt_delete_loser_task = conn.prepare_cached("DELETE FROM tasks WHERE id = ?1")?;

    for (loser_idx, loser_id) in task_ids[1..].iter().enumerate() {
        // `enumerate()` runs over `task_ids[1..]`, so the
        // matching version sits at `task_versions[loser_idx + 1]`.
        let loser_version_str = &task_versions[loser_idx + 1];
        // capture this loser's pre-merge
        // snapshot and compare against the original winner's
        // pre-merge snapshot (NOT the COALESCE'd row). The
        // `already_filled` set carries which winner-NULL fields
        // an earlier loser donated to so a third-or-later loser
        // with a distinct value still gets a conflict_log entry.
        // perf: pull the pre-fetched snapshot from the batched map
        // rather than issuing a per-loser `SELECT`. A loser missing
        // here would mean the row was concurrently deleted between the
        // initial read and the loop, which is a savepoint-level
        // invariant violation worth surfacing distinctly.
        let loser_pre_merge = snapshots.remove(loser_id).ok_or_else(|| {
            ApplyError::Store(lorvex_store::StoreError::Invariant(format!(
                "recurrence merge loser {loser_id} missing from batched snapshot read"
            )))
        })?;
        let divergent =
            divergent_loser_fields(&winner_pre_merge, &loser_pre_merge, &already_filled);
        if let Some(loser_payload) = divergent {
            // index into the caller-collected
            // `task_versions` slice instead of issuing a per-loser
            // `SELECT version FROM tasks` round-trip.
            let loser_version = loser_version_str.clone();
            // A tainted loser version must NOT abort the merge here
            // either. The conflict log entry is a diagnostic
            // surface, not a correctness gate; if we cannot extract
            // a canonical device_suffix from the loser's version we
            // record the tainted bytes in `loser_device_id` and
            // continue. `Hlc::parse(...)?` would propagate
            // `InvalidVersion` and roll the savepoint back together
            // with the merge.
            let loser_device_id = match lorvex_domain::hlc::Hlc::parse(&loser_version) {
                Ok(loser_hlc) => loser_hlc.device_suffix().to_string(),
                Err(parse_err) => {
                    let dedup_signature = format!(
                        "recurrence_merge_conflict_log|loser_version_unparseable|{loser_version}"
                    );
                    lorvex_store::error_log::append_error_log_best_effort(
                        conn,
                        "sync.apply.recurrence_merge_unparseable_version",
                        &format!(
                            "recurrence merge: tainted loser_version \
                             {loser_version:?} for entity_id={winner_id:?} \
                             (parse_err={parse_err}); recording raw bytes \
                             in conflict log loser_device_id and continuing"
                        ),
                        Some(&dedup_signature),
                        Some("warn"),
                    );
                    loser_version.clone()
                }
            };
            // share the once-per-envelope `apply_ts`
            // so this conflict-log row's `resolved_at` matches every
            // other row produced by the same envelope apply.
            let resolved_at = apply_ts.to_string();
            crate::conflict_log::log_conflict(
                conn,
                &crate::conflict_log::ConflictLogEntry {
                    id: 0,
                    entity_type: std::borrow::Cow::Borrowed(lorvex_domain::naming::ENTITY_TASK),
                    entity_id: winner_id.clone(),
                    // Matches the parallel tag-merge site at
                    // `apply/tag.rs:341`. The merge stamps every
                    // re-pointed row + winner row at `merge_version`
                    // (which is strictly greater than
                    // `triggering_version` per the `max_hlc + 1`
                    // construction above, then committed via
                    // `stamp_merge_winner_version`). Recording
                    // `triggering_version` here would let an
                    // operator inspecting Settings → Diagnostics
                    // see a `winner_version` that doesn't match the
                    // version actually written to the row.
                    winner_version: merge_version.clone(),
                    loser_version,
                    loser_device_id,
                    loser_payload: Some(loser_payload),
                    resolved_at,
                    resolution_type: std::borrow::Cow::Borrowed(
                        lorvex_domain::naming::RESOLUTION_RECURRENCE_DEDUP,
                    ),
                },
            )?;
        }
        // After this loser's iteration, the COALESCE merge will
        // donate its non-NULL values into any winner-NULL fields.
        // Track that so the next loser's divergence check knows.
        if winner_pre_merge.body.is_none() && loser_pre_merge.body.is_some() {
            already_filled.insert("body");
        }
        if winner_pre_merge.ai_notes.is_none() && loser_pre_merge.ai_notes.is_some() {
            already_filled.insert("ai_notes");
        }
        if winner_pre_merge.estimated_minutes.is_none()
            && loser_pre_merge.estimated_minutes.is_some()
        {
            already_filled.insert("estimated_minutes");
        }
        if winner_pre_merge.due_time.is_none() && loser_pre_merge.due_time.is_some() {
            already_filled.insert("due_time");
        }

        // Attribute merge: fill in winner's NULL fields from loser's non-NULL fields.
        // This ensures no data is lost when two devices set different optional fields.
        stmt_attr_merge.execute(named_params! {
            ":winner_id": winner_id,
            ":loser_id": loser_id,
        })?;

        // every re-pointed child / edge row must
        // be stamped with `merge_version` (the same HLC used for
        // the loser's tombstone). The pre-merge `version` column
        // belongs to the loser's HLC line; once the row is
        // re-pointed to the winner, peers that see a subsequent
        // local edit on the same edge would otherwise reject the
        // new envelope as LWW-stale. For tables that carry an
        // `updated_at` column (`task_calendar_event_links`), bump
        // it to `now` as well.
        //
        // reuse the once-per-envelope `apply_ts`
        // so re-pointed rows share the same `created_at` /
        // `updated_at` instant as every other apply-time write
        // in this envelope.
        let now = apply_ts;

        // Re-point task_tags from loser to winner with merge_version.
        stmt_repoint_task_tags.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":now": now,
            ":loser_id": loser_id,
        })?;
        stmt_delete_task_tags.execute([loser_id.as_str()])?;

        // Re-point task_dependencies from loser to winner.
        stmt_repoint_task_dependencies.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":now": now,
            ":loser_id": loser_id,
        })?;
        stmt_delete_task_dependencies_from.execute([loser_id.as_str()])?;
        // Also re-point any dependencies that point TO the loser. The
        // composite PK forbids `(task_id, task_id)`, so any rows
        // becoming self-edges fall through to the cleanup DELETE.
        stmt_repoint_dependencies_target.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":now": now,
            ":loser_id": loser_id,
        })?;
        // Clean up any leftover rows that couldn't be updated due to duplicates.
        stmt_delete_dependencies_target.execute([loser_id.as_str()])?;

        // Re-point task_calendar_event_links from loser to winner —
        // this table carries `updated_at`, so bump it alongside.
        stmt_repoint_calendar_links.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":now": now,
            ":loser_id": loser_id,
        })?;
        stmt_delete_calendar_links.execute([loser_id.as_str()])?;

        // Re-point task_reminders from loser to winner. The reminder
        // is an independent child (own UUIDv7 id); only `task_id`
        // and `version` move (no `updated_at` column).
        stmt_repoint_reminders.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":loser_id": loser_id,
        })?;

        // Re-point task_checklist_items the same way we re-point
        // task_reminders. The recurrence-merge path must cover
        // task_checklist_items alongside task_tags,
        // task_dependencies (both directions),
        // task_calendar_event_links, and task_reminders. Without
        // this re-point, every checklist item attached to the loser
        // task would be silently destroyed by the
        // `ON DELETE CASCADE` from the loser's `DELETE FROM tasks`
        // below, with no tombstone written and no peer notification.
        // The schema (single-column PK `id`, FK `task_id` to tasks
        // ON DELETE CASCADE, no composite uniqueness on task_id) is
        // identical to task_reminders, so we mirror that update
        // exactly: bump `task_id` to the winner and stamp `version`
        // at `merge_version` so a subsequent local edit on the same
        // item produces an envelope that beats peer copies still
        // tracking the loser's HLC line. We also bump `updated_at`
        // because the column exists on this table (unlike
        // task_reminders) and re-pointing IS a logical write.
        stmt_repoint_checklist_items.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":now": now,
            ":loser_id": loser_id,
        })?;

        // Re-point current_focus_items and focus_schedule_blocks. See
        // the prepare_cached block above for the rationale; in short,
        // these tables hold task_id as an unversioned soft reference
        // and the loser-task DELETE below does not cascade into them.
        stmt_repoint_current_focus_items.execute(named_params! {
            ":winner_id": winner_id,
            ":loser_id": loser_id,
        })?;
        // Clean up any rows that UPDATE OR IGNORE skipped because the
        // (date, winner_id) UNIQUE INDEX was already satisfied — the
        // surviving winner row stays, and the leftover loser-pointed
        // row is removed so the loser's task_id never lingers.
        stmt_delete_current_focus_items_loser.execute([loser_id.as_str()])?;
        stmt_repoint_focus_schedule_blocks.execute(named_params! {
            ":winner_id": winner_id,
            ":loser_id": loser_id,
        })?;

        // Delete the loser task row.
        stmt_delete_loser_task.execute([loser_id.as_str()])?;

        // Tombstone the loser with redirect to winner, using the merge
        // version that is guaranteed greater than all participants.
        crate::tombstone::create_tombstone(
            conn,
            lorvex_domain::naming::ENTITY_TASK,
            loser_id,
            &merge_version,
            now,
            Some(winner_id.as_str()),
            Some(lorvex_domain::naming::ENTITY_TASK),
        )?;
    }

    // stamp the winner aggregate row's `version`
    // column at `merge_version` so the cluster invariant — root
    // version >= every child / edge version on the same aggregate —
    // is restored. Without this, the loop above leaves
    // `winner.version == triggering_version` while the re-pointed
    // children carry `merge_version` (strictly greater). A peer
    // reading the snapshot would see a winner that's "older" than
    // its own children, opening a subtle LWW-loss path on follow-up
    // edits.
    //
    // The LWW guard mirrors `version_stamp` discipline:
    // if a concurrent peer envelope already landed an even-newer
    // version on the winner row (rare but possible inside the same
    // apply transaction batch), the merge must NOT regress it.
    //
    // Route through `stamp_merge_winner_version` so the LWW guard
    // uses parse-then-typed-compare instead of a raw SQL byte-
    // compare. A `?1 > version` SQL predicate is correct for
    // canonical HLCs but inverts when the row carries a stale-shape
    // literal (`'v1'`, `'seed'`) — letters sort ABOVE digits, so the
    // merge winner would be left at its pre-merge version on a
    // tainted row, opening the same aggregate-root invariant
    // regression this stamp exists to close. The helper logs and
    // continues on partial-tainted cases so the stamp converges
    // even on a legacy DB.
    crate::apply::stamp_merge_winner_version(conn, "tasks", "id", winner_id, &merge_version)?;

    Ok(())
}
