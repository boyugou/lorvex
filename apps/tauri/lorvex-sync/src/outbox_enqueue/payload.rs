//! Core payload-enqueue pipeline: version stamping, payload-shadow
//! merge/remove, blob-hash extraction, canonicalization, coalesced
//! outbox insert, tombstone minting, and post-write pending-inbox
//! drain. Public autocommit callers get a top-level `BEGIN
//! IMMEDIATE`; callers that already opened a transaction keep the
//! nested SAVEPOINT shape.
//!
//! The internal entry points (`enqueue_payload_internal`,
//! `enqueue_payload_internal_body`) are sibling-only; the public
//! surface is `enqueue_payload_upsert` / `enqueue_payload_delete`.

use rusqlite::Connection;
use serde_json::Value;
use std::sync::atomic::{AtomicU64, Ordering};

use lorvex_domain::version::PAYLOAD_SCHEMA_VERSION;

use crate::canonicalize::canonicalize_json;
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::outbox;

use super::context::OutboxWriteContext;
use super::error::EnqueueError;

/// Process-lifetime counter of post-write pending-inbox drain failures.
///
/// `enqueue_payload_internal` opportunistically drains the pending
/// inbox after a successful write so child rows that were
/// FK-stalled on the entity we just wrote can land immediately.
/// The drain is part of the same atomic convergence step as the
/// parent enqueue; this counter records hard enqueue failures caused
/// by the target lookup or drain path (e.g. recurring `SQLITE_NOMEM`)
/// so operators have an out-of-band diagnostic signal.
///
/// Surface via [`pending_drain_failure_count`] so a Settings →
/// Diagnostics panel can render "post-write inbox drain failures: N
/// since process start". Same shape as
/// `lorvex_store::error_log::silent_diagnostic_failure_count` (#3308 T3-2).
static PENDING_DRAIN_FAILURES: AtomicU64 = AtomicU64::new(0);

/// Read the cumulative count of post-write pending-inbox drain
/// failures observed by this process. See
/// [`PENDING_DRAIN_FAILURES`] for the surfacing contract.
pub fn pending_drain_failure_count() -> u64 {
    PENDING_DRAIN_FAILURES.load(Ordering::Relaxed)
}

pub(super) fn enqueue_payload_internal(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    operation: SyncOperation,
    payload: &Value,
    ctx: OutboxWriteContext<'_>,
) -> Result<(), EnqueueError> {
    if conn.is_autocommit() {
        return lorvex_store::with_immediate_transaction(conn, move |c| {
            enqueue_payload_internal_in_transaction(
                c,
                entity_type,
                entity_id,
                operation,
                payload,
                ctx,
            )
        });
    }

    enqueue_payload_internal_in_transaction(conn, entity_type, entity_id, operation, payload, ctx)
}

fn enqueue_payload_internal_in_transaction(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    operation: SyncOperation,
    payload: &Value,
    ctx: OutboxWriteContext<'_>,
) -> Result<(), EnqueueError> {
    // this function does six writes — version_stamp,
    // payload_shadow merge, outbox coalesce (itself a 3-step
    // SELECT/DELETE/INSERT — H2), blob_ref registration, tombstone —
    // that must all commit or all roll back. A partial failure (disk
    // full, FK violation, panic on an over-large BLOB) would leave
    // divergent local state: an outbox row queued for push but no
    // tombstone (peer upsert revives the entity locally), or blob
    // keepalive registry missing entries (`gc_blobs` reaps a
    // still-referenced blob).
    //
    // Autocommit callers are wrapped by the public entry point before
    // reaching this helper; already-transactional production code
    // keeps its existing outer txn. The outer `BEGIN IMMEDIATE`
    // serializes cross-connection writers (the H2 race) at the SQLite
    // lock layer in addition to the UNIQUE partial index defense.
    //
    // Route through the canonical
    // `lorvex_store::transaction::with_savepoint` helper rather than
    // inlining `format!("SAVEPOINT {sp}")`. The helper double-quotes
    // the identifier consistently and stamps a per-process counter
    // suffix so concurrent nested invocations cannot collide. An
    // inline emission that leaves the savepoint identifier unquoted
    // is safe today (UUID `simple()` form is alphanumeric) but a
    // future swap to `Uuid::hyphenated()` or any unsanitized slug
    // would become a SQL parse failure.
    //
    // SAVEPOINTs nest cleanly inside any outer transaction context
    // (the apply pipeline opens its own SAVEPOINTs at
    // `apply/edge/dependency.rs`, `apply/aggregate/recurrence.rs`,
    // `apply/tag.rs:218`), and provide identical atomicity to a
    // top-level `BEGIN IMMEDIATE`. The previous autocommit guard
    // would silently SKIP the wrap whenever called inside an outer
    // txn, producing partial-failure windows that nested writes
    // could not roll back; the SAVEPOINT shape closes that gap and
    // also lets a future inner caller chain into this helper
    // without tripping "cannot start a transaction within a
    // transaction".
    let operation_for_drain = operation.clone();
    lorvex_store::transaction::with_savepoint::<(), EnqueueError>(conn, "enqueue_payload", |c| {
        enqueue_payload_internal_body(c, entity_type, entity_id, operation, payload, ctx)
    })?;

    if matches!(
        operation_for_drain,
        SyncOperation::Upsert | SyncOperation::Delete
    ) {
        // Drain pending-inbox entries that were waiting on this
        // just-created `(entity_type, entity_id)` FK target. Local
        // writes (UI, MCP, CLI) authoring the missing parent must
        // trigger the drain too — otherwise deferred children would
        // sit in the inbox until the next remote pull. The
        // `has_pending_for_target` check is a single indexed
        // lookup that bails on first match, so the per-write
        // overhead on the hot path is negligible. Drain failures
        // are hard enqueue failures: the just-authored parent and
        // any child apply/bookkeeping it unblocks are one atomic
        // convergence step. Autocommit callers are wrapped above in
        // `BEGIN IMMEDIATE`; already-transactional callers inherit
        // their outer transaction boundary.
        //
        // Both Upsert and Delete paths trigger the drain. Delete
        // is rare — a child envelope deferred on a missing parent
        // would normally drain via the parent's tombstone-arrival
        // (the inbox already special-cases that path) — but a
        // child waiting on its OWN deletion target (an FK to a
        // sibling that was just locally deleted) deserves the
        // same opportunistic drain.
        drain_pending_after_enqueue(conn, entity_type, entity_id)?;
    }
    Ok(())
}

