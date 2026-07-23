//! Parse-then-compare LWW gate for `apply_*_delete` and the
//! gate-before-cascade sequencer that every aggregate-root delete
//! handler routes through. Replaces the previous
//! `WHERE :version >= version` SQL predicate (raw byte compare on
//! the local row's `version` column) so a stale-shape literal
//! (`'v1'`, `'seed'`, an old fixture) cannot slip the gate in
//! either direction.

use rusqlite::{Connection, OptionalExtension};

use super::super::super::LwwTieBreak;
use super::super::ApplyError;

/// outcome of the parse-then-compare LWW delete gate.
///
/// HLC strings are fixed-width and lex-ordered so the byte compare
/// yields the right answer for two well-formed HLCs, but a
/// stale-shape literal slips past the gate in either direction:
/// ASCII letters sort above digits, so `'1711…' >= 'v1'` is FALSE
/// and a delete envelope that semantically dominates the row
/// silently no-ops, while a strictly-stale envelope can also flip
/// the comparison the other way.
///
/// Mirrors the parse-then-compare pattern in
/// `version_stamp::stamp_entity_version` (#2950-M3): we Reject the
/// delete when BOTH sides parse AND the local one strictly
/// dominates. On parse failure either side, fall back to a byte
/// compare against the local string — this preserves the pre-H5 SQL
/// `:version >= version` predicate's safety: a tainted local
/// version that sorts strictly greater than the envelope's
/// well-formed string still refuses the delete, so the regression
/// where a corrupt-local row got wiped by a tolerance-fallback
/// `Apply` and then tombstoned at the loser's HLC stays closed.
/// The corruption itself is still surfaced via `error_logs` for
/// diagnostics.
///
/// `Reject` carries both versions so the caller can attribute a
/// typed `RESOLUTION_LWW` conflict-log row without re-reading the
/// local version.
pub(crate) enum DeleteLwwDecision {
    /// Incoming version dominates (or row is missing / has NULL
    /// version / unparseable AND the byte-compare fallback admits);
    /// the caller may run the unguarded `DELETE FROM <table>
    /// WHERE <pk> = ?` body.
    Apply,
    /// Local row's version strictly dominates the incoming version;
    /// the caller MUST NOT delete. Carries the surviving local version
    /// so the caller can record the conflict-log row attributing the loss.
    Reject { local_version: String },
}

/// parse-then-compare LWW gate for `apply_*_delete`.
///
/// Reads the row's current `version` column via `read_version_sql`
/// (must be of the shape `SELECT version FROM <table> WHERE <pk> = ?1`).
/// Returns `Ok(DeleteLwwDecision::Apply)` when the row is absent /
/// has NULL version / the incoming version dominates (parsed or via
/// the byte-compare fallback). Returns
/// `Ok(DeleteLwwDecision::Reject { .. })` when both versions parse
/// and the local one strictly dominates, OR (parse-failure
/// fallback) when the local string strictly sorts above the
/// envelope's.
///
/// `allow_equal_versions = true` mirrors the upsert convention — the
/// shadow-promotion / re-emit replay paths use it to turn `==` into
/// "apply idempotently" instead of "reject as stale". The production
/// `apply_*_delete` callers route here with `true` (matching the
/// previous `:version >= version` SQL predicate's semantics) so
/// shadow-promotion replay stays idempotent.
pub(in crate::apply::aggregate) fn evaluate_delete_lww(
    conn: &Connection,
    read_version_sql: &str,
    entity_id: &str,
    incoming_version: &str,
    allow_equal_versions: LwwTieBreak,
) -> Result<DeleteLwwDecision, ApplyError> {
    evaluate_lww_delete_with_select(
        conn,
        read_version_sql,
        entity_id,
        incoming_version,
        allow_equal_versions,
        "sync.apply.delete_lww_unparseable_version",
    )
}

