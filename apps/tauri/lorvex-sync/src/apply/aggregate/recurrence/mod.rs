//! Recurrence-instance-key dedup for `apply_task_upsert`.
//!
//! If two devices spawn successors offline for the same recurrence,
//! they share the same `recurrence_instance_key` but have different
//! UUIDv7 task IDs. After the upsert, this collapses them: `min(id)`
//! wins, the loser is tombstoned with a redirect to the winner,
//! mirroring `apply::tag::merge_duplicate_tags` (spec Section 13).

use rusqlite::Connection;

use super::ApplyError;

mod merge;
mod snapshot;

use merge::merge_recurrence_inner;

/// If two tasks share the same `recurrence_instance_key`, merge them:
/// min ID wins (UUIDv7 = first-created), loser gets tombstoned with redirect.
pub(super) fn merge_duplicate_recurrence_instances(
    conn: &Connection,
    just_upserted_id: &str,
    instance_key: &str,
    version: &str,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    // when the just-upserted id is itself a known
    // redirect-loser (its own tombstone carries a `redirect_entity_id`),
    // skipping the dedup pass avoids spamming the conflict_log with a
    // redundant merge against a target that's already converged.
    // Re-firing the merge on a redirect-loser produces a redundant
    // tombstone + a noisy `redirected-via-merge` conflict_log row each
    // time the entity replays through the apply pipeline. The guard
    // is conservative — once a row is a known merge-loser, the
    // cluster has already agreed on the winner, and `task_ids.len() <= 1`
    // is the only legitimate state. Querying the tombstone here is
    // cheap (indexed lookup on the composite PK).
    if let Some(ts) =
        crate::tombstone::get_tombstone(conn, lorvex_domain::naming::ENTITY_TASK, just_upserted_id)?
    {
        if ts.redirect_entity_id.is_some() {
            return Ok(());
        }
    }

    // pull `id` AND `version` in one round-trip so
    // the inner merge doesn't have to re-walk the tasks table for
    // each participant. For the typical 2-way merge the saving is
    // 2 round-trips → 1; for an N-way merge it's N → 1.
    let mut stmt = conn.prepare_cached(
        "SELECT id, version FROM tasks WHERE recurrence_instance_key = ?1 ORDER BY id ASC",
    )?;
    let task_rows: Vec<(String, String)> = stmt
        .query_map([instance_key], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    if task_rows.len() <= 1 {
        return Ok(()); // No duplicate.
    }

    // unzip the (id, version) pairs once instead of
    // cloning ids out into a parallel Vec. The two halves are passed
    // as parallel slices into `merge_recurrence_inner`, which now
    // indexes into them directly (no per-loser version round-trip).
    let (task_ids, task_versions): (Vec<String>, Vec<String>) = task_rows.into_iter().unzip();

    // Wrap the entire merge in a savepoint so partial failure doesn't leave
    // the database in an inconsistent state (some edges re-pointed, others
    // not). Routes through `lorvex_store::transaction::with_savepoint` so
    // a panic in the inner orchestration (a poisoned task row, a bad
    // FFI callback) rolls the savepoint back BEFORE the unwind resumes —
    // without that helper, a hand-rolled `SAVEPOINT … ; RELEASE` block
    // would leave the savepoint dangling on the connection and the next
    // write would fail with "no such savepoint" even after the outer
    // mutex recovered from poison.
    lorvex_store::transaction::with_savepoint_mapped(
        conn,
        "merge_recurrence",
        ApplyError::InvalidPayload,
        |conn| merge_recurrence_inner(conn, &task_ids, &task_versions, version, apply_ts),
    )
}

#[cfg(test)]
mod tests;