fn drain_pending_after_enqueue(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<(), EnqueueError> {
    match crate::pending_inbox::has_pending_for_target(conn, entity_type, entity_id) {
        Ok(false) => Ok(()),
        Ok(true) => crate::pending_inbox::drain_pending_inbox(conn)
            .map(|_| ())
            .map_err(|source| {
                PENDING_DRAIN_FAILURES.fetch_add(1, Ordering::Relaxed);
                EnqueueError::PendingDrain {
                    entity_type: entity_type.to_string(),
                    entity_id: entity_id.to_string(),
                    source,
                }
            }),
        Err(source) => {
            PENDING_DRAIN_FAILURES.fetch_add(1, Ordering::Relaxed);
            Err(EnqueueError::PendingDrainTargetLookup {
                entity_type: entity_type.to_string(),
                entity_id: entity_id.to_string(),
                source: crate::error::SyncError::Sql(source),
            })
        }
    }
}

fn enqueue_payload_internal_body(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    operation: SyncOperation,
    payload: &Value,
    ctx: OutboxWriteContext<'_>,
) -> Result<(), EnqueueError> {
    // For Upsert we require the row to exist — otherwise local LWW reads
    // would use a stale version column and let intermediate remote envelopes
    // incorrectly win. For Delete the row has typically just been removed
    // by the caller, so an `EntityNotFound` stamp result is expected.
    //
    // the `Superseded` variant is lifted to
    // `EnqueueError::VersionSuperseded` here rather than at the
    // `From<VersionStampError>` boundary so we can populate
    // `attempted_version` from `ctx.version` (the typed
    // VersionStampError doesn't carry it).
    match crate::version_stamp::stamp_entity_version(conn, entity_type, entity_id, ctx.version) {
        Ok(()) => {}
        Err(crate::version_stamp::VersionStampError::EntityNotFound { .. })
            if operation == SyncOperation::Delete => {}
        Err(crate::version_stamp::VersionStampError::Superseded {
            entity_type,
            entity_id,
            existing_version,
        }) => {
            return Err(EnqueueError::VersionSuperseded {
                entity_type,
                entity_id,
                attempted_version: ctx.version.to_string(),
                existing_version,
            });
        }
        Err(err) => return Err(err.into()),
    }

    // a coalesced UPSERT → DELETE → UPSERT sequence
    //   leave a stale local tombstone (the DELETE step minted
    // one against the row's then-current HLC; the second UPSERT
    // wrote a fresh outbox envelope at a strictly-greater HLC but
    // never cleared the dead tombstone). On the next inbound apply
    // pass for any envelope of this entity, the tombstone-vs-upsert
    // gate compared `tombstone.version >= envelope.version` and
    // could silently drop a peer's concurrent edit at a lower HLC
    // than the dead tombstone — the resurrection fired on the
    // authoring device but every receiving device kept the entity
    // tombstoned.
    //
    // The Upsert path therefore explicitly removes any local
    // tombstone for `(entity_type, entity_id)` after
    // `stamp_entity_version` succeeds. The version_stamp gate has
    // already enforced LWW (a Superseded outbox would have
    // returned above), so there is no risk of clobbering a winner
    // here. The Delete branch leaves the tombstone untouched
    // because the sibling `create_tombstone` call below will mint
    // the correct one for the freshly-emitted Delete envelope.
    if operation == SyncOperation::Upsert {
        // Surface the bool outcome to tracing so on-host log
        // scrapes can correlate "stale tombstone removed" events
        // with the entity write history. Discarding the result via
        // `let _ = ...?` would make it impossible to distinguish
        // "had a stale tombstone, removed it" from "clean upsert,
        // no-op." Both true and false remain valid post-conditions;
        // the trace is the only behavior
        // change.
        let removed_stale_tombstone =
            crate::tombstone::remove_tombstone(conn, entity_type, entity_id)?;
        if removed_stale_tombstone {
            lorvex_store::error_log::append_error_log_best_effort(
                conn,
                "sync.outbox_enqueue.stale_tombstone_removed",
                &format!(
                    "upsert wiped stale tombstone before re-enqueue: {entity_type}:{entity_id}"
                ),
                None,
                Some("info"),
            );
        }
    }

    let payload = match operation {
        SyncOperation::Delete => {
            lorvex_sync_payload::payload_shadow::remove_shadow(conn, entity_type, entity_id)?;
            payload.clone()
        }
        SyncOperation::Upsert => lorvex_sync_payload::payload_shadow::merge_payload_with_shadow(
            conn,
            entity_type,
            entity_id,
            payload,
        )?,
    };

    let payload = match payload {
        Value::Object(mut obj) => {
            if operation == SyncOperation::Upsert || !obj.contains_key("version") {
                obj.insert(
                    "version".to_string(),
                    Value::String(ctx.version.to_string()),
                );
            }
            Value::Object(obj)
        }
        other => other,
    };

    let is_delete = operation == SyncOperation::Delete;
    // parse the wire-boundary `entity_type` into the
    // typed `EntityKind`. The local enqueue surface only ever gets
    // called with values from the canonical naming registry, so an
    // unknown kind here is a programmer error in a new caller — not
    // a forward-compat case — and surfaces via the existing
    // `EnqueueError::UnknownEntityType` arm.
    let entity_kind = lorvex_domain::naming::EntityKind::parse(entity_type)
        .ok_or_else(|| EnqueueError::UnknownEntityType(entity_type.to_string()))?;
    // typed envelope at the wire boundary. The `ctx.version`
    // string is produced upstream by `version_stamp::stamp_entity_version`
    // (canonical HLC), so a parse failure here means an upstream stamper
    // emitted a non-canonical literal. Surface it through the same
    // `TaintedVersion` channel that the outbox refusal uses so callers
    // get a uniform "the caller must re-stamp" signal.
    let typed_version =
        lorvex_domain::hlc::Hlc::parse(ctx.version).map_err(|_| EnqueueError::TaintedVersion {
            entity_type: entity_kind,
            entity_id: entity_id.to_string(),
            version: ctx.version.to_string(),
        })?;
    let envelope = SyncEnvelope {
        entity_type: entity_kind,
        entity_id: entity_id.to_string(),
        operation,
        version: typed_version,
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: canonicalize_json(&payload)?,
        device_id: ctx.device_id.to_string(),
    };

    let outbox_id = outbox::enqueue_coalesced(conn, &envelope)?;

    // Only mint a local tombstone when the delete envelope actually
    // entered the outbox. The coalescer returns `None` when it
    // rejects a stale delete in favor of a newer queued row; writing a
    // tombstone for that rejected envelope would make local delete
    // state contradict the preserved outbox winner.
    if is_delete && outbox_id.is_some() {
        let deleted_at = lorvex_domain::sync_timestamp_now();
        crate::tombstone::create_tombstone(
            conn,
            entity_type,
            entity_id,
            ctx.version,
            &deleted_at,
            None,
            None,
        )?;
    }

    Ok(())
}

pub fn enqueue_payload_upsert(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    payload: &Value,
    ctx: OutboxWriteContext<'_>,
) -> Result<(), EnqueueError> {
    enqueue_payload_internal(
        conn,
        entity_type,
        entity_id,
        SyncOperation::Upsert,
        payload,
        ctx,
    )
}

pub fn enqueue_payload_delete(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    payload: &Value,
    ctx: OutboxWriteContext<'_>,
) -> Result<(), EnqueueError> {
    enqueue_payload_internal(
        conn,
        entity_type,
        entity_id,
        SyncOperation::Delete,
        payload,
        ctx,
    )
}