/// Shared LWW delete-decision gate. Both the per-aggregate path
/// (`evaluate_delete_lww`) and the blob path feed through here. The
/// `select_sql` template controls the WHERE shape (e.g. `id = ?1`
/// for aggregate rows, `content_hash = ?1` for blob rows) so each
/// caller keeps its bind shape but inherits the same parse-then-
/// compare decision semantics and the same error-log key family for
/// the byte-compare fallback path.
pub(crate) fn evaluate_lww_delete_with_select(
    conn: &Connection,
    select_sql: &str,
    entity_id: &str,
    incoming_version: &str,
    allow_equal_versions: LwwTieBreak,
    error_log_kind: &'static str,
) -> Result<DeleteLwwDecision, ApplyError> {
    // Every caller passes a `&'static str` for `select_sql` — see
    // `aggregate/list/mod.rs:220` etc. — so the prepare cache key
    // is stable across calls and we get one parsed plan per
    // delete-decision SQL shape regardless of how many delete
    // envelopes flow through the apply pipeline.
    let local: Option<Option<String>> = conn
        .prepare_cached(select_sql)?
        .query_row([entity_id], |row| row.get::<_, Option<String>>(0))
        .optional()?;
    let local_version = match local {
        // Row absent or NULL local version — admit the (no-op /
        // freshly-inserted) delete. Mirrors `stamp_entity_version`'s
        // `version IS NULL` arm.
        None | Some(None) => return Ok(DeleteLwwDecision::Apply),
        Some(Some(v)) => v,
    };
    // Route through the canonical `compare_versions_with_fallback`
    // so the parse-then-compare path and the byte-compare fallback
    // live in one place. Inlining `Hlc::parse(...)` on both sides
    // and re-implementing the decision branch would let the parse-
    // failure semantics drift from `stamp_merge_winner_version` and
    // friends; sharing the comparator also resolves both-sides-
    // unparseable through one byte-compare arm.
    let incoming_parses = lorvex_domain::hlc::Hlc::parse(incoming_version).is_ok();
    let local_parses = lorvex_domain::hlc::Hlc::parse(&local_version).is_ok();
    let cmp = lorvex_domain::hlc::compare_versions_with_fallback(incoming_version, &local_version);
    if !incoming_parses || !local_parses {
        // a tainted local version (or a malformed
        // envelope) lost typed-LWW arbitration and fell back to a
        // byte compare. Log the corruption so diagnostics surface
        // the unparseable version; the byte-compare result still
        // refuses a delete when the local string sorts strictly
        // greater than the envelope's, closing the regression where
        // the tolerance fallback returned `Apply` and a corrupt-
        // local row got wiped by an older-HLC envelope.
        crate::error_log::log_sync_error(
            conn,
            error_log_kind,
            &format!(
                "delete LWW gate falling back to byte-compare for \
                 entity_id={entity_id}, incoming={incoming_version:?}, \
                 local={local_version:?}"
            ),
            None,
        );
    }
    let dominates = match cmp {
        std::cmp::Ordering::Greater => true,
        std::cmp::Ordering::Equal => allow_equal_versions.allow_equal(),
        std::cmp::Ordering::Less => false,
    };
    if dominates {
        Ok(DeleteLwwDecision::Apply)
    } else {
        Ok(DeleteLwwDecision::Reject { local_version })
    }
}

/// Outcome of [`gate_then_cascade`]. Mirrors the per-handler
/// `*DeleteOutcome::Applied | LwwRejected` shape so each caller can
/// map a single decision into its own typed enum without
/// re-evaluating the gate. The gate runs BEFORE the cascade — running
/// it afterward would let a stale-but-byte-compare-rejecting envelope
/// mint cascade tombstones over child / edge rows whose live parent
/// then stays alive, after which peers' subsequent edge upserts could
/// never lift those tombstones (cascade HLC ≥ edge HLC) and the
/// cluster would diverge permanently on edge state.
pub(in crate::apply::aggregate) enum CascadingDeleteDecision {
    Applied,
    Rejected { local_version: String },
}

