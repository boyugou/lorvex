//! The `dispatch` entry point + its `post_handler_lww_outcome`
//! translator.
//!
//! The dispatcher is the single per-envelope entry point: it
//! resolves the entity-type to its [`super::handler::EntityHandler`]
//! row, snapshots the local row's version when the row's gate
//! configuration silently no-ops on rejection (so the post-handler
//! re-check is the only way to surface `LwwRejected`), invokes the
//! kind- and gate-specific delete-or-upsert path, and translates the
//! handler's outcome into a typed
//! [`super::outcome::EntityApplyOutcome`].
//!
//! Replaces the prior 7-variant enum + parallel-match-arms shape with
//! a flag-driven dispatch: `kind` selects the four broad fn-pointer
//! shapes (Normal vs the three special cases that thread `device_id`
//! or implement append-only semantics) and `gates` selects which of
//! the three optional delete fn-pointers is `Some` for `Normal`
//! rows.

use rusqlite::Connection;

use crate::envelope::{SyncEnvelope, SyncOperation};

use super::super::{aggregate, changelog, ApplyError, LwwTieBreak};
use super::handler::{lookup, EntityHandler, HandlerKind};
use super::outcome::EntityApplyOutcome;

/// Apply a single envelope to its registered handler. Returns
/// `Err(ApplyError::UnknownEntityType)` if the entity type has no
/// registered handler.
///
/// returns a typed [`EntityApplyOutcome`]. For delete envelopes
/// targeting a `Normal` row whose handler does NOT surface a typed
/// `LwwRejected` outcome (`gates == HandlerGates::NONE`), the
/// dispatcher pre-reads the local row's version, runs the handler,
/// then re-checks: if the row still exists at a strictly greater
/// version than the envelope's, the in-handler SQL gate refused the
/// DELETE and we return `LwwRejected`. The caller in `apply_envelope`
/// uses that signal to suppress tombstone creation, which would
/// otherwise record the loser's HLC as the entity's canonical death
/// and corrupt the cluster's converged state on the next re-sync.
pub(in crate::apply) fn dispatch(
    conn: &Connection,
    envelope: &SyncEnvelope,
    allow_equal_versions: LwwTieBreak,
    apply_ts: &str,
) -> Result<EntityApplyOutcome, ApplyError> {
    let id = &envelope.entity_id;
    let payload = &envelope.payload;
    // `envelope.version` is now `Hlc`; the per-entity handler
    // signatures still take `&str` for the canonical lex form
    // (storage columns are `TEXT`). Materialize the canonical string
    // once so every dispatch arm threads the same owned value.
    let version_string = envelope.version.to_string();
    let version = version_string.as_str();
    let is_delete = envelope.operation == SyncOperation::Delete;

    let handler = lookup(envelope.entity_type.as_str())
        .ok_or_else(|| ApplyError::UnknownEntityType(envelope.entity_type.as_str().to_string()))?;

    // Snapshot the local row's version before any delete handler
    // runs, but ONLY for rows that DO NOT already surface a typed
    // `LwwRejected` outcome from their handler. Rows with
    // `gates.lww_gated` (LwwGated / InvariantGated) early-return on
    // LWW rejection — for those, the post-handler block at the
    // bottom of this function is dead code (`get_local_version`
    // returns `None` because the row was actually deleted), so the
    // pre-snapshot SELECT is pure overhead. The unconditional
    // delete paths (Normal-without-gates, Memory) route
    // through `lww_gated_delete` (or its inline equivalent) which
    // silently no-ops on rejection without flowing the typed
    // outcome up — those genuinely need the post-handler re-check
    // to tell "Applied" from "silently rejected" apart.
    let needs_post_handler_lww_check = is_delete && !handler.gates.lww_gated;
    let pre_delete_local_version: Option<String> = if needs_post_handler_lww_check {
        super::super::get_local_version(conn, envelope.entity_type.as_str(), id)?
    } else {
        None
    };

    match handler.kind {
        HandlerKind::Normal => {
            if is_delete {
                if let Some(outcome) = run_normal_delete(conn, &handler, id, version, apply_ts)? {
                    return Ok(outcome);
                }
            } else {
                let upsert = handler.upsert.expect("Normal kind has Some(upsert)");
                upsert(conn, id, payload, version, allow_equal_versions, apply_ts)?;
            }
        }
        HandlerKind::Memory => {
            if is_delete {
                aggregate::apply_memory_delete(conn, id, version, apply_ts)?;
            } else {
                // thread the envelope's `device_id` through so a
                // memory-truncation conflict-log entry attributes
                // the loser correctly.
                aggregate::apply_memory_upsert(
                    conn,
                    id,
                    payload,
                    version,
                    allow_equal_versions,
                    &envelope.device_id,
                    apply_ts,
                )?;
            }
        }
        HandlerKind::AppendOnlyChangelog => {
            // `ai_changelog` is an append-only audit stream. The
            // only writer-side Delete is full data reset, which
            // carries an explicit reset marker in the payload. The
            // table has no `version` column so the upstream LWW gate
            // never fires; unmarked deletes still fail closed inside
            // `apply_changelog_reset_delete`.
            if is_delete {
                changelog::apply_changelog_reset_delete(conn, id, payload)?;
                return Ok(EntityApplyOutcome::Applied);
            }
            // ai_changelog is append-only; `apply_ts` has no role
            // in this arm (the row's `timestamp` field comes from
            // the payload itself). Thread the envelope's
            // `payload_schema_version` so the handler can enforce
            // the same forward-compat gate as the envelope-level
            // dispatcher path.
            changelog::apply_changelog_entry(conn, id, payload, envelope.payload_schema_version)?;
        }
    }

    if needs_post_handler_lww_check {
        if let Some(outcome) =
            post_handler_lww_outcome(conn, envelope, id, pre_delete_local_version.as_deref())?
        {
            return Ok(outcome);
        }
    }

    Ok(EntityApplyOutcome::Applied)
}

