//! Apply handlers for the `list` aggregate root.

use rusqlite::{named_params, Connection, OptionalExtension};

use lorvex_domain::ids::ListId;
use lorvex_domain::naming;

use super::super::LwwTieBreak;
use super::helpers::{
    evaluate_delete_lww, optional_i64, optional_str, required_str, scrub, scrub_opt,
    DeleteLwwDecision,
};
use super::ApplyError;
use crate::conflict_log::{log_conflict, ConflictLogEntry};

pub(crate) fn apply_list_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    // handler doesn't currently consume the apply
    // timestamp, but every aggregate-upsert signature carries it
    // for uniform dispatch — `_apply_ts` keeps the parameter shape
    // without the unused-variable warning.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: thread the typed `ListId` through the apply
    // body. The dispatch table holds fn-pointer types shared across
    // every aggregate handler so the public signature stays `&str`,
    // but the function body operates on the typed id from the very
    // first line — SQL bind sites, error formatting, and helper calls
    // all flow through `list_id.as_str()` (zero-copy) so a future
    // mismatched-kind id can never silently slip into a list-shaped
    // SQL statement. Envelope ids are dispatcher-validated upstream;
    // `from_trusted` skips a redundant parse (the dispatcher would
    // have already rejected a malformed envelope id before reaching
    // here, and re-parsing here would only catch logic bugs the
    // upstream gate is supposed to close).
    let list_id = ListId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    // Unicode hygiene (#2427): scrub free-text list fields at the sync
    // apply boundary.
    let name_owned = scrub(required_str(&val, "name", "list")?);
    let name: &str = &name_owned;
    // cap peer-supplied list name at the shared title
    // length. Empty is also rejected to match the local create path.
    if name.is_empty() {
        return Err(ApplyError::InvalidPayload(format!(
            "list {} name is empty",
            list_id.as_str()
        )));
    }
    if name.chars().count() > lorvex_domain::validation::MAX_TITLE_LENGTH {
        return Err(ApplyError::InvalidPayload(format!(
            "list {} name is too long ({} chars; max {})",
            list_id.as_str(),
            name.chars().count(),
            lorvex_domain::validation::MAX_TITLE_LENGTH
        )));
    }
    let color = optional_str(&val, "color", "list")?;
    let icon = optional_str(&val, "icon", "list")?;
    let description_owned = scrub_opt(optional_str(&val, "description", "list")?);
    let description: Option<&str> = description_owned.as_deref();
    if let Some(d) = description {
        lorvex_domain::validation::validate_body(d).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "list {} description failed validation: {e}",
                list_id.as_str()
            ))
        })?;
    }
    let ai_notes_owned = scrub_opt(optional_str(&val, "ai_notes", "list")?);
    let ai_notes: Option<&str> = ai_notes_owned.as_deref();
    let archived_at = optional_str(&val, "archived_at", "list")?;
    let position = match optional_i64(&val, "position", "list")? {
        Some(position) => position,
        None => conn
            .prepare_cached("SELECT position FROM lists WHERE id = ?1")?
            .query_row([&list_id], |row| row.get(0))
            .optional()?
            .unwrap_or(0),
    };
    let created_at = required_str(&val, "created_at", "list")?;
    let updated_at = required_str(&val, "updated_at", "list")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "lists",
        columns: &[
            "id",
            "name",
            "color",
            "icon",
            "description",
            "ai_notes",
            "archived_at",
            "created_at",
            "updated_at",
            "position",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        // bind the typed `ListId` directly via the rusqlite ToSql
        // impl on the newtype — no `.as_str()` allocation, and the
        // typed id is the only path that reaches the SQL layer.
        ":id": &list_id,
        ":name": name,
        ":color": color,
        ":icon": icon,
        ":description": description,
        ":ai_notes": ai_notes,
        ":archived_at": archived_at,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":position": position,
        ":version": version,
    })?;

    // the previous post-upsert `cleanup_tombstoned_lists`
    // pass (#2855 / #2879) is gone. It existed solely to work around
    // the now-fixed bug where `apply_envelope` wrote a tombstone at
    // the envelope's HLC even when the in-handler DELETE was
    // suppressed by the at-least-one-list invariant — a tombstone
    // sitting over a still-live row that had to be reaped on the
    // next list upsert. The dispatcher now preserves the suppressed-
    // delete signal up to `apply_envelope`, which defers the
    // envelope to `sync_pending_inbox` instead of writing the
    // tombstone. The drain loop retries the deferred delete on
    // every apply pass; once another list lands the invariant
    // relaxes naturally and the delete completes, leaving no
    // tombstone-over-live-row state for cleanup to reconcile.
    Ok(())
}

