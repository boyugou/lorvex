//! Apply handlers for the `task` aggregate root.
//!
//! Includes recurrence-instance-key dedup: if two devices spawn
//! successors offline for the same recurrence, they share the same
//! instance key but have different UUIDv7 task IDs. After the upsert,
//! `merge_duplicate_recurrence_instances` collapses them — `min(id)`
//! wins, the loser is tombstoned with a redirect (spec Section 13).
//!
//! `apply_task_delete` tombstones every cascading child / edge row
//! BEFORE SQLite's `ON DELETE CASCADE` removes them; without this, a
//! later upsert that revives the task would leave every edge
//! permanently lost on the deleting device.
//!
//! Module layout (issue #3279):
//! * [`row_build`] — pure parse + validate + scrub + tri-state-split
//!   pipeline. Returns a fully-typed `TaskRow` ready to bind into
//!   either SQL template.
//! * [`update_sql`] — render-once UPDATE template (per
//!   [`LwwTieBreak`] flavor) and the static INSERT template.
//! * [`upsert_exec`] — `named_params!` binding for the UPDATE /
//!   INSERT execution, given a `TaskRow`.
//! * [`delete`] — delete handler + cascade-tombstone helper.
//! * This file — payload dispatch (UPDATE vs INSERT keyed on row
//!   existence) and the recurrence-instance-key dedup hook.

use rusqlite::{Connection, OptionalExtension};

// `params!` is used only in the in-file test module (which lives
// under `task/tests.rs`). Scoping the import to `cfg(test)` keeps
// clippy's `unused_imports` lint quiet on release builds.
#[cfg(test)]
use rusqlite::params;

use lorvex_domain::ids::TaskId;

use super::super::LwwTieBreak;
use super::recurrence::merge_duplicate_recurrence_instances;
use super::ApplyError;

mod delete;
mod row_build;
mod update_sql;
mod upsert_exec;

use row_build::build_task_row;
use upsert_exec::{execute_task_insert, execute_task_update};

pub(crate) use delete::apply_task_delete;

#[cfg(test)]
mod tests;

pub(crate) fn apply_task_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: thread the typed `TaskId` through the
    // apply body. The dispatch table holds fn-pointer types shared
    // across every aggregate handler so the public signature stays
    // `&str`, but the function body operates on the typed id from
    // the very first line — SQL bind sites, error formatting, and
    // helper calls all flow through `task_id.as_str()` (zero-copy)
    // so a future mismatched-kind id can never silently slip into a
    // task-shaped SQL statement. Envelope ids are dispatcher-
    // validated upstream; `from_trusted` skips a redundant parse.
    let task_id = TaskId::from_trusted(entity_id.to_string());
    let row = build_task_row(conn, &task_id, payload, version)?;

    // Split the upsert into explicit INSERT vs UPDATE branches
    // keyed on row existence. The previous unified
    // `INSERT … ON CONFLICT DO UPDATE` couldn't host the partial-
    // update preservation pattern: SQLite evaluates row-level
    // CHECK constraints (e.g. tasks' "recurrence => due_date NOT
    // NULL" gate) against the *INSERT-attempted* row before
    // falling through to the UPDATE branch, so binding NULL on
    // absent fields would trip the CHECK even when the post-UPDATE
    // row would be valid. Pre-reading the row's existence lets the
    // UPDATE path keep the old values via `CASE WHEN :col_present`
    // without ever proposing an invalid INSERT-shape row.
    //
    // The pre-read is cheap (single PK lookup) and runs inside the
    // same transaction as the apply, so concurrent INSERTs by
    // other pipeline branches cannot race the existence check.
    let row_exists: bool = conn
        .prepare_cached("SELECT 1 FROM tasks WHERE id = ?1")?
        .query_row([&task_id], |_| Ok(()))
        .optional()?
        .is_some();
    if row_exists {
        execute_task_update(conn, &row, allow_equal_versions)?;
    } else {
        execute_task_insert(conn, &row)?;
    }

    // EXDATEs live in `task_recurrence_exceptions` since #4585. The
    // partial-update presence flag (`recurrence_exceptions_present`)
    // gates the replace so an envelope that omitted the field
    // preserves the local registry instead of clearing it. Only run
    // the replace when the upsert actually landed (`changes() > 0`)
    // — a stale-version envelope rejected by the LWW gate must not
    // mutate the registry.
    if row.recurrence_exceptions_present != 0 && conn.changes() > 0 {
        lorvex_store::recurrence_exceptions::replace_task_exceptions_from_json(
            conn,
            task_id.as_str(),
            row.recurrence_exceptions.as_deref(),
        )
        .map_err(ApplyError::Store)?;
    }

    // Recurrence instance key dedup (spec Section 13). If two
    // devices spawned successors offline for the same recurrence,
    // they'll share the same instance key but have different
    // UUIDv7 task IDs. Merge them: min(id) wins, loser is
    // tombstoned with redirect.
    //
    // IMPORTANT: only run the merge if the SQL upsert actually
    // modified a row. If the version check rejected the envelope
    // (stale), `changes()` is 0 and we must NOT run the merge — a
    // stale envelope arriving via the tombstone redirect path
    // could otherwise trigger a spurious recurrence merge and
    // tombstone a legitimate task. This guard matches the tag
    // merge pattern in `apply_tag_upsert` (R24 fix).
    let changes = conn.changes();
    if changes > 0 {
        if let Some(key) = row.recurrence_instance_key.as_deref() {
            if !key.is_empty() {
                merge_duplicate_recurrence_instances(
                    conn,
                    task_id.as_str(),
                    key,
                    version,
                    apply_ts,
                )?;
            }
        }
    }

    Ok(())
}