/// Dispatch the delete fn-pointer for a `Normal` row, choosing
/// among the three optional delete shapes by reading
/// [`HandlerGates`].
///
/// Returns `Ok(Some(outcome))` when the gated handler surfaced a
/// typed early-return (`SkippedByInvariant` / `LwwRejected`); the
/// caller should propagate that outcome upward without running the
/// post-handler LWW re-check or returning `Applied`. Returns
/// `Ok(None)` when the SQL DELETE ran (or was silently no-op'd on
/// LWW rejection in the no-gate case — the post-handler re-check
/// will catch the latter).
fn run_normal_delete(
    conn: &Connection,
    handler: &EntityHandler,
    id: &str,
    version: &str,
    apply_ts: &str,
) -> Result<Option<EntityApplyOutcome>, ApplyError> {
    if handler.gates.invariant_gated {
        // `lists` uses `aggregate::InvariantGatedDeleteOutcome`:
        // `SkippedByInvariant` defers the envelope to
        // `sync_pending_inbox`; `LwwRejected` skips the tombstone
        // (the surviving local row would otherwise be wiped at the
        // envelope's older HLC on re-sync); `Applied` falls
        // through.
        let delete = handler
            .invariant_gated_delete
            .expect("invariant_gated row has Some(invariant_gated_delete)");
        match delete(conn, id, version, apply_ts)? {
            aggregate::InvariantGatedDeleteOutcome::SkippedByInvariant { invariant } => {
                Ok(Some(EntityApplyOutcome::DeleteSkippedByInvariant {
                    invariant,
                }))
            }
            aggregate::InvariantGatedDeleteOutcome::LwwRejected(detail) => {
                Ok(Some(EntityApplyOutcome::LwwRejected {
                    local_version: detail.local_version,
                }))
            }
            aggregate::InvariantGatedDeleteOutcome::Applied => Ok(None),
        }
    } else if handler.gates.lww_gated {
        // collapsed from the three byte-isomorphic Task / Habit /
        // CalendarEvent arms. The shared
        // `LwwGatedDeleteOutcome::LwwRejected` flows through
        // `apply_envelope` which suppresses tombstone creation.
        // silently no-op'd the SQL DELETE on `Reject`; the
        // dispatcher reported `Applied` and the caller minted a
        // tombstone at the envelope's older HLC over the surviving
        // local row.
        let delete = handler
            .lww_gated_delete
            .expect("lww_gated row has Some(lww_gated_delete)");
        match delete(conn, id, version, apply_ts)? {
            aggregate::LwwGatedDeleteOutcome::LwwRejected(detail) => {
                Ok(Some(EntityApplyOutcome::LwwRejected {
                    local_version: detail.local_version,
                }))
            }
            aggregate::LwwGatedDeleteOutcome::Applied => Ok(None),
        }
    } else {
        // Standard / child / edge / tag delete. Children /
        // edges thread the envelope's `version` so the handler can
        // install its in-row LWW guard; aggregate-root standards
        // (preferences, calendar_subscriptions, day-scoped) take
        // the same parameter shape and rely on the post-handler
        // re-check to surface SQL-level LWW rejection.
        let delete = handler
            .standard_delete
            .expect("Normal !lww_gated !invariant_gated row has Some(standard_delete)");
        delete(conn, id, version, apply_ts)?;
        Ok(None)
    }
}