/// Outcome of `apply_list_delete`:
///   - `Applied` — the SQL DELETE ran (or no-op'd against an already-
///     deleted row); the caller writes the tombstone.
///   - `SkippedByInvariant { invariant }` — an aggregate-level guard
///     refused the DELETE while leaving the row alive.
///     the caller in `apply/mod.rs` defers the envelope to
///     `sync_pending_inbox` and DOES NOT write a tombstone. The
///     `invariant` string identifies which guard fired so the
///     diagnostics surface can distinguish "at least one list" from
///     "tasks still reference this list" without re-deriving the
///     condition from the deferral payload.
///   - `LwwRejected { local_version, envelope_version }` — the
///     defense-in-depth in-handler LWW gate refused the DELETE
///     because the local row's version strictly dominates the
///     envelope's. Issue-H5 regression fix:
///     handler's `Reject` arm suppressed the SQL DELETE but still
///     returned `Applied`, so the dispatcher reported `Applied` and
///     `apply_envelope` minted a tombstone at the envelope's older
///     HLC over the surviving local row — the very corruption shape
///     the H5 work was supposed to close. The caller in
///     `apply/mod.rs` now surfaces this as `ApplyResult::Skipped`
///     and does NOT mint a tombstone; the handler also records the
///     loss to `sync_conflict_log` so the diagnostics surface counts
///     it.
// `ListDeleteOutcome` is an alias of the shared
// `super::InvariantGatedDeleteOutcome` (sibling to
// `LwwGatedDeleteOutcome`) so the dispatcher treats the list handler
// with the fn-pointer-and-three-arms pattern.
// See `super::InvariantGatedDeleteOutcome`.
pub(crate) use super::InvariantGatedDeleteOutcome as ListDeleteOutcome;

/// The "at least one list" invariant — deleting the row would leave
/// the device with zero lists, breaking task creation. Public so the
/// dispatcher can match on the same string the diagnostics surface
/// reports.
const INVARIANT_AT_LEAST_ONE_LIST: &str = "at_least_one_list";

/// Inbox-canonical invariant — peer envelope tries to delete `inbox`
/// while local tasks still depend on it as the canonical fallback
/// target. The schema-level `trg_lists_before_delete` trigger raises
/// ABORT in this case (see `001_schema.sql` ~line 152), so the SQL
/// DELETE would surface as a hard apply error and poison the batch.
/// Pre-empt with a typed conflict-log entry and skip. Naming kept as
/// `tasks_reference_list` so existing diagnostics dashboards / alerts
/// keyed on this string keep counting the same condition (which is
/// strictly narrower now: only inbox can stall this way).
pub(crate) const INVARIANT_TASKS_REFERENCE_LIST: &str = "tasks_reference_list";

