//! Local LWW and FK gates for non-redirect inbound envelopes.

use rusqlite::Connection;

use lorvex_domain::hlc::Hlc;
use lorvex_domain::merge::{resolve_lww, MergeOutcome};

use super::super::conflict::record_lww_conflict_and_skip;
use super::super::{ApplyError, ApplyResult, DeferralReason};
use super::{check_fk_dependencies, get_local_version};
use crate::envelope::{SyncEnvelope, SyncOperation};

pub(super) fn gate_lww_and_fk(
    conn: &Connection,
    envelope: &SyncEnvelope,
    apply_ts: &str,
) -> Result<Option<ApplyResult>, ApplyError> {
    // 3. Compare version (LWW) — applies to BOTH upsert AND delete.
    //
    // LWW gate runs BEFORE FK preflight. Order is:
    //   (1) tombstone check  — already done above
    //   (2) LWW gate         — reject stale envelopes outright
    //   (3) FK preflight     — defer envelopes that would land if
    //                          their parent arrived
    //
    // Running FK first would let a stale-AND-missing-dep upsert
    // defer into pending_inbox even though it would ultimately lose
    // LWW once its parent arrived — burning attempt-count slots
    // until the dependency landed, only to be silently dropped
    // seconds later.
    //
    // The delete path runs through this gate too — skipping LWW for
    // deletes would let a stale delete arriving at a device that had
    // already seen a newer upsert for the same entity wipe the row.
    // The subsequent
    // tombstone was created at the delete's HLC, so re-convergence
    // depended on the original upserting device re-pushing — not
    // guaranteed once the outbox GC'd the envelope. Edge deletes
    // (task_tags, task_dependencies, task_calendar_event_links,
    // habit_completions) were especially vulnerable because SQLite
    // CASCADE silently removed them without an upstream peer able to
    // replay. Gate delete on the same LWW guard so a stale delete
    // now gets logged as a conflict and skipped.
    // a corrupted *local* version string (legacy
    // data, manual DB edit, future schema bug) must not poison the
    // apply path for a well-formed *envelope*. If parsing the local
    // version fails, log the corruption to error_log so it surfaces
    // in diagnostics, then let the envelope land on top — the next
    // outbox push will rewrite the bad value with a stamped HLC.
    // Mirrors `payload_shadow::remove_shadow_if_superseded`'s
    // tolerant pattern.
    let parsed_local_version: Option<Hlc> =
        get_local_version(conn, envelope.entity_type.as_str(), &envelope.entity_id)?.and_then(
            |local_version_str| match Hlc::parse(&local_version_str) {
                Ok(hlc) => Some(hlc),
                Err(err) => {
                    let detail = format!(
                        "local version '{local_version_str}' on {}:{} is not a valid HLC: {err}",
                        envelope.entity_type, envelope.entity_id
                    );
                    crate::error_log::log_sync_error(
                        conn,
                        "sync.apply.local_version_corruption",
                        &detail,
                        None,
                    );
                    None
                }
            },
        );

    if let Some(local_version) = parsed_local_version {
        // Re-derive the local version string from the parsed HLC for
        // the conflict-log message — the original string was already
        // validated above, and re-formatting from the parsed HLC
        // gives a canonical representation.
        let local_version_str = local_version.to_string();
        // `envelope.version` is typed `Hlc`.
        let remote_version = &envelope.version;

        if matches!(
            resolve_lww(&local_version, remote_version),
            MergeOutcome::LocalWins
        ) {
            let reason = format!(
                "local version {} >= remote version {} for {} {}:{}",
                local_version_str,
                envelope.version,
                envelope.operation.as_str(),
                envelope.entity_type,
                envelope.entity_id
            );
            return record_lww_conflict_and_skip(
                conn,
                envelope.entity_type.as_str(),
                &envelope.entity_id,
                &local_version,
                envelope,
                reason,
                apply_ts,
            )
            .map(Some);
        }
        // RemoteWins — fall through to apply.
    }
    // If no local entity exists: for upsert this is a new entity,
    // for delete it's a no-op-ish (we still record the tombstone so
    // a late-arriving upsert with a lesser HLC is properly guarded
    // by the existing tombstone-vs-upsert logic upstream).

    // FK dependency preflight for upsert operations — runs after
    // the LWW gate so a stale envelope is rejected before the FK
    // check; otherwise a stale-AND-missing-dep upsert would defer
    // to pending_inbox even though it would ultimately lose LWW.
    // Check whether the entity's parent / FK targets exist locally
    // before attempting INSERT. This prevents SQLite FK constraint
    // errors and enables typed MissingDependency deferral.
    if envelope.operation == SyncOperation::Upsert {
        if let Some((dep_type, dep_id)) = check_fk_dependencies(
            conn,
            envelope.entity_type.as_str(),
            &envelope.entity_id,
            &envelope.payload,
        )? {
            return Ok(Some(ApplyResult::Deferred {
                reason: DeferralReason::MissingDependency {
                    entity_type: dep_type,
                    entity_id: dep_id,
                },
            }));
        }
    }
    Ok(None)
}
