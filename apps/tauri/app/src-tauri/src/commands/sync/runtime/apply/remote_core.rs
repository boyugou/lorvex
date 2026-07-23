use super::super::*;
use super::matching::is_supported_incoming_record;
use super::ordering::sync_entity_apply_priority;
use super::remote_cursors::{
    record_device_cursors_from_applied_records, record_seen_remote_device_cursors,
};
use super::remote_diagnostics::{
    duration_ms_saturating, persist_sync_apply_runtime_warning, record_sync_apply_cycle_best_effort,
};
use super::remote_events::emit_data_changed_for_entity_types;
use super::remote_pending::drain_pending_inbox;
use super::{ApplyRemoteSyncResult, IncomingSyncRecord};
use crate::commands::with_immediate_transaction;
use crate::error::{AppError, AppResult};
use lorvex_sync::apply::{apply_envelope, ApplyResult};

fn invalid_incoming_record_error(message: impl Into<String>) -> AppError {
    AppError::Validation(message.into())
}

fn strict_apply_error(record: &IncomingSyncRecord, error: impl std::fmt::Display) -> AppError {
    AppError::Validation(format!(
        "apply_envelope failed for {}:{} — {error}",
        record.envelope.entity_type, record.envelope.entity_id
    ))
}

pub(crate) fn apply_remote_sync_records_with_checkpoint_writer<F>(
    conn: &rusqlite::Connection,
    records: Vec<IncomingSyncRecord>,
    synced_ts: &str,
    mode: RemoteApplyMode,
    persist_checkpoint: F,
) -> AppResult<ApplyRemoteSyncResult>
where
    F: FnOnce(&rusqlite::Connection, &[IncomingSyncRecord], &str) -> AppResult<()>,
{
    let received = i64::try_from(records.len()).map_err(|_| {
        AppError::Internal(format!(
            "incoming sync record count overflowed i64: {}",
            records.len()
        ))
    })?;
    let cycle_started_at = sync_timestamp_now();
    let cycle_started = std::time::Instant::now();

    let mut ordered = records;
    // Priority is the PRIMARY sort key, NOT a tiebreaker. HLCs
    // include a per-device counter so equal versions are vanishingly
    // rare; if HLC version led the order, in a mixed remote batch
    // (list+task+reminder+edges) a task whose HLC < parent list's
    // HLC would be applied BEFORE the list, `apply_envelope` would
    // return `Deferred(missing_parent)`, and the row would sit in
    // `sync_pending_inbox` for 14 days — and a partially-corrupt
    // batch could fire real reseed events when the parent never
    // landed in any subsequent batch.
    //
    // Order is now: priority (parent-before-child topology) → HLC
    // version (newer-wins tiebreak within the same priority) →
    // outbox id (deterministic FIFO within identical priority +
    // version, which is the rarest case but still needs to be
    // deterministic to pin replay order across devices).
    ordered.sort_by(|left, right| {
        sync_entity_apply_priority(
            left.envelope.entity_type.as_str(),
            left.envelope.operation.as_str(),
        )
        .cmp(&sync_entity_apply_priority(
            right.envelope.entity_type.as_str(),
            right.envelope.operation.as_str(),
        ))
        .then_with(|| left.envelope.version.cmp(&right.envelope.version))
        .then_with(|| left.id.cmp(&right.id))
    });

    // The transaction collects deferred Spotlight actions alongside the
    // sync result. They emit post-commit because Spotlight mutations cross
    // the SQLite / native-index boundary. If the transaction rolls back,
    // the native index must not observe speculative changes.
    let apply_outcome = with_immediate_transaction(conn, |conn| {
        let mut result = ApplyRemoteSyncResult {
            received,
            processed: 0,
            applied: 0,
            skipped_duplicate: 0,
            skipped_stale: 0,
            skipped_deferred: 0,
            skipped_malformed: 0,
            diagnostics_log_failures: 0,
        };

        // Deferred Spotlight actions to apply after commit.
        let mut sl_actions: Vec<crate::platform::spotlight::SpotlightAction> = Vec::new();

        let mut applied_records: Vec<IncomingSyncRecord> = Vec::new();

        // Suspend FTS projection for large batches to avoid per-row trigger overhead.
        let bulk_mode = received > 50;
        if bulk_mode {
            let registry = lorvex_store::projection::ProjectionRegistry::default_projections();
            registry
                .enter_maintenance_mode(conn)
                .map_err(AppError::from)?;
        }

        for record in &ordered {
            // Best-effort mode classifies every received record into exactly
            // one leaf bucket below. Count before early malformed continues so
            // the returned summary stays aligned with received records.
            result.processed += 1;

            if record.id.trim().is_empty() {
                if mode == RemoteApplyMode::StrictAtomic {
                    return Err(invalid_incoming_record_error(
                        "incoming sync record id cannot be empty",
                    ));
                }
                result.skipped_malformed += 1;
                continue;
            }
            // `record.envelope.entity_type` is a typed
            // `EntityKind` and cannot be empty by construction. The
            // unknown-kind case still surfaces here via the
            // `is_syncable_entity_type` check below — local-only
            // entity kinds (e.g. `device_state`, `feedback`) get
            // rejected for inbound traffic.
            if record.envelope.entity_id.trim().is_empty() {
                if mode == RemoteApplyMode::StrictAtomic {
                    return Err(invalid_incoming_record_error(
                        "incoming sync record entity_id cannot be empty",
                    ));
                }
                result.skipped_malformed += 1;
                continue;
            }
            if !crate::commands::is_syncable_entity_type(record.envelope.entity_type.as_str()) {
                if mode == RemoteApplyMode::StrictAtomic {
                    return Err(invalid_incoming_record_error(format!(
                        "unsupported incoming sync record entity_type '{}'",
                        record.envelope.entity_type
                    )));
                }
                result.skipped_malformed += 1;
                continue;
            }
            if !is_supported_incoming_record(record) {
                if mode == RemoteApplyMode::StrictAtomic {
                    return Err(invalid_incoming_record_error(format!(
                        "unsupported incoming sync payload for {}:{}",
                        record.envelope.entity_type, record.envelope.entity_id
                    )));
                }
                result.skipped_malformed += 1;
                continue;
            }
            // enforce per-field size caps + structural
            // invariants on every record BEFORE apply. The earlier
            // trim-empty checks only catch the trivial-null case; a
            // record with a 100MB payload would otherwise flow into
            // the apply pipeline and pin SQLite WAL. In BestEffort
            // mode we skip malformed records; in StrictAtomic we
            // abort the whole batch with a descriptive error.
            if let Err(e) = record.envelope.validate() {
                if mode == RemoteApplyMode::StrictAtomic {
                    return Err(invalid_incoming_record_error(format!(
                        "envelope failed validation for {}:{}: {e}",
                        record.envelope.entity_type, record.envelope.entity_id
                    )));
                }
                result.skipped_malformed += 1;
                continue;
            }

            // observe the remote HLC BEFORE apply so local
            // clock state reflects every envelope we saw, not just the
            // ones we chose to write. Stale (Skipped) envelopes still
            // encode authentic remote-clock progress, and a deferred
            // envelope may never come back (schema-too-new past the
            // retention horizon) — if we skip observation on those, a
            // subsequent local write racing the remote can regress.
            crate::hlc::observe_remote_version(&record.envelope.version.to_string());

            match apply_envelope(conn, &record.envelope) {
                Ok(ApplyResult::Applied | ApplyResult::Remapped { .. }) => {
                    result.applied += 1;
                    applied_records.push(record.clone());
                    // Collect Spotlight actions for synced task changes (applied post-commit).
                    if record.envelope.entity_type == lorvex_domain::naming::EntityKind::Task {
                        match record.envelope.operation {
                            lorvex_sync::envelope::SyncOperation::Upsert => {
                                sl_actions.push(
                                    crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
                                        vec![record.envelope.entity_id.clone()],
                                    ),
                                );
                            }
                            lorvex_sync::envelope::SyncOperation::Delete => {
                                sl_actions.push(
                                    crate::platform::spotlight::SpotlightAction::RemoveTaskIds(
                                        vec![record.envelope.entity_id.clone()],
                                    ),
                                );
                            }
                        }
                    }
                    // When a list is upserted via sync (e.g. renamed on another device),
                    // reindex all its tasks so the Spotlight description stays current.
                    if record.envelope.entity_type == lorvex_domain::naming::EntityKind::List {
                        if let lorvex_sync::envelope::SyncOperation::Upsert =
                            record.envelope.operation
                        {
                            sl_actions.push(
                                crate::platform::spotlight::SpotlightAction::ReindexList(
                                    record.envelope.entity_id.clone(),
                                ),
                            );
                        }
                    }
                }
                Ok(ApplyResult::Skipped { .. }) => {
                    result.skipped_stale += 1;
                }
                Ok(ApplyResult::Deferred { reason }) => {
                    lorvex_sync::pending_inbox::enqueue_deferred(conn, &record.envelope, &reason)
                        .map_err(AppError::from)?;
                    result.skipped_deferred += 1;
                }
                Err(e) => {
                    if mode == RemoteApplyMode::StrictAtomic {
                        return Err(strict_apply_error(record, e));
                    }
                    // Persist every per-record failure to
                    // `error_logs` so Settings → Diagnostics surfaces
                    // it and a timeline of apply failures survives
                    // subsequent runs. A bare counter bump would let
                    // the aggregate warning at the end of this loop
                    // overwrite `sync_checkpoints.last_error` with
                    // "skipped N malformed", losing per-record
                    // detail and leaving silent remote-apply
                    // failures with no UI surface.
                    // pull cycles.
                    let message = format!(
                        "apply_envelope failed for {}:{} (version {}) — {e}",
                        record.envelope.entity_type,
                        record.envelope.entity_id,
                        record.envelope.version,
                    );
                    if crate::commands::diagnostics::append_error_log_internal(
                        conn,
                        "sync.apply",
                        &message,
                        None,
                        Some("error".to_string()),
                    )
                    .is_err()
                    {
                        // Audit (silent-failure-hunter): a failed
                        // diagnostics write — the very record we'd most
                        // want visible, the per-row detail behind the
                        // user-facing aggregate "skipped N malformed"
                        // warning — must not be invisible. The
                        // `diagnostics_log_failures` counter below
                        // surfaces the failure to the user-facing
                        // summary so the partial-data-loss disclosure
                        // is structural, not a dev-only stderr
                        // breadcrumb. Direct stderr was rejected by
                        // contract `sync_apply_runtime_diagnostics_contracts`
                        // (#3066): packaged-build users never see
                        // stderr, and `app/src-tauri` doesn't take a
                        // `tracing` dep, so the counter IS the
                        // diagnostic surface here.
                        result.diagnostics_log_failures += 1;
                    }
                    result.skipped_malformed += 1;
                }
            }
        }

        if result.skipped_malformed > 0 {
            // The durable per-record detail now lives in error_logs
            // (source = 'sync.apply') — this summary only points users
            // there so Settings → Sync doesn't mislead by implying all
            // the information is in this single row. When the
            // diagnostics-log write itself failed for some rows
            // (`diagnostics_log_failures` > 0) the summary discloses
            // that the per-record detail is incomplete; without this
            // disclosure a user reading the warning would assume
            // Diagnostics has the full breakdown when in fact some
            // rows are missing from it.
            let warning = if result.diagnostics_log_failures > 0 {
                format!(
                    "[{synced_ts}] skipped {} malformed incoming sync payload event(s) — see Settings → Diagnostics for per-record detail (note: {} of those failed to record to diagnostics; see app logs)",
                    result.skipped_malformed, result.diagnostics_log_failures
                )
            } else {
                format!(
                    "[{synced_ts}] skipped {} malformed incoming sync payload event(s) — see Settings → Diagnostics for per-record detail",
                    result.skipped_malformed
                )
            };
            lorvex_runtime::sync_checkpoint_set(conn, lorvex_runtime::KEY_LAST_ERROR, &warning)
                .map_err(AppError::from)?;
        }

        persist_checkpoint(conn, &ordered, synced_ts)?;

        // Rebuild FTS projection after bulk apply.
        if bulk_mode {
            let registry = lorvex_store::projection::ProjectionRegistry::default_projections();
            registry
                .exit_maintenance_mode(conn)
                .map_err(AppError::from)?;
        }

        // Record device cursors for tombstone watermark GC. A remote
        // device that was seen but had only deferred/malformed rows
        // must still suppress version-watermark GC via a NULL applied
        // watermark. Then track the highest actually-applied version
        // per device so deferred or malformed records never advance the
        // durable apply watermark.
        record_seen_remote_device_cursors(conn, &ordered, synced_ts)?;
        record_device_cursors_from_applied_records(conn, &applied_records, synced_ts)?;

        // Re-attempt pending inbox entries after each batch apply (doc 03 req 25).
        // Wrap in a savepoint so a SQL-level drain failure can't roll back
        // the genuinely-applied records in this batch. Apply errors within
        // the drain are already swallowed per-entry (pending_inbox/drain.rs), so
        // only a transport-level SQLite error can reach here — when it does,
        // the drain is a best-effort side effect, not a correctness gate.
        //
        // collect the drain summary's replayed entity
        // types so we can emit `data-changed` post-commit for any row
        // the inbox just unblocked.
        let drain_replayed_types = match lorvex_store::with_savepoint(
            conn,
            "pending_inbox_drain",
            |conn: &rusqlite::Connection| drain_pending_inbox(conn),
        ) {
            Ok(summary) => summary.replayed_entity_types,
            Err(error) => {
                persist_sync_apply_runtime_warning(
                    conn,
                    "sync.apply.pending_inbox_drain",
                    "Sync apply pending inbox drain failed",
                    error.to_string(),
                );
                Vec::new()
            }
        };

        Ok((result, sl_actions, drain_replayed_types))
    });
    let cycle_completed_at = sync_timestamp_now();
    let cycle_duration_ms = duration_ms_saturating(cycle_started.elapsed());
    let (result, spotlight_actions, drain_replayed_types) = match apply_outcome {
        Ok(success) => success,
        Err(error) => {
            let error_message = error.to_string();
            record_sync_apply_cycle_best_effort(
                conn,
                &cycle_started_at,
                &cycle_completed_at,
                cycle_duration_ms,
                received,
                None,
                Some(&error_message),
            );
            return Err(error);
        }
    };
    record_sync_apply_cycle_best_effort(
        conn,
        &cycle_started_at,
        &cycle_completed_at,
        cycle_duration_ms,
        received,
        Some(&result),
        None,
    );

    // Post-commit: apply all deferred Spotlight actions.
    if !spotlight_actions.is_empty() {
        crate::platform::spotlight::apply_actions(conn, &spotlight_actions);
    }

    // fan out `data-changed` for entity types the
    // pending-inbox drain just unblocked. Without this, an FK-stalled
    // child envelope that drained as a side effect of this batch
    // mutated the DB but left the UI rendering pre-drain rows. The
    // emit is post-commit so a rolled-back transaction never fires
    // ghost refresh events for state that no longer exists.
    if !drain_replayed_types.is_empty() {
        emit_data_changed_for_entity_types(&drain_replayed_types);
    }

    Ok(result)
}