/// uniform "gate before cascade" sequencer for
/// every aggregate `apply_*_delete` whose delete fans out child /
/// edge tombstones. Runs in this order:
///
/// 1. `evaluate_delete_lww` against the parent row's `version`. If
///    the gate returns `Reject` (either via parsed HLC compare or
///    the byte-compare fallback for tainted local versions), the
///    helper short-circuits with `Rejected { .. }` and the cascade
///    closure NEVER runs. Running the cascade before the byte-
///    compare gate would leave cascade tombstones behind on a
///    rejected parent delete.
/// 2. On `Apply`, runs the caller-supplied cascade closure (which
///    fans out child / edge tombstones via
///    `tombstone_composite_edges` / `tombstone_child_rows`).
/// 3. On cascade success, runs the parent DELETE under
///    `delete_sql` (must be of the shape `DELETE FROM <table>
///    WHERE <pk> = :id`).
///
/// `allow_equal_versions` mirrors the upsert convention — production
/// callers pass `true` so shadow-promotion replay (`>=` semantics)
/// stays idempotent.
pub(in crate::apply::aggregate) fn gate_then_cascade<F>(
    conn: &Connection,
    read_version_sql: &str,
    delete_sql: &str,
    entity_id: &str,
    incoming_version: &str,
    allow_equal_versions: LwwTieBreak,
    cascade_fn: F,
) -> Result<CascadingDeleteDecision, ApplyError>
where
    F: FnOnce(&Connection) -> Result<(), ApplyError>,
{
    match evaluate_delete_lww(
        conn,
        read_version_sql,
        entity_id,
        incoming_version,
        allow_equal_versions,
    )? {
        DeleteLwwDecision::Reject { local_version } => {
            Ok(CascadingDeleteDecision::Rejected { local_version })
        }
        DeleteLwwDecision::Apply => {
            // cascade runs ONLY after the gate
            // says Apply. Closure receives the same connection so the
            // cascade tombstones land in the same outer transaction
            // as the parent DELETE.
            cascade_fn(conn)?;
            conn.prepare_cached(delete_sql)?
                .execute(rusqlite::named_params! { ":id": entity_id })?;
            Ok(CascadingDeleteDecision::Applied)
        }
    }
}

/// Wrap [`gate_then_cascade`] with the boilerplate epilogue every
/// `LwwGatedAggregate` delete handler shares: map the
/// `CascadingDeleteDecision::{Applied, Rejected{..}}` enum into the
/// canonical `super::LwwGatedDeleteOutcome::{Applied, LwwRejected(..)}`
/// shape so the per-handler call site is a single line — task,
/// habit, and calendar_event delete handlers all route through the
/// same epilogue here.
pub(in crate::apply::aggregate) fn gate_then_cascade_into_outcome<F>(
    conn: &Connection,
    read_version_sql: &str,
    delete_sql: &str,
    entity_id: &str,
    incoming_version: &str,
    allow_equal_versions: LwwTieBreak,
    cascade_fn: F,
) -> Result<crate::apply::aggregate::LwwGatedDeleteOutcome, ApplyError>
where
    F: FnOnce(&Connection) -> Result<(), ApplyError>,
{
    match gate_then_cascade(
        conn,
        read_version_sql,
        delete_sql,
        entity_id,
        incoming_version,
        allow_equal_versions,
        cascade_fn,
    )? {
        CascadingDeleteDecision::Applied => {
            Ok(crate::apply::aggregate::LwwGatedDeleteOutcome::Applied)
        }
        CascadingDeleteDecision::Rejected { local_version } => {
            Ok(crate::apply::aggregate::LwwGatedDeleteOutcome::LwwRejected(
                crate::apply::LwwRejectedDetail { local_version },
            ))
        }
    }
}