/// Apply a peer's `Delete{list:id}` envelope.
///
/// Two aggregate-level invariants can suppress the underlying SQL
/// DELETE:
///
/// 1. `at_least_one_list` — the device must always have ≥ 1 list for
///    task creation.
/// 2. `tasks_reference_list` — peer asked us to delete `inbox` while
///    tasks still depend on it (the trigger would ABORT).
///
/// Otherwise the schema's `trg_lists_before_delete` trigger
/// (`001_schema.sql`) re-homes any remaining tasks (active OR
/// archived) to `inbox` BEFORE the DELETE proceeds, so the
/// `tasks.list_id ON DELETE RESTRICT` FK never fires for non-inbox
/// lists.
/// counted *all* referencing tasks and deferred even when only
/// archived rows were left, leaving peers permanently disagreeing
/// about whether the list still existed.
pub(crate) fn apply_list_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    apply_ts: &str,
) -> Result<ListDeleteOutcome, ApplyError> {
    // Issue #3285 phase 3: parse to the typed `ListId` once at the
    // handler entry. Every SQL bind, helper call, and conflict-log
    // write below threads the typed id; the `&str` parameter is
    // preserved only because the dispatch table's fn-pointer type
    // (`InvariantGatedAggregateDelete`) takes `&str` — migrating the
    // dispatcher signatures is a separate batch.
    let list_id = ListId::from_trusted(entity_id.to_string());
    // Prevent deleting the last list — at least one must exist for task creation.
    let total_lists: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM lists")?
        .query_row([], |row| row.get(0))?;
    if total_lists <= 1 {
        return Ok(ListDeleteOutcome::SkippedByInvariant {
            invariant: INVARIANT_AT_LEAST_ONE_LIST,
        });
    }
    // Inbox is the canonical fallback target. The schema trigger
    // ABORTs `DELETE FROM lists WHERE id = 'inbox'` while any task
    // exists; running the SQL would surface that ABORT as an apply
    // error and poison the batch in StrictAtomic mode. Pre-empt with
    // a typed conflict-log entry and let `apply_envelope` defer the
    // envelope to `sync_pending_inbox` — a future drain (after every
    // referencing task is itself deleted) will eventually be able to
    // satisfy the trigger.
    if list_id.as_str() == "inbox" {
        let any_task: i64 = conn
            .prepare_cached("SELECT EXISTS (SELECT 1 FROM tasks LIMIT 1)")?
            .query_row([], |row| row.get(0))?;
        if any_task > 0 {
            log_conflict(
                conn,
                &ConflictLogEntry {
                    id: 0,
                    entity_type: std::borrow::Cow::Borrowed(
                        lorvex_domain::naming::EntityKind::List.as_str(),
                    ),
                    entity_id: list_id.as_str().to_string(),
                    winner_version: version.to_string(),
                    loser_version: version.to_string(),
                    loser_device_id: String::new(),
                    loser_payload: None,
                    resolved_at: apply_ts.to_string(),
                    resolution_type: std::borrow::Cow::Borrowed(naming::RESOLUTION_FK_STALLED),
                },
            )?;
            return Ok(ListDeleteOutcome::SkippedByInvariant {
                invariant: INVARIANT_TASKS_REFERENCE_LIST,
            });
        }
    }
    // defense-in-depth LWW guard,
    // evaluated in Rust against parsed HLCs rather than the
    // previous `:version >= version` SQL byte compare. See the
    // comment on `apply_task_delete` for the byte-compare hazard
    // (`'v1'` and similar tainted values silently flip the
    // comparison; ASCII letters sort above digits). Mirrors the
    // gate landed for `apply_task_delete` — the helper is
    // reachable from `apply_entity_with_version_mode(_, true)`
    // via shadow promotion (`>=` semantics).
    match evaluate_delete_lww(
        conn,
        "SELECT version FROM lists WHERE id = ?1",
        list_id.as_str(),
        version,
        LwwTieBreak::AllowEqual,
    )? {
        DeleteLwwDecision::Apply => {
            conn.prepare_cached("DELETE FROM lists WHERE id = :id")?
                .execute(named_params! { ":id": &list_id })?;
            Ok(ListDeleteOutcome::Applied)
        }
        DeleteLwwDecision::Reject { local_version } => {
            // local list version
            // strictly dominates the envelope's — surface the loss
            // up to the caller so `apply_envelope` skips tombstone
            // creation.
            // SQL DELETE but the handler still reported `Applied`,
            // and the caller minted a tombstone at the envelope's
            // older HLC over the surviving local row — durably
            // wiping it on the next re-sync via the
            // tombstone-vs-upsert gate.
            //
            // The `RESOLUTION_LWW` conflict-log row is written by
            // `apply_envelope::record_lww_conflict_and_skip` once
            // the dispatcher surfaces `EntityApplyOutcome::LwwRejected`,
            // so we MUST NOT log here too — duplicate rows would
            // double-count the gate firing. (`apply_ts` is consumed
            // by the `referencing_tasks > 0` branch above; this arm
            // simply doesn't carry a conflict-log row, so no further
            // mention of the timestamp is needed.)
            Ok(ListDeleteOutcome::LwwRejected(
                super::super::LwwRejectedDetail { local_version },
            ))
        }
    }
}

#[cfg(test)]
mod tests;