/// post-handler LWW-rejection detection.
///
/// Only meaningful when:
///   1. This was a delete envelope targeting a versioned row.
///   2. We saw a local row before the handler ran.
///   3. The local row STILL exists after the handler ran AND
///      its version is strictly greater than the envelope's.
///
/// Condition (3) means the handler's `:version >= version` SQL
/// predicate refused the DELETE — the local row beat the envelope
/// on LWW. Tombstoning at the envelope's version would record an
/// older HLC as the canonical death of a row the cluster knows
/// is alive, durably overriding the winner on the next re-sync.
/// Returns `Some(LwwRejected)` so the caller skips tombstone creation.
///
/// FK-stalled and list-invariant skips do NOT trip this check
/// because those branches preserve the row at its existing
/// version, which equals or is less than the envelope's
/// (envelope.version > local.version is what the outer LWW gate
/// demands before reaching this point). The post-handler version
/// either remains <= envelope.version (intentional skip — tombstone
/// OK per) or the row is gone (DELETE actually ran).
///
/// Returns `Ok(None)` when no rejection is detected (caller continues
/// with `EntityApplyOutcome::Applied`); `Ok(Some(_))` when the
/// post-handler check observed a rejection that should suppress
/// tombstone creation; `Err(_)` when the helper itself fails (only the
/// `get_local_version` SELECT can fail here).
fn post_handler_lww_outcome(
    conn: &Connection,
    envelope: &SyncEnvelope,
    id: &str,
    pre_delete_local_version: Option<&str>,
) -> Result<Option<EntityApplyOutcome>, ApplyError> {
    let Some(pre_version) = pre_delete_local_version else {
        return Ok(None);
    };
    let Some(post_version) =
        super::super::get_local_version(conn, envelope.entity_type.as_str(), id)?
    else {
        return Ok(None);
    };
    // Adopt parse-then-typed-compare with byte fallback (mirrors
    // `outbox::coalesce::enqueue_coalesced` and the
    // parallel sites in `tombstone::create_tombstone`,
    // `apply::edge::dependency::try_break_cycle_by_hlc`, and
    // `apply::stamp_merge_winner_version`). A raw byte-compare on
    // `post_version` is correct for canonical HLCs but inverts when
    // the local row carries a stale-shape literal (`'v1'`, `'seed'`) —
    // letters sort ABOVE digits, so a tainted local row would falsely
    // beat every canonical envelope on the LWW-rejection check and
    // surface spurious `LwwRejected` outcomes that suppress legitimate
    // tombstone creation.
    //
    // Discipline: parse both sides; compare typed whenever both parse;
    // fall back to byte-compare only when both fail to parse so the
    // LWW-rejection check still terminates on a legacy DB. Partial-
    // tainted cases log+continue treating the canonical side as the
    // unambiguous winner.
    let post_parse = lorvex_domain::hlc::Hlc::parse(&post_version);
    let pre_parse = lorvex_domain::hlc::Hlc::parse(pre_version);
    let post_is_strictly_newer = if let Ok(post_hlc) = &post_parse {
        post_hlc > &envelope.version
    } else {
        // Tainted local row vs canonical envelope.
        //
        // Two sub-cases (H1):
        //
        //   A. `pre_version` is also unparseable AND equals
        //      `post_version` — the in-handler SQL gate
        //      (`:version >= row.version`) byte-compared a
        //      digit-leading canonical envelope against a
        //      letter-leading legacy literal (`'v1'`, `'seed'`).
        //      Bytes sort digits BELOW letters in ASCII, so the
        //      SQL refused the DELETE. Reaching this branch with
        //      pre==post means the handler skipped — surface
        //      `LwwRejected` so the caller does not mint a
        //      tombstone over a still-live row. Without this gate
        //      the post-handler would declare `Applied`, the
        //      outbox would persist a tombstone at the envelope's
        //      HLC, and a re-sync would durably override the live
        //      row on every peer.
        //
        //   B. `pre_version` parses cleanly OR pre != post — the
        //      row's shape changed mid-apply (some other writer
        //      canonicalized it, or the handler partially
        //      executed). Treat the tainted side as
        //      NOT-strictly-newer so the tombstone proceeds. A
        //      tainted row "winning" LWW in this sub-case would
        //      silently shadow-ban the cluster's Delete intent.
        let dedup_signature = format!(
            "post_handler_lww|{}|{id}|local_ok=false",
            envelope.entity_type.as_str(),
        );
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            "sync.apply.post_handler_lww_unparseable",
            &format!(
                "post-handler LWW-rejection saw an unparseable local \
                 version for entity_type={}, entity_id={id}, \
                 local={post_version:?} (parsed=false), \
                 pre={pre_version:?} (parsed={}), \
                 envelope={} (parsed=true)",
                envelope.entity_type.as_str(),
                pre_parse.is_ok(),
                envelope.version,
            ),
            Some(&dedup_signature),
            Some("warn"),
        );
        // Sub-case A: both unparseable AND equal → SQL byte-compare
        // refused; surface `LwwRejected` to skip the tombstone.
        if pre_parse.is_err() && post_version == pre_version {
            return Ok(Some(EntityApplyOutcome::LwwRejected {
                local_version: post_version,
            }));
        }
        false
    };
    if post_is_strictly_newer && post_version == pre_version {
        return Ok(Some(EntityApplyOutcome::LwwRejected {
            local_version: post_version,
        }));
    }
    Ok(None)
}
